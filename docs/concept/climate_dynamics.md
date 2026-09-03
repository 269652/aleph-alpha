# Climate Dynamics

This doc replaces two things that exist today but aren't actually climate
simulation: `weather_model.gd`'s weather is a **flat per-region dice roll**
(a desert cell and a rainforest cell have identical odds of a storm today),
and `biome_classifier.gd`'s classification is a **one-shot worldgen
snapshot** (temperature/moisture are computed once, never revisited). This
spec makes both real outputs of a live atmospheric/water-cycle simulation —
pressure, wind, ocean currents, and precipitation all causally connected,
the same way [ecosystem_dynamics.md](ecosystem_dynamics.md) made "boars are
where boars thrive" a real mechanism instead of a spawn table.

## Design pillars

1. **Real mechanisms, not per-region dice rolls.** A storm exists because a
   pressure gradient and a temperature contrast crossed real thresholds at
   that place, not because a hash roll landed in the top 5%. Direct
   extension of [ecosystem_dynamics.md](ecosystem_dynamics.md)'s pillar 1
   ("real mechanisms, not scripted spawns"), applied to atmosphere instead
   of ecology.
2. **Two fidelities, one truth** — same shape
   [ecosystem_dynamics.md](ecosystem_dynamics.md#design-pillars) already
   uses for population, reused here for atmosphere: a **coarse global
   circulation grid** (cells spanning hundreds of kilometers, updated on a
   slow tick) is the aggregate truth; individual terrain tiles read their
   local climate by **interpolating** from that coarse grid, the same way
   `earth_elevation_source.gd` already bilinearly samples real elevation
   data rather than storing a value per tile. No tile runs its own weather
   simulation, exactly no chunk runs its own population simulation today.
3. **Matches real-world climate because it runs on the same causes, not
   because it's told to.** Nothing in this doc names a desert, a current,
   or a region. The Sahara, the Gulf Stream, and the Atacama's aridity all
   exist in reality because of pressure bands, wind-driven currents, and
   coastline geometry — this model computes those same causes over this
   project's already-real latitude and elevation data, so real-world-
   plausible outcomes fall out without any place ever being special-cased.
   Directly extends the reasoning
   [ecosystem_dynamics.md](ecosystem_dynamics.md#why-not-real-world-danger-statistics-and-why-not-manual-region-curation)
   already used to reject hand-mapping real regions for a different system.
4. **Determinism.** Same seed, same elapsed time → same climate state,
   matching every other simulated system in this project.
5. **Biomes transition, they don't snap.** A region whose simulated climate
   crosses into a new biome's range visibly drifts there over real time,
   the same "don't reveal a whole field in one frame" principle
   [weather.md](weather.md#snow)'s snow-accumulation
   section already had to learn the hard way for a much smaller case.

## Real-world grounding

- **Three-cell circulation, flattened to one latitude curve.** Real Earth's
  atmosphere organizes into three circulation cells per hemisphere (Hadley,
  Ferrel, Polar): air rises at the equator (low pressure — this is why the
  world's rainforests cluster there), sinks around 30° latitude (the
  subtropical highs — this is why the world's major deserts, regardless of
  continent, cluster at almost exactly this latitude band), rises again
  near 60°, sinks at the poles. Flattened here to one periodic
  `baseline_pressure(latitude)` curve, real physics compressed to one
  function the same way materials.md compresses real fracture mechanics to
  one threshold check.
- **Land/ocean thermal inertia.** Water heats and cools far more slowly
  than land under the same sunlight — the real reason coasts are milder
  than continental interiors and the real driver of monsoon reversal.
  Already have the input this needs: `biome_classifier.gd`'s ocean/land
  split from elevation.
- **Coriolis deflection.** Moving air and water deflect right of their
  direction of travel in the northern hemisphere, left in the southern,
  strongest at high latitude and zero at the equator — the real reason
  trade winds and ocean gyres blow at a diagonal instead of straight along
  a pressure gradient, and the reason the equator is unusually storm-calm
  (the "doldrums") despite being the warmest, lowest-pressure band on the
  planet. This project already has real latitude (and therefore
  hemisphere) per cell, so this is a direct multiplier, not a new input.
- **Wind from pressure gradient.** Air flows from high to low pressure,
  deflected by Coriolis into something closer to the real geostrophic wind
  than a straight line — this REPLACES `weather_model.gd`'s current
  `wind_direction_for`, which is an independent random walk with no
  relationship to pressure, temperature, or geography at all.
- **Ocean currents: wind-driven, Coriolis-deflected, coastline-redirected.**
  Real surface ocean currents are, to first order, wind stress on the
  ocean surface, deflected by Coriolis and redirected wherever a continent
  blocks the straight path — genuinely emergent from wind + geometry, not
  a separately-designed system. Because this project already has real
  coastline geometry (real Earth elevation data), the same computation run
  here should produce a warm poleward-flowing current on an ocean's western
  boundary and a cold equatorward one on its eastern boundary at the right
  latitudes for the same structural reason the real Gulf Stream and the
  real Peru/Humboldt Current exist — not because either is named anywhere
  in this spec.
- **The water cycle.** Evaporation rate rises with sea-surface temperature
  (real Clausius–Clapeyron relationship, flattened to a monotonic curve);
  evaporated moisture is carried downwind (advection) and accumulates
  along the way; precipitation fires when moisture crosses a saturation
  threshold, when wind is forced to climb real rising terrain (**orographic
  lift** — moisture drops sharply on a windward slope, arrives at the
  leeward side already spent, which is the actual mechanism behind every
  real rain-shadow desert, e.g. the Atacama sitting in the lee of the
  Andes), or where moist air converges at a low-pressure zone (the
  equatorial convergence falls directly out of pressure already being
  lowest there).
- **Storms.** A real extratropical storm forms where a strong pressure
  gradient meets a real temperature contrast (a front); a real tropical
  cyclone forms over sufficiently warm open ocean, gated by needing enough
  distance from the equator for Coriolis to impart spin (the real reason
  hurricanes essentially never form within about 5° of the equator, calm
  "doldrums" and all). Both are threshold crossings over quantities this
  model already computes — no separate storm system.

## Mechanism

### The coarse climate grid

Pressure, temperature, moisture, wind vector, and (ocean cells only) a
current vector live on a grid many times coarser than terrain tiles —
comparable in spirit to how real general-circulation climate models run at
tens-to-hundreds-of-kilometers resolution rather than per-meter, because
the physics that matters here operates at that scale. The grid advances on
a slow **climate tick** (a natural fit for `weather_model.gd`'s existing
`WEATHER_PERIOD_SECONDS`-scale cadence, or `season_cycle.gd`'s pacing — not
decided here, see Open questions), each tick relaxing every field toward
its neighbors and its local forcing — the same **cellular-automaton /
reaction-diffusion shape** [world.md](world.md#a-living-physically-grounded-world)
already names for vegetation spread, applied to atmosphere instead of
plant density.

Terrain tiles never run this simulation themselves — they read it, the
same "individual tiles sample a shared field, they don't each compute it"
relationship `earth_elevation_source.gd`'s bilinear sampling already has to
the underlying elevation data.

### Pressure

`baseline_pressure(latitude)` is the flattened three-cell curve above,
shifted seasonally by `season_cycle.gd`'s existing `warmth_modifier` (the
real reason the equatorial low/ITCZ and the subtropical highs migrate
north and south with the seasons, driving real monsoon reversal — this
project already computes the exact seasonal signal that migration needs,
it just isn't feeding anything atmospheric yet). Local pressure departs
from that baseline based on local temperature (warmer → lower pressure,
colder → higher — `climate_model.gd`'s existing `temperature_at` is a
direct input) and land/ocean identity (land's faster heating/cooling
produces a bigger seasonal pressure swing than the oc' more stable one).

### Wind

`wind = normalize(pressure_gradient) rotated by a Coriolis term`, the
rotation's sign set by hemisphere and its magnitude scaling with
`sin(|latitude|)` (zero at the equator, strongest toward the poles — the
real reason the equator is calm and the mid-latitudes are the stormy
belt). This is a full replacement for `weather_model.gd`'s
`wind_direction_for`, which today has no relationship to anything
physical.

### Ocean currents

Surface current on ocean cells is the wind field's own stress on the
water, Coriolis-deflected the same way wind is, then relaxed against real
coastline geometry so a current redirects along a coast instead of running
through it — an iterative relaxation problem structurally similar to the
one `hydraulic_erosion.gd` already solves for terrain (that module isn't
wired into the live real-Earth pipeline today — see `docs/progress.md`'s
Phase 0 table — but its iterative-relaxation-over-a-grid *shape* is the
right one to reuse here, live or not). A current's own temperature departs
from its cell's baseline sea-surface temperature toward wherever it
originated — a current that's traveled from warmer latitudes arrives
warm, and vice versa — which is what feeds back into evaporation below and
is the actual mechanism (not an assertion) behind a coast being milder or
more arid than its bare latitude would suggest.

### The water cycle and precipitation

`evaporation_rate(ocean_cell) ∝ f(sea_surface_temperature)`, monotonic,
warmer evaporates more. Evaporated moisture is added to that cell's
moisture field and advects along each tick's wind vector, accumulating as
it travels. Precipitation triggers per-cell when any of:

- accumulated moisture crosses a saturation threshold,
- the wind vector is currently climbing a real rising elevation gradient
  (orographic lift, using the exact same slope/aspect field
  [terrain_relief.md](terrain_relief.md#slope-and-aspect-one-derived-field-computed-from-data-that-already-exists)
  computes from this project's real elevation data for its own passability/
  hillshading use — one shared field, not two) — moisture drops sharply
  here, so the leeward side downwind necessarily receives less, a rain
  shadow **as a direct consequence, not a separate rule**,
- or two moisture-carrying wind vectors converge at a local pressure
  minimum.

### Storms

`storm_intensity` is nonzero only where a pressure-gradient magnitude AND
a temperature/moisture contrast both cross their own thresholds — the same
"tags define what's possible, thresholds decide what fires"
[materials.md](materials.md#effects-from-thresholds-not-authorship) pattern
this project already uses for combat outcomes, applied to weather. This
replaces `weather_model.gd`'s flat 5%-of-all-rolls storm chance
(`RAIN_THRESHOLD` to 1.0) with a real, place-and-season-dependent
probability — a subtropical high sits calm nearly all year, a mid-latitude
frontal zone in autumn does not, for the same reason those are true on the
real planet.

### Biomes: a live read, not a worldgen snapshot

`biome_classifier.gd`'s `classify()` keeps its exact elevation/temperature/
moisture threshold logic unchanged — only WHERE its temperature and
moisture arguments come from changes, from a value computed once at
worldgen to a value read live off the climate grid, recomputed on the same
slow climate tick as everything else above. Two things keep a transitioning
region from flickering or snapping:

- **Hysteresis** — a cell's climate has to sit past a threshold for a
  sustained duration before its biome label actually flips, the same
  formation/stabilization/dissolution-hysteresis shape
  [01-society-and-institutions.md](../emergence/01-society-and-institutions.md)
  already specifies for institutions forming and dissolving, reused here
  to stop a biome label flickering on ordinary day-to-day climate noise.
- **Visible drift, not a snap cut** — `vegetation_growth_model.gd` already
  grows/dies vegetation density toward a climate-derived carrying capacity
  over real time; once biome LABEL is also climate-derived, the existing
  density response is what makes a transitioning region visibly thin from
  forest toward grassland (or thicken the other way) rather than an
  instant relabel, the same lesson
  [weather.md](weather.md#snow)'s snow-coverage
  section already learned for a smaller case ("the ground turned white in
  one frame" was a reported bug there; an instant biome flip would be the
  same bug at map scale).

## Worked examples

Mirroring [materials.md](materials.md#worked-example--throw-the-oil-barrel-into-the-torch-lit-room)'s
own worked-example shape — nothing below is scripted for a named place:

1. **A windward rainforest, a leeward desert, same latitude.** Prevailing
   wind carries ocean moisture inland; real rising elevation forces it up
   a mountain range; most of it precipitates on the windward slope
   (orographic lift); the leeward slope receives the same wind, now dry.
   One mechanism, two opposite outcomes a few tiles apart — an
   Atacama/Cascades-shaped result with no desert or rainforest ever named
   in code.
2. **A cold-current coast, arid despite tropical latitude.** A wind-driven,
   Coriolis-deflected current arrives from higher latitude, carrying cold
   water equatorward along a coastline; the cold surface suppresses local
   evaporation; onshore wind that would otherwise be moist arrives dry —
   a Namib/Atacama-coast-shaped outcome, from current temperature alone.
3. **A stormy autumn belt where a current-warmed coast meets a colder
   interior.** The temperature contrast crosses the storm threshold
   specifically where warm-current air meets cold-interior air, and
   specifically in the season the seasonal pressure shift pushes that
   front into range — storms cluster in a real place and a real season for
   a real reason, not a flat 5% anywhere, anytime.

## Open questions

Three of the questions below are now decided in
[hydrology.md](hydrology.md#layer-1-the-climate-grid-climate_dynamicsmd-made-concrete),
which needs them settled to route water: cell size (`CLIMATE_CELL_DEGREES`
1.0), tick cadence (`CLIMATE_TICK_SECONDS` = `WEATHER_PERIOD_SECONDS`), and
fixed-sweep relaxation rather than iteration to convergence. That doc also
answers the reversibility question for lakes, the `weather_model.gd`
presentation-layer question (the lean below is confirmed), and the `Event`
question for the hydrological events. The bullets are kept as written so
the reasoning behind each stays here.

- **Coarse-grid cell size and climate-tick cadence** — needs real
  profiling once built; a tuned constant, not an eyeballed one, per this
  project's no-manual-tuning rule.
- **Full iterative relaxation vs. a cheaper one-pass approximation** for
  currents/pressure — a real performance-vs-fidelity tradeoff, undecided;
  `hydraulic_erosion.gd`'s existing (currently Earth-inactive) relaxation
  solver is the closest precedent either way.
- **Does `weather_model.gd`'s four-state vocabulary (clear/cloudy/rain/
  storm) get replaced outright, or does it become a thin presentation
  layer** that reads this model's real precipitation/pressure output to
  decide which discrete state to report? Leaning toward the latter — its
  existing gameplay-facing hooks (`movement_speed_modifier`,
  `warmth_factor`, `soil_moisture`, `wind_strength_for`) stay exactly as
  useful, they'd just be fed by real climate instead of a hash roll — but
  not decided here.
- **Long-timescale reversibility** — does a desertified region ever green
  again after a sustained wet trend? The model is symmetric by
  construction, so probably yes, but worth confirming once built rather
  than assumed.
- **Exact hysteresis duration for biome transitions** — tuned constant,
  deferred.
- **Should a major storm become a real `Event`** in the emergence
  substrate (`src/emergence/event.gd`) the way a settlement founding
  already is — a storm is exactly the kind of "meaningful state change"
  [00-emergence-architecture.md](../emergence/00-emergence-architecture.md)
  asks to be event-sourced, and it's a very plausible cause feeding
  `exploration.md`'s ruins or `quests.md`'s village-endangerment
  mechanism (a storm as one more real disaster cause alongside drought and
  a world-boss attack). Plausible, not decided here.

## Status

Pure design, nothing implemented. `climate_model.gd`'s temperature formula,
`biome_classifier.gd`'s classification thresholds, `season_cycle.gd`'s
seasonal curve, and `weather_model.gd`'s gameplay-facing hooks all stay as
real code to build ON — this doc replaces what currently *feeds* them
(a worldgen-time constant and a per-region hash roll) with a live
simulation, not the modules themselves.
