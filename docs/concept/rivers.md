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
exclusion — already pinned by
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

## Status

- **Curated river catalog** — ✅ Done for Germany's major rivers + the
  Dreisam (see Roster). Rest-of-world roster — ⬜ Not started, ongoing.
- **Procedural fallback (noise-contour proxy)** — ✅ Built, tested, and
  intact as a module — 🔴 **Reverted from live use** (see "Procedural
  fallback: reverted after playtesting" above); curated-only is what's
  live. A future connectivity-aware redesign could reuse the module.
- **Rendering (water overlay reuse)** — ✅ Done.
- **Flow direction + real gradient-driven speed + turbulence (animated
  overlay)** — ✅ Done. Was silently occluded in live play by an unrelated
  `scenes/world.tscn` sibling-order bug (`HillshadeFx` drawing on top of
  `RiverFlowFx`) until the z-order fix above — now fixed and regression-
  tested against the real scene file (`test_world_ground_layer_order.gd`).
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
