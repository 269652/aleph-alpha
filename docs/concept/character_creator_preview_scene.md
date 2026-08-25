# Character creator preview scene

A small, self-contained, ALWAYS-live diorama embedded in the character
creator's hero panel, replacing the static portrait image: real grass
(swaying), a pond (animated water), a few pebbles at its edge, a couple of
trees, and the hero — built from the same illustrated pipeline the real
world uses, dressed exactly like it is on the "Character" tab today, but
independently strolling around a small bounded patch rather than posing
still. Asked directly, after the static-portrait panel shipped: *"It should
be a real mini in game scene with swaying grass blades; some pebbles the
edge of a pond and some trees where the char should stroll around."*

## Design pillars

1. **Reuse the real world's rendering, not a new art style.** Grass, water,
   pebbles, and trees are the SAME classes `EarthChunkManager`/the real
   world use (`IllustratedGrassPatch`, `WaterShader`, `StoneRenderer`,
   `TreeRenderer`) — a diorama built from placeholder shapes would drift
   from the real game's look the moment either one changes. The character
   itself is the same `CharacterView` the player and every NPC wear.
2. **A diorama, not a slice of the infinite world.** No chunk generation,
   no `EarthChunkManager`, no biome lookup. A small, fixed, hand-placed
   patch — a pond, a couple of trees, some grass, a stroll path — assembled
   directly into a bare scene tree. It only has to look like a believable
   corner of the world, not actually be a reachable one.
3. **Deterministic per appearance.** The diorama's own layout (tree/pebble/
   grass positions, pond shape) is seeded from the SAME DNA seed the
   appearance already carries, so re-opening the creator with the same
   rolled hero shows the same little scene — consistent with every other
   seeded-determinism convention in this codebase (see
   `ecosystem_dynamics.md`'s own "Determinism" pillar). The stroll itself
   (where the character currently is/heading) is not seed-pinned — it is
   ambient motion, not part of the hero's own identity.
4. **Cheap enough to run continuously in a menu.** This renders every frame
   the creator screen is open, alongside the actual game (which may itself
   be paused/backgrounded at the main menu) — grass is GPU/shader-animated
   with no per-frame script at all (see `IllustratedGrassPatch`'s own doc
   comment), water only animates its ambient shimmer unless disturbed
   (never is, here), and the only real per-frame CPU cost is the stroll
   logic moving one `CharacterView`.

## Mechanism

### Layout — pure, seeded, testable

`src/rendering/character_preview_layout.gd` (pure `RefCounted`, no Godot
nodes) takes a seed and a diorama footprint (world units) and returns plain
data: the pond's center/radius, tree positions, pebble positions (scattered
near the pond's rim), grass clump positions (filling the rest of the
footprint, avoiding the pond and trees), and the walkable bounds the stroll
logic confines itself to (the footprint minus the pond and a margin around
each tree). Everything is placed FROM the seed — same seed, same layout,
matching this codebase's established "measure/derive, don't eyeball"
convention for placement (see `StonePlacement`, `WildCropPatch` for the
existing precedent of pure seeded placement logic kept separate from the
nodes it describes).

### Stroll — pure, testable

`src/rendering/character_stroll.gd` (pure `RefCounted`) is the walk-to-a-
point-then-pick-a-new-one behavior: given a current position, a current
target, walkable bounds, and delta time, returns the next position, whether
the target was reached, and the facing direction to move in — the same
shape `CreatureWander`/`creature_movement_gate.gd` already use for
ambient creature movement, scaled down to "one character in a small pen."
When a target is reached, the NEXT target is picked randomly within the
walkable bounds (not seed-pinned — see the determinism pillar above: this
is ambient motion, only the world layout itself needs to reproduce).

### Assembly — Godot-coupled glue

`src/rendering/character_preview_diorama.gd` (`extends Node2D`) is the only
part that touches actual nodes: reads a `CharacterPreviewLayout` result and
builds one `MultiMeshInstance2D` per grass band (`IllustratedGrassPatch
.fill_band`), one `Sprite2D` pond (`ProceduralShoreDistanceSprite` +
`WaterShader.shared_material()`), one `LiftableStone` node per pebble
(`StoneRenderer.build_liftable_stone_node`), one `ChoppableTree` per tree
position (`TreeRenderer.spawn_tree_at`, `age_seconds` defaulting to `INF` —
fully grown), and one `CharacterView` (the same `.tscn` the player/NPCs
use). `_process` drives `CharacterStroll` against the `CharacterView` each
frame — `set_facing`/`set_movement_state`/`.position` are all `CharacterView`
needs to animate correctly standalone (confirmed against `Player
._update_character_view`, its own real driver — no physics/collision/input
required).

### Embedding — the character creator's own UI

`scenes/main_menu.gd`'s hero panel (`_build_hero_column`) swaps its
`TextureRect` portrait for a `SubViewportContainer`/`SubViewport` hosting
one `CharacterPreviewDiorama`, with a `Camera2D` framing the whole
footprint from a fixed position (a diorama viewed from outside, not a
camera that follows the stroll). `_refresh_appearance()` calls
`apply_appearance` on the diorama's own `CharacterView` instead of
generating a portrait texture — every other axis-cycling control keeps
working exactly as it already does, now visibly redressing a live, walking
hero instead of a static image.

## Status / mechanisms

- ✅ All four pieces described above are built and tested: seeded layout
  (`character_preview_layout.gd`), pure stroll motion
  (`character_stroll.gd`), the Godot-coupled assembly
  (`character_preview_diorama.gd`), and the `main_menu.gd` embedding. See
  `docs/progress.md`'s own entry for the full detail and exact file/class
  names.
- ✅ Seen live and iterated across several real rounds of screenshots —
  real bugs only visible once actually rendered, several requiring a
  second pass once the first fix's own result was seen (panel
  containment, the pond's shape/shading — reverted from a first "fix" to
  a genuine circle back to a rectangle once actually seen — fish
  visibility AND containment as two separate bugs, and a real hero-rig
  width bug a concurrent session's own leg-gait rework had introduced,
  found while chasing an "unproportional ... walks like a duck" report).
  See `docs/progress.md`'s own entry for the full list, exact fixes, and
  file names.
- Fish (`FishRenderer.spawn_fish_at`) and grass-parting
  (`IllustratedGrassPatch.set_walker_position`) round out the scene,
  reusing existing real-world mechanisms rather than adding new ones, per
  this doc's first pillar.

## Known open questions

- Whether the class-icon row's small per-class portraits (7 tiny thumbnails
  above the main panel) should also become live dioramas, or stay static
  portraits — a live `SubViewport` per icon is very likely wasteful for a
  thumbnail that small; this doc assumes they stay static unless reported
  otherwise.
- Whether the pond should ever show a disturbance ripple (the character
  wading in, rain) — `WaterShader.add_disturbance`/`set_rain_intensity`
  exist and are wired for the real world, but this diorama does not call
  them; the pond stays a still, ambient backdrop.
