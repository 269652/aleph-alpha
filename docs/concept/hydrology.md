# Hydrology: rivers and lakes as the outflow of the water cycle

[climate_dynamics.md](climate_dynamics.md) specifies the atmosphere and the
ocean: pressure, wind, currents, evaporation, advected moisture, and the
moment that moisture falls as precipitation. It stops the instant a drop
hits the ground. This doc is everything that happens to that drop next --
snowpack, soil, groundwater, runoff, channel, lake, sea -- and it is the
spec for what this world's water still lacks: **lakes**, and **rivers
everywhere a curated one does not reach**. Today a tile is water when its
real elevation is below sea level (`biome_classifier.gd`'s `"ocean"`) or
when it lies on one of the eleven real, named rivers
[rivers.md](rivers.md) curates; every lake above sea level on the planet
is drawn as dry ground, and the rest of the planet is riverless by
rivers.md's own deliberate choice, made after its noise-contour fallback
was reverted in play ("scattered everywhere").

## Relationship to rivers.md

rivers.md is authoritative for what it covers and this doc builds on it,
not beside it:

- **Curated rivers win.** Wherever a curated river reaches, it is the
  river: its course, its real published discharge, its solved hydraulics.
  Nothing here changes that.
- **The drainage bake is the connectivity-aware fallback rivers.md asked
  for.** That doc reverted its per-tile noise proxy because it had no
  connectivity, and named "a real accumulation pass over a bounded region"
  as the redesign it would accept. Its stated obstacle ("no point at which
  a global drainage pass could run" on a chunk-streamed world) is answered
  by running the pass **offline, once, over the asset's own 7.4M-cell
  grid** and shipping the result -- Layer 0 below. The fallback is gated
  (`EarthChunkGenerator.HYDROLOGY_RIVERS_ENABLED`, off) until the real
  bake has been run and looked at in play, the gate the proxy should have
  had.
- **Overlay, never a biome.** rivers.md's rendering decision stands for
  lakes too: a lake or river tile keeps its land biome and carries an
  overlay flag (`Chunk.is_lake` beside `Chunk.is_river`), read through
  one `Chunk.blocks_ground_cover` predicate. The earlier draft of this doc
  proposed `lake`/`river` biome names; that was withdrawn.
- **One rendering path.** A baked channel is handed to the river flow
  overlay in exactly `RiverCatalog.nearest_river_at`'s dictionary shape
  (`EarthChunkGenerator.nearest_river_at`, empty name), at the catalog's
  uniform half-width, and goes through the same Manning solve with its
  stand-in discharge scaled to m^3/s. Lakes use the ocean's shore-distance
  water overlay, which draws a real shoreline well; rivers.md's objection
  to that overlay was about a river's smooth bank curve, which a lake has
  no need of.

The two docs are one system read at two points: climate_dynamics.md computes
**how much water arrives where**; this doc computes **where it goes**, and
rivers and lakes are what that routing looks like from the ground. Nothing
here decides that a river exists. A river is a place where enough routed
water passes through; a lake is a depression whose water balance is
positive; a salt lake is one whose balance is not. Every one of those is a
consequence, not an authored feature.

## Design pillars

1. **Rivers and lakes emerge from routing, not from placement.** No river
   is drawn, no lake is stamped, no place is named. The drainage network
   is derived from the real elevation data already in the repo; the water
   moving through it is the precipitation climate_dynamics.md already
   computes. The same "real mechanisms, not scripted spawns" pillar
   [ecosystem_dynamics.md](ecosystem_dynamics.md#design-pillars) uses for
   animals and climate_dynamics.md uses for storms, applied to water.
2. **Static geometry, live volume.** *Where* water can flow is a property
   of the terrain and never changes: it is baked once from the elevation
   asset (flow directions, accumulation, depressions) and shipped as data,
   the same way the elevation itself is. *How much* water flows is live
   state on a coarse grid, advanced on the climate tick. A river tile reads
   both: the baked network says a channel passes here and how big its
   catchment is; the live state says how much water that catchment is
   shedding right now. This is the "two fidelities, one truth" split
   ecosystem_dynamics.md and climate_dynamics.md already use, with the
   extra observation that the *geometry* half of hydrology is fully
   static and so belongs in a bake, not a tick.
3. **One equation for fresh lakes and salt lakes.** A depression fills
   until inflow equals outflow. If it reaches its spill point first, it
   overflows, stays fresh, and feeds a river. If evaporation off its
   surface balances the inflow first, it stops below the rim, has no
   outlet, and accumulates salt. Nothing labels a lake "salt" or "fresh";
   the label is a reading of where its balance settled.
4. **Equilibrium first, then live perturbation.** Real lakes take
   decades to centuries to fill. A new world therefore starts from the
   **baked equilibrium** of the coupled model (lake levels where their
   balance already settled, rivers at their climatological mean flow), and
   the live simulation moves the world *away* from that equilibrium as
   seasons, weather, and players act on it. A world that started with empty
   basins and filled them in real time would be wrong for the first
   several hundred game-years.
5. **Matches the real planet because it runs on the same causes.** Direct
   extension of climate_dynamics.md's pillar 3. Nothing here names a
   river, a lake, or a basin; the validation tests do (see Test plan), the
   model never does.
6. **Determinism.** Same elevation asset, same seed, same elapsed time,
   same rivers and lake levels. All state is advanced by integer ticks
   from the world clock, never by frame delta.

## Real-world grounding

- **Priority-flood depression filling (Barnes, Lehman & Mulla 2014).** The
  standard way a real digital elevation model is turned into a drainage
  network: seed a priority queue with every ocean cell, pop the lowest
  cell, and raise each unvisited neighbor to at least that height plus a
  tiny epsilon before pushing it. Every cell ends up with a strictly
  descending path to the sea, every real closed basin is identified with
  its **spill elevation** (the height at which it would overflow), and
  flat areas get a consistent drainage direction instead of an arbitrary
  one. Linear-time, deterministic, and exactly the algorithm that handles
  this project's biggest data problem (see "The elevation asset" below).
- **D8 flow direction and flow accumulation (O'Callaghan & Mark 1984).**
  Each cell drains to its steepest-descent neighbor of eight; the number
  of cells draining through a cell is its accumulation, i.e. its catchment
  area. Real rivers are exactly the high-accumulation cells of a real DEM.
- **Hack's law (Hack 1957).** Mainstem length scales with basin area as
  L ∝ A^0.6, on every continent. A place-agnostic statistical fingerprint
  of a real drainage network, used here as a validation test rather than
  as a rule: if the baked network's exponent is not near 0.6, the bake is
  wrong somewhere.
- **Hydraulic geometry (Leopold & Maddock 1953).** At a station, channel
  width scales as w ∝ Q^0.5 and depth as d ∝ Q^0.4 with discharge Q. This
  is how a live discharge becomes a river's width in tiles and its depth
  in meters, and depth in meters is already what `water_movement_model.gd`
  reads to decide wading versus swimming.
- **Meander wavelength (Leopold & Wolman 1960).** λ ≈ 11·w. Used to give
  channels a seeded, organic sinuosity at tile scale instead of the
  straight cell-to-cell lines the coarse network would otherwise produce.
- **The bucket model (Manabe 1969) and the linear reservoir.** The
  land-surface scheme of the first real general-circulation climate
  model: soil is a bucket that fills from precipitation and snowmelt,
  drains by evapotranspiration, and overflows as runoff. Groundwater as a
  linear reservoir (outflow proportional to storage) is the standard
  baseflow model and is the real reason rivers keep flowing through a dry
  season instead of stopping the day the rain does.
- **Degree-day snowmelt.** Melt per day ∝ (T − 0°C) above freezing, with
  a factor of roughly 3–5 mm per degree-day in real catchments. One
  multiplication, and it produces real spring floods: a winter's
  precipitation stored as snowpack and released in a few weeks.
- **Terminal-lake water balance.** A closed basin's lake sits where
  evaporation × surface area = inflow. Surface area grows with level (the
  basin's hypsometry), so the equation has one stable root: this is why
  real terminal lakes have a level at all rather than draining or
  overflowing, and why they shrink when inflow is diverted. Salt has no
  exit from such a basin, which is the entire reason they are salty.
- **Clearing forest raises runoff.** Well-documented in paired-catchment
  studies for a century: less transpiration, more of the same rain reaches
  the channel, higher flood peaks. Falls out of using
  `vegetation_growth_model.gd`'s live density as the transpiration input
  (see Coupling), and makes a player's deforestation a hydrological act
  with no extra rule.

## The elevation asset, and what it forces

Three measured facts about `assets/data/world_elevation.png` decide more
of this design than any pillar does:

1. **It is 8-bit.** 14,400 m of range in 256 steps is **56.5 m per
   step**. Byte 141.67 is sea level, so the lowest land value is byte
   143 = **75 m**, and every coastal plain and delta on the planet reads
   as one flat plateau at 75 m (measured: the same byte at the mouth of
   the largest river on Earth, at the largest delta in North America, in
   the Low Countries, and on the Po plain). On such a plateau the raw
   data has **no** drainage direction at all. Priority-flood with an
   epsilon gradient is the algorithm that gives it one, which is why it
   is the algorithm here and not the droplet walk `hydraulic_erosion.gd`
   uses (a droplet walk stops dead at the first flat cell).
2. **It is ~10 km per pixel** (3840×1920). The credited source is
   21,600×10,800, so ~1.85 km/px exists under the same license. Below
   the pixel scale there is no real relief; the game's ~1 km tiles get
   it from bilinear interpolation plus procedural noise.
3. **The procedural fine detail is ±432 m.** `EarthChunkGenerator.
   FINE_DETAIL_AMPLITUDE` is 0.03 of the range, with a ~10-tile period.
   That is bigger than the relief of most real lowlands. `slope_at_global`
   already refuses to read it for exactly this reason, and drainage must
   refuse too: routed on the blended elevation, the world would be a
   field of ten-thousand fake closed basins ten kilometers apart.
   **All routing runs on the macro elevation** (`macro_elevation_at_
   global`), never on `elevation_at_global`. Where a channel or lake
   exists, the fine detail is then *suppressed*, not fought (see "Valleys
   are read back into the elevation").

**Recommended data upgrade, decoupled from everything else:** a 16-bit
height field at the current 3840×1920 removes the 56 m steps (the bigger
hydrological problem) for ~15 MB raw. Godot's `Image` has no 16-bit
grayscale format and its PNG loader would truncate, so the honest carrier
is a raw little-endian `.u16` file read through `FileAccess` into the same
`PackedFloat32Array` lookup `earth_elevation_source.gd` already builds; the
bilinear sampler does not change. NOAA's ETOPO 2022 is public domain at 30
and 60 arc-seconds. Everything below is specified to work on the 8-bit
asset and to get better, not different, on a 16-bit one.

## Mechanism

### Layer 0: the drainage bake (static, shipped as data)

Run once, offline, by a headless Godot tool script
(`tools/bake_hydrology.gd`, the same "bake it once, commit the output"
relationship the illustrated sprite atlases already have to their
sources), over the elevation asset's **native pixel grid**, wrapping
east-west, clamped at the poles:

1. **Sea mask**: elevation < `EARTH_SEA_LEVEL`.
2. **Priority-flood with epsilon** from every sea cell outward. Outputs a
   *filled* surface (never rendered; only routed on) and, for every cell
   that had to be raised, the **depression** it belongs to: an id, its
   spill elevation, its spill LIP, and the depression it spills into
   (sea, or a parent depression, forming a tree). Depressions below
   `MIN_DEPRESSION_AREA_CELLS` are treated as data noise and simply filled
   through; the rest are **lake candidates**. With ~10 km pixels a
   candidate is a basin of at least a few hundred km², which is also the
   smallest lake the data could physically represent.
3. **D8 flow direction** on the filled surface (0–7, plus a code for
   "drains to sea"), and **flow accumulation** by processing cells in
   descending filled-elevation order.
4. **Per-depression hypsometry**: for each lake candidate, a table of
   surface area and volume as a function of water level from the basin
   floor to the spill elevation, from the *unfilled* elevation. This is
   what the live lake balance integrates against.
5. **Coarse upscaling**: a graph over the climate grid's cells (see
   Layer 1). Each climate cell's **outlet** is the fine cell of highest
   accumulation on its perimeter; its downstream climate cell is whichever
   cell that outlet's D8 path enters next. Every climate cell also records
   which depression, if any, its fine cells drain into. Standard
   dominant-river-tracing upscaling; it keeps a mainstem continuous at the
   coarse scale instead of letting it hop between cells.

Shipped outputs: a flow-direction raster (L8), a log-scaled accumulation
raster (L8; `log2` of catchment cells fits comfortably), a depression-id
raster (16-bit, same `.u16` carrier as the elevation upgrade), and one
compact `hydrology_bake.json` with the depression tree, hypsometry tables,
and the coarse graph. Deterministic from the elevation asset alone, so a
test can re-bake a small synthetic DEM and compare.

### Layer 1: the climate grid (climate_dynamics.md, made concrete)

climate_dynamics.md left cell size and tick cadence open. Hydrology needs
both decided, so:

- `CLIMATE_CELL_DEGREES := 1.0` -- 360×180 = 64,800 cells. Coarse enough
  for a pure-GDScript tick to be time-sliced across frames; fine enough
  that a major mountain range is several cells wide, which orographic
  lift needs (at 2° the highest ranges are one cell, and one cell has no
  windward and leeward side). A tested constant; profiling may move it.
- `CLIMATE_TICK_SECONDS := WeatherModel.WEATHER_PERIOD_SECONDS` (600 s of
  world clock, one game-hour of the 4-hour day). 24 ticks per day, 1,152
  per year. Every field below advances exactly once per tick; nothing
  here reads frame delta.
- Moisture advection is **semi-Lagrangian**: each cell samples the
  moisture field at (its position − wind × tick), bilinearly. Stable at
  any wind speed, no CFL condition, deterministic, and the same "sample a
  shared field at a fractional offset" shape as `elevation_at`.
- Currents and pressure use a fixed small number of Jacobi relaxation
  sweeps per tick (`RELAXATION_SWEEPS_PER_TICK`, tested constant), not
  iteration to convergence. Bounded cost per tick beats exact
  convergence, and the fields are relaxed *again* next tick anyway.
  Resolves climate_dynamics.md's "full relaxation vs. one pass" question.
- Cells carry, per tick: temperature, pressure, wind, moisture,
  **precipitation** (mm-equivalent, normalized), and a **snow fraction**
  of that precipitation (1.0 when the cell's temperature is below the
  freezing threshold, ramping to 0 above it -- the same freezing line
  `snowfall.gd` already uses for whether falling weather is snow).

### Layer 2: the land-surface buckets (live, per climate cell)

Every *land* climate cell keeps three stores, all normalized to
[0, 1] of a tested capacity, advanced once per tick in this order:

```
snowpack   += precipitation * snow_fraction
melt        = min(snowpack, DEGREE_DAY_FACTOR * max(0, T - T_FREEZE))
snowpack   -= melt
input       = precipitation * (1 - snow_fraction) + melt
soil       += input
et          = ET_RATE * f(T) * (0.3 + 0.7 * vegetation_density) * soil
soil       -= et
percolate   = PERCOLATION_RATE * soil
soil       -= percolate;  groundwater += percolate
surface_runoff = max(0, soil - SOIL_CAPACITY);  soil = min(soil, SOIL_CAPACITY)
baseflow    = BASEFLOW_RATE * groundwater;  groundwater -= baseflow
runoff      = surface_runoff + baseflow
```

`vegetation_density` is the climate cell's mean of the live
`vegetation_growth_model.gd` density for loaded chunks, and the biome's
carrying capacity for unloaded ones (the same loaded/unloaded fidelity
split ecosystem_dynamics.md's LOD section already draws). Soil moisture
here **is** the moisture the biome classifier reads (see Coupling); it is
no longer a noise field.

### Layer 3: routing (live, over the coarse graph)

Each tick, every land cell's `runoff` enters the coarse graph at that
cell and moves one edge downstream per tick with a linear-reservoir lag
(`CHANNEL_STORAGE_FRACTION` of the water in a cell's channel stays behind
each tick), summing as it goes. The result is a live **discharge** Q at
every coarse cell. Cells whose fine cells drain into a lake candidate
deliver their runoff to that depression's balance instead of downstream;
a depression's overflow (below) re-enters the graph at its spill cell.
Processing order is the bake's topological order of the graph, so one
sweep per tick is exact.

Discharge reaching a sea cell is delivered to the ocean and, for
climate_dynamics.md's purposes, slightly freshens and cools that coastal
cell (a real, minor effect; included because it is one addition, not
because it is important).

### Layer 4: lakes (live, per depression)

Per lake candidate, per tick, with A(h) and V(h) from the baked
hypsometry:

```
inflow    = routed runoff of the depression's catchment
          + precipitation over A(h)
          + overflow from any child depression that has spilled
evap      = LAKE_EVAPORATION_RATE * g(T) * A(h)
overflow  = max(0, V + inflow - evap - V(spill))
V         = clamp(V + inflow - evap - overflow, 0, V(spill))
h         = level_for_volume(V)
salt     += SALT_LOAD_PER_INFLOW * inflow      # salt arrives with water
salt     -= salt * (overflow / V)              # ...and leaves only by overflow
salinity  = salt / V
```

A depression with positive net balance climbs to its spill and overflows;
its salinity converges to the low inflow concentration. A depression whose
evaporation catches its inflow below the spill stops there and its salt
only ever accumulates. `is_salt_lake := salinity > SALT_LAKE_THRESHOLD`,
a reading, never a stored label. A basin the live climate dries out
*becomes* a salt lake over game-years; one that wets up eventually spills
and freshens, which resolves climate_dynamics.md's "long-timescale
reversibility" question for lakes by construction.

### Layer 5: the tile read (what a chunk actually gets)

`EarthChunkGenerator` gains a `HydrologyField` the way it already holds a
`TerrainRelief`, and asks it three questions per cell. All three are
answered from the baked rasters, the 3×3 fine-cell neighborhood, and the
coarse cell's live state, so a chunk stays computable from its own global
coordinates alone -- no chunk-relative state, no seams.

**Is this tile in a lake, or in the sea?** The bake's water cells are the
footprint; the shoreline is the **half-coverage contour** of that cell
mask under a smooth kernel about a cell and a half wide (the metaball
construction: a blurred binary mask has rounded, blob-like level sets).
The same field decides what the water painter draws and what the player
swims in, and the generator's sea classification reads it too, so the
coastline is one line. This replaced an elevation-contour shoreline
after the third playtest: on 8-bit, 10-km data the bilinear contour is a
staircase of pixel-edge hyperbolas ("a folded-up snake"), while the
kernel contour is "circle-ish, derived from the contour path of the
basin". A lake tile's depth is spill minus macro elevation, never less
than a metre inside the footprint. A river mouth's current runs on into
the still water it empties into and fades over `PLUME_TILES`, so the
flow lines continue out of the mouth and settle into ripples. **Which basins hold water at all** is, in phase 1, a
stand-in for Layer 4's balance: the bake drops basins shallower than one
and a half asset steps (the first real bake found 8,794 of its 10,776
depressions exactly one 8-bit step deep, one flat plain after another
reading as ponds) and basins whose catchment delivers under
`LAKE_MIN_INFLOW_PER_CELL` of full rain per lake cell (a subtropical
pocket fed only by itself dries out; a basin with a catchment a few times
its size holds). "Ponds only where water flows and rain accumulates."

**Is this tile in a river channel?** The fine cell's live discharge is
`Q_fine = Q_coarse * (acc_fine / acc_outlet)`, the coarse cell's discharge
scaled by catchment share. A channel exists where
`Q_fine >= RIVER_MIN_DISCHARGE`. Each channel cell owns one piece of the
centerline: a **quadratic Bezier** from the midpoint toward its mainstem
upstream cell, through its own center (the control point), to the
midpoint toward its downstream cell. Adjacent cells share endpoints and
tangents, so the line is smooth through every corner by construction (the
first playtest's "make curves smoother"); the seeded meander of
wavelength `11 * w` the first draft described is still a follow-up. A
**headwater** cell's piece starts instead at its *source*, the cell that
drains into it below the threshold, at `SPRING_HALF_WIDTH_TILES`, so a
river tapers in from a point rather than appearing full-width ("springs:
rivers just start out of nothing"). A tile is channel if its distance to
the curve is within the local half-width, where the width is the cell's
own discharge interpolated along the curve:

```
w_tiles = clamp(MIN_LEGIBLE_WIDTH + WIDTH_PER_DOUBLING * log2(Q_fine / RIVER_MIN_DISCHARGE), 1, 12)
depth_m = DEPTH_COEFFICIENT * Q_fine ^ 0.4     (field); Manning normal depth (generator)
```

Because width follows discharge and discharge sums at a confluence, two
rivers meeting produce one reach that is wider exactly where they meet,
and the Manning solve on the combined discharge conserves `Q = w * d * v`
("combined volume, width times depth"). The width formula is hydraulic
geometry with the same **monotone exaggeration toward legibility**
[stone.md](stone.md) already applies to pebbles: a real 300 m river is
narrower than one 1 km tile and would be invisible, so widths are
stretched at the small end without ever reordering them. Depth is *not*
exaggerated: it feeds `water_movement_model.gd`'s wade/swim decision and
[infrastructure.md](infrastructure.md)'s ford → ferry → bridge ladder, and
those want real meters. A boulder on the bank apron, not only mid-stream,
is an obstacle the waterline parts around ("wrap shorelines around edge
boulders").

A channel with `Q_fine` below the threshold is **not** absent, it is
**dry**: an accumulation-bearing cell with no discharge is a wadi, and it
runs after a rain because `Q_fine` rises past the threshold for a few
ticks. Ephemeral rivers are the same rule at a different time.

**How wet is the ground?** The cell's soil bucket, bilinearly sampled from
the four nearest climate cells, replaces `moisture_at_global`'s noise.

### Valleys are read back into the elevation

A river that ran across the ±432 m fine-detail noise would climb hills.
So the fine-detail term is scaled down toward zero within
`VALLEY_HALF_WIDTH_TILES` of a channel centerline and inside a lake, and
a small **valley carve** proportional to `log2(acc_fine)` is subtracted
from the macro elevation along the centerline. Both feed `elevation_at_
global`, so slope, hillshading, and passability all see a real valley
with the river at its floor. This is the one place drainage writes back
into terrain, and it is what `hydraulic_erosion.gd` was always trying to
produce; the difference is that the shape comes from the real network
rather than from random droplets, and it is a pure function of position,
so it stays seamless and regenerable.

**The geometry reach covers the map filter, not just the painter
(2026-09-05).** Found live at the Loire spawn: thin phantom channels ran
parallel to the river several tiles out on the world, never on the
minimap. The painter writes every tile's signed across-position into the
flow map, and past a channel's reach `nearest_river_at` falls back to the
nearest *curated* river (the Rhine, 800 tiles away), whose sign is
arbitrary and whose magnitude clamps to `CLAMP_MAGNITUDE`. The channel
query's reach had been raised to cover the painter's bleed, but the map
FILTER reads one texel further (bilinear) or two (the cubic
reconstruction), and interpolating a real `+6` against a fallback `-16`
crosses zero *inside* the painted cell beside it: the shader drew a
hairline of water along the whole reach boundary. `_channel_hits` now
answers out to `GEOMETRY_REACH_TILES` = `VALLEY_HALF_WIDTH_TILES` +
`MAP_FILTER_SUPPORT_TILES` (2 texels), so every texel the filter can
blend into a painted cell still describes the channel's own side; the
valley shoulder itself is unchanged. Pinned by
`test_the_geometry_reach_covers_the_map_filters_neighbours_of_the_bleed`
and `test_a_tile_past_the_bleed_still_gets_real_channel_geometry_on_the_same_side`;
verified on the GPU at the Loire window (the phantom lines are gone, the
real channels untouched). The minimap was right all along: it reads the
river *kind*, which never saw the fallback. What remains honest but
narrow: a channel just over `RIVER_MIN_DISCHARGE` is one tile wide by the
width formula, so the minimap's tile-centre test draws it one or two
pixels wide and a diagonal at exactly the threshold can dot; a rendered
half-width floor of one tile (two tiles total, the least a per-tile
across map reconstructs) would make every river contiguous on both
surfaces at the cost of the taper-to-a-point spring, and is the named
follow-up.

### Water kinds: overlay flags, one predicate

Per rivers.md's rendering decision (see "Relationship to rivers.md"), a
water tile keeps its land biome. `Chunk.is_lake` sits beside the existing
`Chunk.is_river`, both written by `generate_chunk` from the same probe,
and `Chunk.blocks_ground_cover(index)` is the one predicate trees, tall
grass, snow presence and rooting read. **Lakes, rivers and the sea are
one water surface**: all three ride the river flow overlay. A river tile
writes its signed across-channel offset over its own half-width (a mouth
keeps flowing into the sea cells it reaches); a lake tile writes
`1 + (elevation − spill) / LAKE_SHORE_BAND` and a sea tile the same with
sea level as the surface, both with zero current, so every waterline is
an elevation contour drawn with the same smooth bank curve, ink line and
feather a river gets, and still water keeps a quarter of the surface
morph as ripple but never drifts. The ocean's old shore-distance overlay
stays wired only as the fallback for a scene without a flow layer (the
first draft put lakes on it; the first playtest read its square tiles as
"a very different art style", and the same tiles were every coastal
"pond"). Below-sea-level pockets not connected to the ocean are lakes at
sea level (`inland_sea` in the bake), and the fine-detail texture may
never move a tile across sea level, so the coastline is the macro
contour and nothing else. The player's water depth is the maximum of
ocean, river and lake depth.
Salinity and lake id (phase 3) become per-cell side fields on `Chunk`,
never biome names: salt is a property of the water, not a kind of ground.

### Equilibrium bake and catch-up

The bake also runs the *coupled* Layers 1–4 forward, offline, with lake
levels solved directly each step (set h where the balance is zero rather
than integrating toward it) until every field's annual cycle repeats
within a tolerance. It ships two things:

- the **initial state** a new world loads (lakes already at their
  levels, rivers already flowing, soil already at its seasonal value for
  the day of year the world starts on -- [seasons.md](seasons.md) already
  starts worlds at a random point in the year, and hydrology must agree
  with the season it lands in);
- a **climatology**: for each cell and each of the 48 days of the year,
  the mean of every field. This is the fallback when a loaded save is
  further behind than `MAX_CLIMATE_CATCHUP_TICKS` allows replaying: the
  grid is reset to the climatology for the current day of year and
  perturbed forward from there, the same "bounded replay, then jump to
  the closed form" shape `chunk_ecology_catchup.gd` uses for ecology.

Climatology is also the honest **hysteresis baseline** for
climate_dynamics.md's biome transitions: a cell's biome flips when its
*running seasonal mean* moisture, not its instantaneous bucket, crosses
the threshold, which is what stops a single wet week relabeling a desert.

## Coupling: what reads this, and what it replaces

| Consumer | Today | After |
|---|---|---|
| `EarthChunkGenerator.moisture_at_global` | `FastNoiseLite` | soil bucket, interpolated |
| `BiomeClassifier.classify` moisture input | worldgen noise | live soil moisture (via the above) |
| `WeatherModel.soil_moisture(state)` | 4 constants by weather string | the cell's soil bucket; the string API stays as a thin presentation read, resolving climate_dynamics.md's open question the way it leaned |
| `EcosystemSimulation._water_access_fraction` | fraction of ocean cells | fraction of *fresh* water cells, weighted: lake/river 1.0, ocean `OCEAN_DRINK_WEIGHT` (herbivores drink fresh water) |
| `WaterAreaSurvey` / `AquaticPopulationModel` | ocean only | every water kind; salinity gates the species pool ([fishing.md](fishing.md)'s "keyed generically by water region" was written for this) |
| `survival.md` thirst | -- | drinkable iff `is_water` and not salt (ocean counts as salt) |
| `electromagnetism.md` water wheel | "elevation gradient as a proxy" (its own open question) | `Q_fine * slope`, the real hydraulic power input |
| `infrastructure.md` ford/ferry/bridge | no river concept | `depth_m < WADE_DEPTH_METERS` is fordable; deeper needs a ferry, then a bridge |
| `transportation.md` boats | -- | navigable iff `depth_m >= draft` |
| `weather.md` floods and droughts | listed, unbuilt | **flood**: `Q_fine > FLOOD_RATIO * Q_climatology` puts tiles within the channel's floodplain (macro elevation within `FLOODPLAIN_RISE_M` of the channel) under water for the duration; **drought**: soil below `DROUGHT_FRACTION` of climatology for `DROUGHT_MIN_DAYS`. Both are threshold readings of state this doc already keeps, no disaster roller |
| `src/emergence/event.gd` | -- | flood onset, drought onset, a lake crossing its spill in either direction, and a river running dry each emit an `Event`, per [00-emergence-architecture.md](../emergence/00-emergence-architecture.md); this is the concrete answer to climate_dynamics.md's "should a storm be an Event" question, for the hydrological events |

**Fish** live in all three water kinds (`WaterAreaSurvey.is_water_cell`
counts river and lake cells; `FishMarker` reads the river and lake flags
beside the ocean biome). A fish swims against the same current the flow
overlay draws (`EarthChunkManager.river_current_at_global`: the solved
river velocity, or a mouth's fading plume): slower upstream, faster
downstream, and flapping more often upstream, and every fish is fed to
the flow shader as a wader so its flaps ring the current's contour lines
(playtest: "fish should also swim in rivers, upstream just slower and
more flapping, and produce ripples in the current contour lines").

A river or lake tile is a discrete kind flag, not a coverage fraction: the
tile read above calls a tile "river" once its *centre* is within the
channel's own half-width, which for a narrow channel or a tile right at
the bank can flag a tile whose footprint is mostly dry land. Fish spawning
already accounted for this (`WaterAreaSurvey.is_interior_water` holds a
spawn candidate to "this tile and its 4 cardinal neighbours are all
water", never a shore-adjacent cell), but swimming did not, so a fish
already in the water could wander from a genuinely-covered tile onto a
merely-flagged one and visibly sit half on dry ground (reported directly:
"fish should be constrained to the full rivertiles not the shore tiles
otherwise they swim on a half land tile sometimes"). `FishMarker` now
holds its own swim-time water check to the same interior bar for river and
lake tiles -- a neighbour of any water kind counts (a river mouth's bank
against the sea is still open water, not shore) -- while the open ocean
stays unconstrained there, since it already has its own tuned shore-hugging
behavior (`CLEARANCE_PX` and shore deflection) built for a coastline, not a
one-tile-wide channel.

Vegetation density feeding transpiration closes a loop with
[flora.md](flora.md): a forest a player clears sheds more runoff, its
river floods higher, and its soil dries faster between rains, with no
rule written for any of it.

## Worked examples

Nothing below is scripted for a named place; the tests in the plan are
where names appear.

1. **A wet windward coast with a big cold-current desert behind it.**
   climate_dynamics.md's rain shadow puts heavy precipitation on the
   windward slope and almost none in the lee. Layer 2 fills the windward
   cells' soil past capacity every tick: high runoff, big accumulation,
   short steep rivers to the sea, each one tile wide because their
   catchments are small. The lee cells' soil never reaches capacity;
   their channels carry accumulation but no discharge: dry beds that run
   for a few ticks after the rare storm and are otherwise walkable sand.
2. **One basin, two fates.** A closed basin at the same latitude on two
   continents. On the humid one, inflow exceeds lake evaporation at every
   level below the rim; the lake climbs to its spill, overflows, feeds
   the downstream river, and stays fresh. On the arid one, evaporation
   over the growing surface catches the inflow halfway up; the level
   stops, the shoreline sits well inside the basin, and salinity climbs
   past the threshold within a few hundred game-years of the bake's
   spin-up. Same code path, different reading of `is_salt_lake`.
3. **A spring flood.** A mid-latitude interior cell receives most of its
   winter precipitation at `snow_fraction` 1.0; nothing reaches the
   channel for a season and the river runs on baseflow alone. Spring's
   `warmth_modifier` pushes T past freezing, the degree-day melt releases
   the whole pack in a few days, `Q_fine` crosses `FLOOD_RATIO`, the
   floodplain tiles go under, a flood `Event` fires, and a village on the
   terrace above watches from dry ground while the one on the plain does
   not.
4. **A player clears a hillside forest.** The climate cell's mean
   vegetation density falls; transpiration falls with it; the same rain
   now overflows the soil bucket sooner. The stream below runs higher in
   wet weeks and the soil reads drier in dry ones. Nobody wrote a
   deforestation rule.

## Open questions

- **The 16-bit asset upgrade** is recommended before the *shipped* bake,
  because it decides where rivers cross plains. Everything else in this
  doc is indifferent to it. Whether to also move to the 21,600×10,800
  source resolution is a separate, later size-versus-fidelity call.
- **Meander.** The centerline is smooth but follows cell centers; the
  seeded meander (wavelength `11 * w`) on top of the Bezier is still to
  do.
- ~~**Boulder push scale.**~~ Resolved: the push divides by the per-texel
  half-width from the separate scale map, and each boulder now carries
  its own radius from its real diameter (see rivers.md "Boulders are
  hydrology"). Original note kept below for history. The flow shader scales a boulder's displacement
  by one uniform half-width (the catalog's two tiles); a one-tile stream
  gets a push a quarter as strong as it should. The texel has no free
  channel for a per-tile half-width; packing one is a follow-up.
- **Sub-cell water** (ponds, small lakes, first-order streams) is below
  the data's resolution. A plausible extension: within a climate cell
  whose soil is at capacity, tile-scale depressions in the *blended*
  elevation fill as seasonal ponds. Chunk-local priority-flood would need
  a margin to be seamless, and that cost has not been measured.
- **Lake ice.** A lake whose cell temperature stays below freezing for
  `ICE_MIN_DAYS` should become walkable; [snow_cover.md](snow_cover.md)'s
  presence bit is where it would render. Not specified further here.
- **Tick cost.** 64,800 climate cells plus the coarse graph per 600 s of
  world time is the budget; the time-slicing granularity (rows per frame)
  is a tested constant to be set by profiling, not here.
- **Bake cost.** Priority-flood over 7.4M cells in GDScript is minutes,
  which is acceptable for an offline tool that runs once per asset
  change. If the 16-bit source at higher resolution makes it hours, the
  bake becomes a C++ GDExtension or moves to a script outside Godot.

## Test plan

Red-first, per CLAUDE.md; each bullet is the first failing test of its
mechanism, on small synthetic grids unless marked *(real data)*.

- **`DrainageNetwork`**: a 5×5 bowl with one sea cell fills so every cell
  has a strictly descending path to the sea; a flat plateau gets a
  consistent, acyclic flow direction; a crater becomes exactly one
  depression whose spill lip carries its whole outflow; accumulation at
  the sea cell equals the land cell count.

  The lip is a SET of cells, not one cell, and the spec used to say
  otherwise. Filling raises every member of a depression to exactly the
  spill elevation, so the rim it leaves through is flat and the outflow
  splits across it -- three ways in the reference crater, carrying 13, 4
  and 13 of the 30 the basin collects. A basin's throughput is therefore
  the sum over its lip (`DrainageNetwork.outflow_of`), never the value at
  any single cell; reading one cell understated the lake balance's inflow
  by however many ways the lip happened to split. `spill_index` survives
  as the principal outlet -- the member carrying the most flow -- for
  anything that wants one point to name a depression by.
- **Hack's law** *(real data)*: over the baked network's twenty largest
  basins, the fitted exponent of mainstem length vs. area lies in
  [0.5, 0.7].
- **Mass conservation**: over a closed synthetic world for 1,152 ticks,
  precipitation in equals evaporation + discharge to sea + storage change
  within 1e-3 of the total.
- **`LakeBalance`**: a crater under inflow > evaporation reaches its spill
  and overflows; under inflow < evaporation it settles strictly below the
  spill and its salinity increases monotonically; halving evaporation on
  the settled salt lake makes it eventually spill and its salinity fall.
- **Snowmelt**: a cell held below freezing for a season accumulates
  snowpack and sheds no runoff; raising T releases it, and the runoff peak
  exceeds the peak of the same precipitation delivered as rain.
- **Transpiration coupling**: identical rain over two cells with
  vegetation density 1.0 and 0.2 gives the sparser cell strictly more
  runoff.
- **River geometry**: width is non-decreasing in Q; every channel is at
  least one tile wide; depth follows Q^0.4 within tolerance; the meander
  polyline for one fine cell is bit-identical across two chunks that
  share it.
- **Valley carve**: a tile on a channel centerline has lower
  `elevation_at_global` than the same tile with hydrology disabled, and
  its fine-detail contribution is zero.
- **Determinism**: two worlds with the same seed agree on every field
  after 2,000 ticks; catch-up past the cap lands exactly on the
  climatology for that day of year.
- **Reality checks** *(real data, integration, expected to be the tests
  most sensitive to the 8-bit asset)*: the fine cell at (0°S, 50°W) lies
  on the highest-discharge channel of its hemisphere; the depression
  containing (41°N, 112.5°W) is a salt lake in the equilibrium state; the
  depression containing (47.7°N, 87.5°W) is fresh and overflowing; the
  cell at (23°N, 10°E) has accumulation but zero climatological discharge.

## Implementation order

Each phase merges to `main` on its own, per CLAUDE.md, and is playable
without the next.

1. **Drainage bake + tile read with a stand-in climate.** `DrainageNetwork`,
   the bake tool, `HydrologyData`, `HydrologyField`, `Chunk.is_lake` and
   `blocks_ground_cover`, the valley carve, lakes on the water overlay,
   and baked channels as rivers.md's gated fallback through its own flow
   overlay and hydraulics. Discharge comes from a placeholder
   `P(latitude)` curve so lakes are *visible and walkable* before the
   atmosphere exists, and rivers are one flag away once the bake has been
   seen in play.
2. **The climate grid** (climate_dynamics.md's fields, with the constants
   decided above), producing real precipitation and snow fraction.
3. **Buckets, routing, lakes, equilibrium bake, climatology catch-up.**
   The stand-in from phase 1 is deleted.
4. **Coupling**: moisture → biomes and vegetation with hysteresis,
   `WeatherModel` as presentation, water access, thirst, floods and
   droughts as `Event`s.
5. **16-bit elevation asset** and re-bake, whenever the data is sourced.

## Status

Phase 1 is written, red-first, on branch `claude/hydrology-spec`
(2026-09-03): `drainage_network.gd`, `stand_in_precipitation.gd`,
`hydrology_data.gd`, `tools/bake_hydrology.gd`, `hydrology_field.gd`, and
the generator/chunk-manager/player wiring above, with their tests. **None
of the tests have been run yet** (deferred at the user's request) and
nothing is merged to `main`. **The bake has been run** over the real asset
(154 s; 197,109 channel cells at Q>=30 and 10,776 depressions covering
6.6% of land, more than the real ~2% because every one-step basin of the
8-bit asset counts) and ships in `assets/data/hydrology`.
`tools/probe_hydrology.gd` ranked the Loire below Nantes and then the
Gironde as the strongest emergent channels in western France, so the
network finds the real rivers; on that evidence
`HYDROLOGY_RIVERS_ENABLED` is on and the spawn moved to the Loire at
Nantes (`World.SPAWN_LATITUDE`), where the game was launched and the
flowing channel seen on screen. Open from that first look: the player
appeared mid-channel in swimming mode although `tools/probe_spawn.gd`
shows dry land two tiles from the spawn tile, so the dry-land spawn
search wants checking with `test_world_spawn_location.gd`. Phases 2-5
are design only. Depends on
[climate_dynamics.md](climate_dynamics.md) for precipitation (also
unimplemented). `hydraulic_erosion.gd` is superseded by the drainage bake
for Earth and stays as-is for future procedural planets
([planets.md](planets.md)), whose heightmaps can be fed through the same
bake. `docs/progress.md` tracks each phase.
