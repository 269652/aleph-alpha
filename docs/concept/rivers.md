# Rivers

Before this doc, "river" existed nowhere in the codebase as real geometry —
only as flavor text (a Bridgekeeper riddle answer, a kingfisher-behaviour
comment, a village-placement comment) riding on top of the single `"ocean"`
biome threshold `BiomeClassifier` already computes from real elevation data.
This doc specifies the first real river system: a **curated set of actual
named real-world rivers**, layered over a **procedural fallback** everywhere
a curated river doesn't reach, both rendered as an overlay on top of whatever
land terrain is already there — not a new ground-texture biome.

## Design pillars

1. **Curated where it matters, procedural everywhere else.** The world's
   bundled real elevation data (`assets/data/world_elevation.png`, ~10.4
   km/pixel — see `docs/concept/item_illustrations.md`'s sibling honesty
   about data limits, and `earth_elevation_source.gd`'s own encoding
   comment) is far too coarse to resolve an actual small river's course —
   Freiburg's own real ~278 m valley floor already reads as ~570–680 m in
   it, blended with the Black Forest hillside next door (measured live,
   see `test_world_spawn_location.gd`). A real named river a player should
   be able to recognize (the Dreisam at this game's own spawn point) can
   only be **curated data**, not derived from what's already bundled.
   Everywhere a curated river doesn't reach, a procedural fallback grounded
   in real elevation keeps the rest of the planet from being riverless.
2. **Grow the roster deliberately, starting with Germany.** One river
   (the Dreisam) is necessary for this game's own spawn point; the roster
   is designed to grow indefinitely, but ships starting with **Germany's
   major rivers** as the first real batch rather than attempting global
   coverage in one pass. See Roster below.
3. **Rendered as a water overlay on real terrain, not a new ground biome.**
   A river doesn't turn the forest it cuts through into a different kind of
   ground — it's a blue ribbon threading through whatever land was already
   there. Mechanically and visually this reuses `EarthChunkManager`'s
   existing ocean water-overlay layer (shore-blend distance, ripple
   response to rain) rather than adding an eighth entry to
   `BiomeClassifier.KNOWN_BIOMES`. See Rendering below for why the
   alternative (a full peer biome) was rejected.
4. **Gameplay-scale width, not survey accuracy.** The real Dreisam is
   roughly 10–15 m wide. At this world's ~1 km/tile scale
   (`EarthChunkGenerator.TILES_PER_DEGREE`), a survey-accurate width would
   be a fraction of one tile — invisible and unwalkable-around in practice.
   Curated rivers carve a minimum width instead, calibrated in tiles, the
   same kind of deliberate real-scale compression this world already
   accepts elsewhere (a single tile already stands in for a ~1 km real
   area).

## Curated rivers: real named waterways

`src/world/river_catalog.gd` holds an ordered table of named rivers, each a
simplified real-world polyline (source → a handful of real via-points a
river actually passes through → mouth), gathered from real geographic
sources (Wikipedia infoboxes, Wikimedia Commons geo-tags, OpenStreetMap/
Nominatim — cross-checked against each other the same way this session
verified the Freiburg spawn point). "Simplified" is deliberate: a handful of
real waypoints per river, not a survey-grade centerline — consistent with
what "curated" means throughout this doc.

The core query, `distance_to_nearest_river_tiles(tile_x, tile_y, world_width,
world_height)`, converts every waypoint to tile space with the same
`GeoCoordinates.tile_for_coordinate` this project already uses for every
other real-coordinate feature (Easter eggs, Bridgekeeper, the spawn point
itself), then takes the minimum point-to-segment distance across every
consecutive waypoint pair of every river — the same "distance in tile
space, not real spherical distance" tradeoff `GeoCoordinates.
tile_is_within_radius` already makes and documents.

### Roster (Germany first)

Phase 1 ships Germany's major rivers plus the Dreisam (small, but the one
this game's spawn point sits on, so it ships regardless of size):

Rhine, Danube, Elbe, Weser, Main, Mosel, Neckar, Oder, Spree, Isar, Dreisam.

**Explicitly deferred**: every other river on Earth. The catalog structure
places no limit on this — adding a river is adding one data entry — but
populating "all big rivers, worldwide" is real, ongoing curation work the
user has already signalled as the intended next phase, not attempted here.

## Width

`RiverCatalog.RIVER_HALF_WIDTH_TILES` is a tested constant, not an eyeballed
one: the requirement is a curated river reads as **at least 4 tiles wide**
in-game (real width would be sub-tile and effectively invisible at this
world's ~1 km/tile scale — see pillar 4), so half-width is set to clear that
total-width floor with the same tile-space distance query described above.
A cell within `RIVER_HALF_WIDTH_TILES` of any curated river's polyline
segment renders as river.

Real rivers taper — wide near the mouth, narrow near the source — but a
uniform width for this first pass is the honest MVP; real width-tapering
per waypoint is a plausible later refinement, not attempted here.

## Procedural fallback: reverted after playtesting (2026-08-29)

A true flow-accumulation network (tracing every upstream cell that drains
through a given point, the way `hydraulic_erosion.gd`'s droplet carver
works for the disused fictional-planet pipeline) is not feasible here: this
world is chunk-streamed at ~40,000 × 20,000 tiles with only nearby chunks
ever loaded (`docs/concept/world.md`), so there is no point at which a
global drainage pass could run, and a per-tile on-demand upstream walk
would be arbitrarily expensive (real rivers accumulate thousands of
upstream cells). `docs/concept/electromagnetism.md`'s own water-wheel
proposal already accepted this exact limit for flow SPEED specifically.

The chosen proxy (`src/world/procedural_river.gd`) was a **stylized
noise-contour heuristic**: a cell qualified as a procedural river candidate
when a seeded 2D noise field sampled at that real latitude/longitude sat
within a narrow band of a fixed iso-value, and the cell's real elevation
sat in a low-lying band. **Reported directly after real play: "the rivers
are scattered everywhere"** — measured, ~6% of tiles in a curated-river-free
region tested true via this proxy alone, and because each cell is an
independent per-tile test with no connectivity guarantee, that 6% reads as
disconnected patches with no relationship to real geography, not "one
coherent stream" the way a curated, GPS-traced river does — the opposite of
what "can we do rivers next" was asking for.

`is_river_at_global` is now **curated-only** — the procedural module stays
real, tested, and intact (a future connectivity-aware redesign, e.g. a
real accumulation pass over a bounded region rather than per-tile noise,
could reuse it), but nothing calls it live. Everywhere on Earth without a
curated river is simply riverless, the honest tradeoff for "the rivers you
see are real, named, and shaped like a real river," which is what was
actually asked for.

**The connectivity-aware redesign exists as of 2026-09-03, gated off:**
[hydrology.md](hydrology.md) runs a real priority-flood + flow-accumulation
pass over the elevation asset's own grid *offline, once* (the "no point at
which a global drainage pass could run" objection above is answered by not
running it live), ships the result as data, and hands baked channels to
this doc's flow overlay and Manning solve through
`EarthChunkGenerator.nearest_river_at` in the catalog's own shape. It sat
behind `EarthChunkGenerator.HYDROLOGY_RIVERS_ENABLED` until the real bake
had been run; the same day the bake ranked the Loire and the Gironde as
western France's strongest channels, the flag went on and the spawn moved
onto the Loire at Nantes (an emergent river, no curated course near it).
Curated rivers remain authoritative wherever they reach.

## Rendering: overlay, not a new biome

`TerrainRenderer` already has an extensive corner/edge blend system keyed
off `BiomeClassifier.KNOWN_BIOMES` (`BLEND_PRIORITY`, per-pair corner art) —
adding an eighth biome there multiplies that system's already-combinatorial
blend-tile generation and risks regressing tests built around the current
7-biome roster, for a payoff (a river rendered as its own ground texture,
with its own land-blend art against all 7 other biomes) that doesn't even
match how a river actually looks: a river cutting through grassland doesn't
turn the grassland into a different ground texture at the edges, it's water
laid over the top.

So: **a river cell keeps whatever biome `BiomeClassifier` already assigned
it** (forest, grassland, whatever the real elevation/temperature/moisture
say) — rivers never touch `classify()` or `KNOWN_BIOMES` at all. A new
`EarthChunkGenerator.is_river_at_global(global_x, global_y)` query (curated
catalog OR procedural fallback) is consulted only by
`EarthChunkManager._paint_water_overlay`, generalized from "mark every
`ocean` cell on the water overlay layer" to "mark every `ocean` cell **or
river cell**" — reusing the existing shore-blend-distance/ripple-response
shader machinery ocean already has, unmodified. The visual result: a blue,
shore-blended, rain-rippling ribbon threading over the real ground texture
underneath, exactly like a real river does.

## Flow: real direction and speed, with turbulence (2026-08-29, updated)

Reported directly: "rivers should flow" — a river read as visually
identical to still ocean, since `_paint_water_overlay` treats every water
cell alike. `EarthChunkManager._paint_river_flow_overlay` adds a SECOND,
SPARSE overlay layer (`RiverFlowFx`, painted only where `is_river_at_global`
is true — everywhere else stays empty/transparent, unlike the water/
hillshade overlays which paint every loaded cell) carrying each river
cell's real downhill direction (`TerrainRelief.
aspect_degrees_from_gradient` — "the direction water would actually flow",
by that function's own doc comment, the SAME real elevation-gradient
primitive hillshading already samples). `RiverFlowShader` reads that
direction and animates a translucent, directional streak pattern scrolling
downstream over the base water color, the same "bake data into a small
quantized tile atlas, animate continuously on the GPU from a live/derived
uniform" shape hillshade's slope/aspect overlay already established
(`ProceduralRiverFlowSprite`, now a 2D `DIRECTION_BINS x SPEED_BINS` atlas).

This is `docs/concept/electromagnetism.md`'s own long-standing, previously-
unvalidated water-wheel proposal ("flow speed is derived from the water
tile's own local elevation gradient") **built**: both direction AND speed
are now real and driving a real visual.

**Speed, added after "can you implement more natural water flow" feedback**
(a uniform speed everywhere read as mechanical, not like water actually
responding to the terrain it runs through): `RiverFlowShader.
speed_fraction_for_slope_deg` maps the SAME real gradient's magnitude
(`TerrainRelief.slope_degrees_from_gradient` — already sampled for
direction, so this is nearly free) to a `[0,1]` fraction between
`MIN_FLOW_SPEED` and `MAX_FLOW_SPEED`, anchored at `TerrainPassability.
HARD_THRESHOLD_DEG` — the same real "genuine scrambling/technical-climbing"
steepness `BiomeClassifier.SLOPE_MOUNTAIN_THRESHOLD_DEG` already reuses for
a different purpose, rather than inventing a second, independently-
eyeballed cap. A steep mountain stretch now visibly rushes; a flat lowland
stretch visibly ambles. Discharge/channel-width data still isn't curated,
so this is real GRADIENT-driven variation, not a claim of hydraulically
exact current speed — the water wheel MECHANIC itself (torque, power
generation) remains unbuilt; only the visual half of that doc's proposal
is validated here.

**Turbulence**, added the same pass: two octaves of scrolling value noise
(the exact technique `water_shader.gd`'s own wind-shimmer already proves)
perturb the streak phase itself, so bands waver and drift rather than
reading as a perfectly rigid scrolling barcode — real flowing water is
never that mechanically regular. Purely cosmetic (like the wind-shimmer it
borrows the technique from), so it has no CPU mirror — only the periodic-
streak physics another caller might reason about does
(`RiverFlowShader.streak_intensity`, now taking an explicit `flow_speed`
argument instead of a shared constant, since speed is no longer uniform).

## Flow overlay invisible in live play: a z-order bug, not a shader bug (2026-08-30)

Reported directly, the day after Flow shipped: "the flow animations [aren't]
visibly working." Live play showed a dark, grooved, tile-boundary-aligned
static pattern over rivers instead of the pale, glinting streak pattern
`RiverFlowShader.SHADER_CODE` describes — unmoving across two screenshots
~7 seconds apart, while a nearby, unrelated rain-ripple effect visibly
changed in the same two screenshots, proving the game clock genuinely
advanced and this specific pattern was still real, not a too-fast-to-see
motion artifact.

Everything upstream of rendering checked out on inspection, and each was
then confirmed rather than assumed: `EarthChunkGenerator.is_river_at_global`
correctly classifies the spawn tile; `EarthChunkManager.set_river_flow_layer`/
`_paint_river_flow_overlay` wire a real tile_set and the shared
`ShaderMaterial` onto a real `$RiverFlowFx` `TileMapLayer` exactly as
designed; and the atlas itself already had dedicated pixel-level tests
(`test_procedural_river_flow_sprite.gd`, `test_terrain_renderer.gd`'s
river-flow atlas tests) proving it carries real, non-flat (direction, speed)
data, not a blank fill. None of that was the bug.

**The actual cause was in `scenes/world.tscn`, not in any `.gd` file.** Its
five ground-effects layers share draw order rules: `Terrain` is `z_index=-2`,
and `WaterFx`/`RiverFlowFx`/`SnowFx`/`HillshadeFx` are all `z_index=-1` —
Godot breaks a `z_index` tie by scene-tree sibling order, later sibling on
top. `RiverFlowFx` had been inserted as a sibling *before* `SnowFx` and
`HillshadeFx`. `HillshadeShader` paints a near-black overlay (alpha up to
`MAX_SHADOW_ALPHA` = 0.55) over **every** loaded cell with no river
exclusion (2026-09-01 update: only on genuinely steep terrain now — see
`terrain_relief.md`'s "Hillshading" section — but river tiles themselves
still get no exclusion, and this z-order bug's own cause was never about
river tiles specifically) — already pinned by
`test_hillshade_overlay_paints_a_real_tile_for_every_loaded_cell` in
`test_earth_chunk_manager.gd`, this is intentional general behavior, not a
hillshade bug — so on any river tile with real slope/aspect, `HillshadeFx`'s
darker, higher-alpha, per-tile-quantized shading painted directly on top of
`RiverFlowFx`'s paler, more translucent (max alpha 0.35) streaks, visually
swamping them. **The dark, grooved, tile-boundary-aligned, unmoving pattern
actually seen in live play IS the hillshade overlay itself** — static
because the sun position advances slowly relative to a few seconds of play,
grooved/blocky because hillshade bakes one uniform slope/aspect value per
tile — not a separate pre-existing water texture, as first suspected from
the screenshots alone.

Confirmed with a real, headless-checkable regression test rather than by
eye or by live screenshot: `test_world_ground_layer_order.gd` loads the
actual `scenes/world.tscn` `PackedScene` (the file this game really ships)
and asserts `RiverFlowFx.get_index() > HillshadeFx.get_index()` (and
`> SnowFx.get_index()`). Run against the real committed scene file before
any fix, both assertions failed **red** at the real indices — `(2, 4)` and
`(2, 3)` — proving the z-order bug existed in the actual shipped scene, not
merely in theory.

Two other named hypotheses were checked with real evidence and ruled out,
not just reasoned past:
- **Shader compile failure.** `test_river_flow_render_smoke.gd` builds the
  exact `TileMapLayer` + `tile_set` + shared `ShaderMaterial` combination
  `scenes/world.gd` wires for real, adds it to a *live* `SceneTree`, and
  runs it for several real frames. No engine error or warning surfaced (GUT
  itself fails a test on an unhandled script error during a run, and none
  fired). Godot 4.7 does apply a `ShaderMaterial` via `TileMapLayer.material`
  the same way it would on any other `CanvasItem` — confirmed independently
  by the fact hillshade, wired through the identical `set_*_layer` pattern,
  visibly renders (that render IS the pattern actually seen in live play).
- **Atlas data wrong or blank.** Already covered by the existing
  `test_procedural_river_flow_sprite.gd` / `test_terrain_renderer.gd`
  pixel-level tests referenced above; not re-litigated here.
- **Missing per-frame trigger.** Not applicable — the shader animates
  purely from the live `TIME` uniform once a cell is painted; no per-frame
  CPU re-paint is needed for the streak pattern itself to move.
  `_paint_river_flow_overlay` only needs to re-run when a cell's underlying
  terrain data changes (chunk load), which it already does.

**The fix**: reorder `scenes/world.tscn` so `RiverFlowFx` is the *last*
`z_index=-1` sibling — after `SnowFx` and `HillshadeFx`, not before them —
so its streaks draw on top of whatever those two paint instead of being
occluded by it. No `.gd` file changed; this was purely a scene-file
draw-order bug.

**Live visual confirmation was attempted and blocked by the environment,
not skipped**: a real game process was launched for a live screenshot check,
but the interactive desktop session was locked at the OS level at the time
(confirmed directly — a screen capture of the game window's own rect
returned the Windows lock screen, not the game), so no window could be
brought to the foreground or captured regardless of process/focus tricks.
The process was killed rather than left running blind. The fix's evidence
is therefore the real, headless-checkable regression test above (which
reproduces the exact z-order bug against the actual shipped scene file and
now passes against the fixed one) plus the two ruled-out-with-evidence
hypotheses, not a live screenshot.

## Flow effect made more visible (2026-08-30)

Reported directly, after the z-order fix above made the streaks actually
reach the screen: "make the flow effect more visible" — it still read as a
subtle, easy-to-miss glint rather than obviously flowing water. Two real,
measured causes, not a single "raise the alpha" guess:

1. `STREAK_ALPHA` = 0.35 was faint even in isolation, and — per the z-order
   fix above — now sits directly on top of a `HillshadeFx` overlay that can
   paint up to alpha 0.55 of near-black on the very same river tile
   (`HillshadeShader.MAX_SHADOW_ALPHA`). The streak needs enough contrast to
   punch through that darkening, not just be visible against a blank
   background.
2. `STREAK_SHARPNESS` = 4.0 raises a clamped sine to the 4th power, which
   (by the closed form `(pi - 2*asin(0.5^(1/n))) / (2*pi)` for the fraction
   of one period where `pow(max(sin(phase*TAU),0), n) > 0.5`) keeps the
   bright part of each cycle to only ~18.2% of the period — a thin, sparse
   band rather than a current that visibly covers the water's surface at any
   given instant.

**Headless measurement (primary evidence).** `streak_intensity()` (the
existing CPU mirror of the shader's exact periodic-streak math) was swept
across a dense grid — 5,000 positions spanning 500 world units, at 6
distinct time instants (30,000 samples per configuration) — comparing the
prior shipped constants (`eae510d`: alpha 0.35, sharpness 4.0) against the
new ones, both at the real `MAX_FLOW_SPEED` and `STREAK_FREQUENCY`:

| metric | OLD (0.35 / 4.0) | NEW (0.5 / 2.0) |
|---|---|---|
| mean raw streak intensity | 0.1875 | 0.2500 |
| bright duty fraction (intensity > 0.5) | 18.4% | 24.8% |
| mean effective on-screen alpha (intensity × `STREAK_ALPHA`) | 0.0656 | 0.1250 |
| peak effective on-screen alpha | 0.35 | 0.50 |
| fraction of surface with effective alpha > 0.1 | 24.0% | 35.2% |

The combined change makes the streak field cover a measurably wider slice of
the river at any instant (bright duty fraction up ~35% relative) at
measurably higher contrast (peak alpha up ~43% relative), for an effective
on-screen opacity that is nearly double (mean effective alpha 0.0656 →
0.1250) — a real, quantified "more visible," not an eyeballed adjustment.

**The three changes, each reasoned against this codebase's own precedent:**

- `STREAK_ALPHA`: 0.35 → **0.5**. Placed with real reasoning relative to
  this project's own existing overlay-alpha ceilings, not picked in a
  vacuum: still below `HillshadeShader.MAX_SHADOW_ALPHA` (0.55, the very
  overlay it now needs to be visible against) and below
  `WaterShader.WATER_ALPHA` (0.6, the base water tile itself) — a sparse,
  pulsing highlight must stay under both, never becoming the dominant layer
  in the stack. Regression-tested (`test_streak_alpha_stays_under_this_
  projects_own_overlay_alpha_precedents`).
- `STREAK_SHARPNESS`: 4.0 → **2.0**. Halving it broadens the bright duty
  fraction from a derived ~18.2% to a measured ~25% of the period —
  comfortably clear of a 22% floor, while staying well under a 45% ceiling
  so it still reads as a periodic streak rather than dissolving into a flat,
  motionless tint. Regression-tested
  (`test_streak_bright_duty_fraction_is_measurably_broader_than_the_prior_sharpness`).
- `STREAK_COLOR`: `(0.75, 0.88, 1.0)` → **`(0.85, 0.94, 1.0)`**. A second,
  alpha-independent lever: `COLOR = vec4(streak_color, streak*streak_alpha)`
  blends toward whatever sits underneath, so brightening the source color
  (red/green raised toward the already-maxed blue channel) lands lighter at
  the same alpha — the effect that matters most on top of a near-black
  hillshade tile. Every channel stays within [0.7, 1.0] (pale, not
  saturated/neon) and blue remains the dominant channel — a water highlight,
  not a warm tint. Regression-tested (`test_streak_color_was_brightened_
  without_turning_saturated_or_neon`).

All three land in `src/rendering/river_flow_shader.gd`
(`STREAK_ALPHA`/`STREAK_SHARPNESS`/`STREAK_COLOR`), covered by
`tests/unit/test_river_flow_shader.gd`. A real headless viewport-rendering
attempt (`ShaderMaterial` on a `TextureRect` in a `SubViewport`, read back
via `get_texture().get_image()`) was tried first and abandoned immediately
after one clean, conclusive failure — Godot's `--headless` mode runs the
dummy rendering driver with no real GPU/software rasterizer, so
`texture_2d_get` errors on a null backing texture rather than producing
real pixels; the CPU-mirror sweep above is this project's own
already-established, explicitly-sanctioned fallback for exactly this case
(see `RiverFlowShader.streak_intensity`'s own doc comment). Live in-game
screenshot verification was not attempted for this pass, consistent with
the environment's well-documented desktop-lock/window-focus unreliability
noted in the z-order fix above — the headless measurement is the real
evidence this change rests on.

## Real hydraulics: volume, pressure, current speed (2026-08-30)

Reported directly: *"implement real water flow with volume pressure current
speed"*. Before this, the three quantities were either invented or absent —
depth was an authored linear taper from a 2.5 m centreline maximum (a number
chosen so a river would straddle the wading/swimming threshold, not derived
from anything), current speed was faked from local slope alone, and pressure
did not exist. Three independent inventions that could not have agreed with
each other even in principle, because in real water they are **not
independent**: continuity (`Q = A·v`) binds them.

### Why this is feasible here at all

A real flow model normally needs the upstream catchment — the Rhine at
Cologne drains ~185,000 km², thousands of chunks, none of them loaded. This
doc's own "Procedural fallback" section already established that no global
pass can ever run on this world. So a locally-integrated water volume would
be **a lie dressed as physics**.

The escape is the same one pillar 1 already uses for the courses: **curate
the thing that can't be derived, derive everything else locally.**
`river_discharge.gd` carries real published mean discharge (MQ) per river
from German gauging-station data — the Danube's 6,452 m³/s down to the
Dreisam's 10.86 — and interpolates it along the course, because real
discharge grows source-to-mouth as drainage accumulates. Everything else is
then a local, closed-form solve.

### The model (`open_channel_flow.gd`)

Real open-channel hydraulics, the formulas civil engineers actually use:

- **Manning's equation** `V = (1/n)·R^(2/3)·S^(1/2)` for velocity (USGS WSP
  1849 p.7 for the SI form; FHWA HDS-4 Metric eq. 13 for the units).
- **Continuity** `Q = A·v` — which is what makes depth and speed one answer
  rather than two.
- **Normal depth**, closed form: `h = (n·q/√S)^(3/5)`, `q = Q/b`. Closed form
  matters: the naive way to satisfy Manning and continuity together is to
  iterate to a fixed point, and this solves it in one step — which is what
  makes real hydraulics affordable per-tile.
- **Hydrostatic pressure** `p = ρgh`, and **force on a dam face**
  `F = ½ρgh²b` (note the square — doubling pooled depth *quadruples* the
  load; that is the physical basis of dam failure, not an invented threshold).
- **Weir overtopping** `Q = 1.4407·b·h^1.5` for a broad-crested stone crest
  (Zachoval et al. 2014), with the real ~0.06 m surface-tension floor below
  which the equation stops holding.

**The correction that mattered most**, and which a naive implementation gets
wrong: standard Manning roughness tables are measured on *low-gradient*
channels and badly understate resistance in steep ones. Yochum et al. 2012
measured average `n = 0.18` across 15 Colorado reaches at 1.5–20% slope —
3–20× the textbook "mountain stream" value — and state plainly that using
table `n` there yields *"substantially overestimated flow velocities."* So
the module uses a table value only below 0.2% slope and **Jarrett's (1984)**
measured steep-channel relation above it.

### Two traps this had to avoid

1. **Rendered width is not real width.** `RIVER_HALF_WIDTH_TILES` draws a
   river 4 tiles across — at ~1 km/tile, a 4 km-wide Dreisam (a deliberate
   visibility compression, pillar 4). Feeding that into continuity would put
   current speed out by ~3 orders of magnitude. Real channel width is
   separate data: curated where a real published width exists (5 rivers),
   derived by hydraulic geometry (`w ∝ √Q`, coefficient fitted to those real
   widths) everywhere else.
2. **Slope is a tangent, not an angle.** Manning's `S` is dimensionless
   rise/run; feeding degrees in directly would be a unit error of ~57×.

### What it produces, checked against reality

Validated against real gauged reaches rather than self-consistency:
Manning reproduces the USGS-measured velocities at Columbia River/Vernita
(2.49–2.64 m/s) and Beaver Kill/Cooks Falls (2.78–2.96 m/s), and the
course-discharge model lands near 9 real gauging stations.

The behaviour that falls out is right: **flat reaches run deep and slow,
steep reaches shallow and fast** — continuity doing its job. The Spree in
Berlin solves to ~2.8 m against its real published 2–3 m. The Dreisam at the
spawn point solves to ~0.31 m at 0.71 m/s on its real 4% Black Forest
gradient — a wadeable mountain stream, which is what the real Dreisam is and
why a town grew at that crossing.

That last one **changed existing behaviour honestly**: the player used to
swim at spawn, because the authored 2.5 m taper said so. Real physics says
wade. The test that pinned "swimming" was pinning an invention, and now pins
the real claim (you are in real water) with the swim path proved separately
against the Rhine.

### Honest limits

- Discharge is **mean** flow. No flood/drought variation, no rainfall
  coupling — `weather_model.gd` has no rain-intensity scalar and its
  precipitation is a flat per-region dice roll, so runoff-fed volume would be
  building on a known-fake field. The real MNQ/MHQ extremes are known and
  curated nowhere yet.
- Width for small rivers is **extrapolated**, not verified — every real
  published width in the calibration set is a large river, and no width was
  published for any small one to check against.
- Depth on very flat lower courses runs somewhat deep (Rhine ~11 m vs a real
  ~9 m) because slope hits the model's floor there.

## Dams: building one from stones (2026-08-30)

Reported directly: *"i want to be able to build a dam from stones"*. Now
that the hydraulics are real (above), a dam is real physics rather than a
special case — the weir equation, hydrostatic force and sliding friction
were all already needed, so the dam mostly *consumes* physics that exists.

### The piece

`stone_dam` is a **`BuildingPiece`** (new `CATEGORY_DAM`), not a
`"placeable"` structure like a campfire. A piece gets, for free: collision,
tile-atlas registration, persistence in `chunk.modifications`,
boulder-respawn suppression, participation in the connected-structure flood
fill, and material drop-back on collapse. A placeable gets none of those,
and a dam wants all of them.

The item id and the piece id are **deliberately the same string**.
`build_at_global` writes whatever id it is handed, so one string means the
existing placeable-arming path places it *and* `BuildingPiece.has_piece`
lights up collision/atlas/persistence — no new plumbing on either side, and
`_destroy_step` refunds it because the catalog knows the id.

It costs `rock` (6), **not** `stone`: rock is what picking up a pebble and
smashing a boulder both yield, so damming a stream needs only what its own
banks offer, whereas `stone` is the *mined* output and would gate dams
behind a pickaxe for no good reason. No skill or structure gate either —
heaping rock across a shallow stream is the least technological
construction there is.

`support_capacity` is 0, keeping it out of `BuildingStatics`' span solver: a
dam holds back water, not a roof, and a run of them across a channel must
never be mistaken for an unsupported cantilever and collapsed. Its real
failure mode is hydraulic instead (below).

### The impoundment is derived, never stored

Water pools behind a dam at **steady state**: the pool rises until what
spills over the crest equals what the river brings in, and that balance is
closed-form from the weir equation
(`OpenChannelFlow.equilibrium_weir_head_m`). So the pool depth is
`crest height + equilibrium head`, computed on demand.

Nothing about the pool is stored. It is re-derived every time from the dam's
presence in `chunk.modifications` (which already persists), the river's real
curated discharge, and the real terrain. That is what lets an impoundment
survive a chunk unload, cross a chunk seam, and need no catch-up
integration — it is a pure function of state that already persists. It also
means destroying the dam releases the pool immediately and correctly, with
no cleanup code.

**Deliberately not modelled: the transient fill.** A real reservoir takes
time to fill. Modelling that would need per-dam stored volume, unloaded-chunk
catch-up, and cross-seam bookkeeping — the exact apparatus the steady-state
formulation avoids entirely — in exchange for a few seconds of one-off
animation. Not attempted.

### The one honest compression

A real 1.2 m hand-built check dam ponds water some *tens of metres*
upstream. At this world's ~1 km/tile that is a few hundredths of one tile —
and on the Dreisam's real 4% gradient at the spawn point, one tile upstream
is already ~40 m above the dam, so a physically literal pool **could never
reach even the next cell**. It would be invisible.

So the pool's **extent** is compressed (`MAX_BACKWATER_TILES`, tapering by
`backwater_falloff`) while its **depth stays real**, straight from the weir
equation and the river's real discharge. This is the same trade pillar 4
already makes for channel width — a real ~15 m Dreisam is drawn 4 km wide,
because a survey-accurate river would be sub-pixel. Stated plainly here
rather than buried, because it is the one place the dam stops being literal
physics.

### Failure is derived, not a threshold

Dry-stacked stone fails by **sliding**, when the water's push beats the
friction holding the stone down:

```
push       = ½·ρ_water·g·h²·b        (hydrostatic force)
resistance = μ·ρ_stone·g·H·t·b       (friction × weight)
```

The dam's own width `b` cancels, leaving a pure depth limit
`h_max = √(2·μ·ρ_stone·H·t / ρ_water)` ≈ **1.66 m** for a 1.2 m dam of
loose stone. Because the push goes as depth **squared** while resistance is
fixed, this is a genuine threshold rather than gradual weakening — which is
why a dam that has held for ages gives way suddenly when the water rises a
little further. Real constants throughout (loose-stone bulk density
~1600 kg/m³ at 20–40% voids; μ = 0.6 rock-on-rock).

## Art direction: stylized, not realistic (2026-08-30) — SUPERSEDED

> **This direction was tried and reversed the same day.** It is kept
> because the reversal is the instructive part; see "Art direction:
> back to realism" at the end of this document for what is live now.
> Everything below describes a state the code is no longer in — with one
> exception, the channel cross-section, which survived and is still live.

Requested directly, after seeing the realistic version in play: make the
water read like flat cel-animated cartoon water instead. **This supersedes
the realism goal**, and the reason is worth stating because it was learned
the hard way over several passes:

**Realism is the wrong target for this canvas.** At 16 px, top-down, in a
game whose art already commits to chunky shapes, hard outlines and a small
palette, every soft gradient and noise field fights the surrounding art
rather than adding to it. The realistic water kept disappointing not
because the physics was wrong — it is real and stays — but because
photoreal shading and pixel art are pulling in opposite directions.

So the shader's rules are now deliberate **negatives** as much as positives:

| Excluded | Why |
|---|---|
| Gradients | Colour comes from a small set of flat bands, chosen hard |
| Noise | Not a single hash or noise call remains in the shader |
| Soft edges | Every boundary is a `step()`, never a `smoothstep()` |

and positively: a flat body colour quantised by real depth, one bold darker
outline at the bank, and crisp white wave lines scrolling downstream.

**The simulation still drives all of it** — this is a restyle of the
OUTPUT, not a retreat from the physics:

- the **flat colour band** comes from the real solved depth *including dam
  ponding*, so damming a river visibly darkens it
- the **band thresholds are the movement thresholds** —
  `WaterMovementModel.WADE_DEPTH_METERS` itself is the shallow/mid boundary,
  so the colour tells you whether you can wade across or must swim, and what
  the player sees can never disagree with what the player can do
- the **wave lines** follow the real flow direction along the real course
  phase, and a **second line** appears on genuinely fast reaches
- the **bank outline** comes from the cross-channel distance
  `nearest_river_at` already computed and previously discarded — so it costs
  no new geometry work at all

The layer is **opaque**, unlike this project's other overlays. That is a
deliberate departure: `WaterShader`/`HillshadeShader` stay translucent
because they decorate what is beneath, but this layer *is* the river's
surface, and the base water under it is full of exactly the noise and
gradients this direction excludes. A translucent stylized layer over a
noisy realistic one would read as neither.

The continuous phase field from the previous pass is **retained and still
load-bearing** — hard-edged lines make a phase discontinuity *more*
obvious, not less, so without it the wave lines would visibly break at
every tile edge.

Atlas: (phase 12 × direction 16 × style 12) = 2304 tiles in a 2D grid. The
style dimension packs depth band, fast flag and bank flag together — all
three must be atlas dimensions, because a TileMapLayer cell can only select
a tile and there is no per-cell uniform; packing them into one index keeps
that a single dimension rather than three.

**Lava** was raised in the same request and deliberately deferred: none
exists anywhere in the game today, so it is net-new content (a biome or
hazard, with placement and damage) rather than a restyle.

### Iteration from real screenshots (2026-08-30)

The stylized look took two corrective passes, both driven by seeing it in
the running game rather than by reasoning about it. Recording them because
the same root cause produced both:

**Root cause: designing for a 16 px tile while forgetting the camera zoom
makes each tile tens of screen pixels.** Everything called "thin" was huge.

1. **Wave lines ran unbroken across the whole channel** — bounded only
   along the flow, so each mark became a continuous diagonal band reading
   as hazard tape. Fixed by bounding marks on *both* axes into short
   dashes, with alternate rows brick-offset so they never form a grid.
2. **The bank outline was a solid dark block** — bank-ness is decided per
   *tile*, so a near-black outline colour filled whole tiles, ate half a
   four-tile channel, and made a navy staircase. Removed entirely.
3. **The river was still a flat slab of one colour**, with no sense of
   being a channel. Fixed by drawing its real **cross-section**.

The cross-section is the change that mattered most, and it is real physics
rather than decoration: a natural riverbed is roughly **parabolic**,
deepest mid-stream and shallowing to each bank
(`OpenChannelFlow.cross_channel_depth_fraction`). Manning's normal-depth
solve gives the channel's *mean* depth, so the profile is what turns that
one number into a shape — scaled so the section's own mean still equals the
solved mean depth, rather than silently adding water.

Rendered as five flat bands from light at the edge to dark at the
centreline. Because the bands follow distance from the centreline, they
**curve with the river**, which is what makes it read as a channel. Banded
by cross-channel *fraction* rather than absolute metres, so a small stream
shows structure too — an absolute scale would paint the whole Dreisam
(0.31 m mean) a single colour and put the flat slab straight back.

## Flow rendering: the phase-field rewrite (2026-08-30) — SUPERSEDED

> **`river_phase_field.gd` no longer exists.** Defects 2 and 3 below are
> still fixed, by the same reasoning, in the advection shader that replaced
> this one. Defect 1's fix — a baked per-tile phase — became *actively
> harmful* under advection and was deleted; see "Art direction: back to
> realism" for why. The analysis is kept because the arithmetic is what
> makes the current design's constraints non-negotiable.



Reported directly: *"overhaul the flow shader and animations they should
look realistic and natural"*. The old streak shader read as "a tilemap with
a filter on it", and research into why turned up **three quantified
defects** — not matters of taste, but arithmetic. All three are now fixed
*by construction* rather than by tuning, which is why they cannot silently
come back.

### Defect 1 — the phase reset at every tile boundary (the dominant one)

The phase was `dot(world_pos, flow_dir)`: `world_pos` is absolute canvas
space (up to ~639,000 units across this world) and `flow_dir` was quantised
to 16 compass bins, constant per tile. At any tile edge where the bearing
changed bin, the chord between the two directions is `2·sin(11.25°) = 0.390`,
so the phase differed by

```
639,000 × 0.390 × 0.12 ≈ 30,000 cycles
```

which, wrapped by the sine, is a **uniformly random phase reset** at that
edge. Adjacent river cells routinely land in different bins, so the pattern
restarted on a 16 px lattice — and that lattice *is* the tilemap, made
visible. It was the single biggest reason the water looked artificial.

**The fix** (`river_phase_field.gd`): bake a continuous phase potential
along each river's own course instead. Two cells' baked phase now differ by
exactly the number of streak cycles between them, so the bands are one
ribbon following the channel with no basis to disagree at an edge. The
phase is quantised to 12 bins, capping the worst residual seam at 1/24 of a
cycle (15° of the sine) — versus an arbitrary reset before.

### Defect 2 — fast rivers aliased and flowed backwards

The phase's time term was `TIME · flow_speed · streak_frequency`, giving
`32 × 0.12 = 3.84 Hz` at top speed. At this game's measured ~7 fps floor
that is **0.549 cycles/frame — past the 0.5 Nyquist limit**, so the
fundamental reversed: the fastest rivers visibly flowed *upstream*. The
parameter carrying "this water is fast" was the one broken hardest by speed.

**The fix**: one global temporal rate everywhere
(`STREAK_RATE_HZ = 0.75`, i.e. 0.107 cycles/frame at 7 fps, with headroom
for the streak's own harmonics). Speed no longer appears in the time term
at all, which makes aliasing impossible at any speed rather than merely
unlikely — pinned by a test that asserts it against the worst measured
frame rate.

### Defect 3 — turbulence was scrambling the bands, not wavering them

The old field displaced the phase by ±15 world units against an 8.33-unit
wavelength: **±1.8 wavelengths**. Past ~1/(2π) the iso-phase map folds back
on itself, so the bands were being decorrelated rather than bent. The old
code's own comment claimed the displacement was "small enough that streaks
still read as flowing roughly downstream"; the arithmetic said otherwise.
A second octave sat at ~1.5× the streak's own frequency, shredding the very
pattern it was meant to perturb, for four extra `sin()` per fragment.

**The fix**: turbulence is now expressed as a **fraction of a wavelength**
(0.22), which makes the error impossible to reintroduce by accident, and
uses one octave instead of two.

### What speed reads as now

Because one global wavelength and rate is what buys defects 1 and 2, speed
can no longer drive the streak *geometry*. It drives **contrast** and
**whitewater** instead, which is the more legible cue at 16 px anyway.

Honest note on the foam: real whitewater tracks flow **deceleration**, not
speed — a uniformly fast chute is glassy and green, and it is the hydraulic
jump where fast meets slow that goes white. Computing that needs an
upstream sample this pass does not carry, so what ships is the cheap proxy:
broken speckle on the fastest reaches, hash-quantised to the art-pixel grid
so it sits still against nearest-filtered ground instead of crawling.
Deceleration-driven foam is the named refinement.

### Data layout

The overlay tile's four channels each earn their place: **R** the wrapped
course phase, **G/B** the flow direction as a unit *vector* (not a bearing —
which saves a `radians`/`sin`/`cos` per fragment and removes the 0°/360°
wrap hazard entirely), **A** the speed fraction — which now comes from the
**real solved current velocity** (see "Real hydraulics" above) rather than
the old slope proxy.

The atlas is keyed on (phase × direction × speed) = 12 × 16 × 4 = 768 tiles,
laid out as a **2D grid**: a single row would be 24,576 px wide, past the
16,384 `GL_MAX_TEXTURE_SIZE` common on the integrated GPUs this game
targets — it would simply fail to upload. Measured cost: a 1024×768 atlas
built in **9 ms**, so the boot-time worry did not materialise.

Verified by a real GPU compile check (`test_river_flow_render_smoke.gd`
builds the exact live TileMapLayer + material + tile-set combination and
runs it several frames), not only by unit tests on the uniforms.

## Player interaction: wading, swimming, and the submersion tint

`Player._resolve_water_state` originally only checked real elevation-
below-sea-level (`BiomeClassifier.depth_at`), which every river tile fails
by construction (a river never changes `biome_at_global`'s own elevation-
derived result, per Rendering above) — so a player could walk straight
through a river with no wading/swimming, no submersion tint
(`SubmersionShader`, already fully built and wired for ocean via
`character_view.gd` before this doc existed), and no water-disturbance
ripples at all. Reported directly alongside the flow request: "char should
be tinted for underwater."

`river_depth.gd` gives rivers a real (if not survey-accurate) depth:
curated rivers deepen toward their own centerline using the exact same
`distance_to_nearest_river_tiles` the width band already computes (0 at
the centerline's real deepest point, shallowing to 0 m at
`RIVER_HALF_WIDTH_TILES`), calibrated so the range spans both
`WaterMovementModel.WADE_DEPTH_METERS`'s wading band AND real swimming
depth — a wide curated river genuinely offers a wadeable bank and a
swimmable middle, not just one or the other. (`RiverDepth.
PROCEDURAL_RIVER_DEPTH_METERS` still exists for a flat, shallower "minor
stream" reading, but is now dead code in practice — the procedural
fallback it was paired with was reverted, see above.)
`_resolve_water_state` now takes `maxf(ocean_depth, river_depth)`, so nothing
about ocean's existing behavior changes. Once depth is real, the entire
pre-existing chain (`current_mode` → `CharacterView.MovementState.SWIMMING`
→ `SubmersionShader.set_waterline`) fires exactly as it already does for
ocean — no new tinting code was needed, only real river depth for the
existing mechanism to actually see.

## Decoration exclusion: trees, grass, and snow (2026-08-29)

Reported directly, alongside "the rivers are scattered everywhere": **"it's
still treated like normal biome... grass and trees grow in rivers and snow
falls on rivers."** This is the direct, predictable cost of Rendering's own
decision above (a river cell keeps its ordinary land biome) — every system
that decorates land from `chunk.biome` alone had no way to know a river was
there at all, since nothing in `chunk.biome` ever says so. Three real,
independent placement bugs, all the exact same shape as an existing one
this project had already hit and fixed once before for lakes
(`EarthChunkManager._can_root_at`'s own doc comment: "the first thing the
fix produced was trees standing in a lake") — now recurring for rivers
specifically, because rivers are a new water concept none of these systems
knew existed:

- **Worldgen tree placement** (`TreeRenderer.spawn_trees`) and **tall-grass
  seeding/spread** (`TallGrass`) both only ever received `chunk.biome` — a
  new `Chunk.is_river` field (populated once in `generate_chunk`, alongside
  `biome`/`elevation`/etc.) gives them something to exclude against without
  either needing its own live `EarthChunkGenerator` reference. Both checks
  are size-guarded so a `Chunk`/`TallGrass` built without ever setting
  `is_river` (every pre-existing test fixture) is treated as "no rivers"
  rather than an index error — additive, not a breaking signature change.
- **Seed-spread saplings** (`EarthChunkManager._can_root_at`) and **snow**
  (`EarthChunkManager._paint_snow_tile`) are both manager methods with
  direct access to `is_river_at_global` already, so each just gained one
  more excluding condition alongside their existing ocean check.

## What this pass touches, and what it deliberately doesn't

Touches:
- `_find_dry_land_spawn` (`scenes/world.gd`) excludes river tiles the same
  way it already excludes ocean, so a fresh spawn search can't land a
  player in a river.
- `Player._resolve_water_state` now consults real river depth (see above)
  — wading, swimming, the submersion tint, and water-disturbance ripples
  all now work in rivers, not just ocean.
- A real, animated flow-direction overlay (see Flow above).
- Worldgen tree placement, tall-grass seeding/spread, seed-spread saplings,
  and snow all exclude real river cells now (see Decoration exclusion
  above) — a river no longer grows a forest or a lawn or gathers a
  snowdrift through it.
- The procedural fallback is no longer live-wired (curated-only; see
  Procedural fallback above).

Deliberately deferred (named here so nothing pretends to be more finished
than it is, matching this project's usual practice):
- **Freshwater fishing** — `docs/concept/fishing.md` already scoped itself
  to "ocean-only... v1" pending exactly this system; wiring `FishRenderer`/
  population modelling to spawn in rivers too is real follow-up work, not
  attempted here.
- **Village water-avoidance** — `village_renderer.gd`'s dry-origin search
  doesn't yet know about the new `is_river_at_global` query; a village
  could still be placed straddling a river. Follow-up, not attempted here.
- **Creature water-depth awareness** — only `Player._resolve_water_state`
  was wired to real river depth; whatever the equivalent creature-side
  swim/depth logic is (fish population/kingfisher wading, animal swimming)
  was not audited or touched here.
- **The water wheel mechanic itself** (`docs/concept/electromagnetism.md`)
  — flow DIRECTION and real gradient-driven SPEED are both now real and
  visualized (see Flow above), but no torque/power-generation mechanic
  exists yet; still an open proposal for that half.
- **Boats, fords, ferries, bridges** (`docs/concept/transportation.md`,
  `docs/concept/infrastructure.md`) — unchanged; both docs already scope
  these as entirely unbuilt, and this pass adds the water they'd cross
  without adding any way to cross it.
- **Nix (Wasserfrau) spawn-gating on real water geometry**
  (`docs/concept/worldbosses.md`) — Nix is still reachable only via the
  debug `/spawn` console command; this pass does not wire the "river and
  lake water spirit" flavor text to any actual water-proximity check.
- **Lakes** — a freshwater body *above* sea level with no flow is a
  genuinely different shape (closed polygon, not a polyline) from
  everything above; not attempted here, and real-world lakes above sea
  level remain invisible to this world exactly as before this doc.
- **Already-spread saplings in an existing save** — the decoration
  exclusion stops FUTURE tree spread/worldgen placement from landing in a
  river; a `planted_trees` entry a save already persisted from before this
  fix is not retroactively swept. The deterministic map-generated forest
  itself isn't affected by this gap (it regenerates fresh from
  `generate_chunk`/`spawn_trees` on every chunk load, never persisted).

## Art direction: back to realism (2026-08-30)

Reported directly, of the stylized version above: *"but uts just some
moving strokes not realistic water flow"*. That is an accurate description
of what the shader did, and the reversal is on me — going stylized was my
own recommendation, offered after the realistic version disappointed, and
it made the water worse rather than better. Three separate reports of "not
realistic" preceded it.

**The failure was structural, not a matter of tuning.** A periodic shape
*translated* downstream can only ever read as marks sliding past a window,
however it is styled or timed — because real water does not translate. It
continuously **deforms**. No amount of adjusting a scrolling pattern's
wavelength, dash length or rate could have fixed that; the technique itself
was wrong for the thing being depicted.

### Two-phase flow-map advection

The standard solution to exactly this problem, and now the core of
`river_flow_shader.gd`:

1. The surface field is **dragged backward along the flow** by an amount
   that grows with each phase's age, so the water genuinely stretches as it
   moves rather than sliding rigidly.
2. Left alone that distortion would smear without bound, so **two phases
   run half a cycle apart** and are crossfaded, each resetting while the
   other carries the image. Distortion never exceeds half a cycle.
3. The crossfade weight is **triangular, peaking exactly when a phase
   resets** — so the phase being reset always has zero weight, and the
   reset is invisible. This is why **no repeating period is ever visible**,
   which a scrolling pattern cannot avoid by construction.

All three are pinned as tests (`test_the_crossfade_weight_is_zero_when_a_
phase_resets`, `test_advection_distortion_is_bounded_and_never_accumulates`,
`test_the_shader_samples_two_advected_phases`) rather than left to tuning,
and the suite was verified to genuinely fail when the technique is reverted
to a single translating phase.

### What survived the reversal, and what did not

**Survived: the channel cross-section.** It is real physics — a natural
riverbed is parabolic, deepest mid-stream — and it is what makes a river
read as a channel rather than a slab *in any style*. It is now a depth
**cue beneath a moving surface** rather than the whole look, so its five
bands sit closer together; hard banding would fight the water.

**Survived: opacity, and the simulation driving everything.** Depth band
still comes from the real solved depth including dam ponding; the fast flag
still comes from the real solved current.

**Did not survive: the "no noise, no gradients, no soft edges" rules.**
Those are exactly what a stylized look needs and exactly what realistic
moving water cannot do without.

**Did not survive: the baked per-tile phase channel** — and this is the
sharpest lesson of the reversal. Under the old streak pattern a baked phase
was load-bearing (see the superseded section above). Under advection it is
worse than useless: a per-tile offset applied to a **noise** field makes
the noise jump at every tile boundary, which would have put a grid of seams
straight across the river — the *same* tilemap-lattice artefact the phase
field was originally built to remove, reintroduced by keeping its fix.

World position already decorrelates every reach continuously and for free,
so the offset is simply gone, and with it `river_phase_field.gd` (deleted
rather than left as a module nothing calls).

**This paid for itself in performance too.** The phase was a 12-bin *atlas
dimension* — a TileMapLayer cell can only select an atlas tile, so every
baked dimension multiplies the tile count. Dropping it took the atlas from
**1920 tiles to 160**, a 12× cut in generation work and texture memory, on
a game already measured at ~7 fps. A dimension the shader does not read is
paid for in full and returns nothing.

Atlas now: (direction 16 × style 10) = 160 tiles, style packing depth band
and fast flag together.

### Aliasing, still non-negotiable

`ADVECT_RATE = 0.35 Hz` is 0.05 cycles/frame at the measured ~7 fps floor,
far inside the 0.5 Nyquist limit — the same constraint that made the old
shader's fastest rivers flow *backwards* (superseded Defect 2). Speed is
expressed as **surface contrast**, never as a faster time term, so it
cannot reintroduce aliasing no matter how fast a reach runs.

### Iteration from screenshots, round two (2026-08-30)

Three live reports against the advection shader, each fixed by measurement:

1. **"Still doesn't look lik water ... can you flowing lines that morph?"**
   The isotropic field read as a flat mosaic (surface swing 0.070 vs the
   depth banding's 0.26 -- the static banding was 3.7x stronger), and even
   made visible it would have been blobs. Now: contrast is pinned to at
   least match the depth profile's span, band edges are dithered off the
   tile grid, and the field is ANISOTROPIC -- compressed along the flow so
   features are ~8x longer downstream than wide. Streaklines: the lines
   come from the stretch, the morphing from the advection.
2. **Scale.** The first lines were ~14 tiles long and 2 wide -- correct
   technique, wrong scale, read as vast soft gradients. Feature size is now
   pinned in TILES (0.4 wide, ~3 long); note a tile is 32 world px, not 16.
   The drag is measured in the field's own feature lengths
   (`drag_in_feature_lengths`), after the stretch-order bug made 1.15 units
   come out as 0.18 features -- near-still water.
3. **"better but still no fluid like animation no turbulences streams
   flows."** Two causes. The flow DIRECTION was the terrain aspect --
   bilinear DEM gradient, visibly unrelated to the channel -- so lines ran
   diagonally across the river; it is now the course polyline's own
   downstream tangent (`course_bearing_deg`). And the lines were rigid:
   a uniformly-stretched field advected uniformly can only translate.
   Now a STANDING-EDDY field bends them -- anchored to the bed (unadvected
   coordinates), the way real boils shed by bedforms hold station while
   the water pours through (Jackson 1976), so the surface is continuously
   re-bent as it streams past and visibly deforms WHILE it travels. The
   old defect-3 fold lesson is re-applied as a measured no-fold test, and
   a lines-survive-the-warp test stops the turbulence being turned up
   until the field dissolves.

### The continuous cross-section and the smooth shoreline (2026-08-30)

Reported directly, of the advected version: *"still a lot of individual
squares ... soften / blend the shoreline and make water feel like real
fluid / flowing water"*. The squares had a STRUCTURAL cause no amount of
band-softening could fix: depth was a per-tile quantized band, so every
water tile broadcast one flat colour over its whole 32 px, and the
shoreline was the rectangle of whichever cells were painted.

**The fix: reconstruct, per fragment.** The atlas now bakes each tile
centre's **signed cross-channel offset** (R channel, ±1.4 half-widths in
32 bins), and the shader adds every fragment's own within-tile delta,
projected on the flow perpendicular, over the half-width:

```
frag_across = decode(R) + dot(fragment - tile_centre, flow_perp) / half_width
```

Depth is then a per-pixel quantity — `1 - across²`, the same real parabola
— shaded through a **continuous five-stop ramp** (no band index exists any
more, so there is nothing left to jump at a tile edge). The worst
tile-to-tile disagreement is one across-quantisation step (0.0875 of a
half-width), pinned by a both-sides-of-the-edge continuity test, versus
the full band a tile used to jump.

**The shoreline is now the real bank curve.** The water clips at
`|across| == 1` with a short feather (±0.08), so its outline is the smooth
analytic curve through the middles of tiles, not the tile grid. Three
things had to move together:

- the catalog reports `signed_across_tiles` — the perpendicular component
  of (tile − centreline), signed by bank side, whose rotation convention is
  pinned to the bearing's perp by a reconstruction-identity test
- the painter paints an **apron** (`RIVER_BANK_APRON_TILES` = 0.75 past the
  half-width): the bank curve runs through cells whose centres sit beyond
  it, and a fragment can only be clipped smooth if its cell was painted at
  all. Gated on euclidean distance, never on |signed| — past a course's
  endpoints the perpendicular component goes small while the distance does
  not
- the translucent base water overlay **no longer paints river cells**
  (ocean only): it was per-tile square water showing through under the
  smooth curve. The flow overlay is now the river's entire water surface,
  and past the bank the ground simply shows through

Atlas: direction 24 × across 32 × speed 2 = 1536 tiles. The 16-px world
tile (`TILE_SIZE`, the layer is scaled — NOT the 32 px art tile) is what
the reconstruction divides by, pinned against TerrainRenderer by test.

### World-anchored sampling, smoothed courses, round caps (2026-08-30)

Reported directly, of the continuous-reconstruction build: *"there are
still hard cuts / misalignments and the curve could be smoother"*, then
*"theres also a sharp alignment error in the straight part"*. Three causes,
each with its own fix:

1. **The pattern seams (the dominant one, including on straights).** The
   field was sampled in each tile's rotated channel frame
   (`along = dot(world, flow_dir)`), and a rotation about the WORLD ORIGIN
   moves a point by angle × its distance from the origin — thousands of
   tiles per direction bin out here. Two neighbouring tiles in different
   bins showed simply unrelated noise: a hard cut, firing even mid-straight
   whenever the course drifted past a bin edge. Now every sample is
   anchored at the fragment's own world position; the lines are oriented by
   **smearing** — a 9-tap line-integral-convolution stroke along the flow —
   so direction only steers offsets a fraction of a cell long. Pinned by a
   seam test at real world magnitudes (~25,000 noise cells out, where the
   old formulation exploded): a one-bin direction change may move the field
   by at most 0.06 mean. Direction bins 48 → 96 to shrink the last trace.
2. **The kinked curve.** The curated waypoints are city-to-city straight
   lines, so every vertex was a sharp corner the bank inherited. Courses
   are now Chaikin corner-cut (two global passes plus targeted cuts on any
   vertex still turning past 45°), endpoints pinned, length preserved
   within 6% (the Rhine gives up ~4% rounding its knee — the straight-line
   roster was already an underestimate of the real winding length).
3. **The junction patchwork.** Past a course's very tips the perpendicular
   component degenerates (shrinks while the real distance does not), which
   painted the region around every source and mouth — most visibly a
   tributary mouth mid-confluence — as ragged mid-channel water. The across
   offset is radial there now, capping each end in a clean semicircle.

### The comic / 16-bit pass (2026-08-30)

Requested directly: *"make it more comic like? / 16bit pixel art?"* -- and
this time stylization is safe, because the thing that killed the FIRST
stylized attempt was never the flat colours: it was the translating
pattern underneath them. This pass quantizes ONLY the presentation; every
physical quantity (per-fragment reconstruction, advection, standing
turbulence, the bank curve) is untouched underneath it.

- **Cel posterization**: one continuous shade (reconstructed depth pushed
  around by the advecting surface) quantized into 6 flat levels. The cel
  boundaries ride the moving field, so they wobble and morph like
  hand-animated water -- and can never fall along the tile grid, because
  everything upstream of the quantizer is continuous and world-anchored.
- **Art-pixel snapping**: all sampling starts from the position snapped to
  one ART pixel (TILE_SIZE / ART_TILE_SIZE world px, pinned against
  TerrainRenderer) -- no gradient is ever smoother than the surrounding
  sprite art's own pixels.
- **Ordered dither**: the 2x2 checker phase shifts the quantization
  threshold half a step, weaving band boundaries the classic 16-bit way.
- **Comic ink line**: a dark outline hugging the real bank curve, a few
  art pixels wide. The old stylized attempt drew its outline per TILE and
  it became a black block; this one is a function of the reconstructed
  |across|, exactly as smooth as the shoreline.
- **Punchier palette**: the five ramp stops go saturated-ink rather than
  atmospheric grey, same shallow-to-deep order, same pinned darkening.

SURFACE_CONTRAST changes meaning with this pass: it now works in SHADE
units (the quantizer input), pinned so the surface's real p05..p95 swing
can drive the shade across the WHOLE palette -- the same
surface-vs-static-structure relation as before, in the new units.

### Strokes, not shading (2026-08-30)

Reported directly, of the cel pass: *"still looks like a gas animation and
not stylized illustrated smooth lines morphing 16bit"*. The diagnosis is
exact — when EVERY fragment shades with the moving field, the picture is
amorphous drifting patches: vapour. Illustrated water is the opposite:

- **The body is STATIC** — flat cels of pure reconstructed depth, dithered
  at their (static) boundaries. No field term in the body shade at all.
- **All motion lives in drawn WAVE STROKES**: each stroke is a CONTOUR
  (level set) of the smooth advected field -- PERIODIC contours at every
  one of LINE_COUNT evenly spaced levels (two fixed levels left most of
  the channel blank: "most of the stream doesnt show any currents"), with
  a transect test capping the longest strokeless stretch. A level set of a smooth field
  is by construction a smooth curve; because the field underneath advects,
  crossfades and bends through the standing eddies, the strokes snake,
  merge and split — morphing wave lines, drawn rather than shaded. Two
  families (main lines + sparser twinkling highlights), heavier on fast
  reaches. The fine detail octave is GONE — its jitter is what made
  contour edges ragged.
- **A constant shore highlight line** traces the bank just inside the ink,
  pinned to the reconstructed geometry — the most illustrated mark of all.
- **The animation is an exact half-cycle loop** (the two triangular
  crossfade weights swap symmetrically, so n(t+T/2) == n(t) — discovered
  when a morph test probed T/2 and measured literally zero change).
  Embraced, not fought: 16-bit water animation WAS a short loop, and each
  phase's drag slides monotonically downstream within it, so it reads as
  flow. Pinned as an explicit contract.
- Glint and foam are folded into the stroke families; the smear taps are
  triangle-weighted (outer taps pay the most at a direction-bin change).

## Boulders shape the flow (2026-08-31)

Requested directly: *"boulders that are layed in or exist from the
beginning should properly affect path and flow of the water so that it's
possible to build a pond by dropping boulders into the river"*. Two
mechanisms, both riding systems that already exist:

**An in-channel boulder is a flow obstacle.** Two kinds, one predicate:
- *natural*: the procedural stone roll (`StonePlacement.has_stone_at` +
  `StoneSize.class_for`) lands a boulder-class stone on a river tile —
  these have always spawned mid-river; now the water knows about them
- *dropped*: a new `boulder` BuildingPiece (category DAM, built from
  quarried rock — "dropping a boulder" is stacking your rock into a
  boulder-sized cairn where you stand). Persists exactly like every other
  building modification.

**Visual: the water parts around the rock.** Entirely through the baked
per-tile across-offset — the shader is untouched. Each painted tile's
across is pushed AWAY from nearby boulder tiles
(`DamImpoundment.obstacle_across_shift`, linear falloff over ~2.5 tiles),
and the boulder's own tile is railed past the waterline
(`DamImpoundment.eyot_across`, beyond 1 + the bank feather by test): the
boulder becomes a dry eyot, the waterline necks around it, and the guided
current lines bend past — streamlines around an obstacle, from the same
reconstruction that draws everything else.

**Mechanical: a boulder row is a crest.** The impoundment walk (the same
one `stone_dam` uses, with the same real weir head and backwater falloff)
now also recognises a course position where EVERY wet tile across the
channel holds a flow boulder — placed, natural, or a mix. Drop boulders
until the row closes and the pool rises upstream: a pond, from the
existing dam physics. A partial row deflects but does not pond
(`test_a_partial_boulder_row_does_not_pond`), so a single mid-channel
rock never dams a river. The engineered `stone_dam` piece keeps its
one-piece behaviour — it IS a constructed full-channel weir; loose
boulders must genuinely span the water.

## The wader's wake (2026-09-01)

A player walking through the stream displaces the current the same way a
boulder does — one soft moving obstacle, fed to the shared shader
material every frame (position + in-water state, the same per-frame shape
as the moonlight lift). The push is softer and smaller than a boulder's
(legs, not a rock face: `WADER_PUSH 0.3` vs `0.5`, reach 26px vs 40px),
and it is stretched DOWNSTREAM: displaced water is carried off by the
current, so the wake trails behind the legs up to ~1.8× the base reach
instead of ringing them symmetrically (`wader_across_push`, mirrored on
CPU and pinned by `test_the_wake_trails_downstream_not_upstream`). A
wader never dries the water — no eyot; exactly one place in the fragment
shader may carve dry ground and it is the boulder loop (structural pin).
Active whenever the player's mode is wading, swimming, or drowning.

## Rivers on the minimap (2026-09-01)

River tiles paint water-blue over whatever biome they cross
(`MinimapRenderer`, duck-typed optional `is_river_at_global` lookup so
biome-only sources keep working). The catalog polyline walk is too heavy
for 81×81 queries per rebuild, so the renderer memoises answers per tile
— rivers never move — re-querying only the freshly exposed edge when the
window steps (`test_river_lookups_are_remembered_across_builds`), with a
250k-tile cap so a cross-country hike cannot hold the world in memory.

## The full bilinear frame, forward drift, round obstacles (2026-09-01)

Four reports, one round:

**"there are still individual square river tiles visible"** -- the across
map fixed across, but flow DIRECTION still rode the atlas texel (96
quantized bins, constant per tile) and speed was a binary per-tile flag.
Both fed the advected noise, so strokes broke at every bearing or speed
change. The flow texel is now FORMAT_RGBAF and carries the whole
reconstruction frame -- R across, GB the course's downstream unit vector,
A the real solved current speed (m/s) -- all interpolated bilinearly by
the sampler. The atlas sprite is now only the painted canvas; the shader
never samples it (`texture(TEXTURE` absent, pinned). Painted apron texels
carry their reach's real bearing/speed too, so bank-adjacent blends stay
sane (bank speed dilutes toward zero -- banks ARE slower).

**"there should be more of a forward motion"** -- the two-phase advection
morphs but never travels. A linear drift term now translates the sampled
noise domain downstream at `DRIFT_PX_PER_MPS (9) x` the texel's real
current speed -- the Rhine at 2.2 m/s visibly travels ~1.2 tiles/s, a
sluggish lower course crawls. The bed-anchored eddy field deliberately
does NOT drift (boils hold station; the surface pours through them). This
retires the half-cycle loop contract -- a pattern that loops in place
cannot also travel; the new pin measures that the t+dt field correlates
better with the t field sampled a drift-length upstream than with itself
in place. Unbounded TIME translation is safe because the noise hash is
fract-first at any coordinate (the Basel lesson).

**"player and boulders behave like a singularity and don't have a radius"**
-- the falloff-squared push peaked at a point. Both boulders and waders
now displace via the real cylinder midplane streamline shift:
`sqrt(lateral^2 + R^2) - |lateral|` -- exactly R on the stagnation line
(the parting streamline clears the actual rock/legs), decaying smoothly,
nonzero everywhere inside the reach, converted to across-fraction through
the channel's real half-width. Boulders R=11px, waders R=6px.

**"animals should also cause water displacement like the player"** -- the
single wader uniform became an array (8 slots): world.gd hands the player
plus every creature marker to `river_wader_positions`, which memoises a
per-tile river lookup and keeps only candidates actually standing in
river water; survivors reach the shader each frame and part the current
with the same round core and downstream-trailing wake.

**Crest closure is now the wall itself** -- the boulder-row verdict
flood-fills the connected chain of blocked wet tiles from seeds near the
asked course position and asks whether the CHAIN reaches both waterlines
(one tile footprint short of the bank line). Two window-based versions
broke against the smoothed course -- what falls in a window is an
accident of the asking tile's bearing -- and adjacency doubles as the
watertightness rule: a one-tile hole breaks the chain. Pinned from every
tile of the wall by test.

## Movement ripples in the river (2026-09-04)

Reported: *"Fishes don't produce interferencing ripples anymore in the new
unified river water ... players and animals neither ... the old ripples
looked nice so we want them back adapted to new water shader."*

Not a regression in the ripple machinery — that is entirely intact. Fish
(`FishMarker._step_water_ripple`), the player (`Player._step_water_ripples`)
and creatures (`CreatureMarker._step_water_ripple`) all still call
`EarthChunkManager.record_water_disturbance` on the same schedules, and
`WaterShader` still ages and draws them. The cause is a rendering boundary:
`_paint_water_overlay` is **ocean only** ("rivers used to be painted here
too... the flow overlay is now the river's entire water surface"), and
`RiverFlowShader` is **opaque** and had no disturbance term. So on a river
there was no surface capable of showing a ripple at all — the wakes were
being recorded and aged into a layer that river tiles no longer have.

The fix is not to re-paint the ocean overlay under the river (that is
exactly the square-tiles-under-a-smooth-bank-curve bug it was removed to
fix). The river surface draws its own ripples, from the same buffer.

**One buffer, two surfaces.** `WaterShader` keeps ownership of the
disturbance ring buffer (`add_disturbance`/`advance_disturbances`,
`MAX_DISTURBANCES` 16, `DISTURBANCE_LIFETIME`); it now exposes the padded
arrays it pushes, and `EarthChunkManager` fans the same three uniforms out
to the river-flow material as well. There is no second buffer to keep in
sync, no second lifetime, and the distance cull
(`DISTURBANCE_RADIUS_TILES`) applies once, to both.

**The same wave packet.** `RiverFlowShader.ripple_packet` is the identical
signed expanding-packet math as `WaterShader`'s — several concentric crests
and troughs behind an advancing front, fading with age and with the
circumference it spreads its energy around. Signed is the whole point:
overlapping ripples must genuinely interfere, constructively AND
destructively, rather than only ever adding. Keeping the shape identical is
what makes a fish's wake read the same in a river as in the sea; the tuning
constants are shared by import rather than re-tuned
(`RIPPLE_SPEED`/`LIFETIME`/`WAVELENGTH`/`PACKET_WIDTH`/`SPREAD_DECAY`).

What is genuinely adapted, and why each part:

- **The ring is carried downstream.** In still water a ripple is concentric
  about a fixed point; in a current it is concentric about a point that
  moves with the water. The centre is carried by
  `flow_dir * surface_px_per_s(speed_mps) * age` — the water's whole
  VISIBLE speed, so a wake and the water it sits in travel together instead
  of the ring standing still while the river slides out from under it. This
  is the one thing ocean water cannot express and the river must. (First
  shipped carried by the linear drift alone, `DRIFT_PX_PER_MPS * speed_mps`,
  which at a typical reach is a third of the water's visible speed — the
  ring visibly sat there. See "One visible water speed" below.)
- **Drawn, not glowed.** This surface is illustrated water: a flat cel body
  plus contour strokes. A bright ring composited on top would read as an
  overlay sticker. So the packet enters two fields that already exist. It
  is added to the **stroke field** whose level sets are the current lines,
  so the drawn lines genuinely bow into arcs around the disturbance —
  closing into rings where the packet is steepest, which is exactly what a
  ripple is — and interfere with the flow pattern instead of being drawn
  over it. And its crests enter the **stroke strength**, so the ring inks
  in its own right, inheriting the adaptive ink, the moonlight lift and the
  alpha clamp for free (`max`, not a sum: a strong crest takes over the
  mark, a weak one leaves the flow line alone, and neither can push a
  stroke past full).
- **Not into the cel body**, though an earlier draft of this section
  specified exactly that — a crest stepping the fragment toward a lighter
  band, a trough toward a darker one. It was dropped before implementation
  on the strength of this doc's own history: the body cels are static
  reconstructed depth *because* shading them with a moving field produced
  the reported "gas animation", and `test_the_body_cels_are_static_depth_
  only` pins that literally. The art direction here is that the body holds
  still and the drawn strokes carry ALL the motion — and a ripple is
  motion, so it belongs in the strokes with the rest of it.
- **Both gains bounded from both sides, against the packet's own scanned
  peak** rather than against a written-down amplitude, so re-tuning the
  packet re-tunes its bounds. `RIPPLE_LINE_GAIN`: a crest must bend the
  stroke field by more than a third of one contour spacing (below that it
  draws nothing) and by less than half the wobble's own swing (above that
  it stops being a local disturbance and restructures the channel-wide
  line family into the closed "perlin noise cells" the across ramp exists
  to prevent — rings closing around the fish itself are wanted, which is
  why the ceiling is set against the wobble and not against zero).
  `RIPPLE_CREST_FULL` must stay reachable by a real crest or it is ink
  that never prints; `RIPPLE_CREST_MIN` is the threshold `WaterShader`
  already paid for once — set against a fresh ripple it made the ring
  visible only in its first moments ("a mini ripple appears but nothing
  looks natural"), so it is pinned low enough that a crest still inks
  three quarters of the way through the ring's life.

The ripple deliberately does NOT displace `frag_across`, the way boulders
and waders do. That field is the channel's geometry: pushing it moves the
bank line and the dry eyot, and a passing fish must not narrow the river.

**Verified where it is actually visible.** Every CPU mirror can be green
while the ring still never reaches a pixel — that is precisely the failure
that produced the report. So `test_river_flow_render_smoke.gd` renders two
blocks of the same river, quiet and disturbed, and requires the picture to
change. They must share a FRAME: this surface advects continuously, so two
renders taken a few frames apart differ in every pixel regardless, and a
first attempt at this test passed with the ripple term deleted outright
(measured). Same frame, one shared `TIME`, and the disturbance buffer is
the only thing left that can differ — with the ripple disabled the
difference measures 0.00%. Both readback tests in that file now skip
explicitly under `--headless` (no GPU target, `get_image()` returns null,
and the engine error that raises fails the test on its own); the far-world
one had been reporting a shader failure on every headless run for a reason
that had nothing to do with the shader.

## Fish really do live under the river surface (2026-09-04)

The ripple entry above first shipped with a caveat saying fish were not
among a river's ripple causes yet — that `FishRenderer` spawns on ocean
cells only, so a river would show the player's and the animals' wakes and
nothing else. Reported back, flatly: *"The rivers are full of fish."*

That caveat was wrong, and wrong in an instructive way: it came from
reading the spawn gate and stopping there. `WaterAreaSurvey.
is_interior_water` requires the ocean BIOME for a cell and all eight of its
neighbours, and a river never changes `biome_at_global`'s elevation-derived
result — from which it seemed to follow that no curated course could ever
qualify. Measuring says otherwise. Sweeping the whole apron band around
every curated course (10,743 cells): **64 qualify for fish, and 53 of those
are also painted by the river-flow overlay.**

The two decisions ask different questions, and that is the whole of it:

- **Fish spawn by biome.** The world's elevation source is coarse, so real
  reaches sit below sea level and classify as ocean — broad water, lakes a
  course runs through, the last stretch to a mouth. Those are ordinary
  fish water by every existing rule.
- **The river surface paints by DISTANCE.** `_paint_river_flow_overlay`
  gates on `nearest.distance_tiles > apron` and consults no biome at all —
  correctly, since the shader clips the water at the real bank curve and
  needs the cells around it painted to do so.

So along those reaches a cell is ocean biome *and* under the opaque flow
overlay at once: fish swimming in water whose surface had no term to draw
their wake. That is not an edge case bolted onto the ripple bug — it is a
second, independent path into the exact same symptom, and the same fix
covers it, because the disturbance buffer now reaches the river material
regardless of which cells the swimmers are on.

Pinned by `test_a_river_reach_can_be_both_fish_water_and_under_the_flow_
overlay` at one measured Rhine coordinate rather than by re-sweeping ten
thousand cells per run — one real example is enough to stop the case being
reasoned away as impossible a second time.

(Freshwater fishing as a *designed* mechanic — river-specific species,
spawning rules, a reason to fish a stream rather than the sea — is still
⬜ Not started. What exists is incidental: ocean-biome water that a curated
course happens to run through.)

## The boulder's shore band, not a halo (2026-09-04) — SUPERSEDED

*Superseded by "Boulders are hydrology" below: the band is no longer a
painted ring at all. The rock is a rise in the bed, and the light water
around it is the same shallow water the banks show.*

Reported directly against the ring introduced above: *"The rocks should
not have a halo around them... instead they should have a layered band
like the shore which also wobbles and moves"*. The ring's REACH was
already right -- a soft-edged annulus starting exactly where the rock's
dry eyot ends (`boulder_band_envelope`, unchanged) -- what was wrong was
what filled it: one flat, static `line_color` at a fixed alpha, nothing
like the channel's own illustrated shore a few tiles away.

The fix reuses the channel body's own machinery instead of inventing a
second one. `boulder_band_ring_t`, the fragment's own position inside the
ring (0 at the rock's edge, 1 at the outer edge), is carried out of the
boulder loop and, in the composite, nudged by `n` -- the SAME advected
field whose contours already draw the channel's wave strokes -- before
being quantised by the SAME world-anchored dither hash the channel body's
cel bands use. The result steps through `BOULDER_BAND_LEVELS` (3) flat
layers between `line_color` (the shore highlight's own tint, at the rock's
edge) and `band0_color` (the channel's own shallowest water tone, at the
ring's outer edge) -- the same palette the real shore draws in, not a
colour invented for the ring. Because `n` both varies across world
position and advects with TIME, the layer boundaries are uneven rather
than perfect circles and visibly animate frame to frame, exactly like the
channel's own cel/stroke boundaries do -- "wobbles and moves" is the same
mechanism, not a new one, reused rather than reinvented.

Old halo, new band: same ring extent and alpha (`BOULDER_BAND_WIDTH_PX`,
`BOULDER_BAND_ALPHA` -- renamed, unchanged values), same "independent of
the channel's own wet/dry verdict" property that lets a boulder on dry
bank ground still show a band. Only the fill inside the ring changed.

## One visible water speed: ripples, eddies and lines together (2026-09-04) — PARTLY SUPERSEDED

*The shared-speed mechanism below stands; the NUMBERS and the claim that
the drag's translation is most of the visible speed do not. See "A calm
picture: the drift carries everything, the drag only deforms" further
down for what the real GPU showed and what replaced them.*

Reported in three steps, live, on the ripple work above: *"Can you make
the river ripples move downstream at water speed?"*, then *"eddy swirls
also don't move downstream.. a wobble stays in place instead of flowing
with the river"*, then — the ripples having been carried by the drift in
the meantime — *"Ripples now do move downstream, but the lines should move
at same speed."*

One cause. The drawn surface is moved by TWO terms, and only one of them
had been treated as "the water's speed":

| term | what it is | world px/s at a 0.5 m/s reach |
| --- | --- | --- |
| two-phase drag | `ADVECT_STRENGTH` cells every `1/ADVECT_RATE` s, regardless of the reach | ~19.8 |
| linear drift | `DRIFT_PX_PER_MPS` per m/s of real current | 10 |
| **visible surface** | the sum: what the pulses and kinks actually stream at | **~29.8** |
| ring centre (before) | drift alone | 10 |
| eddy field (before) | `BEND_DRIFT_FRACTION` (0.6) of the drift alone | 6 |

The drag is not a wobble-in-place: each phase's layer is the field
translated by a distance growing linearly with the phase's age, so
features on the surface genuinely travel at `ADVECT_STRENGTH x
ADVECT_RATE` cells per second, and the crossfade only decides which of
two offset copies is showing. That translation is most of the visible
speed at every ordinary reach, and neither the ring nor the eddies had it —
so a wake moved at a third of the water and the whirls at a fifth, and
both read as standing still while the pulses streamed past them.

**The fix is one function.** `surface_px_per_s(speed_mps, moving)` in the
GLSL, mirrored by `RiverFlowShader.surface_px_per_s` (and
`surface_cells` in noise units), is the water's visible downstream speed:
drag translation plus drift, gated by the same hard `STILL_FLOW_M_S` step
the strokes use, so a lake — whose still path breathes sideways and never
drifts — carries nothing either. Every consumer that has to "move with the
water" rides it:

- **The ring centre** is carried by `surface_velocity * age`
  (`surface_velocity = flow_dir * surface_px_per_s`, computed once per
  fragment next to the field's own drift). Over its `RIPPLE_LIFETIME` a
  wake in a 0.5 m/s reach now travels ~65 world px — four tiles — instead
  of 22.
- **The eddy field** translates at `surface_px_per_s x
  BEND_DRIFT_FRACTION`, and the fraction goes **0.6 → 1.0**: the lines'
  shape IS the eddy-bent guide, so the eddies' migration is the lines'
  motion, and the report was that it must match the ripples. The
  Jackson-1976 "boils lag the surface" grounding that set the fraction
  below one is superseded here by art direction — the lines are the water
  — and the fraction stays as the one knob to bring the lag back. This is
  a deliberate divergence from the earlier "eddies migrate downstream,
  slowly" spec in "The full bilinear frame, forward drift, round
  obstacles".

Why the picture still does not slide as one rigid sheet at fraction 1.0,
which is what that ceiling existed to prevent: the eddy coordinate is a
STEADY translation, never the phase drag itself. Each phase still
stretches away from that translation and resets, so the wobble keeps
deforming relative to the whirls even though their mean speeds now agree;
the structural pin (`eddy_p` is sampled at `p - flow_dir * bend_drift`,
never at the advected `q`) is unchanged, and the fold-margin test still
holds at a real drifted offset because a translation cannot change the
Jacobian.

Not changed: `DRIFT_PX_PER_MPS`, `ADVECT_STRENGTH`, `ADVECT_RATE` and
their pins — the surface itself streams exactly as before. Only the
things carried ON it caught up with it.

Pinned in `test_river_flow_shader.gd`: the visible speed is the drag
plus the drift and zero below the still gate; the shader's three lines of
wiring are pinned by source; the ring's carry and the eddies' migration
both equal the shared speed and each other; and both clear a legibility
floor at a 0.5 m/s reach (a wake carried more than three and a half tiles
within its lifetime, whirls crossing a tile in two seconds — the same 8
world px/s floor the pulse has to clear). The GPU readback smoke test
still confirms a disturbed river draws differently from a quiet one.

## A softer, slower, broader wake (2026-09-04)

Reported on the carried ripples: *"Can you make the ripples a little less
pronounced so they appear smoother a bit slower and more natural."* Three
adjectives, two owners.

**Slower and smoother are the packet's business, and the packet is
shared.** The wake's shape is one set of constants in `WaterShader`,
imported by `RiverFlowShader` so a fish's wake reads the same in a river
as in the sea — so the shape tuning lives there and both surfaces follow.
`RIPPLE_SPEED` 14 → 11.5 world px/s: the front ambles rather than races.
`RIPPLE_WAVELENGTH` 6 → 8: crests half a tile apart read as broad swells
rather than fine rings. `RIPPLE_PACKET_WIDTH` 7 → 9.5, widened with the
wavelength so the packet keeps the same ~1.2 rings behind the front —
still more than one (several rings, not a lone circle), still well under
two (never a bullseye). The wake's reach shrinks from ~1.9 to ~1.6 tiles,
still past its own tile and still nowhere near swamping a pond, both of
which stay pinned. `RAIN_RIPPLE_SPEED` 12 → 10 alongside, so the splash
stays pinned under half a wake's radius — and a slower splash is the same
ask.

**Less pronounced is this surface's own.** The ring inks in its own right
through `smoothstep(RIPPLE_CREST_MIN, RIPPLE_CREST_FULL, crest)`, and with
`FULL` at 0.40 against the packet's scanned peak of ~0.82 a ring printed
at full stroke strength for most of its life — as dark as a current line,
a stamp rather than a disturbance. `FULL` 0.40 → 0.60 sits near the peak,
so only a fresh crest prints at full strength and the ring GRADUATES down
through its life (about 0.4 at half life, fading out past three quarters)
instead of switching off; `MIN` 0.10 → 0.12 keeps the faint tail clean
while staying under the crest still reachable three quarters through the
life — the "mini ripple" lesson is still pinned. `RiverFlowShader.
ripple_ink` mirrors the shader's smoothstep so the graduation is a tested
curve rather than a pair of eyeballed literals. The crest's bend of the
current lines (`RIPPLE_LINE_GAIN`) is untouched: its floor and ceiling
are pinned against the wobble and the contour spacing, and the ring's
prominence was the ink, not the bend.

Pinned: speed under 12, wavelength at least half a tile, packet-to-
wavelength ratio in (1.1, 1.4) (`test_water_shader.gd`); `FULL` within
70% of the scanned peak, a fresh crest at 1.0, half-life ink in (0.25,
0.6), still drawing and fainter at three quarters, the ink curve is the
shader's own smoothstep (`test_river_flow_shader.gd`). The fish ripple
timing tests, which derive from `RIPPLE_LIFETIME`, are unaffected
(lifetime unchanged); the GPU readback smoke test stays green.

## A calm picture: the drift carries everything, the drag only deforms (2026-09-04)

Reported on the two sections above, live: *"now they look worse and just
seem to drift and fade faster ... i want a more relaxed and calm picture
now everything is faster and the wobbly lines still don't move at the
same speed (a wobble stays at place)."*

This time it was LOOKED AT rather than argued from the algebra.
`tools/probe_river_motion.gd` renders a 0.5 m/s reach with the real
shared material on the real GPU, saves frames at successive times, and
writes amplified difference images between them (anything static comes
out black). Two things were plain in the frames:

- The ring was carried 30 world px in one second and was already faint
  at 1.5 s — "drift and fade faster", exactly.
- The lines did not translate at all. The two-phase drag at
  `ADVECT_STRENGTH` 7.2 cells crossfades two copies of the field offset
  by HALF the drag — 45 world px — and at that distance the copies are
  uncorrelated, so the crossfade is a dissolve between two unrelated
  patterns: a kink fades out where it is and a different one fades in
  somewhere else. No kink ever travels. That is the wobble that "stays at
  place", and it was the same whether the copies were being stretched 90
  px per cycle or not. The previous section's arithmetic — that the drag
  "translates features at 19.8 world px/s" — was true of each copy and
  false of the picture.

**The contract is reversed.** The drag is DEFORMATION only; the linear
drift is the carrier.

| constant | before | after | why |
| --- | --- | --- | --- |
| `ADVECT_STRENGTH` | 7.2 cells | 1.2 | phases 0.6 cells apart stay correlated: a kink survives the fade and rides the drift |
| `DRIFT_PX_PER_MPS` | 20 | 16 | with everything coherent, 8 px/s at 0.5 m/s reads as a calm, unmistakable current |
| `surface_px_per_s` at 0.5 m/s | ~30 world px/s | ~11 | the one speed the ring, eddies, kinks and pulses all ride |
| `STILL_RIPPLE` | 0.25 | 0.45 | lakes keep breathing (22 → 7 px sideways): calmer, not frozen |
| `RIPPLE_LIFETIME` | 2.2 s | 3.0 | the ring lingers and its fade is slower; carried ~2 tiles over its life instead of 4 |

Nothing structural changed: two phases, triangular crossfade, the
world-anchored field, the eddy translation at `BEND_DRIFT_FRACTION` 1.0,
the shared `surface_px_per_s`. The probe frames after the change show
the line kinks translating downstream frame to frame at the ring's own
rate, and the ring still visible half way through its life.

**Pins replaced, not deleted.** Two tests encoded the drag as the
carrier — "the drag covers at least half a feature length per phase" and
"the surface travels 1.0 to 2.6 cells per second" — and could only be
satisfied by the dissolve. They became: phases under one cell apart
(`test_the_drag_is_a_small_deformation_so_kinks_survive_the_crossfade`);
a 0.5 m/s reach between 8 and 16 world px/s with the drag's translation
under a third of it (`test_the_water_travels_at_a_calm_speed`); the drift
at least two thirds of the visible speed. The two motion sweeps that
watched "a quarter drag cycle in speed-zero water" — which measured the
dissolve and nothing else — now watch a quarter feature length of travel
at a real reach speed. The ring's carry over its life is bounded on both
sides now (1.5 to 3 tiles) and its lifetime floored at 3 s on both
surfaces.

## Boulders are hydrology: shoal, force balance, foam and wake (2026-09-04)

Reported, as a design correction rather than a bug: *"The boulders halo
should not be computed by the boulder, but rather be part of the river's
hydrology... the lighter color bands should come from elevation (rock is
above waterline) and the rock should as entity have a mass and produce a
counterforce against the hydrological water pressure which is a smaller
force than the weight of the boulder so it should bend the guidelines and
produce foam in front and whirls behind it."*

That is four mechanisms, and they share one principle: **nothing about a
boulder is painted; everything about it is what the water does around a
real rock of a real size.**

### Design pillars

- **The rock is an entity with a size and a mass.** Every flow boulder
  carries its own diameter (`StoneSize.diameter_for` its seed; the
  dropped piece and ore rocks use the smashable stone's default), hence
  its own radius on the water in world px (`boulder_radius_px_for`:
  half its drawn height, `StoneSize.world_height_px`, floored so the
  smallest boulder still parts the water) and its own real mass
  (`StoneSize.mass_kg_for`). The push reach, the dry eyot, the shoal,
  the foam and the wake all scale with that radius. The one-size-fits-
  all `BOULDER_RADIUS_PX` is gone.
- **Light bands come from elevation, not from a ring.** The rock stands
  above the waterline, so the bed rises to meet it, so the water
  shallows toward it — and shallow water is light in this renderer for
  the same reason the banks are: the cel body is depth. The boulder
  contributes a **shoal** to the depth field, `depth_frac *= 1 - shoal`,
  with `shoal` 1 at the rock's edge falling to 0 over
  `BOULDER_SHOAL_RATIO` radii. The existing cel quantisation and the
  world-anchored dither then draw the bands, in the channel's own
  palette, with no boulder-specific colour code at all. The body stays
  static depth, as pinned.
- **The force balance is real, and it is why the water bends.**
  `BoulderHydraulics` (`src/world/boulder_hydraulics.gd`): the water
  pushes with dynamic-pressure drag, F = ½ρv²·Cd·A on the rock's wet
  frontal area (Cd 0.47, a sphere); the rock resists with its submerged
  weight (granite 2.7, buoyed over its wet fraction) times bed friction
  (0.6, the tangent of loose rock's angle of repose). `load` is their
  ratio and `holds` is it under 1. Checked against real cases: a metre
  boulder in a 1 m/s reach carries a load under 0.1; a thirty-centimetre
  boulder — still a boulder on the Wentworth scale — is swept by a 3 m/s
  flood, which is exactly what bedload transport does. Because the rock
  holds, the water has to go around it: the potential-flow displacement
  of the guide lines (unchanged, `sqrt(lateral² + R²) − |lateral|`) is
  the consequence of the rock winning the balance.
- **Foam in front.** Flow stagnates on the upstream face and, fast
  enough, the pile-up breaks white. The foam term is confined to the
  upstream sector (the square of the cosine from the stagnation line,
  zero at and behind the rock's shoulders), to a radial window from the
  rock's edge out `BOULDER_FOAM_REACH_RATIO` radii, driven by the reach's
  speed between `FOAM_MIN_M_S` and `FOAM_FULL_M_S` (a slow reach parts
  cleanly, a fast one foams), and broken up by the channel's own advected
  field so it streams and flickers rather than sitting as a pale cap.
  Composited as near-white over the body after the strokes.
- **Whirls behind.** A rock sheds eddies: the standing-turbulence bend
  the guide lines already whirl with is amplified in a wake lobe behind
  each boulder — downstream only, within a couple of radii laterally,
  rising over the first radius and dying out by `BOULDER_WAKE_LENGTH_RATIO`
  radii — by `BOULDER_WAKE_GAIN`, gated by the current. The fold-margin
  pin holds at the gained strength, so the wake whirls without the
  surface ever folding over itself — and that bound turned out to be
  tight: a gain of 0.5 pinched the warp to 0.17 against the 0.35 margin,
  0.15 holds it. So the wake reads as disturbed water mostly through
  `WAKE_FOAM`, a thinner trail of the face's foam streaming down the
  lobe, which is what a real wake carries. Measured on the probe: a 0.9
  m/s reach shows the white cap on the upstream face and a pale streak
  trailing behind the rock; the whirl amplification is subtle by
  construction.

### Real-world grounding

Bedload stability (Shields; Costa 1983 for boulder entrainment) is a
drag-versus-submerged-weight balance, which is what `load` computes
with textbook constants. Flow around a cylinder or sphere: stagnation
upstream, the parting streamline clearing the body (already the push),
and a von Kármán wake of shed vortices downstream at any river-scale
Reynolds number. Whitewater is deceleration, not speed — hence the foam
lives on the upstream face where the water is brought to rest, and its
strength follows dynamic pressure.

### What this replaces, deliberately

The painted band (`boulder_band*` uniforms, the ring envelope, the
three-stop colour ramp, the wobble, and the rule that a rock on dry bank
ground lights water around itself) is removed, not restyled. A rock on
dry ground is dry ground with a rock on it; the water around a rock in
the river is light because it is shallow. The old band's tests are
replaced by shoal tests. The eyot stays: it is the part of the rise that
breaks the surface.

## Status

- Force balance (`BoulderHydraulics`: drag, submerged weight, load,
  holds) — ✅ tested against real cases. Using the verdict to actually
  MOVE a swept rock (bedload transport in floods) — ⬜ Not started; the
  manager exposes the verdict per flow boulder.
- Per-boulder radius fed to the shader from the rock's real diameter — ✅.
- Shoal replaces the band — ✅.
- Foam in front — ✅. Wake whirls behind — ✅ (bend gain bounded by the
  fold margin, foam streaks carry most of the read). Wake-specific eddy
  shedding (a real vortex street with its own period) — ⬜ Not started.

## The ring is a thin, light line (2026-09-04)

Reported on the calm picture: *"Can you make the ripples stroke width
smaller and a bit more transparent?"*

The ring's ink was `smoothstep(RIPPLE_CREST_MIN, RIPPLE_CREST_FULL, crest
amplitude)`, so its WIDTH was however much of the crest's sine cleared
the thresholds — about three world px, three times a current line — and
it swelled with a fresh wake and shrank as it faded. Width and strength
were one knob.

They are two now. `movement_ripples` also sums an **envelope** — the
packet without its sine, i.e. how strong the wake is here, now, whether
this pixel sits on a crest or a trough — and the ring's ink band is cut
from the pure sine (packet over envelope) above `RIPPLE_RING_EDGE`. The
arc of a sine above a threshold is a fixed length, so the ring is one
width in px at every age: `RIPPLE_WAVELENGTH / TAU × (π − 2 asin EDGE)`,
~1.4 world px at 0.85, pinned no wider than a current line's full extent
(`ripple_ring_width_px` against `line_width_px`) and no thinner than a
snapped pixel and a half. The envelope alone drives the strength through
the same graduated crest curve, under `RIPPLE_INK_MAX` (0.6) so the ring
prints lighter than the lines it sits among — "a bit more transparent".

The signed packet still bends the current lines exactly as before
(`RIPPLE_LINE_GAIN`), and two wakes still interfere in it; only the
ring's own ink changed. `ripple_envelope` is mirrored on the CPU and
pinned never under the packet's magnitude and equal to it at a crest;
`ripple_ink` now carries the ceiling, and the life-graduation pins
measure as fractions of it.

## Status

- **The ring is a thin, light line** — ✅ Done — width from the sine,
  strength from the envelope; see the section above.
- **A calm picture (drift carries, drag deforms)** — ✅ Done — see the
  section above; the probe tool is `tools/probe_river_motion.gd`.
- **One visible water speed (ripples, eddies, lines)** — ✅ Done — see
  its section above; `surface_px_per_s` is the single source, both
  consumers ride it, `BEND_DRIFT_FRACTION` 1.0. Its speed numbers are
  superseded by the calm-picture section.
- **A softer, slower, broader wake** — ✅ Done — shared packet slowed and
  broadened in `WaterShader`, the river's ring inks graduated through its
  life; see the section above.
- **Curated river catalog** — ✅ Done for Germany's major rivers + the
  Dreisam (see Roster). Rest-of-world roster — ⬜ Not started, ongoing.
- **Procedural fallback (noise-contour proxy)** — ✅ Built, tested, and
  intact as a module — 🔴 **Reverted from live use** (see "Procedural
  fallback: reverted after playtesting" above); curated-only is what's
  live. A future connectivity-aware redesign could reuse the module.
- **Rendering (water overlay reuse)** — ✅ Done.
- **Flow rendering: realistic advected water** — ✅ Done — two-phase
  flow-map advection over the real parabolic cross-section, with crest
  glints and bank whitewater that travel with the water. Supersedes the
  stylized direction, which was tried and reversed (see "Art direction:
  back to realism"). Verified to compile and run on a real GPU
  (`test_river_flow_render_smoke.gd`), not only headless.
- **Continuous cross-section + smooth shoreline** — ✅ Done — per-fragment
  reconstruction from the baked signed across-offset kills the per-tile
  squares structurally; the waterline is the real bank curve with a
  feather, painted out to an apron; base water overlay is ocean-only now.
  Sub-tile GROUND blending at the bank (sand/mud strip under the
  waterline) — ⬜ Not started.
- **Comic / 16-bit presentation** — ✅ Done — static depth cels + art-pixel
  snapping + ordered dither + bank ink line + contour wave strokes carrying
  all the motion (see "Strokes, not shading").
- **World-anchored field + smoothed courses + round caps** — ✅ Done — the
  LIC smear keeps the streak pattern continuous across direction-bin
  changes (the "hard cuts", pinned by a world-magnitude seam test),
  Chaikin-smoothed courses un-kink the banks, radial tips clean up
  confluences. A fragment-continuous along-course coordinate (for
  perfectly stationary streaks under very long observation) — ⬜ Not
  needed so far.
- **Flow rendering: stylized cartoon look** — 🔴 **Reverted.** Reported as
  "just some moving strokes, not realistic water flow"; the failure was
  structural (a translated periodic shape cannot read as water). Its
  channel cross-section survived and is still live.
- **Flow rendering: baked phase field** — 🔴 **Removed**
  (`river_phase_field.gd` deleted). Load-bearing under the old streak
  pattern, actively harmful under advection (it would seam the noise at
  every tile edge), and a 12× atlas multiplier for a channel the shader no
  longer reads.
- **Ocean water** — ⬜ Not started. Still uses the older realistic
  `water_shader.gd`; unifying the two looks is open. Lava likewise ⬜ Not
  started (it does not exist anywhere in the game yet).
- **Flow rendering z-order** — ✅ Done. The overlay was silently occluded in
  live play by an unrelated `scenes/world.tscn` sibling-order bug
  (`HillshadeFx` drawing on top of `RiverFlowFx`); fixed and regression-
  tested against the real scene file (`test_world_ground_layer_order.gd`).
  Deceleration-driven foam and bank foam from the shore-distance channel —
  ⬜ Not started.
- **Dams (buildable stone check dam)** — ✅ Done — `stone_dam`
  BuildingPiece + `dam_impoundment.gd`. Real weir-equation pool depth,
  real sliding-failure physics, derived-not-stored impoundment. Transient
  fill, multi-piece dam runs, and dam-break flooding — ⬜ Not started.
- **Boulders shape the flow** — ✅ Done — natural and dropped boulders
  deflect the waterline and current lines (eyot + across push), and a
  full boulder row across the channel ponds via the same weir physics.
  Pushing/carrying an intact boulder (rather than building one from
  rock) — ⬜ Not started.
- **Boulders are hydrology** — ✅ Done — each rock has its own size and
  mass; the light water around it is its shoal in the depth field, not a
  painted ring; the drag-versus-weight balance is computed
  (`BoulderHydraulics`); foam on the upstream face, amplified whirls in
  the wake. Moving a swept rock — ⬜ Not started. See "Boulders are
  hydrology: shoal, force balance, foam and wake".
- **The wader's wake** — ✅ Done — player AND creatures (8 slots, river
  filter memoised) displace the current with a round-core,
  downstream-trailing wake; never dries the channel.
- **Movement ripples (fish, player, animals)** — ✅ Done — the shared
  `WaterShader` disturbance buffer now feeds the river surface too; the
  same signed wave packet, its centre carried downstream at the water's
  visible speed (see "One visible water speed"), drawn into the stroke
  contours and the stroke strength rather than composited on top. Confirmed on a real GPU
  (`test_a_recorded_disturbance_actually_changes_what_the_river_draws`),
  which is the only place the symptom was ever visible. Fish are among the
  causes — see "Fish really do live under the river surface" above, which
  corrects a wrong claim this bullet made first time round.
- **Rivers on the minimap** — ✅ Done — water-blue over any biome, memoised
  per tile so the polyline walk never hitches the rebuild.
- **Real hydraulics: volume, pressure, current speed** — ✅ Done —
  `river_discharge.gd` (real curated gauge data + derived width) +
  `open_channel_flow.gd` (Manning, continuity, closed-form normal depth,
  hydrostatic pressure/force, weir overtopping), solved per-tile by
  `EarthChunkGenerator.river_hydraulics_at_global`. This also answers
  `electromagnetism.md`'s long-standing "DISCHARGE-accurate speed" open
  question — there is now a real per-cell discharge and velocity for a water
  wheel to consume. Rainfall/flood coupling and the water wheel mechanic
  itself — ⬜ Not started.
- **Player wading/swimming/submersion-tint/ripples in rivers** — ✅ Done.
- **Decoration exclusion (trees, grass, snow)** — ✅ Done.
- **Dry-land spawn exclusion** — ✅ Done.
- **Freshwater fishing, village avoidance, creature water-depth awareness,
  boats/fords/bridges, Nix water-gating, lakes, already-persisted stale
  saplings** — ⬜ Not started (see above).

## Bounded drift: the far-time shredding (2026-09-05)

Found live at the Loire near Nantes after roughly 25 minutes of play, at
night: every **curved** reach of a fast river dissolved into per-pixel
white speckle while the straight reach beside it kept its long moonlit
lines. Reproduced on the real GPU by advancing the shader clock with
`Engine.time_scale` on the real Loire flow map: 0.003 of the water pixels
read as isolated bright specks fresh, 0.056 at `TIME` ~2000 s; 0.015 with
the drift zeroed, 0.030 with the eddy drift zeroed; the curved-smear
direction lookup and the bicubic map filter changed nothing.

Two unbounded translations were at fault, and each had two halves.

**Direction.** The drift and the eddy drift move a sample coordinate by
`flow_dir x (TIME x speed)`. `flow_dir` is reconstructed continuously
between texels, so on a bend two neighbouring fragments differ by a
fraction of a degree, and that fraction times thousands of noise cells is
many cells: neighbouring pixels read unrelated noise. The same "angle
times distance" trap the world-origin seam fix guards against, re-entered
through `TIME`. Both drifts now wrap modulo `DRIFT_PERIOD_CELLS` (20 -- in
noise cells for the smear, in eddy units for the eddies), and the noise
they translate is `value_noise_tiled`, whose lattice wraps at that same
period (the eddy detail octave at period x `EDDY_DETAIL_FREQUENCY`, a
whole 52 cells), so a translation by one period is the identity and the
wrap is invisible.

**Speed.** That alone left 0.041: the texel's speed is also interpolated
per fragment and varies along a reach (Manning on the local slope, 2.26
to 2.35 m/s across a few tiles of the Loire), and `TIME x speed`
diverges between neighbours without bound whatever the direction does.
Written with one constant speed in the map the same frame measured
0.008. So the two unbounded translations now share one reference current,
`DRIFT_SPEED_M_S` (0.5, the typical reach of the tuning notes), gated
still by the same still-water step. The reach's real speed still shows
through the fast-flow brightness, the foam, and the ring, which is
carried at the local `surface_velocity` and is bounded by its own
lifetime. What is given up, honestly: "the Rhine visibly travels, a lower
course crawls" as a *stroke-speed* cue. A per-reach CONSTANT speed in the
map (one value between confluences) would restore it with a seam only at
confluences, and is the named follow-up.

Measured after both: 0.002 fresh, 0.002 at ~2000 s. Pinned by
`test_the_drift_translations_are_bounded_by_the_noise_period`,
`test_a_long_session_does_not_shred_the_field_on_a_bend` and
`test_the_drift_is_one_shared_speed_for_every_moving_reach`; the eddy
pins (`test_the_bend_drifts_downstream_with_the_current`,
`test_the_shader_streams_every_consumer_from_the_same_surface_speed`) now
state the shared speed.

**Both halves landed on `main` together** via this branch's own merge
(`830f4ba`, merged in `b51d80e`) — there is no longer a separate
direction-only state anywhere in the tree; a session dispatched afterward
against a stale pre-merge snapshot of `main` to fix "the eddy drift
specifically" found the CPU-mirror suite already green on arrival
(`test_a_long_session_does_not_shred_the_field_on_a_bend` included, 172/172
in the file). Re-confirmed independently on the real GPU rather than taken
on trust, with a probe this fix's own commits never left behind
(`tools/probe_eddy_drift_shredding.gd`): a synthetic bending reach, TIME
pinned by literal substitution rather than the engine clock, isolated-
bright-speck fraction fresh vs. at 2000 s. The shipped (fixed) shader held
flat -- 0.0098 -> 0.0075 -- while a copy patched back to the exact
pre-`830f4ba` eddy formula (proving the metric itself is sound, not just
silent) shredded exactly as this section describes -- 0.0099 -> 0.1099, an
11x rise concentrated at the tightest thresholds.


### The reach's own speed (2026-09-05, later the same day)

The one shared drift speed above was the honest stopgap; it lost "the
Rhine visibly travels, a lower course crawls". What actually diverges is
a speed that varies *between neighbouring pixels*, and a speed that is
constant along a whole reach and steps only at a confluence does not:
the step is a fixed line across the river where the water changes
character anyway, and the strokes there merely kink by the wobble term.

So the drift speed is now a property of the **reach** -- the run of
channel cells between confluences, `HydrologyField.reach_discharge`,
judged by the reach head's discharge and memoised per cell -- converted
to m/s by `EarthChunkGenerator.drift_speed_m_s_for_discharge_units`
through the same hydraulic geometry the field already uses (Q = w x d x
v with `RiverDischarge.derived_width_m` and the depth power law), never
the per-tile Manning solve. A curated river drifts at one speed along
its whole course (its mid-course discharge, `curated_drift_speed_m_s`,
memoised per river) for the same reason; a mouth plume drifts at its
river's reach. The painter writes it into the scale map's G channel and
the shader reads it through a **second, nearest-filtered sampler** on
the same texture (`flow_drift_map`): a linear ramp between two reaches'
speeds, times `TIME`, would be the shredding again along that one-texel
band. The ring wake still rides the local `surface_velocity`; it is
bounded by its lifetime. `DRIFT_SPEED_M_S` is gone; `drift_cells` and
`bend_drift_cells` take the reach speed and are linear in it again.

Measured on the real Loire flow map at `TIME` ~2000 s: 0.002 of the
water pixels isolated specks, the same as a fresh frame, with the
tributary and the main river visibly drifting at different speeds.
Pinned by `test_the_reach_discharge_is_constant_between_confluences`
and siblings (field), `test_the_drift_speed_grows_with_discharge_and_is_zero_without`
and `test_every_river_answer_carries_a_constant_drift_speed` (generator),
`test_the_scale_texel_carries_the_reach_drift_speed_and_the_drift_map_is_bound`
(manager) and `test_the_drift_rides_the_reachs_own_constant_speed`
(shader).
