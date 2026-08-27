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
near the pond's rim), grass clump positions, and the walkable bounds the
stroll logic confines itself to (the footprint minus the pond and a margin
around each tree). Everything is placed FROM the seed — same seed, same
layout, matching this codebase's established "measure/derive, don't eyeball"
convention for placement (see `StonePlacement`, `WildCropPatch` for the
existing precedent of pure seeded placement logic kept separate from the
nodes it describes).

Two placement rules deserve naming, because both were originally absent and
both were visible the moment the scene was actually looked at:

- **Meadow density is the real world's, not "wherever there is room."** A
  grass clump is not placed on every clear cell — that was ~100% coverage
  against a real meadow's ~20%, and since one clump draws several
  overlapping full-tile cards it read as a hedge the hero was buried in.
  The share of clear ground kept is `TallGrass.SEED_CHANCE` (the reference
  grassland coverage `TallGrass.FIELD_NOISE_THRESHOLD` is itself pinned to)
  and WHICH cells get it is decided by the same `PixelNoise.smooth` field
  `TallGrass._seed_initial_patches` uses at the same `FIELD_NOISE_SCALE`, so
  the meadow drifts in clumps instead of speckling — pillar 1 applied to
  density, not just to art. (The share is taken directly rather than by
  TallGrass's own fixed threshold because a 6×6 footprint is under one noise
  lattice cell across, where a threshold is all-or-nothing per seed.)
- **Placement accounts for an object's own DRAWN extent, not just its centre
  point.** The camera frames exactly the footprint, and a tree is anchored at
  its trunk foot and drawn upward across `ProceduralTreeSprite.WORLD_SIZE`,
  so sampling tree positions over the raw footprint cut canopies off the top
  of the frame and trunks off its sides. `tree_bounds(footprint)` insets the
  sampling rect by that art's own world size — derived from the art, never an
  eyeballed margin — and the no-clear-spot fallback is the inset rect's
  centre rather than the footprint's corner (which put three quarters of a
  tree outside the frame).

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
builds a **ground plane** (one `Sprite2D` per `TerrainRenderer.TILE_SIZE` of
footprint, textured through the same has-art-then-fallback seam
`TerrainRenderer._biome_frame_image` uses — `IllustratedTerrainSprite
.frame_for("grassland", seed)`, `ProceduralTerrainSprite` otherwise — at a
scale derived from the art's own pixel width so 32px illustrated and 64px
procedural tiles both cover exactly one world tile, and at a `z_index` below
both the pond's and the grass band's), one `MultiMeshInstance2D` per grass
band (`IllustratedGrassPatch.fill_band`), one `Sprite2D` pond
(`ProceduralShoreDistanceSprite` +
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

`scenes/main_menu.gd`'s hero panel (`_build_hero_column`) hosts a
`SubViewportContainer`/`SubViewport` wrapping one `CharacterPreviewDiorama`,
with a `Camera2D` framing the whole footprint from a fixed position (a
diorama viewed from outside, not a camera that follows the stroll).
`_refresh_appearance()` calls `apply_appearance` on the diorama's own
`CharacterView` — every other axis-cycling control keeps working exactly as
it already does, now visibly redressing a live, walking hero instead of a
static image.

The static portrait wasn't fully retired, though: a toggle button
(`_preview_toggle_button`, top-right of the panel) lets the player switch
back to it — `_standard_portrait`, a `TextureRect` showing
`ProceduralCharacterSprite.generate_hero_portrait_texture` at the panel's
own full size (the same pipeline the class-icon row already uses for its
tiny thumbnails). Both views are kept in sync with the current appearance on
every `_refresh_appearance` call; only one is ever `.visible`, and the
diorama's own `_process`/`SubViewport` rendering pauses while it isn't the
visible one, so an unwatched hero holds still rather than silently acting
off-screen.

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
- ✅ The diorama stands on the real world's own ground art at the real
  world's tile size (`_build_ground`). This was a genuine SPEC GAP, not a
  missed implementation: no version of this doc ever mentioned ground, so
  none was ever built — grass, pond, pebbles and trees were drawn straight
  onto the `SubViewport`'s transparent background and what showed between
  them was the creator panel's near-black `StyleBox`. It also explains a
  second report that looked unrelated: the pond's shore fade is pure ALPHA
  (`water_shader.gd`), so with nothing behind it to fade INTO, a
  deliberately rectangular pond read as a hard-edged blue box. No pond code
  changed; giving the fade a bank to land on is the whole fix, and the
  rectangle stays rectangular per the standing instruction ("should be more
  rectangular not a real circle").
- Fish (`FishRenderer.spawn_fish_at`) and grass-parting
  (`IllustratedGrassPatch.set_walker_position`) round out the scene,
  reusing existing real-world mechanisms rather than adding new ones, per
  this doc's first pillar.

## Known open questions

- Whether the class-icon row's small per-class portraits (7 tiny thumbnails
  above the main panel) should also become live dioramas, or stay static
  portraits — a live `SubViewport` per icon is very likely wasteful for a
  thumbnail that small; this doc assumes they stay static unless reported
  otherwise. They are now at least genuinely per-class: all seven used to
  render byte-identically, because the illustrated rig's outfit art is
  pre-coloured (so the portrait path never tints by the class tunic/leg
  palette — which is the only thing that differs between seven appearances
  at one shared DNA seed). The outfit ROW is the one channel that art has,
  so `HeroAppearance.outfit_variant_for` has the class pick a row and the
  DNA seed rotate it, carried on the appearance dict so a renderer takes it
  rather than re-rolling its own.
- Whether the pond should ever show a disturbance ripple (the character
  wading in, rain) — `WaterShader.add_disturbance`/`set_rain_intensity`
  exist and are wired for the real world, but this diorama does not call
  them; the pond stays a still, ambient backdrop.
