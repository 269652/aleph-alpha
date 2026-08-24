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

- **Exact soft/hard slope thresholds** — the ~15–20°/~45° figures above are
  real mountaineering anchors, not tuned game constants; need their own
  calibration pass and test, per this project's no-manual-tuning rule.
- **Exact vein-probability-vs-slope curve** — tuned, deferred.
- **Does biome classification itself ever read slope**, not just
  elevation/temperature/moisture — a plausible future tie-in to
  [climate_dynamics.md](climate_dynamics.md#biomes-a-live-read-not-a-worldgen-snapshot)'s
  live reclassification, not decided here.
- **Creature movement** — should steep terrain gate herbivore/predator
  movement too, or stay player-only for now (the same scoping call
  `stone.md`'s pebble dispersion already made, deliberately player-only to
  avoid an O(creatures × terrain) cost nothing currently needs)?
- **Rope mechanics specifics** — how much a rope raises the hard
  threshold, whether it's consumed or reusable, whether it can anchor for
  others to follow — genuinely open, `transportation.md`'s own open
  questions don't cover this yet either.

## Status

Pure design, nothing implemented. Builds directly on two pieces of real,
live, already-wired code — `earth_elevation_source.gd`'s bilinear
elevation sampling and `solar_position.gd`'s real solar position — plus
reuses `weather_model.gd`'s movement-speed-modifier shape and
`creature_movement_gate.gd`'s ask-before-moving pattern as direct
precedent rather than new mechanisms of their own.
