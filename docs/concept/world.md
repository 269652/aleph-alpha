## A living, physically-grounded world

The planet is not a painted backdrop — it's a simulation the player walks
around inside.

- **Terrain**: generated from a heightmap + hydraulic erosion pass
  (rivers/lakes carve themselves out during generation, not hand-placed).
  This happens *once* at world-gen time — we are not running a live
  plate-tectonics simulation. "Realistic" means the *output* looks and
  behaves like Earth, not that we simulate continental drift. Elevation
  itself is real data, but today only feeds a biome threshold — nothing
  currently stops the player walking straight up a cliff.
  [terrain_relief.md](terrain_relief.md) is what turns that same elevation
  data into real slope: passability, visible hillshading, and mountain ore
  exposure, all from one shared field.
- **Climate**: Köppen-style biome banding by latitude, elevation, and
  distance from water was originally a one-shot worldgen classification,
  same as terrain above. [climate_dynamics.md](climate_dynamics.md)
  replaces that snapshot with a live pressure/wind/ocean-current/water-cycle
  simulation — biomes are now a continuous *read* of that simulation, able
  to genuinely transition over time, not a value frozen at world-gen.
- **Day/night and seasons**: a global clock drives sunlight per-tile (as a
  function of latitude, time of day, and season), which feeds directly into
  the ecosystem simulation below, NPC schedules, and nocturnal/diurnal
  creature behavior. [weather.md](weather.md) builds dynamic weather and
  disaster events on top of this same clock.
- **Ecosystem simulation (the "boars" pillar)**: every map cell tracks
  vegetation density, sunlight, and soil moisture. Plants grow toward a local
  carrying capacity and spread to suitable neighboring cells (a
  cellular-automaton / reaction-diffusion model) — no sunlight or water,
  no growth. Herbivore populations spawn, reproduce, migrate, and die based on
  nearby vegetation density and water access. Predators do the same, tracking
  prey density. **There is no "boar spawn zone" — boars exist wherever the
  simulated conditions make boars viable, and that can shift over time** (a
  drought or overhunting measurably changes where you find them). This runs
  as a regional/aggregate simulation for performance; only creatures near a
  player get promoted to fully simulated, individually-rendered agents. See
  [evolution.md](evolution.md) and [dna.md](dna.md) for how individual
  creatures within this simulation reproduce and vary genetically, and
  [worldbosses.md](worldbosses.md) for how it can spontaneously produce a
  boss-tier individual. [fishing.md](fishing.md) runs the same model for
  the rivers/lakes this world-gen pass carves out, and
  [farming.md](farming.md) lets players locally override the vegetation
  side of it. Fruit/nut-bearing trees go a level deeper than the aggregate
  density field: see [flora.md](flora.md) for how individual trees carry
  DNA and how animal foraging/seed dispersal drives real plant evolution
  over time.
- **Land health: overharvesting leaves a lasting mark, not just a slower
  respawn.** Today a cell's carrying capacity (the ceiling
  `vegetation_growth_model.gd`'s density grows toward) is purely a function
  of biome and CURRENT weather — strip a plot bare and it fully regrows the
  moment weather allows, indistinguishable from a plot nobody ever touched.
  That undersells the "a drought or overhunting measurably changes where
  you find them" claim two paragraphs up: overhunting already thins
  population, but overharvesting the PLANTS underneath it leaves no trace
  at all once pressure stops. Real land does: sustained harvesting faster
  than regrowth depletes soil organic matter and structure, not just
  standing biomass, and that recovers on a much longer real timescale
  (years, not one growing season) than the biomass itself does. A new
  persistent per-cell (or per-chunk-aggregate, for performance — same
  fidelity tradeoff the density field itself already makes) **land health**
  value multiplies the existing weather-driven ceiling down further:
  depletes when a cell is harvested faster than it can regrow, recovers
  slowly if left fallow, tested named constants for both rates grounded
  against real soil-recovery timescales rather than eyeballed. This is
  what makes deforestation/overharvesting a genuine, lasting choice rather
  than a respawn timer, and it feeds directly into
  [npc.md](npc.md#needs-and-the-local-production-economy)'s farmer/hunter
  yield, which already reads these same density/capacity numbers — a
  village near land the player stripped bare goes hungry for real,
  measurable years, not until the next rain. **Depletion drivers wired so
  far**: a working farmer NPC's harvest, and real grazing pressure — both
  a grazer's deliberate walk-to-a-tuft bite (`GrazerForaging`) and the
  ambient any-herbivore-standing-on-mature-grass sweep
  (`EarthChunkManager._graze_by_herbivores`) — now feed the same
  `record_vegetation_harvest` mortality term, so sustained horse/sheep
  grazing measurably depletes land health exactly like sustained
  overharvesting does. **Known gap, honestly flagged**: tree felling
  (`ChoppableTree`) does not yet — a chopped tree is a wholly separate
  discrete-node system with no chunk-coordinate/`EarthChunkManager`
  reference at all (unlike every other depletion driver above, which
  already receives a `world`/`manager` reference to call through), and a
  felled tree has no existing real quantity analogous to "vegetation
  density consumed" the way a farmer's yield or a grazed tuft's growth
  level does. Wiring it would mean threading a manager reference through
  `TreeRenderer`'s spawn path AND inventing a new amount from nothing,
  not just adding a caller — a separate, larger follow-up.
- **Globe topology**: the world wraps — walk far enough in any direction and
  you return to your start. Implementation note: true spherical tiling
  (geodesic/cube-sphere) has serious complexity costs (pole singularities,
  distorted tiles, harder pathfinding) for uncertain gameplay benefit in a 2D
  top-down game. **Decision: the map is a torus (wraps on both X and Y)**,
  not a literal sphere. Gameplay-wise this is indistinguishable from "it's a
  globe" for a top-down game; revisit only if a future 3D/orbital-view mode
  needs a true sphere.
- **Persistent, modifiable world**: the world is stored in chunks (à la
  Minecraft/Terraria). Player changes (built structures, cut-down trees,
  dug tunnels) persist. Chunks near active players simulate at full fidelity
  every tick; distant/unloaded chunks get a coarse "catch-up" simulation pass
  when next visited, so the ecosystem keeps evolving off-screen without
  needing full-fidelity simulation of the entire planet at all times. See
  [building.md](building.md) for player-driven modification of this world,
  and [exploration.md](exploration.md) for how the world's own simulated
  history seeds discoverable points of interest.
