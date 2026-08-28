## Fishing & aquatic ecosystem

[rivers.md](rivers.md) now gives real rivers a distinct, queryable identity
on top of the ocean this world's real elevation data already carves out
(`EarthChunkGenerator.is_river_at_global`) — but nothing lives in them yet.
Fishing gives water a gameplay reason to exist, and does it by **reusing the
land ecosystem/evolution simulation** rather than building an unrelated
bolt-on minigame.

- **Aquatic creatures run the same sim as land animals.** Fish and other
  aquatic life follow [world.md](world.md)'s population model (reproduction/
  migration/death driven by local conditions — here, water
  quality/temperature/food density instead of vegetation/water access) and
  [evolution.md](evolution.md)'s full DNA/phenotype/sexual-selection
  machinery. A rare-phenotype fish is exactly as desirable to catch as a
  rare-phenotype boar is to tame.
- **Catching is an active minigame** (BOTW/Stardew-style skill check —
  timing, tension, bait choice) layered on top of the underlying sim, not a
  replacement for it: what fish are even available to catch at a given spot
  is determined by the aquatic population sim, not a fixed loot table.
- **Feeds the same production chain** as farming/hunting — caught fish are
  [cooking.md](cooking.md) ingredients and [crafting.md](crafting.md)
  material inputs, with the same DNA-quality → material-quality link.
- **Beastmaster/Herbalist crossover**: can a sufficiently rare/high-fitness
  fish be *tamed* rather than caught (a companion fish in a pond, or an
  aquatic mount)? Open question, but consistent with
  [pets.md](pets.md)'s species-sets-category/DNA-sets-quality model if so.

### Aquatic population model

[ecosystem_dynamics.md](ecosystem_dynamics.md)'s two-fidelity pattern —
individually-simulated agents near the player, a cheap aggregate elsewhere,
reconciled by catch-up integration on reload — and its underlying
logistic-growth machinery (`population_model.gd`) apply to water exactly as
they do to land, per [world.md](world.md)'s "fishing.md runs the same model
for the rivers/lakes this world-gen pass carves out." This section is the
aquatic-specific wrapper: what plays the role of vegetation density (the
capacity input) and what plays the role of grazing/hunting (the mortality
term) for a body of water.

**Why an aggregate per-chunk stock, not a simulated individual for every
fish in every pool.** Tracking every fish in every loaded *and unloaded*
body of water would mean carrying live state for a population that scales
with total planet water area, almost all of which no player is ever near —
the same reasoning that already keeps land herbivores/predators aggregate
outside the loaded radius. It's also not what "realistic" actually calls
for: real fisheries science doesn't model individual fish either — stock
assessment uses exactly this shape, a **surplus-production model**
(Schaefer model): logistic growth toward a carrying capacity, minus a
harvest term, applied to the whole stock as one number. That's a real-world
mechanism, not a performance shortcut dressed up as one, so it keeps
pillar 1. Concretely:

- Each chunk carries one aggregate scalar, **fish population** — the
  aquatic sibling of `EcosystemSimulation`'s existing
  `_herbivore_population`/`_predator_population` dictionaries, call it
  `_fish_population`. It's wrapped by a new `aquatic_population_model.gd`,
  a thin wrapper around the shared `population_model.gd` exactly like
  `herbivore_population_model.gd`/`predator_population_model.gd` already
  are, with its own tuned growth rate — fish are more r-selected than land
  mammals (high fecundity, high juvenile mortality), so a real fish stock's
  intrinsic growth rate is plausibly higher than
  `HerbivorePopulationModel.GROWTH_RATE_PER_DAY`'s 0.3 — pinned by test,
  never eyeballed, per this project's tuning convention.
- Only chunks currently loaded (or freshly reloaded via catch-up, below)
  run this step; distant water isn't ticked at all — same LOD boundary as
  land.
- Individual `FishMarker` nodes near the player stay exactly what they are
  today for rendering/AI purposes (lightweight wander, no needs/perception)
  — the aggregate model doesn't add per-fish simulation, it just becomes
  the thing that decides *how many* markers exist and feeds their
  depletion back into that number (see Harvest, below).

#### Water area → carrying capacity

