## A living, physically-grounded world

The planet is not a painted backdrop — it's a simulation the player walks
around inside.

- **Terrain & climate**: generated from a heightmap + hydraulic erosion pass
  (rivers/lakes carve themselves out during generation, not hand-placed) and
  Köppen-style climate banding by latitude, elevation, and distance from
  water. This happens *once* at world-gen time — we are not running a live
  plate-tectonics simulation. "Realistic" means the *output* looks and
  behaves like Earth, not that we simulate continental drift.
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
