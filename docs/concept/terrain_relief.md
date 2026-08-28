# Terrain Relief

Real elevation already exists as data (`earth_elevation_source.gd`, real
bathymetry/topography, bilinearly sampled) — it currently only decides a
biome threshold ("mountain" starts above some elevation). This doc is what
makes it a real, felt, *visible* physical feature: mountains you can be
turned back by, slopes that visibly catch the light, and ore that shows up
specifically where the rock is exposed rather than scattered flat like
grassland gravel.

## Design pillars

1. **Slope blocks you, not raw elevation.** A high plateau is walkable; a
   low but sheer cliff isn't — the real distinction mountaineering makes,
   and the one this project's terrain doesn't make at all yet.
2. **One derived field, three consumers.** Slope and aspect, computed once
   from the elevation gradient, feed passability, visual hillshading, and
   mountain ore exposure — not three separately-designed systems that
   happen to agree.
3. **Ask before you step, don't correct after.** Exactly the fix
   `creature_movement_gate.gd` already made for creatures walking into
   trees, applied here to the player walking into a mountainside: a step
   onto terrain too steep to cross is refused before it happens, not
   allowed and then visually corrected.
4. **Real-world-matching from real inputs, not a named place.** No mountain
   range is asserted in code — same pillar
   [climate_dynamics.md](climate_dynamics.md#design-pillars) and
   [ecosystem_dynamics.md](ecosystem_dynamics.md) already commit to.
   Real-looking ranges fall out of running the same slope math over real
   elevation data everywhere.
5. **Gives an existing, unused tool concept something to unlock.**
   [transportation.md](transportation.md#traversal-tools-crafted-from-the-shared-grammar-gated-by-material-sourcing)
   already specifies a climbing rope, crafted from a high-tensile
   material, with nothing today that actually requires one. This doc is
   what a rope is *for*, not a reason to invent a second tool.

## Real-world grounding

- **Slope from a gradient, not a lookup table.** Real terrain steepness is
  the elevation difference over horizontal distance between two points —
  exactly what four bilinear elevation samples around a position already
  give for free, no new data source.
- **Real mountaineering slope bands.** Roughly: under ~15° is unremarkable
  walking; ~15–30° is a real uphill grind but still ordinary hiking;
  ~30–45° is scrambling territory, hands-on-rock but still unroped for a
  skilled climber; beyond ~45° is genuine technical climbing. These are
  real, commonly-cited mountaineering thresholds, not invented tiers — the
  same "use the real classification" discipline
  [stone.md](stone.md#real-world-grounding)'s Wentworth scale already
  models for this project.
- **Hillshading is a real, standard technique.** GIS terrain maps have
  rendered elevation as shaded relief for over a century: illuminate each
  point by the dot product of its surface normal (derived from local
  slope + aspect — which compass direction the slope faces) against a
  light direction, the same Lambertian-reflectance idea any 3D engine's
  basic lighting uses, just applied to a 2D elevation field instead of a
  mesh.
- **Mountains really do hold more ore.** This isn't a convenient game
  fiction — real mountain-building (orogeny) is genuinely why exposed
  mineral-rich rock concentrates in mountainous terrain (the Rockies, the
  Andes, the Urals are major real mining regions for exactly this
  geological reason): uplift and erosion expose deep rock strata at the
  surface that stay buried everywhere else.

## Mechanism

### Slope and aspect: one derived field, computed from data that already exists

`slope_at(lat, lon)` and `aspect_at(lat, lon)` sample `earth_elevation_source.gd`'s
existing `elevation_at` at four neighboring points (a small real-world
offset north/south/east/west) and derive a gradient: `slope` is the
gradient's magnitude (in real degrees, `atan(Δelevation / Δdistance)`),
`aspect` is its direction (which way the slope faces). No new dataset —
this is the same "real elevation data was already there, just not used yet"
relationship [electromagnetism.md](electromagnetism.md) has to
`conductivity`.

**Honest scope note**: at this project's real-Earth world scale (roughly
1km per tile, per `docs/progress.md`'s Phase 0 entry), this is tile-to-tile
slope — a real, coarse approximation of ruggedness, not true meter-scale
terrain detail. Consistent with how this project already treats terrain as
"coarse but genuinely real, not painted," same as the elevation data
itself.

**Slope and aspect are two readings of ONE gradient.** That gradient is
public (`terrain_relief.gd`'s `gradient_at`), because asking for both
readings separately takes the same four elevation samples twice over — and
doing exactly that per tile *is* the whole per-tile cost of hillshading a
chunk, the largest per-chunk cost in the running game. A caller that wants
both takes the gradient once and derives them with the pure
`slope_degrees_from_gradient` / `aspect_degrees_from_gradient`. `slope_at`
and `aspect_at` keep their signatures and are now thin wrappers over the
same function, so a caller that wants only one reading is unaffected. The
`gradient_at` seam takes "any object with an `elevation_at(lat, lon)`
method" exactly as `slope_at`/`aspect_at` always did.

**Constraint on the elevation asset.** `assets/data/world_elevation.png`
must stay a **single-channel 8-bit** height field. `earth_elevation_source.gd`
decodes it once per process into a flat `PackedByteArray` and indexes that
directly, rather than paying `Image.get_pixel()`'s boxed `Color` per sample
— four per bilinear reading, and 32,768 per hillshaded 32×32 chunk. Two
consequences that are spec, not implementation detail:

- Bytes are mapped back to the `[0,1]` encoding through a 256-entry
  `PackedFloat32Array`, **not** a plain `byte / 255.0`. `Color` stores
  32-bit floats, so the float64 division differs from what `get_pixel`
  returned in *every* sample — the lookup table reproduces it bit for bit,
  which is what keeps every coastline exactly where it was.
- Replacing the asset with a **16-bit** height field would silently
  truncate it to 8 bits here. A higher-precision source needs the decode
  widened deliberately, not dropped in.

The encoding itself is unchanged: `0.0` = −8000 m, `1.0` = +6400 m, linear,
sea level at ~0.5556.

### Passability: ask before you step

Extends `creature_movement_gate.gd`'s already-established "decide before
moving, never correct after" principle from creatures dodging trees to the
player crossing terrain:

- **Below a soft threshold** (~15–20°): unaffected, ordinary movement.
- **Between the soft and hard thresholds** (~20–45°): movement is slowed
  proportionally to slope — the exact same "environment scales a movement
  multiplier" shape `weather_model.gd`'s existing
  `movement_speed_modifier` already uses for rain/storm, just driven by
  slope instead of weather state.
- **Above the hard threshold** (~45°+): the step is refused outright,
  exactly the way `CreatureMovementGate.clear_direction` already refuses a
  heading that runs into a tree — **unless** the player is carrying a
  climbing rope. A rope (`transportation.md`'s existing traversal-tool
  concept, crafted from a high-tensile material per
  [materials.md](materials.md#the-material-property-vector)) raises the
  hard threshold, turning a genuine wall into a slow, deliberate climb
  instead of an impossibility — the Zelda-style "aha, now I can cross
  that" moment `transportation.md` already wanted, delivered by a terrain
  feature that, today, has nothing to gate at all.

### Hillshading: the same field, rendered

`illumination = cos(zenith) × cos(slope) + sin(zenith) × sin(slope) × cos(sun_azimuth − aspect)`
— the standard real hillshade formula, with `zenith` and `sun_azimuth` read
from `solar_position.gd`'s already-real, already-computed solar position
(the same values already driving day/night `CanvasModulate` tinting) rather
than an invented light direction. Applied as a **brightness multiplier
layered on top of** the existing ground texture
(`procedural_terrain_sprite.gd`/`illustrated_terrain_sprite.gd`), the same
"overlay the ground, don't replace it" relationship
[weather.md](weather.md#snow) already established for snow cover. Because
the light direction is the real sun, a mountainside's shading subtly shifts
through the day exactly the way a real one does — one more thing that's
true for free because it reads from the same shared solar truth everything
else already does, not a separate lighting rig for terrain.

This is a general mechanism — every tile has *some* slope, even a gentle
one — not mountain-specific code. It just reads as dramatic specifically
where slope is high, which is exactly where a player would expect it to.

### Mountain ore: steepness exposes it

`ore_placement.gd` today only layers onto `StonePlacement`'s
`STONE_BIOMES` (`grassland`, `forest`) — mountain is explicitly excluded.
Mountain ore is proposed as its own placement rule rather than extending
the flat per-tile density roll grassland/forest use: **vein probability
scales with local slope** — a steep, eroded face is more likely to expose
a seam; a gentler mountain slope accumulates soil/scree that buries one,
the same real geological logic named above. This produces a genuine,
unplanned coupling: **the same steepness that makes a face hard to cross
is what makes it worth crossing** — risk and reward from one shared
quantity, not two systems designed together to agree.

Visually, a vein renders as a mineral-colored streak following the local
slope direction directly on the mountain wall texture, subject to the same
hillshading pass as the rock around it — so it reads as *part of* a lit,
exposed rock face, not a decal stamped on top of one. Interaction stays
exactly the existing `MinableOre` mining flow — only placement and
rendering are new, not a second mining mechanic.

**A natural home for magnetite specifically**
([electromagnetism.md](electromagnetism.md#magnetism-a-material-property-not-a-separate-system)'s
open fourth ore type) — real magnetite concentrates in exactly this kind
of orogenic/metamorphic mountain rock, so mountain terrain is where that
open question resolves itself rather than needing a separate placement
rule invented for it.

## Interaction with `climate_dynamics.md`

[climate_dynamics.md](climate_dynamics.md#the-water-cycle-and-precipitation)'s
orographic lift already needs to know "is the wind currently climbing a
rising elevation gradient" — that's exactly this doc's `slope_at`/`aspect_at`
field, not a separate computation. The two docs should share one
implementation: terrain relief computes slope/aspect from real elevation,
climate dynamics reads it for rain-shadow precipitation, this doc reads it
for passability/hillshading/ore. One field, at least three consumers.

## Worked examples

1. **A high plateau and a low sheer ridge, same elevation-eligible
   "mountain" biome range, opposite passability.** The plateau's slope is
   near zero — ordinary walking despite the altitude. The ridge is a wall.
   Elevation alone, which is all this project currently checks, would
   treat them identically; slope tells them apart correctly.
2. **A visible vein on a sunlit, steep face; none on a gentler slope
   nearby.** Both are "mountain." The steep face's hillshading reads as a
   dramatic exposed cliff, and that's exactly where a vein is likely to
   have rolled — the player learns to read exposed, well-lit rock as
   promising the same way a real prospector does, without a hint arrow
   anywhere.
3. **Turned back without a rope, crossing fine with one.** The same
   45°+ face refuses the player outright on the first attempt and admits
   them, slowly, once they've crafted and equipped a rope from a real
   high-tensile material — nothing about the terrain changed, only the
   player's own capability did.

## Open questions

- ~~**Exact soft/hard slope thresholds** — the ~15–20°/~45° figures above
  are real mountaineering anchors, not tuned game constants; need their
  own calibration pass and test, per this project's no-manual-tuning
  rule.~~ Resolved: `terrain_passability.gd`'s `SOFT_THRESHOLD_DEG` (18°)
  and `HARD_THRESHOLD_DEG` (45°) are real, named, tested constants sitting
  inside/on the cited mountaineering bands, not eyeballed — see the Status
  section below. `HARD_THRESHOLD_WITH_ROPE_DEG` (65°, what a rope buys
  beyond the hard threshold) is a third value this bullet didn't originally
  ask about; it's tested for shape (`test_terrain_passability.gd`) but,
  honestly, has no real-world citation of its own the way the other two
  do.
- ~~**Exact vein-probability-vs-slope curve** — tuned, deferred.~~ Resolved:
  `mountain_ore_placement.gd`'s `vein_chance_for_slope` is a real, tested
  (`test_mountain_ore_placement.gd`, 16/16) linear ramp — zero at/below
  `MIN_SLOPE_FOR_VEINS_DEG` (= passability's own `SOFT_THRESHOLD_DEG`,
  18°), rising to a ceiling at `MAX_SLOPE_FOR_SCALING_DEG` (= passability's
  `HARD_THRESHOLD_WITH_ROPE_DEG`, 65°) and held flat beyond it. The
  ceiling itself, `MAX_VEIN_CHANCE`, is derived rather than eyeballed —
  `StonePlacement.STONE_DENSITY * OrePlacement.ORE_FRACTION`, the same
  order of magnitude as flat-ground ore's own rarity (the 2026-08-28 fix
  covered in the Status section's mountain-ore bullets below). Honest
  nuance, same as the bullet above: the endpoints reuse already-grounded
  constants, but LINEAR specifically is this implementation's own choice,
  not itself derived from a cited real-world curve — this doc only ever
  said "scales with local slope," not what shape that scaling takes.
- ~~**Does biome classification itself ever read slope**, not just
  elevation/temperature/moisture — a plausible future tie-in to
  [climate_dynamics.md](climate_dynamics.md#biomes-a-live-read-not-a-worldgen-snapshot)'s
  live reclassification, not decided here.~~ Resolved: `biome_classifier.gd`'s
  `classify()` now takes an optional `slope_deg`; a slope at/beyond
  `TerrainPassability.HARD_THRESHOLD_DEG` forces "mountain" outside the
  elevation-based band (real alpine tree-lines), ocean always excluded.
  Honestly, the real bundled elevation dataset never actually triggers it
  at current sampling resolution (see the Status section's own bullet) —
  the mechanism is real and tested, the live world just doesn't currently
  contain a tile that exercises it. `climate_dynamics.md`'s own live
  reclassification tie-in is still a separate, undecided question.
- ~~**Creature movement** — should steep terrain gate herbivore/predator
  movement too, or stay player-only for now (the same scoping call
  `stone.md`'s pebble dispersion already made, deliberately player-only to
  avoid an O(creatures × terrain) cost nothing currently needs)?~~ Resolved:
  yes — `creature_marker.gd` now gates herbivore/predator movement the
  same way, genuinely O(creatures) (one slope sample per creature's own
  candidate tile, never a terrain scan), so the cost this question worried
  about was never actually necessary. See the Status section below.
- ~~**Rope mechanics specifics** — how much a rope raises the hard
  threshold, whether it's consumed or reusable, whether it can anchor for
  others to follow — genuinely open, `transportation.md`'s own open
  questions don't cover this yet either.~~ Two of three now answered: a
  rope raises the threshold from `HARD_THRESHOLD_DEG` to
  `HARD_THRESHOLD_WITH_ROPE_DEG` (45° → 65°, already real/tested before
  this), and it is reusable, not consumed — `Player._has_climbing_gear()`
  is a plain inventory-count check, unaffected by crossing terrain. Still
  genuinely open: whether a rope can anchor for others to follow —
  unrelated to what shipped here, and multiplayer-shaped in a way this
  pass didn't touch.

## Status

Real and live, not pure design — built out the same week this doc was
written (2026-08-24). Full build detail lives in `docs/progress.md`'s own
"Terrain Relief" section; this is the cross-aligned summary, checked here
directly against the current `src/` files rather than assumed current.

- ✅ **Slope/Aspect field, from real elevation data** —
  `src/world/terrain_relief.gd` (`slope_at`/`aspect_at`, both thin
  wrappers over a shared public `gradient_at` so a caller wanting both
  readings takes one set of four elevation samples instead of two), tested
  21/21. Exposed per-global-tile via `EarthChunkGenerator`/
  `EarthChunkManager.slope_at_global`/`aspect_at_global` — the one field
  the consumers below all read. Still unconsumed by
  [climate_dynamics.md](climate_dynamics.md)'s orographic lift.
- ✅ **Slope-gated passability (soft slow, hard refusal)** —
  `src/gameplay/terrain_passability.gd` (`speed_multiplier`/`is_passable`,
  tested 11/11), with real tested thresholds rather than the bare figures
  above: `SOFT_THRESHOLD_DEG` 18°, `HARD_THRESHOLD_DEG` 45°,
  `HARD_THRESHOLD_WITH_ROPE_DEG` 65°. Wired live into `scenes/player.gd`'s
  `_authority_step`: `_terrain_speed_multiplier` applies the soft
  slowdown, `_terrain_blocks_movement` refuses the frame's movement
  outright ahead of `move_and_slide()` — the same ask-before-you-step
  principle `creature_movement_gate.gd` established for creatures. The two
  gaps this bullet used to note here are both closed now — see the
  Climbing Rope and Creature Slope Gating bullets immediately below.
- ✅ **Climbing rope — a real, craftable item** —
  `item_catalog.gd`'s `climbing_rope` (kind "tool"), recipe'd from 3 hide +
  3 plant_fibre (`crafting_recipe_book.gd`). Material picked against
  `MaterialProperties`' real toughness column, not eyeballed: hide (7.0)
  clears `ROPE_MIN_TOUGHNESS` (5.0) via the previously-orphaned
  `is_viable_for_tool(material, "grapple_rope")` check that already
  existed, unused, before this — and hide is non-trivial to source
  (hunting + butchering), matching this doc's own "materials further out
  on the danger gradient" framing rather than the trivially-gathered
  plant_fibre alone. `Player._has_climbing_gear()` now reads real
  inventory state (`_inventory_counts().get("climbing_rope", 0) > 0`, the
  same raw-count pattern `_has_fishing_rod()` already used) instead of its
  old hardcoded `false`. `terrain_passability.gd` needed no changes.
  Tested: 50/50, 50/50, 75/75, 2/2 across the four touched files.
- ✅ **Creature slope gating** — `src/rendering/creature_marker.gd` gained
  `_terrain_speed_multiplier`/`_terrain_blocks_movement`, mirroring
  `player.gd`'s own two functions exactly and reading slope through the
  same duck-typed world reference `solid_obstacles_near` already uses.
  Genuinely O(creatures), not O(creatures × terrain) — resolving the
  formerly-open question below by construction, the same one-slope-sample-
  per-candidate-tile shape `player.gd` already used, not a new technique.
  Tested: 8 new tests plus a full `test_creature_marker.gd` regression run,
  144/144 passing, zero regressions.
- ✅ **Hillshading (real Lambertian formula, real solar position)** —
  `src/rendering/hillshade.gd`'s `illumination()` (tested 8/8) is the
  formula above verbatim, fed by `solar_position.gd`'s azimuth alongside
  its existing elevation. `procedural_hillshade_sprite.gd` bakes quantized
  slope/aspect into a real atlas (tested 14/14); `hillshade_shader.gd` is
  a compiled `canvas_item` shader (tested 12/12). Wired live:
  `EarthChunkManager.set_hillshade_layer`/`_paint_hillshade_overlay`/
  `set_sun_position`, called from chunk load/unload; `scenes/world.tscn`
  carries a real `HillshadeFx` layer and `world.gd` pushes real per-frame
  sun azimuth into it. No automated test instantiates `world.tscn` itself,
  so that last scene-level wire is verified only by both resources loading
  without a structural error, not a live GUI session.
- ✅ **Slope-gated mountain ore veins — placement** —
  `src/world/mountain_ore_placement.gd` (tested 16/16): vein chance is
  zero below the same `SOFT_THRESHOLD_DEG` passability uses, scaling
  linearly to a ceiling at `HARD_THRESHOLD_WITH_ROPE_DEG` — one shared
  quantity gating both crossability and ore exposure, exactly as designed
  above. Wired live into `EarthChunkManager._load_chunk` via
  `StoneRenderer.spawn_mountain_veins` (tested 6/6).
- 🚧 **Mountain ore veins — rendering: real, but not what this doc specs.**
  This doc says above that a vein should render as a mineral-colored
  streak following the slope direction directly on the mountain wall
  texture, under the same hillshading pass as the rock around it — "not a
  decal stamped on top of one." The live renderer does exactly the decal
  this section was written to rule out: `StoneRenderer._build_mountain_vein_node`
  spawns a discrete `MinableOre` `StaticBody2D`, positioned at the tile
  center with a composited boulder texture — the same node shape flat-
  ground ore already uses. Mechanically this is fully correct (the real
  `MinableOre` mining flow, real slope-gated placement, no second mining
  mechanic invented); visually it is the thing this doc explicitly says
  not to do. Known and deliberately deferred, not silently resolved by
  rewriting the spec to match the code: a 2026-08-28 playtest-driven fix
  (`docs/progress.md`'s Terrain Relief section, same date) re-tuned this
  same placement rule's density and explicitly left this visual mismatch
  untouched.
- ✅ **Biome classification reads slope** — beyond this doc's original
  four-piece Mechanism list, closing the Open Questions bullet of the same
  name above: `biome_classifier.gd`'s `classify()` takes an optional
  `slope_deg` (a `-1.0` sentinel default, every pre-existing caller/test
  byte-identical); a slope at/beyond `HARD_THRESHOLD_DEG` forces "mountain"
  regardless of temperature/moisture — real alpine tree-lines, never
  overriding ocean. `EarthChunkGenerator._biome_at_global` wires it through
  a `_slope_override_deg_for` gate that skips the four-fresh-elevation-
  sample cost entirely for a cell elevation alone already decided (ocean,
  or already elevation-mountain) — a real, addressed perf concern, since
  terrain regenerates from scratch on every chunk load, never cached.
  **Honest limitation, empirically checked**: probing the real bundled
  elevation data (Everest/K2/Nanga Parbat/Annapurna plus a global scan)
  found slope in the "undecided" band never actually reaches 45° at this
  dataset's ~10km/pixel resolution and the existing ~1.1km sampling
  offset — the mechanism is real and correctly built, no live tile
  currently exercises it. Tested: `test_biome_classifier.gd` 28/28,
  `test_earth_chunk_generator.gd` 20/20, zero regressions.

Builds directly on two pieces of real, live, already-wired code —
`earth_elevation_source.gd`'s bilinear elevation sampling and
`solar_position.gd`'s real solar position — plus reuses
`weather_model.gd`'s movement-speed-modifier shape and
`creature_movement_gate.gd`'s ask-before-moving pattern as direct
precedent, exactly as this doc originally planned.