`EcosystemSimulation` already computes `_water_access_fraction` (the
fraction of a chunk's cells that are ocean biome) to feed herbivore water
access. The aquatic model needs the same fact as an absolute count, not a
fraction, since stock size should scale with how *much* water a chunk
holds, not just whether it's mostly water: **water area = count of
interior-water cells**, reusing `FishRenderer`'s existing
`_is_interior_water` (ocean biome, not on the chunk edge, all four
cardinal neighbors also ocean — so beach-adjacent cells don't get credited
as open water). Capacity is then:

```
fish_capacity(water_area_cells, mean_water_temperature)
  = water_area_cells * FISH_PER_WATER_CELL
    * temperature_suitability(mean_water_temperature)
```

`temperature_suitability` reuses `Chunk.temperature` (already computed by
worldgen — no new per-cell state needed) through a bell-shaped curve: most
fish species have a real thermal tolerance band, productive in a middle
range and falling off toward both poles and the equator — the same
"ceiling × condition multiplier" shape `vegetation_growth_model.gd` already
uses for effective capacity (biome ceiling × temperature/moisture
multiplier). `FISH_PER_WATER_CELL` and the curve's shape are tuned
constants pinned by test, same convention as
`HERBIVORES_PER_VEGETATION_UNIT`. Food density (aquatic vegetation/plankton
as a capacity input, the water equivalent of land vegetation density) is a
real future refinement but has no model to hook into yet — tracked as open
below rather than invented wholesale here.

Real rivers ARE now distinguishable from ocean
(`EarthChunkGenerator.is_river_at_global`, see [rivers.md](rivers.md)) — but
this model doesn't consume that yet. v1 stays **ocean-only**, the same water
detection `FishRenderer` already uses; freshwater lakes above sea level
remain undistinguished from land entirely (rivers.md's own scope — a lake is
a closed shape, not a polyline, and wasn't attempted there either). The
model is keyed generically by "water region," so wiring in real freshwater
bodies later is additive (a new water-area source per chunk checking
`is_river_at_global`), not a rewrite — see Open Questions.

#### Seeding: base population when a chunk first loads

`EcosystemSimulation.add_region` already seeds vegetation/herbivores/
predators at equilibrium the first time a chunk is ever loaded. Fish follow
the same rule: a never-before-visited water chunk seeds `_fish_population`
at its full capacity — an undisturbed stock at natural carrying capacity
(virgin biomass), not zero and not an arbitrary starter constant. A
previously-visited chunk instead restores its last known population and
catch-up-integrates it forward (below) — it does **not** reseed to full, so
a stock a player fished down stays down until it regrows, rather than
quietly resetting on every visit.

#### Growth, saturation, and migration

Reuses `population_model.gd` directly, unmodified:

- `PopulationModel.step(population, capacity, delta_days)` is the logistic
  growth/saturation term — fast growth well below capacity, stalling as
  the stock fills up, the same density-dependence already proven for
  herbivores.
- `PopulationModel.migrate(...)` moves surplus population from
  higher-density water chunks into lower-density neighbors, so a heavily
  fished stretch of coastline gradually restocks from adjacent untouched
  water rather than only from its own local growth — the aquatic reading
  of "no fixed spawn zone": fish redistribute across connected water the
  same way herbivores migrate across connected land.

#### Harvest: fishing as the mortality term

This is the one piece with no land-side equivalent to copy, because the
land model has a known, documented gap here: killing a herbivore/predator
today doesn't decrement `EcosystemSimulation`'s aggregate population, it
just despawns a decorative node that silently comes back on next reload.
Fishing shouldn't inherit that gap — the entire point of a population-based
spawn rate is that fishing a hole out should matter. So the aquatic model
adds an explicit harvest term the land model doesn't have yet: a
successful catch calls a new `EcosystemSimulation.record_catch(chunk_coord,
count)`, subtracting directly from `_fish_population` the moment
`EarthChunkManager.catch_nearest_fish` (today purely cosmetic — frees a
`FishMarker` node and returns its species string for the message) succeeds.
The classic surplus-production reading: `dN/dt = r·N·(1 − N/K) − catch`. A
hard-fished spot visibly has fewer/no fish until logistic regrowth and
migration from neighboring chunks bring it back — real, felt scarcity
instead of an infinite decorative pond. Once proven out for fish,
backporting the same `record_catch`-style hookup to land hunting is a
natural, small follow-up (tracked in
[ecosystem_dynamics.md](ecosystem_dynamics.md)).

#### Individual-fidelity promotion (what the player actually sees)

`FishRenderer.spawn_fish` currently rolls an independent `SPAWN_CHANCE`
(0.12) per interior-water cell, capped at `MAX_FISH_PER_CHUNK` (10), with no
population state behind it at all. That per-cell hash roll becomes
**species/placement only**; *how many* fish spawn switches to reading the
aggregate: `target_count = clamp(round(fish_population / fish_capacity *
MAX_FISH_PER_CHUNK), 0, MAX_FISH_PER_CHUNK)` — the same "promote individual
nodes sized to the region's current aggregate population" pattern
`CreatureRenderer` already uses for land animals. A freshly-seeded, unfished
chunk still looks exactly like it does today (full population → full
10-cap visual density); a fished-down chunk visibly has fewer swimming
markers, which is the actual player-facing point of this whole model.
DNA/phenotype-driven species selection (per [evolution.md](evolution.md))
stays future work — the per-cell hash pick remains a placeholder for that,
unaffected by this change.

#### Unloaded-chunk catch-up

`ChunkEcologyCatchup.advance` extends with a `fish`/`fish_capacity` pair
alongside its existing `herbivores`/`predators`/`fruit_stock`/`vegetation`
state and capacity inputs — the same pure, deterministic, single-step
logistic integration by elapsed unloaded seconds, no new mechanism, just
one more tracked quantity. `EarthChunkManager._unload_chunk`'s existing
`_unloaded_ecology` snapshot and `_apply_ecology_catchup`'s reload path
carry it the same way they already carry herbivores/predators.

#### Persistence (a gap shared with land ecology, worth closing here first)

Worth being explicit about a real limitation: **no ecology state survives a
game restart today**, for anything — herbivores, predators, and vegetation
all live only in `EcosystemSimulation`'s in-memory dictionaries plus the
`_unloaded_ecology` catch-up snapshot, both wiped on exit. Only
`modifications` and `planted_trees` are actually written to disk
(`ChunkSerializer.save_modifications`/`save_planted_trees`). That's
survivable for land — a herd not persisting across a restart is a minor
believability gap — but it directly undercuts the point of a harvest term
for fish: "fish a hole out, come back tomorrow and it's still down" is the
whole ask, and that requires surviving a restart, not just an in-session
reload. So this spec adds what land doesn't have yet: a
`ChunkSerializer.save_fish_population`/`load_fish_population` pair, same
shape as `save_planted_trees`/`load_planted_trees` (its own
`user://chunk_fish_population` file), so a chunk's `_fish_population`
genuinely persists across sessions. Backporting the same treatment to
herbivore/predator/vegetation state is a reasonable, larger follow-up, not
required for this to ship.

### Current implementation status (divergence note)

The aquatic population model spec'd above is now implemented and live,
matching the land ecosystem's shape: `aquatic_population_model.gd` (the
fish sibling of `herbivore_population_model.gd`) wraps the shared
`population_model.gd`; `EcosystemSimulation` carries `_fish_population`
alongside herbivores/predators, seeded at capacity equilibrium the first
time a water chunk loads (`water_area_survey.gd` computes interior-water
cell count and mean water temperature -> `fish_capacity_at`); `step()`
grows/migrates fish the same logistic-plus-surplus-migration way as
herbivores; `record_catch(chunk_coord, count)` is the explicit harvest term
(wired to both the player's `catch_nearest_fish` and, now, a piscivore
bird's successful dive — see below); `ChunkEcologyCatchup.advance` carries
fish through unloaded-chunk catch-up the same way; and
`ChunkSerializer.save_fish_population`/`load_fish_population` give fish
population real cross-session persistence (`EarthChunkManager`'s
`FISH_POPULATION_DIR`), something land ecology still doesn't have.
`FishRenderer.spawn_fish`'s `target_count` parameter switches visible fish
*count* from the old independent per-cell roll to this aggregate — a
fished-down chunk visibly shows fewer markers on the next periodic refresh
(`EarthChunkManager._refresh_creatures`), not just after a reload.

What's still exactly as before: species is a per-tile deterministic pick,
not DNA/phenotype-driven; a rare/legendary catch is its own item
(`rare_fish`/`legendary_fish`, `FoodConsumption.FISH_BUFFS`) via a
per-catch independent roll (`FishingMinigame.fish_rarity`), decoupled from
the population sim; casting is visible (`fishing_cast.gd`,
`ProceduralBobberSprite`) and draws nearby fish toward the bobber
(`EarthChunkManager.set_attraction_point`). Full DNA/evolution reuse,
sexual selection, rare-phenotype desirability, bait-driven targeting, and
taming/companion fish are all still open, unstarted work.

**New since this doc was first written**: fish-eating birds (kingfishers)
are live -- see [ecosystem_dynamics.md](ecosystem_dynamics.md#a-new-aerial-tier-ambient-flyers-and-one-predator)
for the full mechanism. A kingfisher spawned near water
(`piscivore_bird_renderer.gd`) cruises like an ambient flyer, dives when
`EarthChunkManager.fish_population_near` reports a nonzero local population
(`piscivore_bird_behavior.gd`'s cruise/dive/grab-or-miss/ascend/cooldown
state machine), and on a successful grab (a probability roll, real
herons/kingfishers miss most strikes) calls the exact same
`record_fish_catch_near` -> `EcosystemSimulation.record_catch` the player's
rod uses. Fishing pressure is no longer only ever the player's.

### Open questions

- Bait/lure system depth — does bait choice meaningfully bias which species/
  quality you can hook, giving skilled fishing real strategy?
- Saltwater/ocean vs. freshwater ecosystems as distinct populations, or one
  unified aquatic model to start? (The implementation is water-region-generic
  and ocean-only for v1 for exactly this reason — worth deciding once real
  freshwater bodies exist in worldgen, not before.)
- Food-density coupling (aquatic vegetation/plankton as a capacity input,
  the water equivalent of land vegetation density) — no model to hook into
  yet, tracked here rather than invented for this pass.
- Aquatic predator-prey tier ("big fish eat little fish," mirroring land's
  predator/herbivore coupling) — plausible and grounded, but still out of
  scope; the mortality terms live are angler harvest and piscivore-bird
  harvest (both call the same `record_catch`), not a fish-on-fish one.
- Should kingfisher's own presence become population-simulated (more fish
  supporting more birds, mirroring how predator capacity derives from
  herbivore population), rather than a fixed per-chunk decorative spawn
  chance? Tracked in ecosystem_dynamics.md's Species roster section.
