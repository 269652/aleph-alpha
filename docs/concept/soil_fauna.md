# Soil Fauna: Earthworms and the Birds That Eat Them

This doc specifies the **soil invertebrate layer** — the trophic level below
every plant-eater the world already simulates — and the first consumer wired
onto it: a robin that hunts, lands on, and eats an earthworm.

[ecosystem_dynamics.md](ecosystem_dynamics.md) already names this exact gap in
its ambient-flyer section: *"Real songbirds are largely insectivore/granivore —
no feeding model exists for either input, so like butterflies this is presence
without population dynamics."* Songbirds were pure decorative drift with no
behaviour whatsoever. This doc closes the **insectivore** half of that gap. The
granivore (seed-eating) half is specified here too, because the per-species
diet concept only makes sense if it distinguishes at least two birds — but only
the worm half is built in this pass.

## Design pillars

1. **Real mechanisms, not scripted spawns.** A worm is at the surface because
   the soil is moist and mild, not because a timer fired. A robin lands where a
   worm actually is, and eating it actually removes it. The reason robins
   famously appear on lawns after rain is a real mechanism, and it should be
   the same mechanism in game.
2. **Diet is a property of the species, not of the code path.** "Robins eat
   worms, sparrows eat seeds" is a lookup, not an `if species == "robin"`
   scattered through the marker. Adding a food type (seeds, fruit) or a species
   must be a table edit.
3. **Legible on screen.** The whole point of the mechanic is that the player
   *sees* a bird drop out of the air, sit down on the grass, dip its head,
   take the worm, and fly off. The simulation exists to make that moment
   truthful, not the other way round.
4. **Determinism.** A given chunk seeds the same worm burrows every time it
   loads, and a given bird makes the same choices, the same way every other
   patch sim and flyer in this project does.

## Real-world grounding

- **Earthworms live in the soil column and come up, not into existence.** They
  are a permanent resident population of a patch of ground; what changes with
  the weather is how close to the surface they are. So the model gives a chunk
  a fixed, deterministic set of **burrows** and animates a per-burrow
  **surfacing** value, rather than spawning and despawning worms.
- **Moisture drives surfacing.** Wet soil lets worms respire at the surface and
  move above ground without desiccating; rain is the classic trigger, and a
  drying soil sends them back down. This is why "robins on the lawn after rain"
  is a real and universally-observed thing.
- **Temperature gates it.** Below roughly soil-freezing, earthworms move deep
  and go dormant; they are a mild-and-moist animal. Cold ground therefore
  suppresses surfacing regardless of how wet it is.
- **Not every worm comes up at once.** Even in ideal conditions a fraction of
  the population stays down. Surfacing is therefore a *drive* compared against
  a per-burrow reluctance, so drizzle brings a few worms up and a downpour
  brings most of them — a graded response, not a switch.
- **Soil-bearing biomes only.** Earthworms need organic soil with moisture:
  grassland, forest, rainforest. Not ocean (no soil), not desert (no moisture),
  not tundra (permafrost — the boreal earthworm-free zone is a real and
  well-documented thing). This mirrors the biome gate the songbirds that eat
  them already use.
- **A robin hunts by sight, from the ground.** It flies, lands, stands, watches,
  strikes, swallows, and moves on — the stop-run-peck cycle. It does not eat on
  the wing like a swallow. That is why the animation is *land and sit*, not a
  swoop.
- **Predation is real but not extinctive.** A robin taking a worm empties that
  burrow for a while; another worm occupies it later. A lawn is a renewable
  resource for a robin, which is why robins hold small feeding territories
  rather than stripping ground bare and moving on forever.

## Mechanism spec

### Per-chunk earthworm population

Deliberately shaped like `FlowerPatch`/`TallGrass`/`DesertScrub`/`TundraLichen`
— the project's established per-chunk patch-sim contract — rather than sharing
a base class with them (see `DesertScrub`'s doc comment on why three similar
things beats a premature abstraction):

- Pure `RefCounted`, `_init(seed_value, width, height, biome)`, hard per-chunk
  cap on burrows.
- Deterministic placement via `PixelNoise`, **never** Godot's string `hash` —
  that correlates neighbouring cells and is the clustering bug this project has
  hit five times.
- `advance(delta)` moves every burrow's surfacing toward its current target.
- A **pure consumption method returning bool**, so a caller can just try and
  let the sim decide: `take(cell)` returns false if there is no worm at the
  surface there.
- Constructed on chunk load, dropped on chunk unload, stepped centrally.

State per burrow:

- **surfacing**, 0..1. 0 is deep in the soil (invisible, uncatchable), 1 is
  fully at the surface (rendered, catchable). It *animates* rather than
  snapping, so worms visibly appear and withdraw.
- **reluctance**, a deterministic per-burrow constant in [0,1) derived from the
  chunk seed. A burrow rises only while the environmental **drive** exceeds its
  reluctance. This is what makes the population response graded: at drive 0.35
  roughly a third of a chunk's worms are up.
- **recovery**, a countdown after a worm is eaten during which that burrow
  stays down regardless of conditions — the time it takes another worm to
  occupy it. Without it a robin could stand in one spot and eat the same burrow
  forever.

### Surfacing drive

A pure, tested function of two live world inputs, not a hand-tuned literal:

```
drive(moisture, warmth) = wetness(moisture) * cold_gate(warmth)
```

- `moisture` comes from the live weather at that chunk (`WeatherModel`): a
  storm soaks the ground, rain wets it, cloud keeps it damp, clear dries it.
  Clear weather deliberately does **not** go to zero — it is half of all
  weather rolls, and a mechanic the player only ever sees in the rain is a
  mechanic they mostly never see. Dry ground still has a baseline of worms
  near the surface; rain multiplies it.
- `warmth` is the same `climate x season` figure fruiting already uses
  (`SeasonCycle.warmth_modifier` over the real Earth temperature at that tile).
  Below a cold cutoff the gate is 0 (frozen ground, no worms, so no winter
  robin foraging); it ramps to 1 by mild.

### Bird diet, as a first-class concept

A per-species table mapping a flyer to the food types it eats. This is the
system that makes "robins eat worms, sparrows eat seeds" true, and it is what
every feeding behaviour gates on:

| species | eats |
| --- | --- |
| robin | worms |
| sparrow | seeds |
| kingfisher | fish |
| monarch / swallowtail / blue_morpho / bee | nectar |

Note this is **not** `CreatureInfo.DIET_BY_SPECIES`, which is HUD flavour text
("Grazer", "Hunter") read by nothing behavioural. This table is behavioural: a
species with `worms` in its diet is given a worm world and a ground-forage
brain at spawn time; a species without one is not, and therefore *cannot*
hunt worms no matter what else changes. Sparrows not eating worms is a
structural fact, not a missing branch.

Food types are strings so the follow-on work slots in without redesign:
**seeds** (flower seeds + sparrows) reuses the identical shape — a per-chunk
seed sim, a `seeds_near`/`take_seed_at` pair on the chunk manager, and the same
ground-forage state machine — and **fruit** (fruit trees, later) becomes a
third entry that a robin's diet can gain without touching the machinery.
(Both have since shipped, alongside a fourth robin entry, caterpillars — see
"Some birds eat caterpillars too" far below for the full account; this
table predates all three and is not updated in place.)

### Ground foraging behaviour

A pure `RefCounted` state machine with no engine dependencies, following
`PiscivoreBirdBehavior`'s shape exactly so it is unit-testable headlessly. The
marker owns the world effect; this owns the rules.

```
SEEKING --commit--> DESCENDING --arrive--> PECKING --strike--> RESUMING --> SEEKING
```

- **SEEKING** — airborne, drifting on the ordinary ambient-flyer wander. After
  a re-hunt interval has elapsed it may commit to a worm it can see. That
  interval is the run-between-pecks part of the real cycle: a robin does not
  chain strikes back to back.
- **DESCENDING** — committed, flying straight at the worm. Ends on *arrival*,
  not on a timer, because the distance varies.
- **PECKING** — on the ground, wings folded, holding still. The strike resolves
  partway through (the same "resolve once, keep animating" split
  `PiscivoreBirdBehavior` uses for its dive), at which point the caller
  actually removes the worm from the world. The bird dips its head several
  times across this phase so the peck reads as pecking rather than a freeze.
- **RESUMING** — still on the ground for a beat, head up, before taking off
  again. This is the "swallow it and look around" beat; without it the bird
  teleports back into flight the instant it eats.

### What the player sees

A robin drifting over grassland after rain breaks off, flies in a straight
committed line to a spot on the ground, lands, sits with its wings folded, dips
its head into the grass several times, the worm on the ground disappears, the
bird holds a beat, then lifts off and resumes wandering. A sparrow in the same
meadow never does this. In a hard frost, no worms are up and no robin lands.

### Consumption is live, end to end

`DesertScrub` and `TundraLichen` are now both stepped live from `World._process`
(`_chunk_manager.step_desert_scrub`/`step_tundra_lichen`, see `progress.md`).
This mechanic is likewise deliberately wired the whole way: chunk load creates
the population, `World._process` steps
it under the same server/singleplayer authority gate as every other ecology
step, a spawned robin is given the real chunk manager as its worm world, and a
successful peck calls the real `take_worm_at`, which removes the real worm and
its sprite.

An eaten worm leaves the screen on the **same frame** the bird takes it, not
at the next throttled sprite refresh. The refresh interval throttles
*background* node churn (worms surfacing and withdrawing on a weather
timescale); a worm being eaten is a direct consequence of something the player
just watched happen, so it re-syncs its own chunk immediately, the same way
planting a flower does. This is not a hypothetical: the runtime probe reported
59 rendered worms against 56 actually at the surface, i.e. worms robins had
already eaten lying in the grass for up to five more seconds while the player
watched the bird peck at them.

### Scope choices (explicit)

- **Not persisted, not catch-up integrated.** A reloaded chunk re-seeds its
  burrows deterministically and loses which ones had been eaten, exactly like
  `FlowerPatch`, `TallGrass`, `DesertScrub` and `TundraLichen` before it. Worm
  predation is a short-timescale, self-renewing local effect; carrying it in
  `ChunkEcologyCatchup` alongside herbivore/predator/fish aggregates would
  imply a fidelity the rest of the patch-sim layer does not have. Called out
  here rather than left as a silent gap.
- **No worm population dynamics.** Burrow count is fixed and deterministic per
  chunk; worms do not reproduce, spread, or starve. Only their *availability*
  varies. A real detritivore population model (litter input → worm biomass →
  bird carrying capacity) is the natural follow-up and is deferred, the same
  way the ambient-flyer tier defers its own population model.
- **No feedback onto bird numbers.** Songbird spawning stays decorative and
  capped; a worm-rich chunk does not yet hatch more robins the way a
  flower-rich chunk hatches more pollinators. Grounded and natural, deferred
  for the same reason as above.
- **Robins only, for now.** Sparrows are specified as granivores but there are
  no seeds in the world yet, so a sparrow still only drifts. That is an honest
  gap, not a bug — and it is exactly the gap the next pass closes.

## Status

- ✅ Per-chunk earthworm population — `src/world/earthworm_patch.gd`:
  deterministic `PixelNoise`-seeded burrows on soil biomes, capped, animated
  surfacing, per-burrow reluctance, post-predation recovery, pure `take(cell)`.
- ✅ Surfacing drive as a tested pure function of moisture and warmth —
  `EarthwormPatch.surface_drive`, with soil moisture per weather state from
  `WeatherModel.soil_moisture`.
- ✅ Biome gate (grassland/forest/rainforest only) — `EarthwormPatch.SOIL_BIOMES`,
  mirroring `AmbientFlyerRenderer.BIRD_BIOMES`.
- ✅ Per-species flyer diet table — `src/gameplay/flyer_diet.gd`; robins eat
  worms, sparrows do not.
- ✅ Pure ground-forage state machine (seek → descend → peck → resume) —
  `src/gameplay/ground_forage_behavior.gd`.
- ✅ Visible worms — `src/rendering/procedural_worm_sprite.gd`, one foot-anchored
  sprite per surfaced burrow, diffed against the sim by
  `EarthChunkManager._sync_worm_sprites`.
- ✅ Visible bird animation — `ProceduralBirdSprite.generate_pecking_image`
  (head dipped to the ground), driven through `AmbientFlyerMarker`'s existing
  `perched` folded-wing state, which nothing in `src/` had ever set before this.
- ✅ Live wiring end to end — `EarthChunkManager` (`worms_near`, `take_worm_at`,
  `step_worms`, chunk load/unload lifecycle) called from `World._process`.
- ⬜ Seeds + sparrow granivory (next pass — same shape, see above).
- ⬜ Fruit as a diet entry for robins (waits on fruit trees).
- ⬜ Worm population dynamics / bird carrying capacity from worm density.
- ⬜ Persistence and catch-up integration of eaten burrows (deliberate, above).
- ✅ Crushed underfoot: weight-emergent worm mortality (`CreatureMass`,
  `EarthwormPatch.CRUSH_MOMENTUM_THRESHOLD_KG_M_S`/`is_crushed_by`,
  `EarthChunkManager.crush_worm_at`, wired for the player and every
  `CreatureMarker`) — see "Crushed underfoot" below.
- ✅ Illustrated worm sprite (crawl/emerge/retreat/die, real corpse
  persistence) — `src/rendering/illustrated_worm_sprite.gd`,
  `EarthwormPatch.is_corpse`/`corpse_age_seconds`/`is_rising`,
  `EarthChunkManager._worm_texture_for` — see "Illustrated worm
  sprite" below.
- ✅ Corpse pickup — `WormMarker`, `EarthwormPatch.take_corpse`, a real
  massed `"worm"` `ItemCatalog` item — see "A corpse can be carried off"
  below. Not yet wired into the fishing mechanic itself (see
  `docs/concept/aquatic_foraging.md`'s still-⬜ "Worms as fish bait").
- ✅ Ants (mound population + myrmecochory, both grassland grass-seed AND
  forest/rainforest windfall fruit/nut foraging, a real rendered presence
  that visibly grows with its own colony, real round-trip foraging
  behaviour, pheromone-trail recruitment, and a queen-driven per-mound
  population fed by BOTH food and water/rainfall) —
  `src/world/ant_colony.gd` / `EarthChunkManager.step_ants`, see "Ants:
  myrmecochory" below. This closes the placement half of the "other soil
  fauna" item above, the "forest/rainforest mound has nothing to harvest"
  gap this doc used to name (fixed 2026-08-26, see "Windfall foraging" in
  that section), the "no rendered ant or mound sprite" gap (fixed
  2026-09-04 — reported live: ants "should be a real gear in the
  ecosystem", see "Rendered presence" in that section), the "no ant
  population dynamics" gap this doc used to name explicitly as out of
  scope (see "A queen, and where a colony's size comes from"), a
  scripted-not-real forage resolution (see "Real foraging: a round trip,
  not an instant resolve"), no ant-family marker answering the
  hover-tooltip contract (see "Ants at half their old size, and finally
  hoverable"), and — this pass (2026-09-05) — growth being food-only and
  a mound's own size never reflecting how its colony was actually doing
  (see "Water, not just food: a second real growth driver" and "Mound
  size grows with the colony"). What's left of the original item (ants as
  prey, or as non-windfall detritivores) is still open, see that
  section's own scope note.
- ✅ Caterpillars (requested live: "wire caterpillars which live on trees
  and on the ground around them; they should also do groundforaging and
  eat green leaves (spring, summer only)") — real illustrated crawl/climb/
  eat art, a pure `CaterpillarForageBehavior` state machine (seek ->
  approach -> eat, no flight), a `CaterpillarMarker` that climbs a real
  nearby tree to eat OR forages real green (spring/summer-fallen) leaf
  litter on the ground, and a season-gated per-chunk spawn
  (`CaterpillarRenderer`, spring/summer only). See "Caterpillars: on
  trees, on the ground, green leaves only" below.
- ⬜ Snails, and any other soil fauna beyond ants/caterpillars — the table
  and the patch-sim contract extend to them the same way ants did, nothing
  else is needed structurally, but nothing has built one yet.


## Ants: myrmecochory

Ants close the placement half of the "other soil fauna" gap named above: a
second soil-invertebrate population, built on the exact same per-chunk
patch-sim contract as the earthworm burrows this doc already specifies. What
they add mechanically is **myrmecochory** — ant-mediated seed dispersal — the
shortest-range member of the seed-carrier family this game already has
(`SeedDispersal`'s grazer coat-carry, `SeedEndozoochory`'s bird gut-passage
flight, `SeedCaching`'s rodent scatter-hoard, and now this).

### Real-world grounding

- **Ant colonies are permanent, sited populations, exactly like earthworm
  burrows.** A colony excavates a mound and works the ground around it for
  as long as it survives — it is not a transient spawn. So a chunk gets a
  fixed, deterministic set of **mounds** at construction, the same shape as
  earthworm burrows, rather than spawning and despawning individual ants.
- **A mound represents a whole colony, not one animal.** Unlike an earthworm
  burrow (one worm) or a bird (one animal), one mound stands in for an
  entire colony ranging out from a single entrance. That is why this pass
  gives ants no individual `CreatureMarker` the way the mouse has one: an
  ant colony is a background population effect on the ground itself, driven
  centrally by the chunk manager, not something that needs (or would even
  read as) an individually-pathed sprite.
- **Ant nest density is real, and typically denser than earthworm burrow
  density in the same soil** — a temperate hectare commonly carries many
  dozens of nests across several species, a higher areal density than a
  worm population usually reaches. `AntColony.MOUND_CHANCE` sits above
  `EarthwormPatch.SEED_CHANCE` for exactly this reason (pinned as an
  ordering, not eyeballed — see `test_mounds_are_denser_than_earthworm_burrows`).
- **Myrmecochory moves a seed the shortest distance of any disperser in
  nature.** A worker ant carries an elaiosome-bearing seed on foot to the
  nest to feed the fatty appendage to larvae, then discards the seed itself
  nearby — a real-world distance of centimetres to a couple of metres. That
  is shorter than a scatter-hoarding rodent's cheek-pouch range, which is
  itself shorter than a bird's gut-passage flight or a grazer's coat-carried
  wander. `AntColony`'s carry constants are the shortest of the whole family
  for exactly this reason (see the ordering below).
- **Ants forage close to the mound, not across a whole territory.** A
  worker's practical foraging radius from the entrance is a small fraction
  of the range a mouse works its whole home range for scatter-hoarding, so
  `AntColony.FORAGE_RADIUS_TILES` is shorter than `SeedCaching.PICKUP_RADIUS_TILES`.
- **Ants live in far more habitats than earthworms do** (leafcutter and army
  ants are a defining feature of rainforest, for instance), so mounds are
  seeded across the same soil-bearing biomes as earthworms
  (grassland/forest/rainforest) rather than grassland alone. `TallGrass`, the
  only source of ground SEED in this game, only grows on grassland, so a
  forest/rainforest mound cannot forage grass seed — but it now has a second,
  real forage target instead of sitting idle (see "Windfall foraging" below).
- **A single forager ant cannot carry off an intact fallen nut or dried
  fruit the way a squirrel or bird can.** Real ants interacting with fallen
  fruit/nut debris are documented almost entirely as scavengers/decomposers
  — stripping and consuming soft pulp and residue in place — not as
  dispersers of the hard propagule itself. True myrmecochory in nature is
  specific to small, elaiosome-bearing seeds (the ground-seed case above);
  a fallen tree nut is a genuinely different, far more consumption-dominant
  case for this disperser. `AntColony.WINDFALL_CONSUMED_CHANCE` is pinned
  ABOVE both `SquirrelNutCaching.NUT_CONSUMED_CHANCE` (0.7) and
  `SeedEndozoochory.GRANIVORY_CONSUMED_CHANCE` (0.8) for exactly this reason
  — ants are the least effective disperser of a large propagule of any
  forager in this game — while still leaving a real, nonzero minority chance
  of a genuine cache (never 1.0).

### Mechanism spec

**Per-chunk ant colony population** — `src/world/ant_colony.gd`. Shaped
exactly like `EarthwormPatch` (pure `RefCounted`, `_init(seed_value, width,
height, biome)`, `PixelNoise`-seeded — never Godot's string `hash` — hard
`MAX_MOUNDS` cap, `advance(delta)`) rather than sharing a base class with it,
for the same "three similar things beats a premature abstraction" reason
`DesertScrub` gives. What is genuinely minimal by comparison: a mound has no
`EarthwormPatch`-style surfacing value to animate, because it is not
rendered and not itself consumed this pass (see scope below) — the only
per-tick state is a discrete step counter, which the foraging roll and the
carry placement below are sampled against.

**The foraging roll.** Each call to `advance(delta)` increments the
colony's step counter; each mound independently rolls a small
`FORAGE_CHANCE` per step (`AntColony.should_forage`), seeded via
`PixelNoise` off the mound's own cell and the current step — never `hash`,
which correlates neighbouring inputs instead of spreading them, the
clustering bug this project keeps re-finding. `EarthChunkManager.step_ants`
drives this centrally, the same shape `step_worms` drives burrows: for every
loaded chunk's colony, advance it, and for every mound whose roll succeeds
this step, look for the nearest fallen grass seed within
`FORAGE_RADIUS_TILES` (reusing `grass_seeds_near`/`take_grass_seed_at`, the
same ground-seed API the mouse's own scatter-hoarding already uses — no
duplicate seed-tracking layer). If one is there, it is taken and cached a
short carry away (`AntColony.carry_distance_tiles`/`carry_direction`, both
derived from a per-(mound, step) `carrier_seed_for` so a reloaded chunk at
the same step caches identically) via `plant_grass_at` — the same sink the
mouse's own cached seed lands in.

**Carry range, in order.** Pinned by test, mirroring how `SeedCaching`
itself is pinned below `SeedDispersal`/`SeedEndozoochory`:

1. `SeedDispersal` (grazer epizoochory, coat-carried): 3.0 – 14.0 tiles.
2. `SeedEndozoochory` (bird gut-passage, carried in flight): 10 – 40 tiles.
3. `SeedCaching` (mouse scatter-hoard, carried on foot): 1.0 – 6.0 tiles.
4. `AntColony` (this): 0.15 – 0.9 tiles — shorter than even `SeedCaching`'s
   own minimum, the shortest-range disperser of the whole family.

The RESOLUTION still has no individual ant walking that distance over time
the way the mouse's carried state does: a mound is a background population
effect, not a pathfinding creature, so the harvest and the cache resolve
completely in the same step (`EarthChunkManager._forage_seed_near_mound`) --
this has not changed, and is not something the visual below changes either.
What changed (2026-09-04, see "Rendered presence" below): a purely
decorative `AntForagerMarker` now spawns right after that instant
resolution and visibly WALKS the same mound -> pickup -> cache geometry
over real time, so a player can actually see what already happened rather
than it resolving invisibly in the background. It carries no state the
resolution depends on -- deleting it changes nothing about correctness,
only what is visible.

**Windfall foraging (forest/rainforest).** `EarthChunkManager.step_ants`
branches on the MOUND's own biome (a chunk can straddle a boundary, so
different mounds in one colony can take different branches): a grassland
mound forages grass seed exactly as above; a forest/rainforest mound instead
calls `_forage_windfall_near_mound`, which looks within the same
`FORAGE_RADIUS_TILES` for a fallen, named-species fruit/nut ground item via
`fruit_near`/`take_fruit_at` — the identical ground-item API
`SquirrelNutCaching` already reads — filtered to real NUTS
(`TreeSpecies.is_nut`) exactly like `SquirrelNutCaching`'s own gate. A fallen
fleshy fruit (cherry/apple) is left alone: a single forager ant cannot
meaningfully interact with an intact fleshy fruit the way a bird or squirrel
does, so that stays on the ordinary generic fruit-eating path. Once a nut is
taken, the outcome resolves through `AntColony.windfall_is_consumed`
(seeded off its own `windfall_carrier_seed_for`, salted independently of
both the foraging roll and the grass-seed carrier roll so the three draws
never correlate): most of the time it is consumed outright on the spot — a
colony processing pulp/residue, not carrying off an intact propagule, see
`WINDFALL_CONSUMED_CHANCE`'s own real-world grounding above — and only
rarely does it survive to be cached, in which case it is carried the same
short `carry_distance_tiles`/`carry_direction` as a grass seed and planted
via `try_plant_seed_at`, the same tree-seed sink robin/squirrel dispersal
already use. This is what actually closes the "forest/rainforest mound has
nothing to harvest" gap named above — a real, tested, live-wired mechanism,
not just a placement fact.

### Ants at half their old size, and finally hoverable

Two reported gaps, both small on their own. **Size**: an ant/mound was
scaled for legibility when this was pure background population math with
no rendered presence at all — now that a player can actually stand next to
one, both read as oversized. `IllustratedDecomposerSprite.BASE_WORLD_WIDTH`
(6.0, shared by ant and carrion bug alike — "there is no size
differentiation between them today") is now two separate constants,
`ANT_WORLD_WIDTH` (3.0, halved) and `BUG_WORLD_WIDTH` (6.0, unchanged) —
splitting them, not just halving the shared one, since a carrion beetle is
a genuinely different, larger insect and halving it too was never asked
for and isn't grounded in anything about beetles.
`ProceduralAntMoundSprite.MOUND_WORLD_WIDTH` (7.0 → 3.5) halves similarly;
`MOUND_WORLD_SCALE` and `IllustratedAntMoundSprite.marker_scale()` both
derive from it, so one constant change halves both the procedural and
illustrated mound art.

**Follow-up (2026-09-05): a literal half overshot into invisible.**
Reported live right after relaunch: "antmounds are tiny and I see no ant
whatsoever". A literal halving of ANT_WORLD_WIDTH (6.0 → 3.0) put an ant at
barely 3 world-pixels wide against a 16px tile (`TerrainRenderer.TILE_SIZE`)
— measured directly (`IllustratedDecomposerSprite.new().marker_scale("ant",
"walk")` against the real frame's own pixel size): about 3.0 × 2.6 world
pixels of actual opaque content, for a thin, many-legged, low-contrast
silhouette against grass. A mound's solid, higher-contrast dome shape
survived the same halving as "tiny" but still visible; an ant's did not
survive it as visible at all. This was a genuine tuning overshoot, not a
functional bug — spawning, dispatch, and the scale math were all confirmed
working correctly at the smaller number, which is exactly the problem: the
code did precisely what a literal "half" asked for, and half was too much.
Corrected to a smaller-than-original-but-not-illegible 25% reduction
instead of 50%, preserving the original ant:mound proportion (6:7):
`ANT_WORLD_WIDTH` 3.0 → **4.5**, `MOUND_WORLD_WIDTH` 3.5 → **5.25**. Both
values remain pinned test constants (never eyeballed comments), same as
before — only the chosen number changed, following a second real-world
report the same way the first "oversized" report drove the original
halving.

**Tooltip**: neither an individual forager nor a mound answered
`HoverTargetFinder`'s contract (join the `"hoverable"` group, implement
`get_display_name()` — see [`hover_target_finder.gd`](../../src/rendering/hover_target_finder.gd)),
despite `DecomposerMarker` already preloading `HoverTargetFinder` and never
finishing the wiring. All three ant-family markers (`AntForagerMarker`,
`AntMoundMarker`, and `DecomposerMarker` itself, closing that dangling
gap too) now join and answer a name — a mound's name includes its current
colony strength (see the queen section below), so hovering one is how a
player actually learns anything about the colony living there without
ever seeing inside it.

### Real foraging: a round trip, not an instant resolve

Every forage used to resolve **completely in one step**: the mound found a
seed, took it, and cached it, all before the purely decorative
`AntForagerMarker` was even spawned to walk the geometry after the fact —
"the resolution still has no individual ant walking that distance over
time," this doc's own words for it above. That was an honest, named scope
choice at the time (a mound is a background population effect, not a
pathfinding creature), but it means the visible ant was cosmetic in the
strongest sense: freezing it, deleting it, or teleporting it changed
nothing about whether the seed was really taken.

That is no longer true. A forage attempt now dispatches a **real** forager
that:

1. **Scouts for a real target** rather than being handed one (see
   "Scouting: real search, not omniscient dispatch" below) and, once it
   has genuinely sensed something nearby, **walks there for real**, at
   the same `WALK_SPEED` it always animated at.
2. **Takes the seed/nut/leaf only on real arrival** (`take_grass_seed_at`/
   `take_fruit_at`/`consume_leaf_litter_at`), re-checked at that moment —
   something else (a mouse, a bird, simple bad luck) may have taken it
   first in the time the ant spent walking, in which case the trip comes
   back empty. This is the actual, meaningful sense in which foraging is
   now real rather than scripted: the walk has a causal effect that can
   fail, not a guaranteed one animated after the fact.
3. **Walks back to the mound**, not onward to a cache point out in the
   field — a genuine change from the old geometry, and a more accurate
   one: real ants carry a harvested seed *toward the nest*, discarding the
   processed remnant in a midden near the entrance, not out where they
   found it. The cache/consume roll (`AntColony.windfall_is_consumed` for
   windfall; grass seed always survives to be planted; a leaf simply
   disappears, real detritus rather than a propagule) and the resulting
   `plant_grass_at`/`try_plant_seed_at` call now happen at the mound,
   using `carry_distance_tiles`/`carry_direction` from the *mound's*
   position rather than the pickup's.
4. Frees itself once home, the same one-shot-per-trip lifetime as before.

`AntForageBehavior` (new, pure, no engine dependency, mirroring
`CarrionForageBehavior`'s shape) owns the phases this needs —
`SCOUTING` (no known target yet, see below), `APPROACHING` (walking to a
now-sensed target, arrival resolves found-or-not), and `RETURNING`
(walking home, arrival resolves cache-or-consumed). `phase` still
*defaults* to `APPROACHING`, not `SCOUTING` — a deliberate compatibility
seam: a direct construction (chiefly a test exercising APPROACHING/
RETURNING in isolation against an already-known target, the shape every
test written before scouting existed already uses) is completely
unaffected; only real dispatch opts in, via `begin_scouting()`.
`AntForagerMarker` takes a duck-typed `_world` reference (the same
contract shape `FishMarker`/`PiscivoreBirdMarker` already use) so it can
make these calls itself, plus the owning `AntColony` and mound `cell` so
the cache roll at arrival reads the colony's own deterministic
per-(cell, step) carrier seed, sampled live at the moment it's actually
needed rather than captured stale at dispatch time.

### Scouting: real search, not omniscient dispatch

Reported live, in sequence: first "ants go straight to the next leaf when
moving out the mound... they should either explore randomly or follow
pheromones"; then, after that was answered with a pheromone-*biased*
version of the dispatch below (score every candidate within reach against
the mound's own trail, send the forager at whichever scores highest) —
"no omniscience please". The second report was right to reject the first
fix: scoring every real candidate within the mound's *whole* forage reach,
from the mound's own stationary position, before a forager ever takes a
single step, is still a colony that already knows exactly where the food
is. An ant that "explores" was never actually possible under that model —
there was nothing left to discover.

A dispatched forager now starts knowing **nothing**. `AntForagerMarker.
scout` (set only by real dispatch — `EarthChunkManager._dispatch_ant_
scout`, which replaces the old `_forage_seed_near_mound`/
`_forage_windfall_near_mound`/`_forage_leaf_near_mound` trio entirely, one
per forage kind, each running its own omniscient query) puts the forager
into `SCOUTING` with no `target_position` and no `forage_kind` at all.
While scouting it:

1. **Wanders.** `AmbientFlyerMovement` — the same already-tested,
   home-anchored roam algorithm `DecomposerMarker`'s own ambient ants/bugs
   already use for their idle wander, not a second, near-duplicate one —
   anchored at the mound, with `AntColony.FORAGE_RADIUS_TILES` doubling as
   the wander disc's own radius: the mound's forage reach and a scout's
   home range are the same real-world quantity, so this needed no second,
   independently-tuned number. Slower than a committed approach
   (`SCOUT_SPEED_FRACTION`, mirroring `DecomposerMarker.WANDER_SPEED_
   FRACTION`'s identical "a hurrying insect reads as one that found
   something" reasoning) — an ant visibly speeds up the instant it
   commits to something real, the same tell a player already reads off
   the carry pose.
2. **Senses, locally.** New `LeafLitterField.leaves_near`/
   `EarthChunkManager.leaf_litter_near` (the plural counterparts
   `nearest_leaf_near`/`nearest_leaf_litter_near` never had — both of
   *those* are untouched, still used by `DecomposerMarker`'s own
   unrelated in-place eating) let a scout check for real food within
   `AntColony.SENSE_RADIUS_TILES` — half `FORAGE_RADIUS_TILES`, derived
   rather than an independent number, so a scout must genuinely cover
   real ground within its own small home range before stumbling onto
   something, rather than sensing the whole range at once from wherever
   it happens to stand (which would just be omniscience again, at a
   smaller radius) — of its own **current, moving** position, never the
   mound's. Leaf is checked first (not biome-gated at all, so any mound
   may have one nearby regardless of biome), then seed and windfall
   (gated to real nuts, `TreeSpecies.is_nut`, exactly as before — a lone
   ant cannot meaningfully take an intact fleshy fruit). No biome
   pre-filter is needed at dispatch time any more: those two queries
   simply come back empty wherever the world itself doesn't place that
   kind of food (no `TallGrass` outside grassland, no fruiting trees
   outside forest/rainforest), the same way they always have.
3. **Commits** the instant something real is sensed — `target_position`/
   `forage_kind` (and, for a leaf, `carried_leaf_species`/`season`) are
   set from what was actually found, `AntForageBehavior.commit_to_food()`
   moves to `APPROACHING`, and the rest of the round trip above resolves
   exactly as it always has.
4. **Gives up** if nothing turns up within `AntForagerMarker.MAX_SCOUT_
   SECONDS` — derived from how long it would take to cross its own
   wander disc several times over at scouting speed, not an independent
   guess — and walks home empty-handed, the same "still returns, just
   with nothing to show for it" contract an unsuccessful `APPROACHING`
   trip already has.

`_dispatch_ant_scout` above is kept as a single, un-spread dispatch for
direct callers, but real production dispatch (`step_ants`) no longer calls
it directly — see "Cluster recruitment: multi-scout waves, directional
trails, and invalidation" below for the actual per-tick scout-vs-resolver
wave dispatch this now goes through.

**Deliberately not built:** biome-aware re-sensing as a scout physically
wanders into a neighbouring biome (it still only ever senses for the kind
its OWN mound's placement would suggest is worth checking — sensing all
three kinds unconditionally already covers this well enough in practice,
since a query for a kind the world doesn't place nearby just comes back
empty; a scout literally crossing a live biome boundary mid-wander is a
real, separable refinement, not attempted here).

### Pheromone trails: recruitment to a known-good source

Real ants recruit nestmates to a food source with a **trail pheromone**: a
successful forager lays it down as it returns to the nest, it evaporates
over real time, and another forager senses it as a bias toward a *known*
source rather than an equally-convenient unknown one — the mechanism
behind Deneubourg et al.'s classic double-bridge experiments, where a
colony collectively converges on the shorter of two paths to a food source
purely through this reinforce-and-evaporate loop, with no individual ant
ever comparing the two.

`PheromoneField` (new, `src/world/pheromone_field.gd`) is the mechanism.
Deliberately **not** a reuse of `ScentField` despite the similar-sounding
job: `ScentField.concentration_at` recomputes its answer fresh, every
call, from whichever flowers are *currently* alive and blooming — there is
nothing to persist because a flower's own presence already is the state.
A pheromone trail is the opposite: it has to outlive the ant that laid it,
which is the entire point of another ant finding it later. So
`PheromoneField` is a real stateful, decaying store —
`deposit(tile, amount)`, `decay(delta_seconds)` (exponential falloff,
`HALF_LIFE_SECONDS`, pruning anything below a floor so the backing
dictionary doesn't grow forever) — while still borrowing `ScentField`'s
**math**, not its statelessness: the same squared-taper `falloff` and
finite-difference `gradient_direction` sampling, because a concentration
field is a concentration field regardless of what maintains it.

**Where it plugs into foraging, concretely — read locally, not compared
from afar.** A first version of this scored every real candidate within a
mound's whole reach by distance *and* the trail concentration already
sitting at each one (`PheromoneField.best_candidate_index`), sending the
forager straight at whichever scored highest. That is real recruitment
math, but it is also exactly the omniscient shape reported as a problem
(see "Scouting" above) — it still requires knowing every candidate's
existence and position up front. `best_candidate_index` is gone (along
with its 4 dedicated tests); a scout instead reads `gradient_direction` —
a concentration **sensed at its own current position**, real chemotaxis —
and `AntScoutWander.biased_heading` (new, mirrors `ThreatAvoidantWander`'s
own shape: a pure post-process on an already-computed candidate heading,
so `AmbientFlyerMovement` itself never needs touching for this one extra,
ant-specific need) bends its wander heading toward that gradient when one
is sensed nearby, leaving it completely untouched — genuine, undirected
exploration — when nothing is. A previously-successful spot's own trail
can still pull a scout further out of its way than a fresh, unmarked one
would (`AntScoutWander.TRAIL_BIAS`), the same real recruitment effect,
just read the way a real ant actually reads it: locally, in passing, not
compared against a remembered list. With no trail nearby yet (a colony's
first-ever forage in some direction), a scout's own heading is simply
untouched, undirected exploration — not "pick the nearest candidate" the
way the old omniscient dispatch's own no-pheromone fallback was, since
there is no candidate list left to fall back to at all.

A successful forager depositing at the food's own position the moment it
picked its find up, unconditionally, was the model at this point in the
project — since superseded (see "Cluster recruitment: multi-scout waves,
directional trails, and invalidation" below) by a deposit that fires only
for a real cluster find, encodes a direction rather than a bare amount,
and is laid progressively on the walk home rather than once at the food
itself.

**Per mound, not per chunk.** Each mound owns its own `PheromoneField`
(lazily created on first deposit) — different colonies don't smell each
other's trails, matching how real colony odour is colony-specific.
`AntColony.advance(delta_seconds)` now genuinely uses the `delta` it
receives (previously ignored — "ants have no ... value to animate over
real seconds") to decay every mound's field by real elapsed time, the
first real use of that parameter this class has ever had.

### A queen, and where a colony's size comes from

"No ant population dynamics. Mound count is fixed and deterministic per
chunk... colonies do not grow, split, or die out from how much they
forage" — named explicitly above as out of scope. This closes that gap,
in the same real-mechanism, two-fidelity shape every other population in
this game already uses (`PopulationModel`, wrapped per-domain by
`HerbivorePopulationModel`/`PredatorPopulationModel`/
`AquaticPopulationModel`/`RobinPopulationModel`/`SparrowPopulationModel`/
`KingfisherPopulationModel` — see [ecosystem_dynamics.md](ecosystem_dynamics.md)'s
"The two fidelities are one population").

**Real-world grounding.** A real ant colony's size is driven almost
entirely by one animal: the queen, whose egg-laying rate — and therefore
the colony's growth — is itself bounded by how much food her workers
actually bring back. A well-fed colony with abundant nearby forage grows;
a colony working barren ground stalls near its founding size. Colony
growth genuinely does follow a real, roughly logistic curve over its
life — fast while young and under capacity, levelling off as the colony
fills whatever the local area can support — which is exactly the shape
`PopulationModel.step` already gives every other species in this game, no
new growth law needed.

**The mechanism.** `AntColony` gains, per mound cell: a population
(`STARTING_POPULATION`, an abstract colony-strength number, not a literal
worker headcount — the same abstraction level `fish_population`/
`herbivore_population` already sit at) and a real feedback signal, a
decaying exponential average of recent forage outcomes
(`record_forage_result(cell, succeeded)`, updated by
`EarthChunkManager` every time a dispatched forager's trip actually
resolves — success or failure, arrival is what tells the colony whether
this attempt fed anyone). Carrying capacity
(`capacity_at(cell)`) is `BASE_CAPACITY` scaled up by that recent-success
signal (`FOOD_CAPACITY_BONUS`) — a colony that keeps finding food supports
a bigger population than one that keeps coming home empty, the real
mechanism the grounding above names, not an invented one. `AntPopulationModel`
(new, `src/world/ant_population_model.gd`) is the thin per-domain wrapper
this shape always gets; `GROWTH_RATE_PER_DAY` is pinned **slower** than
`HerbivorePopulationModel`'s own (an ordering, not an eyeballed number,
mirroring how `AntColony.MOUND_CHANCE` is already pinned faster than
`EarthwormPatch.SEED_CHANCE` above) — a real ant colony matures over
years, the slowest-growing population this game tracks, against
land mammals' comparatively fast seasonal reproduction. `advance`
converts its `delta_seconds` to simulated days against the same
`SECONDS_PER_SIMULATED_DAY` (60s) `EarthChunkManager` already calibrates
every other species' growth rate against — restated as `AntColony`'s own
constant rather than importing `EarthChunkManager` back into the class it
is already owned by (that would be circular), and cross-checked by test
so the two can't silently drift apart.

**What the player actually sees.** There is still deliberately no
separate queen sprite (real queens are sessile and essentially never seen
outside the nest; a player learns a colony is thriving the same way they
would in reality, from how much worker traffic it produces and how big
its own works have grown, not by being shown her directly) — but
population now drives two real, visible things, not one:

1. How many foragers a mound may have **concurrently active**
   (`active_forager_cap_for`, `MAX_CONCURRENT_FORAGERS` = 6 — see
   "Thriving colonies, and a real swarm" below for why this rose from its
   own original 3), replacing the old hardcoded "one forager in flight at
   a time." A young or food-poor colony still reads exactly as before —
   one ant, one trip at a time — while a large, well-fed one visibly has
   several workers out at once, the same "aggregate population promotes
   to visible individual markers" pattern `FishRenderer`'s own
   `target_count` already uses for fish.
2. **The mound's own size** — see "Mound size grows with the colony"
   below, added directly in response to a real report: with the fixed
   size the previous pass shipped, a mound read as static regardless of
   how the colony inside it was actually doing, which undercut the whole
   point of a visible colony-strength signal.

A mound's hover tooltip reports the real population number directly (see
above) — the one place a player can read an exact figure for what is
otherwise inferred only from traffic and size.

### Water, not just food: a second real growth driver

**Real-world grounding.** Ant colony growth is not food-limited alone.
Larval development needs humidity, and colonies measurably struggle
through drought even with forage still available — which is exactly why
real colonies so often site their nest near a stable moisture source
(under a log, beneath damp leaf litter, near a water table) rather than
on the driest available ground. Rainfall is the other half of "how well
is this colony actually doing," alongside how much its workers bring
home, and treating them as two independent inputs to the same capacity
(rather than only ever reading food) is truer to the real biology, not
just a second knob for its own sake.

**The mechanism.** Mirrors `EarthwormPatch.set_conditions`'s own
weather-derived moisture sampling exactly, on the same
`WORM_REFRESH_INTERVAL`-scale cadence (weather turns over on a day scale,
far slower than a frame, so there is no reason to sample it every step):
`EarthChunkManager.step_ants` samples `WeatherModel.soil_moisture` at
each loaded chunk's own centre tile and feeds it to every mound in that
chunk via `AntColony.record_moisture(cell, moisture)` — a decaying
exponential average of recent moisture, the identical shape
`record_forage_result`'s own EMA already uses for forage outcomes, for
the identical reason: a single rainy day should not swing a colony's
fortunes any more than a single successful trip does; sustained
conditions should. `AntPopulationModel.capacity` now takes both signals:

```
capacity = BASE_CAPACITY * (1 + FOOD_CAPACITY_BONUS * forage_success + WATER_CAPACITY_BONUS * moisture)
```

`WATER_CAPACITY_BONUS` is pinned equal to `FOOD_CAPACITY_BONUS` (1.0) —
both are real, independently-acting inputs to the same real mechanism
(how much of a colony a mound can support), and nothing in the grounding
above argues one should structurally dominate the other. A colony that
finds food AND sits on consistently damp ground can now reach up to
`BASE_CAPACITY * 3` — the new `AntPopulationModel.MAX_REFERENCE_POPULATION`,
which the mound-size mechanism below normalizes against.

### Mound size grows with the colony

**Reported live, right after relaunch**: mounds read as barely visible at
their previous fixed size, with an explicit ask — "it should be half a
human high and grow with the colony." Two real, separate corrections:

**Size target.** A mound now grows from `MOUND_WORLD_WIDTH_MIN` (4.0, a
small but real founding pile — close to the previous pass's own flat
5.25, not a step backward at the weakest end) toward
`MOUND_WORLD_WIDTH_MAX`, pinned to **half the player's own real-world
height** (`CharacterView.HEAD_TOP_Y * CharacterView.SCALE * 0.5`,
restated locally rather than importing `StoneSize` for one shared number
— the same "read against the player" convention `StoneSize`/
`ProceduralFlowerSprite` already establish, cross-checked by test against
the real player height so the two can't silently drift apart the way
`ProceduralFlowerSprite.PLAYER_WORLD_HEIGHT_PX` itself once did). A
thriving, near-`MAX_REFERENCE_POPULATION` mound reads as a genuinely
substantial ground feature — not the tiny bump either version before it
was — while a brand-new one is still legibly small.

**Growth curve.** `ProceduralAntMoundSprite.world_width_for(growth_fraction)`
takes `AntColony.growth_fraction_at(cell)` (`population_at(cell) /
AntPopulationModel.MAX_REFERENCE_POPULATION`, clamped to `[0, 1]`) and
eases it with the identical `pow(fraction, EXPONENT)` technique
`StoneSize.world_height_px` already uses for stones, exponent below 1 —
growth reads fastest early (a young colony's own workforce can dig
faster than the queen can fill the extra room, so the mound visibly
swells right away) and flattens out approaching full size (a mature
colony's digging capacity outstrips how fast population can still be
rising). `IllustratedAntMoundSprite.marker_scale(growth_fraction)` and
`ProceduralAntMoundSprite`'s own fallback both take the same fraction, so
the illustrated art and the procedural fallback grow identically.

**Live, not static.** `AntMoundMarker` was "deliberately inert... no
per-frame behaviour of its own" (see that class's own prior doc comment)
because population had nothing for it to react to yet. It now takes a
real `setup(colony, cell)` (mirrors `AntForagerMarker`'s identical
contract) and re-checks its own growth fraction on a slow
`MOUND_RESIZE_INTERVAL_SECONDS`-scale cadence — population moves over
simulated DAYS, so anything faster would be spending per-frame cost on a
number that is, for all practical purposes, motionless between checks. A
mound a player watches over a real session should visibly, if slowly,
grow.

### Thriving colonies, and a real swarm

**Reported live**: "I almost see no ants but a lot of mounds... we want
real swarm intelligence and thriving ant colonies." Investigated end to
end rather than assumed — this was not a rendering or LOD bug (foragers
carry no decoration-culling of any kind, and never did); it was three
compounding, individually-reasoned tuning decisions that, together, meant
almost no mound a player ever encounters in ordinary play was ever seen
above its own absolute floor.

**Why "a lot of mounds, almost no ants" was the honest, arithmetic
result of the numbers above.** `active_forager_cap_at` scales with
`population_at(cell) / capacity_at(cell)` — but until this pass, EVERY
mound seeded at exactly `AntPopulationModel.STARTING_POPULATION` (1.0),
the literal founding minimum, regardless of how long that mound had
"existed" in the world before the player found it. `GROWTH_RATE_PER_DAY`
is deliberately the slowest-growing population this game tracks — real
ant colonies mature over years, not seasons — so climbing from that
floor to a population fraction that unlocks more than one concurrent
forager took, by the project's own test timescales, on the order of
**200 simulated real-time MINUTES** of one mound's own chunk staying
continuously loaded (`test_dispatches_a_second_forager_once_the_mounds_
own_cap_allows_it`), and **400** to approach the visual-growth ceiling
(`test_growth_fraction_approaches_one_for_a_thriving_colony`). Since
mounds are not persisted across a chunk unload/reload, and a player
exploring an open world rarely dwells within 2-3 chunks of one spot for
anywhere near that long, almost every mound a player ever actually looks
at was permanently stuck at its own lowest tier — capped at exactly one
concurrent forager, and even that one only actually dispatched when real
food happened to fall within a mere 1-tile radius of that exact mound
cell. Compounding this further: this doc's own "Pheromone trails"
section above already specified doubling `FORAGE_RADIUS_TILES` to 2.0
"because it is what makes more than one candidate food item plausible
within reach at once" — checked directly against the live constant and
the full git history of this file, **that change was never actually
made** (the constant has been 1.0 in every commit since its
introduction). `docs/progress.md`'s own investigation of an earlier,
related report ("ants don't carry seeds/nuts to the mound") had already
found this exact radius too tight to catch a real dispatch in a short
session, and left it "unchanged rather than loosened without confirming
that tradeoff is what's actually wanted" — this pass is that
confirmation.

**Three real, grounded fixes, not one:**

1. **`FORAGE_RADIUS_TILES`: 1.0 → 2.0 tiles.** Actually ships the
   doubling this doc already specified above. Still comfortably under
   `SeedCaching.PICKUP_RADIUS_TILES` (3.0) and still the shortest forage
   reach of any disperser in this game — an ant's mound-centred range
   stays real, just no longer so tight that a genuine nearby seed rarely
   ever falls inside it.
2. **A mound's population now SEEDS across a real established range**
   (`AntPopulationModel.STARTING_POPULATION` .. `BASE_CAPACITY`, i.e.
   1.0 .. 4.0, `PixelNoise`-seeded per mound off its own independent
   salt) instead of uniformly at the bare founding minimum — see
   `AntPopulationModel.STARTING_POPULATION`'s own doc comment. This is
   not a new mechanism, only a corrected starting point: every other
   map-generated patch-sim in this game (`TallGrass`, `WildCropPatch`,
   every tree) already starts mature rather than as a seedling, on the
   reasoning that a freshly-LOADED chunk represents content that has
   existed in the game world for real (if previously unmodeled) time —
   `AntColony` was the one holdout still seeding every mound at the
   literal instant of founding, every single time, which is what made a
   "thriving" colony functionally unreachable in ordinary play regardless
   of how sound the ongoing growth model was. The range is capped at
   `BASE_CAPACITY` (never higher) specifically so a freshly-seeded mound
   never reads as already ABOVE its own (still-unobserved) capacity
   ceiling, which would make `PopulationModel.step` read it as
   overcrowded and immediately start shrinking it back down before the
   player ever sees it settle. Ongoing growth — a colony's population
   catching up to a RAISED ceiling as it keeps finding food and damp
   ground — is untouched and still genuinely slow, preserving the real
   grounding above; only the moment a mound is first ever observed reads
   as an established colony instead of a newborn one.
3. **`MAX_CONCURRENT_FORAGERS`: 3 → 6.** The old value was deliberately
   framed as "a special sight, not a swarm" — exactly the framing this
   report asks to change. Raising it is also what makes the EXISTING
   pheromone-trail recruitment (`PheromoneField.best_candidate_index`,
   biasing every concurrently-dispatched forager toward the same
   known-good, trail-marked source) actually visible as a swarm
   converging on a rich find, rather than one ant's smarter-but-solitary
   pathing — "real swarm intelligence" was already correctly implemented
   at the individual-forager level; it simply never had enough
   simultaneous foragers to read as a swarm with.

**What this does NOT change**: mound count is still fixed and
deterministic per chunk (unchanged from "Mound COUNT is still fixed" in
the scope list below); colonies still are not persisted or
catch-up-integrated across a chunk unload/reload — a specific mound's
exact population is not remembered forever, only its INITIAL seed is now
a believable established value rather than the bare minimum, every time
it is (re)seeded; and ongoing population growth is still deliberately
the slowest in the game.

### A real food economy: storage, upkeep, and fewer, bigger, hungrier colonies

**Reported live**: "Ants still eat leaves on the spot... ants should bring
food (seeds, leaves, nuts) to the mound which should get a food supply
stat (visible on hover like hunger/thirst)... food then becomes driver
and constraint of population growth... make there much less mounds, I'd
say 1 for every 5, then make them substantially bigger (mound size also
based on population)... start at 15 ants at the beginning which forage
the area around the mound... unify any duplicates."

**Unifying the duplicate ants first.** `DecomposerMarker` ("ants"/"bugs",
[carrion.md](carrion.md)) and this file's own real colony forager
(`AntForagerMarker`) have drawn the identical `IllustratedDecomposerSprite`
"ant" art since decomposers got real illustrated art — a player has never
had any visual way to tell a real colony worker from a decorative,
mound-less wanderer that happens to look the same, and only one of them
could ever carry anything home, grow a colony, or register on a mound's
new food stat below. `DecomposerRenderer` no longer spawns an "ant"
species at all (`"bug"` is now its only species) — every ant a player
sees anywhere in the world is now a real forager from a real, nearby
colony. This also quietly fixes a real geography mismatch: decomposer
"ants" used to wander desert/tundra/mountain chunks too, biomes
`AntColony.SOIL_BIOMES` has always excluded (soil there is too loose/dry
or frozen for a real mound) — those sightings could never have been
explained by any mound anywhere, and now simply do not happen.

**Real-world grounding for a stockpile.** A real ant colony does not
consume what it forages where it finds it — workers carry food back to
the nest, where it is shared through the colony (trophallaxis) and part
of it becomes a genuine, if informal, reserve the colony draws on between
good finds. That reserve is exactly what a queen's egg-laying rate — and
so colony growth — actually tracks day to day, more directly than any
single trip's outcome: a colony a few good trips ahead of its own upkeep
grows; one that has been running a deficit for a while stalls or shrinks,
same as any real population outrunning its resources.

**The mechanism: a real, depleting stockpile, not another success-rate
proxy.** Every mound gains `food_stored_at(cell)`, a plain float in real
"food units," seeded generously at founding (see the new starting
population below) so a freshly-loaded colony is never born already
starving. Two things move it:

1. **Every completed, successful forage trip deposits real food** —
   `AntColony.record_forage_result(cell, true)` (already the one place
   `AntForagerMarker` reports a trip's outcome, on real arrival back at
   the mound) now also calls the new `deposit_food(cell,
   FOOD_PER_SUCCESSFUL_FORAGE)` internally, for every one of the three
   forage kinds (seed, windfall, leaf) alike — a plain, equal-weight
   deposit rather than an invented per-food-type nutrition table nothing
   in this file has ever measured. This does not touch or replace any of
   the existing myrmecochory: a windfall nut that survives
   `WINDFALL_CONSUMED_CHANCE`'s roll still gets planted nearby exactly as
   before, and a grass seed still always does — a real ant colony
   genuinely both feeds itself on part of what it forages (the fatty
   elaiosome of a myrmecochorous seed, the soft pulp of a fallen fruit)
   and disperses the rest, so the two are compatible, not competing,
   uses of the same trip.
2. **The colony's own population eats from it every day** — `advance`
   now also depletes `food_stored_at(cell)` by
   `population_at(cell) * FOOD_PER_ANT_PER_DAY * delta_days` each call,
   clamped at zero (a colony cannot owe food it doesn't have). This is
   the real upkeep a growing population represents: more ants, more
   mouths, more draw on the same reserve.

**Food as the real driver AND constraint capacity() asks for.** A new
`food_availability_fraction(cell)` compares the reserve actually on hand
against what the CURRENT population needs to feel secure —
`food_stored_at(cell) / (population_at(cell) * FOOD_PER_ANT_PER_DAY *
FOOD_BUFFER_DAYS)`, clamped to `[0, 1]`. A colony sitting on a healthy
multi-day buffer reads `1.0` (unconstrained — capacity is exactly what
recent forage-success and moisture already say it should be, untouched);
one running low reads partway; one that has genuinely run out reads `0.0`.
`capacity_at` now multiplies the existing forage-success/moisture-driven
capacity by this fraction:

```
capacity_at(cell) = AntPopulationModel.capacity(forage_success, moisture) * food_availability_fraction(cell)
```

No change was needed to `PopulationModel.step` itself for the
"constraint" half of the ask, either — it already declines population
that finds itself above its own current capacity (the same real
famine/overcrowding behaviour every other species' aggregate population
already has), so a colony whose capacity has genuinely collapsed from a
real, sustained food shortage now genuinely starves back down through the
exact same logistic mechanism that already governs growth, rather than a
new bespoke "starve" branch. Food becomes the driver (nothing else can
raise capacity if the reserve is running out, however good recent luck or
rainfall has been) and the constraint (a colony that keeps failing to
restock a shrinking reserve genuinely shrinks) at once, from one small
multiplicative gate.

**Fewer, bigger, hungrier colonies from the start.** Four related
constants move together, deliberately, rather than one at a time, because
they only make sense relative to each other:

- **`AntColony.MAX_MOUNDS`: 10 → 2** ("1 for every 5" of the previous
  per-chunk cap, taken literally). Fewer, individually more significant
  colonies read as real neighbours a player can learn and return to,
  rather than an undifferentiated scatter of a dozen indistinguishable
  small holes.
- **`AntPopulationModel.STARTING_POPULATION`: seeded RANGE floor (1.0) →
  flat `15.0`.** Taken literally rather than folded back into a range:
  the previous pass's own seeded-range fix (above) was itself a
  correction for colonies that could functionally never be seen thriving
  in ordinary play; asked directly for a specific number here, every
  mound now founds at exactly that number rather than variance around it.
  `_seed_initial_mounds` assigns it directly instead of sampling
  `PixelNoise.range_value` across a range that no longer exists.
- **`AntPopulationModel.BASE_CAPACITY`: 4.0 → 15.0`, so a founding
  colony's unfed-baseline capacity still exactly matches its own seeded
  population** — the same "never seed a mound already above its own
  unobserved ceiling" safety the previous pass's range fix already
  established, preserved at the new scale rather than reintroducing the
  bug it fixed. `FOOD_CAPACITY_BONUS`/`WATER_CAPACITY_BONUS` stay at
  their existing 1.0 ratio to `BASE_CAPACITY` (neither bonus is
  structurally more important than before, only the base they scale from
  moved), so `MAX_REFERENCE_POPULATION` (derived, `BASE_CAPACITY * (1 +
  FOOD_CAPACITY_BONUS + WATER_CAPACITY_BONUS)`) rises from 12 to 45 —
  a founding population of 15 now reads at exactly 1/3 of a mound's own
  visual growth range (`growth_fraction_at`), a real, established colony
  with real room left to grow into, not a newborn wisp and not already
  maxed out the instant it is seeded.
- **`AntMoundMarker`/`ProceduralAntMoundSprite` size: `MOUND_WORLD_WIDTH_
  MAX` (half the player's own height) → `PLAYER_WORLD_HEIGHT_PX * 1.5`
  (three times its previous ceiling; the floor, a founding colony's
  smallest reading, is unchanged).** A real, well-established nest —
  large ant species' mounds routinely spread well past a person's own
  height across — is a genuinely substantial feature of the ground it
  sits on, not something a player can walk past without noticing. Still
  driven by `growth_fraction_at` exactly as before (see "Mound size grows
  with the colony" above) — bigger ceiling, same live population-driven
  curve underneath it.
- **`AntColony.MAX_CONCURRENT_FORAGERS`: 6 → 15`, matching the new
  starting population.** Fewer, bigger colonies would otherwise mean
  LESS total visible ant activity across the world even though each
  colony individually thrives harder — a healthy, well-fed mound can now
  visibly have as many workers out at once as it actually starts with,
  the same "aggregate population promotes to visible individual markers"
  ceiling this file has used since "Thriving colonies" above, just raised
  to match the new scale rather than left as a leftover ceiling from the
  old population range.

**What the player actually sees, now three things, not two.** A mound's
hover panel (new — see below) reads its real, live food-storage fraction
directly, alongside the population number the plain-text tooltip already
reported; a well-stocked colony visibly supports more simultaneous
foragers and a bigger mound, and a colony a player watches go through a
real dry spell visibly shrinks back down, not just stalls.

**A pre-existing test's stale assumption, found and fixed (2026-09-06).**
`test_stepping_ants_drives_capacity_from_the_live_weather`
(`tests/unit/test_earth_chunk_manager.gd`, introduced in a344983, well
before this section's own food-economy pass — see "Water, not just food"
above) started failing deterministically the moment this pass merged:
it expects `capacity_at(cell)` to converge on a pure weather-derived
value after 20 stepped intervals, but landed at ~6.5 against an expected
~18.75. Root-caused directly against `AntColony`/`AntPopulationModel`
rather than assumed: not a convergence-timing or EMA-rate bug in the
moisture wiring (`MOISTURE_EMA_RATE` is over 99.9% converged within
those 20 steps), but `food_availability_fraction(cell)` gating
`capacity_at` down exactly as designed just above — the test never fed
its colony a single successful forage or deposit, so its reserve simply
drained over the run, precisely the "food becomes driver AND constraint"
behaviour this section exists to produce. Fixed by pinning the food
economy non-limiting with a single large `deposit_food` call before
stepping (not `record_forage_result`, which would also move the
unrelated recent-forage-success EMA `capacity()` itself reads, and so
break the test's own weather-only expectation in a different way) — the
same "keep depositing food throughout" isolation the five tests
mentioned above already needed, for the identical reason. No production
code changed; this section's own mechanism was never the bug.

### A mound's own hover panel

**The gap.** Every wild creature already gets a live, bar-and-percentage
hover card the instant a player gets close (`CreaturePanel`, driven by
`World._update_creature_panels` iterating `CreatureMarker.GROUP_NAME`) —
but an `AntMoundMarker` has never been a `CreatureMarker` (a mound is a
background population effect, not an individually-simulated creature —
see this file's own opening framing), so the richest a mound's own
hover ever got was `HoverTargetFinder`'s plain cursor-following text
label (`get_display_name()`, `"Ant Mound (population %d)"`). Asked
directly for a food-supply stat "visible on hover like hunger/thirst" —
the player's own mental model is explicitly this existing bar-card
shape, not the plain-text tooltip mounds have used until now.

**The mechanism.** Rather than duplicate `CreaturePanel`'s whole
layout for a second, mound-specific scene, its state-dictionary contract
(already loosely-typed and forgiving of missing keys, see
`CreaturePanel.set_state`) gains two small, backward-compatible fields:
`bar_label` (default `"HP"`, so every existing creature card is
byte-for-byte unchanged) and `show_level` (default `true`, same
reasoning). `AntMoundMarker.panel_state()` returns
`{"name": "Ant Mound", "show_level": false, "bar_label": "Food",
"health_fraction": food_availability_fraction(cell), "invested": false}`
— the SAME bar-fill/percentage widget a hungry sheep's card already
draws, just reading a mound's own food fraction under a different label,
with no fake level number and no player-investment condition row (a
mound is never tamed). `World._update_creature_panels` now also walks
`AntMoundMarker.GROUP_NAME` into the same nearby-and-sorted-by-distance
list `CreatureMarker.GROUP_NAME` already builds, so a mound competes for
one of the same `MAX_CREATURE_PANELS` slots on exactly the same distance
rule as every wild animal, rather than a parallel, separately-capped UI.

### What is explicitly NOT in this pass

- **Rendered presence (2026-09-04).** Every mound now has a real,
  always-visible `AntMoundMarker` (`ProceduralAntMoundSprite` — a small
  dirt dome with a dark entrance hole, same offline procedural style as
  `ProceduralSoilSprite`/`ProceduralDecomposerSprite`), spawned/freed with
  its chunk exactly like every other per-chunk marker here. Every real,
  successful forage (grass-seed OR windfall) additionally spawns a
  short-lived, purely decorative `AntForagerMarker` — reusing
  `ProceduralDecomposerSprite`'s existing "ant" silhouette rather than a
  new design — that visibly walks mound → pickup → cache (or mound → pickup
  only, if the windfall was eaten outright) before freeing itself. Capped
  at one forager in flight per mound (`EarthChunkManager.
  _active_ant_foragers`): `AntColony.FORAGE_CHANCE` can succeed several
  times a SECOND per mound at normal frame rate, and a new visible ant for
  every single one would read as an overlapping-sprite flicker, not a
  colony that reads as alive. The earthworm/robin pair went through exactly
  this same "logic first, sprite later" split when it was built; ants have
  now completed both halves.
- **Real illustrated art (2026-09-05).** `AntMoundMarker` now draws one of
  9 hand-illustrated mound variants (`ant_mound.png`,
  `IllustratedAntMoundSprite`, deterministic per mound cell via a seed
  derived from its GLOBAL coordinate — not the chunk-local mound cell
  alone, or two different chunks' own local (0,0)-ish mounds would always
  pick the identical variant) in place of `ProceduralAntMoundSprite`'s
  drawn dome, at the identical real-world width
  (`ProceduralAntMoundSprite.MOUND_WORLD_WIDTH`) so the swap changes
  nothing about how big an already-placed mound reads. `AntForagerMarker`
  now draws `IllustratedDecomposerSprite`'s real "ant" art instead of
  `ProceduralDecomposerSprite`'s silhouette — a single held pose per leg
  (not an animated cycle, since this marker is short-lived and purely
  decorative), empty-handed while walking to the pickup and switched to
  `ant.png`'s own dedicated carry pose (body + cargo) once it has
  something to actually carry to the cache. See
  [carrion.md](carrion.md)'s own Status entry for `DecomposerMarker`'s
  matching (and more involved, since that ant animates continuously)
  upgrade. Both fall back to the procedural generator if `has_variants()`/
  `has_action()` ever reports no art, unchanged.
- **Ants are not bird prey.** `FlyerDiet` is not extended with an insect
  food type here — a real robin or sparrow eating ants at a mound would be
  a genuine, well-grounded follow-on (the same insectivore mechanism this
  doc's earthworm half already specifies), but it is a separate piece of
  work, deliberately left for later.
- **Ants are not detritivores of CARRION.** `fly_colony.gd`'s corpse/rot
  decomposer loop is untouched; ants scavenging carrion or competing with
  flies over a carcass is real and common but out of scope here. Windfall
  foraging above is a separate, narrower thing — a fallen fruit/nut ground
  item via the existing tree-fruit API, not the corpse/rot system.
- ~~**Leaf litter is a separate forage source this mound simulation does
  not see.** [leaf_litter.md](leaf_litter.md) adds a fallen-leaf ground
  item alongside fallen fruit/nut, picked up by the VISIBLE
  `DecomposerMarker` ants/bugs ([carrion.md](carrion.md)) via the ordinary
  `DroppedItem.FORAGEABLE_GROUP_NAME` path with no changes needed there —
  but this invisible colony's own `_forage_windfall_near_mound` queries the
  fruiting model's abstract fruit/nut stock directly, never `DroppedItem`
  nodes, so it has no way to see a leaf item without a parallel query this
  pass does not build. Named there as a reasonable, separable follow-up,
  not silently dropped.~~ **Resolved (2026-09-06).** Reported live as "ants
  eat leaves at the spot instead of physically carrying the leaf to the
  mound" — a real, confirmed gap, not a misreading: the VISIBLE ambient
  `DecomposerMarker` ants/bugs genuinely do eat leaf litter in place (they
  have no mound/colony concept at all, by design — see carrion.md), and a
  player watching one has no visual way to tell it apart from a real
  colony forager, since both draw the identical "ant" art. But the
  above-quoted premise ("via the ordinary `DroppedItem.FORAGEABLE_
  GROUP_NAME` path") was itself stale: leaf litter is GPU-instanced plain
  data (`LeafLitterField`), never a real `DroppedItem` node, reached
  through `EarthChunkManager.nearest_leaf_litter_near`/
  `consume_leaf_litter_at` instead (see leaf_litter.md). New
  `EarthChunkManager._forage_leaf_near_mound` gives the real colony
  simulation that same query, checked in `step_ants` BEFORE the
  grassland/forest-rainforest biome branch below — unlike grass seed or
  windfall, a leaf is not biome-gated at all (a "grassland" chunk can
  still have real trees shedding leaves onto it). `AntForagerMarker`
  carries it home exactly like a seed or windfall nut (same walk, same
  real "carry" pose, same real-arrival-resolves contract against
  `consume_leaf_litter_at`), but a leaf is real detritus/food, not a
  propagule — it disappears at the mound rather than being re-cached or
  re-planted, unlike a survived grass seed or windfall nut. Pheromone-
  biased recruitment toward a known-good leaf source is a real, separable
  follow-up left undone: `nearest_leaf_litter_near` only ever reports the
  single closest leaf, with no plural "leaves near" query to run
  `PheromoneField.best_candidate_index` against the way seed/windfall do.
  **Follow-up bug, same day:** "disappears at the mound" above was the
  intended final state, but the shipped code actually made the leaf vanish
  at PICKUP instead — `_resolve_arrival_at_food`'s `consume_leaf_litter_at`
  call genuinely removes it from `LeafLitterField` (and so from the ground
  renderer) the instant the ant arrives, correct for the ground-litter
  side of the world, but nothing ever stood in for it visually for the
  walk back: only the ant's OWN body switched to its carry pose, same as
  an empty-handed return. Reported directly: "the ant now uses the carry
  sprite sheet animation row when dragging a leaf into the mound but it
  still disappears when the ant touches it ... it should actually drag
  the real leaf entity visibly over the ground and it should vanish only
  when it's in the mound." Fixed by threading the picked-up leaf's own
  species/season through from dispatch time (`_forage_leaf_near_mound`
  already has both, from the same leaf-near query that found the target
  position) to a second, real sprite on
  `AntForagerMarker` — cropped from the exact same `LeafLitterAtlas` cell
  a ground-resting leaf of that species/season would use, at the same
  `LeafLitterRenderer.WORLD_SIZE` — shown only while genuinely returning
  with real food, hidden on an empty-handed return, and freed automatically
  with the rest of the forager at real arrival at the mound (ordinary
  Godot child-node ownership, no extra bookkeeping needed for "vanish only
  at the mound"). Also reported in the same message: **ant forager walking
  speed halved** (`AntForagerMarker.WALK_SPEED`, 24.0 → 12.0) — a
  deliberate, tuned divergence from `DecomposerMarker`'s own ambient
  ants/bugs, which this constant used to equal on purpose (see that
  constant's own doc comment); the ambient decomposer ants/bugs are
  unchanged.
  **Second follow-up, same day: the named pheromone-recruitment gap above
  is now closed.** Reported live: "ants go straight to the next leaf when
  moving out the mound ... they should either explore randomly or follow
  pheromones." True as reported: with `nearest_leaf_litter_near` only ever
  returning the SINGLE closest leaf, a known trail could never matter even
  in principle — there was never more than one candidate to bias a choice
  among, so every trip beelined to whichever leaf happened to be nearest.
  New `LeafLitterField.leaves_near`/`EarthChunkManager.leaf_litter_near`
  are the missing plural query (mirrors `nearest_leaf_near`/
  `nearest_leaf_litter_near`'s own radius contract exactly, just collecting
  every match instead of tracking only the best one; those two are
  untouched and still used by `DecomposerMarker`'s own single-leaf
  in-place eating). `_forage_leaf_near_mound` now mirrors
  `_forage_seed_near_mound`/`_forage_windfall_near_mound`'s own shape
  exactly, including `PheromoneField.best_candidate_index` — a real,
  previously-successful spot's own trail can now outweigh a marginally
  closer, never-visited leaf, the same recruitment effect seed/windfall
  foraging already had. ~~Deliberately NOT built: a genuine random-explore/
  wander phase before a target is even known — every forage kind in this
  simulation (seed, windfall, leaf alike) is architected around the colony
  already having found a real, reachable candidate before ever dispatching
  a forager at all (`AntForageBehavior` has no SEEKING phase for any of
  them, by original design, not oversight), so a true "wanders with no
  known target yet" scout behaviour would be a materially bigger,
  cross-cutting change to that shared architecture, not a leaf-specific
  fix — left as a separate, explicitly named follow-up rather than
  attempted here.~~ **Partially resolved (2026-09-06) — see "Scouts mark
  leaf clusters, workers collect from marks" below.** A real scout/worker
  split now exists, but the SEEKING-phase gap named above is still
  genuinely open: a "scout" is still dispatched to an already-known
  candidate exactly like an ordinary forager, just one found at a wider
  radius — there remains no true "wanders with no target at all yet"
  behaviour anywhere in this simulation. With no trail yet (a colony's
  first-ever leaf forage, or after one has fully decayed),
  `best_candidate_index` still falls back to pure nearest-candidate
  selection, same as before this fix.
- **Mound COUNT is still fixed and deterministic per chunk** (see "A queen,
  and where a colony's size comes from" above for what is no longer fixed
  — each mound's own population now genuinely grows or stalls with real
  forage success). A grown colony does not split off and found a NEW
  mound elsewhere, and a starved one does not disappear outright — both
  are real, grounded follow-ons (colony fission/budding is a genuine
  phenomenon in several ant subfamilies) deliberately left for later
  rather than attempted alongside everything else in this pass.
- **No worker/soldier caste differentiation.** Every ant this pass renders
  is visually and behaviourally identical; real polymorphic castes (major/
  minor workers, soldiers) are a separate, later refinement, not attempted
  here.
- **Not persisted, not catch-up integrated.** A reloaded chunk re-seeds
  its mounds deterministically; a specific mound's exact population is
  not remembered indefinitely across an unload/reload. **Correction**:
  earlier revisions of this note borrowed `EarthwormPatch`'s own "a
  short-timescale, self-renewing local effect does not need
  `ChunkEcologyCatchup` fidelity" reasoning — that never actually applied
  here. Worm surfacing genuinely IS short-timescale (`SURFACE_RATE`
  reaches full emergence in ~2 seconds); ant colony growth is the
  OPPOSITE — this section's own `GROWTH_RATE_PER_DAY` is deliberately
  pinned as the slowest-maturing population this game tracks. That
  mismatch is exactly why colonies never appeared to mature in ordinary
  play (see "Thriving colonies, and a real swarm" above) — not a
  short-timescale effect that didn't need catch-up, but a long-timescale
  one that was never given any way to accumulate. This pass's real fix
  is not persistence (a bigger, separate lift — genuine
  `ChunkEcologyCatchup` integration would need first extending it to
  per-MOUND granularity, since `AntPopulationModel`'s own doc comment
  already notes a colony's population lives per mound, not per chunk,
  unlike every other species' aggregate) but seeding every mound's
  INITIAL population at an established range instead of the bare
  minimum — see above. Real persistence/catch-up remains open, now
  honestly scoped rather than mis-justified as unnecessary.

### A real food stock number, not just a percentage, on hover

Requested directly: "the ant mount should show how much food is on stock
in the hover tooltip." "A mound's own hover panel" above already reads
`food_availability_fraction` — a derived 0-1 RATIO (stored ÷ what the
current population needs for a healthy buffer) — as a percentage bar,
which answers "is this colony food-secure," a genuinely different
question from "how much is actually in the larder." `AntColony.
food_stored_at(cell)` has held that raw absolute quantity since the food
economy landed (see above) but was never plumbed through to either hover
surface. Added to `AntMoundMarker.get_display_name()` (the plain
mouse-hover NAME tooltip, via `HoverTargetFinder`) rather than the bar
panel: that surface already establishes the exact "interpolate a real
number into hover text" pattern for population
(`"Ant Mound (population %d)"`), so the stock number joins it there —
`"Ant Mound (population %d, food %d)"` — rather than teaching the shared,
every-creature `CreaturePanel` a second number format for one species.
The bar panel's own percentage is untouched; the two hover surfaces stay
complementary, not duplicated.

### Cluster recruitment: multi-scout waves, directional trails, and invalidation

Reported live, as a single dense follow-up to the scouting rework above:
"the ant behavior still has some flaws ... When a scout goes out other
ants follow him in a line even when nothing has been discovered yet...
the mound should send out multiple scouts in random directs. these
scouts should only lay out pheromones after they discovered a cluster
for which multiple ants are needed ... he encodes direction and amount
in the pheromones so other ants don't follow it back into the mound on
the way back from a discovery ... then when the scouts return the mound
dispatches more ants which follow / resolve the pheromone trails and the
last ant which takes home the last piece or one that encounters it empty
invalidates the pheromone trail by masking the existing pheromone trail
with complete marker."

**This superseded two earlier, narrower mechanisms built in the same
spot, both landed the same day, neither meeting this bar.** The plain
per-tile `PheromoneField.deposit` described in "Pheromone trails" above
fired unconditionally on every successful pickup regardless of size — a
lone find recruiting nobody was never distinguished from a real cluster.
Separately, a concurrently-built `AntColony._cluster_marks` memory (a
mound remembering a handful of exact pixel positions where a scout once
found `CLUSTER_MIN_LEAVES`-or-more leaves together, then dispatching
workers straight at those remembered coordinates via
`EarthChunkManager._dispatch_cluster_workers`) was real progress on
"collect from marks," but not on "explore randomly... other ants follow
him in a line": a worker sent straight at a remembered exact position is
still omniscient dispatch, just against a smaller, scout-populated
candidate list instead of a whole-mound scan, and it never encoded a
direction or a stop signal into the pheromone field itself — the actual
mechanism asked for. That whole memory (constants, dispatch function,
tracking bucket, and its own dedicated tests) was removed in favour of
the mechanism below, rather than kept running alongside it — the two
disagreed on what a successful arrival should even do to the pheromone
field, and running both would have meant one silently overwriting the
other's effect on every single trip.

**Scouts wander in a real spread, not a line.**
`EarthChunkManager._dispatch_ant_scout_wave` dispatches
`AntColony.SCOUT_WAVE_SIZE` (3) scouts together, each assigned a
DIFFERENT sector spread evenly around a circle
(`Vector2.from_angle(TAU * i / SCOUT_WAVE_SIZE)`) as its own
`assigned_heading_bias`. `AntScoutWander.spread_heading` (new,
`SPREAD_BIAS := 0.3`, sharing a `_lerped_heading` helper with the
existing `biased_heading`) gently nudges each scout's own independent
wander toward its assigned sector — applied AFTER `biased_heading`'s own
real pheromone-gradient bias, never instead of it, so a genuine nearby
trail still wins over an assigned sector — so several scouts dispatched
from the same mound at the same moment visibly fan out in different
directions, rather than reading as one wandering ant with the others
correlating onto the same path by coincidence of a shared `wander_seed`.

**Only a real cluster ever touches the pheromone field, in either
direction.** `AntForagerMarker._sense_food_nearby` now reports a
`cluster_size` (how many of the same kind were sensed together at commit
time); `_is_cluster_find := cluster_size >= AntColony.CLUSTER_THRESHOLD`
(3, deliberately not 2 — see that constant's own doc comment: a pair is
still well within what one forager quietly handles over ordinary trips).
A solo find below threshold neither deposits nor invalidates anything —
the exact "should only lay out pheromones after they discovered a
cluster" ask, read as a hard gate rather than a bias.

**Direction and amount, laid progressively on the way home, not at the
food and not at the mound.** `PheromoneField`'s own deposit shape is now
`{amount, direction, exhausted}` (previously a bare scalar).
`deposit_trail(tile, direction, amount)` REPLACES whatever was at a tile
rather than accumulating into it, the way plain `deposit` still does — a
fresh "amount left, which way to the resource" reading is more useful
here than a blended history of possibly-stale ones.
`AntForagerMarker._maybe_deposit_trail_tile`, called from `_process`'s
RETURNING branch once per newly-crossed tile (tracked via
`_last_trail_tile`/`_has_deposited_trail_tile`, not once per frame),
computes `direction` as the real unit vector from THAT tile toward the
food's own position — so a trail read anywhere along the homeward walk
points back OUT toward the resource, never toward the mound. This is the
literal fix for "other ants don't follow it back into the mound on the
way back from a discovery": the earlier plain-deposit model marked only
the food's own position, which a later ant reading it from partway home
had no way to distinguish from "the mound is this way." `amount` carries
the cluster's own sensed size through unchanged from commit.

**Resolvers follow the exact trail; scouts merely lean toward it.**
`PheromoneField.nearest_trail_near(point, tile_size)` returns the
nearest deposit that is both non-exhausted AND carries a real direction
— a plain historical `deposit()` (`Vector2.ZERO` direction) or an
exhausted one is never returned. A `resolver`
(`AntForagerMarker.resolver`, set only by dispatch, never a plain scout)
checks this FIRST on every scouting step and, if found, walks in exactly
that stored direction — no blending with its own ambient wander at all,
a deliberate committed step, unlike a scout's own soft
`gradient_direction` lean. A resolver with no known trail nearby (or a
scout, which never takes this branch) falls through to the same
wander-plus-gradient-plus-spread heading every scout already uses.

**Which role the mound actually dispatches.** `EarthChunkManager.
step_ants` calls `AntColony.has_active_pheromone_trail(cell)` (true iff
the mound's own field has any real, non-exhausted, directional deposit)
to decide, per mound, per forage tick: a resolver wave
(`RESOLVER_WAVE_SIZE`, 2) if a trail is already known, or a scout wave
(`SCOUT_WAVE_SIZE`, 3) otherwise — "the mound should send out multiple
scouts... then when the scouts return the mound dispatches more ants
which follow / resolve the pheromone trails," read as a literal per-tick
EITHER/OR. Unlike the superseded `_cluster_marks` design, there is no
separate concurrent-ant pool here: scouts and resolvers both draw from
the same `active_forager_cap_at` slots ordinary foraging has always used
— a resolver is not additional traffic on top of scouting, it is what
the SAME mound dispatches next once something is actually known.

**Invalidated by masking with a stop signal, not by erasing.**
`PheromoneField.invalidate_near(point, radius_tiles, tile_size)` sets
`exhausted = true` on every real deposit within radius, kept rather than
removed so it still decays on its own ordinary schedule instead of a
fresh, unrelated deposit reusing the same tile before the stop signal
has had time to matter. `concentration_at`/`gradient_direction`/
`nearest_trail_near`/`has_active_trail` all already skip an exhausted
entry, so masking one is enough to make it inert everywhere at once.
Triggered from `AntForagerMarker._resolve_arrival_at_food`, for any
cluster find or resolver (never a plain solo find): arriving to discover
the spot already emptied invalidates immediately; otherwise a fresh,
real, LOCAL re-check (`_remaining_same_kind_count`, re-querying the world
at the food's own position the same way `_sense_food_nearby` does, not
arithmetic on the `cluster_size` sensed back at commit time) invalidates
the instant nothing of the same kind remains. "The last ant which takes
home the last piece or one that encounters it empty invalidates the
pheromone trail by masking the existing pheromone trail with complete
marker" — both halves, literally.

**What this does NOT include**, named rather than silently dropped: no
seed/windfall cluster recruitment (`CLUSTER_THRESHOLD`'s own gating is
kind-agnostic, but leaf litter is still the only kind this project places
densely enough to realistically cluster — see leaf_litter.md's own
GPU-instanced point-record shape; seed/windfall clusters are a
reasonable, separable follow-up). No visual distinction between a
scout, a resolver, and an ordinary solo forager (identical
`AntForagerMarker`, same art, same walk). No choice between several
simultaneously-active trails — `nearest_trail_near` returns only the
single closest one.

### Winter dormancy, and a mound that can come back from zero (2026-09-06)

Reported live: "now i don't see any ant mounds at all anymore (fresh
start, winter)". Root-caused directly rather than assumed, by simulating
a freshly-seeded mound receiving zero successful forages: `FOOD_BUFFER_
DAYS`(3) × `SECONDS_PER_SIMULATED_DAY`(60) = 180 real seconds is far
shorter than a real winter's near-total lack of forage success (bare
trees drop no windfall; fallen leaf litter ages into its own terminal
decay stage — see [leaf_litter.md](leaf_litter.md) — with nothing
replacing it while the canopy stays bare), so every mound was starving to
a literal `population_at` 0.0 well within one season. Worse: once there,
it stayed there — `PopulationModel.step`'s own hard "`carrying_capacity
<= 0.0` → population immediately 0.0" rule means population can never
grow itself back out through ordinary logistic growth alone (growth is
proportional to CURRENT population, and zero population growing at any
rate is still zero) — confirmed directly by feeding a starved mound a
GUARANTEED forage success on every single `advance()` call for a real 5
simulated minutes: `food_stored` climbed into the thousands: `population_
at` never moved off 0.0. "A real food economy"'s own `test_a_fully_
starved_colony_reads_zero_food_availability_not_full` had already pinned
the "starves within a handful of simulated days" half of this as a
confirmed, deliberate famine; nothing had yet pinned that this made
EVERY colony's eventual, permanent extinction a certainty rather than a
real, occasional risk.

**Two changes, addressing both halves.**

1. **Real winter dormancy**, mirroring `EarthwormPatch`'s own cold-gate
   exactly (same soil, same real mechanism — real ants, like real
   earthworms, drastically cut activity and metabolism in cold soil
   rather than continuing to draw full upkeep while genuinely unable to
   forage for it). `AntColony.record_warmth` (new, mirrors `record_
   moisture`'s own EMA-fed, `EarthChunkManager._refresh_ant_moisture`
   -sourced shape) feeds `dormancy_multiplier_at`, which reuses
   `EarthwormPatch.COLD_CUTOFF`/`MILD_WARMTH` directly against the
   SAME real `EarthwormPatch.soil_warmth(climate, season_warmth)`
   reading `step_worms` already computes for the identical soil — not a
   second, independently-eyeballed pair of numbers. `_deplete_food` now
   scales its draw by this multiplier, floored at `DORMANCY_FLOOR` (0.2,
   never all the way to 0.0 — mirrors `WINTER_SOIL_FLOOR`'s own "a
   seasonal swing is a partial cooling, not a multiplication down to
   zero" reasoning exactly: a genuinely dormant colony still needs SOME
   food to survive winter on stored fat, the same as a real
   overwintering colony). A mound that has never had a real reading yet
   defaults to full, undiminished activity (`record_warmth`'s own "1.0,
   not 0.0" default) — the OPPOSITE of moisture/forage-success's own
   defaults, deliberately: those feed a capacity BONUS, where "none
   earned yet" safely reads as a neutral baseline; warmth drives a
   PENALTY, where the equivalent "coldest possible" default would
   throttle every freshly-loaded mound before its own first real reading
   ever arrives, directly contradicting "a freshly-seeded mound is never
   born already starving" (`_founding_food_reserve`'s own doc comment).
2. **Re-founding**: the actual fix for a mound that DOES still reach a
   literal 0.0 regardless (a sufficiently long or severe cold spell, or
   any other real famine — dormancy above narrows how often this
   happens, it does not claim to make it impossible). Real ant nest
   sites get recolonized once conditions improve — a new queen/swarm
   founds again where an old colony died out — so `AntColony.advance`
   now checks, per mound per step, whether real, on-hand food has
   genuinely piled back up at an empty mound past
   `REFOUNDING_FOOD_THRESHOLD` (see that constant's own doc comment for
   why this is deliberately NOT the same full, multi-day standard
   `_seed_initial_mounds` starts a brand-new colony at), and re-founds it
   at `STARTING_POPULATION` exactly as a brand-new mound would, before
   the ordinary logistic-growth step ever runs that tick. Still reachable
   even for an "extinct" mound: `EarthChunkManager._dispatch_forager`'s
   own `active_forager_cap_at` floors at 1 forager regardless of
   population, so a lone forager keeps trying — and can keep depositing
   real food home — even after every worker has starved.

**Follow-up (2026-09-06, same day): the re-founding threshold itself was
too slow to ever be observed working.** Reported live: "when an ant mound
collapses and hits 0 population then it stays at 0 population even if
new ants enter or bring food. the food stock correctly increments, but
the population stays zero." Root-caused directly (a throwaway diagnostic
probe, not a logic bug): gating re-founding on a full founding reserve
(45.0 units) took over 22 REAL MINUTES to trigger even under a perfectly
successful lone-forager trip every 30 real seconds — a threshold nobody
would ever realistically wait out, even though the mechanism itself was
working exactly as designed. `REFOUNDING_FOOD_THRESHOLD` (new,
`FOOD_PER_SUCCESSFUL_FORAGE * 3.0`) replaces the full-reserve gate: 3
successful trips' worth is real, repeated evidence the site is
productive again — not a single lucky fluke, but nowhere near a full
mature colony's own reserve — mirroring `CLUSTER_THRESHOLD`'s own
identical "3, not 1, not a fluke" reasoning from the cluster-recruitment
section above. A mound re-founded this way starts at the full
`STARTING_POPULATION` but on a comparatively thin food reserve, so it
reads as genuinely fragile at first (`food_availability_fraction` low
relative to that fresh population's own upkeep) rather than instantly
"safe" — the same real vulnerability any newly-founded colony already
has, resolved by the ordinary food economy catching up over subsequent
ticks, not a special case.

**What this does NOT include**: no seasonal reduction in FORAGE_CHANCE
or dispatch itself (a dormant colony still sends its usual foragers out;
it is only the UPKEEP draw that is throttled, matching how real dormant
ants still occasionally forage on a mild winter day rather than sealing
the nest outright). No warning/UI telling a player a mound is dormant or
has gone extinct — `AntMoundMarker`'s own hover tooltip already reports
real population/food, so an attentive player can already read a dormant
or refounding mound off the same numbers. No migration-based
recolonization from a NEIGHBOURING mound (`AntPopulationModel`'s own doc
comment already names ants as the one regional population in this game
with no `migrate()` at all, mounds being sessile) — re-founding here is
a single mound's own site recovering, never population moving in from
elsewhere.

### Colony budding: overpopulation founds a new mound (2026-09-06)

Reported live: "ant mounds should have a maximum capacity and upon
overpopulation half of the colony will found a new mound hatch a new
queen and grow the new colony again... they should found based on
minimum distance to original mound and food availability within scout
radius." Real ant colonies bud/split exactly this way once a nest
genuinely outgrows its site — a new queen and a share of the workforce
founding a fresh, independent colony nearby rather than the parent
growing without limit forever.

**"Maximum capacity" is not a new concept — it already exists.**
`AntPopulationModel.MAX_REFERENCE_POPULATION` is already named "the
ceiling `capacity()` can ever produce" (see that constant's own doc
comment), and population chases capacity via ordinary logistic growth —
so a mound whose population has reached it is already, by construction,
sitting at the real maximum it can ever sustain. `AntColony.
is_overpopulated_at(cell)` is simply `population_at(cell) >=
MAX_REFERENCE_POPULATION`, no second, redundant ceiling invented on top.

**The split, `AntColony.bud_new_mound(from_cell, to_cell)`**: "half of
the colony" — both its population AND its real stored food reserve, so
the new colony is not born starving (the same "never born already
starving" standard `_founding_food_reserve` already gives every
brand-new mound) and the parent is not left with an oddly outsized
reserve for its own now-halved population. A no-op at an invalid target
(the caller is expected to have already checked `is_valid_mound_site`,
but this stays safe on its own regardless).

**Whether a mound even attempts to bud this step, `AntColony.
should_bud(cell)`**: gated on `is_overpopulated_at`, then a small
per-step chance (`BUD_CHANCE`, mirroring `FORAGE_CHANCE`/`MOUND_CHANCE`'s
own "ongoing background activity, not a single guaranteed burst"
reasoning exactly) — keeps the real site-search below naturally rare
even while a colony sits at its own reference maximum for a long
stretch, rather than repeating an expensive search every single tick.

**Site selection is EarthChunkManager's job, not AntColony's** — the
same "AntColony owns the abstract economy, EarthChunkManager owns the
real ground" split every other mound accessor already keeps.
`AntColony.is_valid_mound_site(cell)` only knows the two facts
`_seed_initial_mounds` itself already gates a brand-new mound on: real,
excavatable soil (`SOIL_BIOMES`), and not already somebody else's
entrance (bounds-checked too, so a caller scanning a fixed window
larger than this colony's own real grid — a real possibility once a
budded colony can, in principle, differ from the chunk's own `CHUNK_
SIZE` — never indexes `_biome` out of range). `EarthChunkManager.
_find_bud_site(chunk_coord, colony, from_cell)` does the rest, and IS
the literal "minimum distance... and food availability within scout
radius" ask: every real candidate cell in the chunk is collected via
`is_valid_mound_site`, sorted NEAREST-to-`from_cell` first, then checked
in that order via new `_has_food_near` (leaf litter, grass seed, or a
real windfall nut within `AntColony.SENSE_RADIUS_TILES` — the literal
"scout radius" a real scout would need to physically wander into range
of to notice anything at all, mirroring `AntForagerMarker._sense_food_
nearby`'s own identical priority query at the site-selection level
rather than a live forager's own current position) — returning the
first, so nearest, real candidate that actually has food nearby, or no
site at all if nothing in the whole chunk qualifies this attempt (tried
again on some future tick, per `should_bud`'s own small chance).

**Wired into `step_ants`**: per mound, per step, independently of the
ordinary forage roll right below it (an overpopulated mound can bud AND
send a forage wave out on the identical tick — the two are unrelated
events). A successful bud calls `bud_new_mound`, then spawns a real,
visible `AntMoundMarker` for the new mound via `_spawn_ant_mound_marker`
— extracted from `_load_chunk`'s own original inline marker-creation loop
(a real refactor landed alongside the new functionality, not a second
hand-copied construction) so budding's one new mound gets the identical
illustrated-variant seeding, tile-centre placement, and colony/cell
wiring every mound has had since chunk-load.

**What this does NOT include**: no cap on how many mounds budding can
add to a chunk beyond `AntColony.MAX_MOUNDS` — that constant governs
INITIAL seeding density only (see its own doc comment's "fewer, bigger
colonies" reasoning); budding is a separate, later-game growth mechanic
deliberately allowed to exceed it, since gating a thriving colony's own
real expansion behind the same cap that limits how many colonies a
chunk starts with would make the feature rarely fire in practice. No
cross-chunk budding — `_find_bud_site` only searches the SAME chunk the
overpopulated mound already lives in; a mound on a chunk boundary
finding no room within its own chunk simply keeps re-rolling
`should_bud` until conditions change, a real, named scope cut rather
than the cross-`AntColony`-instance coordination true cross-chunk search
would need. No visual "budding in progress" animation or effect — the
new mound simply appears, fully formed, the same "no fanfare" precedent
`_maybe_refound` already set for re-founding.


## Crawling out, and back down

A worm crawls out of the earth rather than appearing on top of it. The sprite
used to be created at full size the moment the worm counted as surfaced and
freed the moment it stopped, so worms blinked in and out of existence -- the
model already tracked how far up a worm was, and only the drawing ignored it.

Emergence is revealed along the worm's own LENGTH rather than faded in: a worm
coming up is a nose, then a body, then a tail, where a fade would just be a
ghost appearing. The visible part stays put as the rest follows it out, so the
worm reads as crawling rather than as being dragged sideways.

Nothing shows below the surfacing threshold, which is the same line the
gameplay uses -- a bird can never see a worm it cannot take.

## Crushed underfoot: weight-emergent worm mortality

Requested directly: stepping on a worm should splatter it, and this should
**emerge** from real weight and force rather than being a flat "anyone can
squash a worm" rule — the calibration example given was a frog's step
sparing a worm while a horse's kills it. No frog or other amphibian exists
in this game at all (checked directly — no species, sprite, or concept doc
mentions one), so the real substitutes below are the smallest and largest
land creatures that DO exist: a mouse or squirrel sparing a worm is the
frog's role in this codebase, and a horse killing one is exactly the given
example already, unchanged.

**Real-world grounding.** An earthworm's entire structural integrity is a
thin cuticle around a fluid-filled, hydrostatic body — there is no
skeleton, no rigid shell, nothing standing between outside pressure and the
worm's own insides. It fails under strikingly little force compared to
almost anything that could step on it; the real determining factor for
"does this animal's step kill it" is overwhelmingly the animal's own body
mass (a horse outweighs a mouse by four orders of magnitude), not exotic
foot-shape differences — a mouse's paw and a horse's hoof are both small
relative to the animal's own bulk, so mass carries the calibration example
on its own without needing per-species contact-area data this project has
no real reference for.

**The mechanism** reuses this codebase's own established "one damage
model for the whole world" (see [materials.md](materials.md)'s section by
that name and `ImpactResolver`) in shape, not in its literal numbers:
`impact = momentum (mass × velocity)`, resolved against a target's own
resistance threshold. `ImpactResolver.T_CRUSH` itself is calibrated for
thrown-rock-vs-creature combat, an entirely different scale from
"anything at all stepping near a soil invertebrate" — reusing that exact
number would mean nothing above a whisper of momentum could ever be
*under* it, so this pass adds a new, worm-scaled threshold rather than
misapplying an unrelated one, the same reasoning `docs/progress.md`'s
earlier passes already use whenever an existing constant belongs to a
different scale.

- **`CreatureMass`** (new, `src/world/creature_mass.gd`) — real average
  adult body mass, in kilograms, for every land-mammal species
  `AnimalAnatomy` defines a real anatomy profile for (deer, horse, goat,
  camel, reindeer, sheep, boar, tapir, bear, wolf, lynx, jaguar, jackal,
  arctic_fox, mountain_lion, lion, the generic "herbivore"/"predator"
  builds, and the two snake species), each a commonly-cited reference
  figure for that real animal, not an invented number. The player's own
  mass reuses `StoneSize.AVERAGE_BODY_MASS_KG` (70kg) directly — the
  SAME reference figure this codebase already established for a human,
  restated rather than duplicated as a second, independent guess. The
  handful of purely mythical species this game also has (world bosses:
  lindwurm, rubezahl, nyx, krampus, squallmaw, coilnecca, champ, kraken)
  have no real animal to cite a mass for at all, so they fall back to
  `AnimalAnatomy.profile_for(species).world_scale` CUBED against the
  deer's own real mass/scale ratio — mass follows volume, which follows
  the cube of a linear dimension, the identical reasoning
  `StoneSize.mass_kg_for` already uses to turn a stone's diameter into a
  real mass. Cubing matters: `world_scale` is tuned for on-screen
  legibility, not real mass ratios (a horse is only 1.2x a deer's
  `world_scale` for readable on-screen size, nowhere close to its real
  ~7x mass) — verified directly before relying on it anywhere: cubing the
  real land mammals' own `world_scale` ratios against their real masses
  reproduces the tabulated real figures only loosely at the high end
  (confirming REAL reference data, not a derived formula, is what the
  tabulated species actually need), which is exactly why only the
  mythical, no-real-reference species use the derived fallback at all.
- **`EarthwormPatch.CRUSH_MOMENTUM_THRESHOLD_KG_M_S`** (new) — the
  worm's own resistance, at the worm's OWN scale rather than combat
  scale. Momentum here is a full body's weight settling through one
  foot at ordinary walking pace (`PebbleDispersion.FOOTSTEP_SPEED_MPS`,
  already this codebase's own "average human walking speed" reference,
  reused rather than invented again) — deliberately the CREATURE'S OWN
  FULL mass, not `PebbleDispersion`'s own foot-mass FRACTION: kicking a
  pebble aside in passing is a glancing, foot-only contact, but standing
  weight settling onto something underfoot transmits close to the whole
  body's own mass through that one point of contact, a genuinely
  different physical situation from a glancing kick and so deliberately
  not sharing that fraction. Pinned so a mouse/squirrel's own momentum
  falls under it and a deer/boar/horse/player's own falls over it —
  the real, tested boundary this whole mechanic exists to draw.
- **`EarthwormPatch.is_crushed_by(momentum_kg_m_s) -> bool`** (new) — the
  threshold comparison itself, mirroring `ImpactResolver.resolve_impact`'s
  own `momentum >= threshold` shape exactly, kept on `EarthwormPatch`
  itself rather than routed through `ImpactResolver` (whose own threshold
  constants are combat-scaled, not worm-scaled, per the grounding above).
- **`EarthChunkManager.crush_worm_at(pixel_position, momentum_kg_m_s) -> bool`**
  (new) mirrors `take_worm_at`'s own shape exactly (same `is_surfaced`
  gate — a burrowed worm has no exposed body to step on, so nothing can
  crush what nothing can see — same `_sync_worm_sprites` resync on
  success) but resolves through `is_crushed_by` instead of unconditional
  taking, and only removes the worm when the momentum actually clears
  the threshold; an insufficient step leaves a surfaced worm exactly
  where it was, same as never having been stepped on at all. Recovers on
  the identical `RECOVERY_SECONDS` clock as being eaten — the burrow
  itself is not destroyed, only whatever worm was in it at the time.
- **Wired for the player AND every creature**, mirroring `tread_snow_at`'s
  own "player position, then every `CreatureMarker` in the group" call
  shape in `World`'s per-frame step: the player's own momentum uses
  `StoneSize.AVERAGE_BODY_MASS_KG`; a creature's own uses
  `CreatureMass.mass_kg_for(creature.info.species)`. No new debounce
  machinery needed for either: a worm's own removal is already
  idempotent (`is_surfaced` reads false the instant it's gone), so
  re-checking the same tile every frame a foot rests on it costs nothing
  extra and needs no per-entity "last tile" tracking the way continuous
  accumulators (path wear, snow depth) do.

**What this pass does NOT include**, named rather than silently dropped:
no dedicated splat visual effect — a crushed worm currently disappears
exactly the way an eaten one already does (the sprite layer already
re-syncs to "no worm here" either way), a real but purely cosmetic
follow-up, not a gap in the mechanic itself. Flying creatures
(`AmbientFlyerMarker`'s own robins/sparrows/kingfishers) are airborne, not
walking, so they are deliberately excluded from this entirely — a robin
already interacts with a worm through `take_worm_at` on its own terms
(eating it), never by incidentally landing weight on it.

**The dedicated splat visual named above as a scope cut is the direct
follow-up this section itself pointed at — see "Illustrated worm sprite"
below, which closes it.**

**Size.** An earthworm is about ten centimetres, the same as a crocus is tall,
and is drawn at the size that makes true. It was set by eye back when every
flower shared one invented height; once flowers were pinned to the player's own
scale the worm was suddenly longer than several of them and read as a snake
lying in the grass.

### Generalized to caterpillars too (2026-09-06)

Reported directly, right after caterpillars shipped: *"they don't get
flattened when I step on them ... make that mechanic work for all animals
based on physics (only worms and caterpillars are affected by that
tho)"* — i.e. the underlying RULE should be one shared, physics-based
check available to any creature small enough to be at risk underfoot at
all, not a worm-specific special case duplicated by hand for a second
species; the request's own parenthetical already recognises that in
practice, today, that still only ever means worms and caterpillars —
nothing else in this codebase is both small enough and lacks its own real
health/combat stack the way `CreatureMarker` wildlife (sheep, wolf, deer,
...) does.

**The threshold itself moves out of `EarthwormPatch`**, into a new
`CrushMechanic` (`src/world/crush_mechanic.gd`) — `CRUSH_MOMENTUM_
THRESHOLD_KG_M_S` and `is_crushed_by(momentum_kg_m_s)`, byte-for-byte the
same constant and comparison, just no longer owned by a class named after
one specific victim. `EarthwormPatch.crush` now calls through
`CrushMechanic.is_crushed_by` instead of a local copy — a pure rename at
the physics layer, not a behaviour change (every existing worm crush test
still holds, unchanged in substance, just now targeting the class that
actually owns the rule).

**The DETECTION side, not the threshold, is what actually differs between
the two victims** — and deliberately stays two call sites rather than one,
because a worm and a caterpillar are not the same *shape* of thing in this
codebase (see "Caterpillars: on trees, on the ground, green leaves only"
above): a worm is per-tile cell state inside a chunk's own `EarthwormPatch`
sim, with no node identity at all, while a caterpillar is a real,
independently-positioned `Node2D` (`CaterpillarMarker`). Forcing both
through one lookup shape would mean inventing fake node identity for worms
or fake cell state for caterpillars, purely to satisfy a shared function
signature — the "three similar things beats a premature abstraction"
reasoning this doc's own ant/desert-scrub sections already lean on
elsewhere. So:

- **`EarthChunkManager.crush_caterpillars_near(pixel_position,
  momentum_kg_m_s) -> bool`** (new) — the caterpillar-shaped sibling of
  `crush_worm_at`. Resolves the stepper's own tile/chunk coordinate (the
  same `_world_tile_for_pixel`/`_chunk_coord_for_tile` pair every other
  per-tile query in this file already uses), then checks every
  `CaterpillarMarker` this manager is tracking for THAT chunk
  (`_caterpillar_markers`, the same dictionary `_load_chunk`
  populates and chunk-unload frees) against the identical tile, via each
  marker's own real `.position` — a caterpillar has no burrow to look up,
  its position IS the lookup. A caterpillar on the stepped-on tile whose
  momentum clears `CrushMechanic.is_crushed_by` is `queue_free()`'d and
  dropped from the tracking array; returns whether anything was actually
  crushed, mirroring `crush_worm_at`'s own boolean contract exactly.
- **Wired identically to the worm call**, in the same `World._client_
  process` block, right alongside it: the player's own
  `_PLAYER_STEP_MOMENTUM_KG_M_S`, and every `CreatureMarker`'s own
  `CreatureMass.mass_kg_for(species)`-derived momentum — so a wolf or a
  deer stepping on a caterpillar crushes it exactly as readily as the
  player does, the same "any sufficiently heavy stepper, not just the
  player" generalization the worm mechanic already had from the start.

**No corpse/recovery state** — unlike `EarthwormPatch`'s own machinery
(`_crushed`, `RECOVERY_SECONDS`), which exists because a worm's burrow is a
renewable resource that repopulates on a clock, a caterpillar has no
equivalent "spot" to repopulate — it was never tied to a place the way a
worm's burrow is, so there is nothing for a recovery clock to apply to. A
future caterpillar respawn, if wanted, belongs to the same spawn-density
reasoning `CaterpillarRenderer.spawn_caterpillars` already owns, not to
this mechanic.

**The "no splat VFX" gap this section originally named here is closed**
(2026-09-06, "build both — crushed sprite for all small animals"):
`caterpillar.png` has no dedicated crushed pose of its own (its four rows
are crawl/climb/eat/rest, see `IllustratedCaterpillarSprite`'s own doc
comment), so `CaterpillarMarker.crush()` reuses `SquashCrushEffect`'s
shared procedural fallback — flattens and tints whatever frame it was
already showing, lingers briefly, then frees — rather than the instant
`queue_free()` this section originally described. See "A real death
treatment for every small victim" further down for the full account
across all five victims.

**Bigger animals are excluded by which system a creature lives in, not by
a new per-species mass check on the VICTIM side** — there still is no
"how much can this creature's own body withstand" table for anyone
(worm, caterpillar, or otherwise; see `CreatureMass`'s own doc comment:
it is entirely the STEPPER's mass, never the steppee's). Sheep/wolf/deer/
etc. are `CreatureMarker` instances in the `"creature"` group, with their
own real health and combat stack — structurally a different tier from
both worms and caterpillars, and simply never scanned by either crush
call. The exclusion the request's own parenthetical asked for falls out
of scope (which sim/group a creature belongs to) rather than a size
threshold that would need its own tuning and its own test.

### Generalized past animals: mushrooms and walnuts (2026-09-06)

Reported directly: *"A mushroom is a physical entity and should have
mechanical und structural definitions like most entities and when you
walk over one it should be crushed because of the player weight. Same
for walnuts (crack open) excempt flowers."* `CrushMechanic.is_crushed_by`
itself needed no change at all (see its own doc comment: it was already
victim-agnostic from the start) — this is purely two more DETECTION
shapes, a third and fourth beyond the worm/caterpillar pair above, wired
into the identical `World._client_process` block (player's own momentum,
then every `CreatureMarker`'s own species-derived momentum).

- **`WildMushroomPatch.crush(cell, momentum_kg_m_s)`** — a real third
  shape, but one that fits the WORM'S pattern almost exactly (per-tile
  sim state, not a Node2D): mirrors `EarthwormPatch.crush` line for line
  (see `docs/concept/mushrooms.md`). `EarthChunkManager.
  crush_mushroom_at` mirrors `crush_worm_at`'s own three-step shape.
- **`EarthChunkManager.crush_walnut_near(pixel_position, momentum_kg_m_s)`**
  — the one genuinely NEW shape: a fallen walnut is a plain `DroppedItem`
  with no per-chunk sim and no dedicated marker class at all (unlike a
  worm, caterpillar, or mushroom). Detection scans `DroppedItem.
  GROUP_NAME` directly, filtered to a real walnut item stack, matched by
  exact tile (the same tile-exact-match `crush_caterpillars_near` already
  uses for a real Node2D). Cracking one destroys it outright — the same
  "gone, not transformed into a different item" outcome a crushed worm/
  caterpillar already gets; nothing in this project models a separate
  cracked-kernel item, and inventing one was out of scope for this pass.
- **No Karma penalty for either, originally** — a deliberate divergence
  from the worm/caterpillar wiring. Stepping on a worm or caterpillar
  ends an animal's life; a mushroom is a fungus and a walnut a seed,
  neither an animal, so `Karma.WORM_OR_CATERPILLAR_CRUSH_PENALTY` simply
  never applied to either new call.
  **Reversed for mushrooms only, same day:** asked directly, as part of
  "instant karma feedback" — a mushroom underfoot should cost Karma too.
  `crush_mushroom_at`'s bool return now feeds `Karma.
  WORM_OR_CATERPILLAR_CRUSH_PENALTY` the identical way every animal
  crush call does (see `docs/concept/mushrooms.md`'s own "Crushed
  underfoot" section and `karma_and_luck.md`'s event table). Walnuts are
  unaffected — a seed still is not a fungus or an animal, so
  `crush_walnut_near` stays exempt.
- **Flowers are excluded by construction, not a new check** — flowers are
  deliberately not `Node2D`s in any group at all (a bare `Sprite2D` per
  cell, no script -- see `EarthChunkManager._sync_flower_sprites`'s own
  doc comment), so there is nothing flower-shaped for either new crush
  call to sweep in; the request's "except flowers" needed no code of its
  own to honour.

### Mushroom corpses actually linger, and a bug's single bite (2026-09-06)

The user delivered real 1:1 crushed/bitten art for each specimen (see
`docs/concept/mushrooms.md`'s own "Crushed underfoot") — wiring the ART
LOADING side first (`IllustratedMushroomSprite.crushed_frame_for`/
`bitten_frame_for`) exposed that `crush_mushroom_at` froze the marker at
the exact moment it stopped fruiting, same as a picked mushroom — there
was nowhere for the new art to ever actually be seen. This closes that
gap, generalizing `EarthwormPatch`'s own `is_corpse`/`corpse_age_seconds`
"a corpse is new ground" precedent (see below) from one cause to two.

- **`WildMushroomPatch._corpse_kind: Dictionary`** (cell → `"crushed"` or
  `"bitten"`) replaces what would have been a plain `EarthwormPatch`-style
  bool: a mushroom corpse can arise from either `crush()` (now also
  recording `"crushed"`) or the new `bite()` (recording `"bitten"`) — two
  distinct causes needing two distinct sprites, unlike a worm's single
  death. Both ride the identical `_recovery`/`SPENT_SECONDS` clock,
  cleared there and nowhere else, exactly like the worm's own
  `_crushed`. `pick()` still leaves no corpse at all.
- **`WildMushroomPatch.bite(cell)`** — a decomposer's single bite (real
  fungivory, reported live: "a bug takes a bite"). No momentum/threshold
  gate, unlike `crush()`: an insect bite isn't a weight-emergent physics
  event, it simply happens once a decomposer commits to feeding. Otherwise
  mirrors `pick()`/`crush()`'s exact `has_fruiting` gate and recovery
  shape.
- **`MushroomRenderer.sync_markers`** now also treats every
  `sim.is_corpse(cell)` as live (mirrors
  `EarthChunkManager._sync_worm_sprites`'s own `is_corpse` check) instead
  of sourcing `live_cells` from `get_fruiting_cells()` alone — a corpse's
  marker survives the sync that would otherwise have freed it the instant
  `crush()`/`bite()` erased the cell from fruiting. `_build_marker` always
  bakes `sim.corpse_kind(cell)` into the marker it builds (a live cell
  simply gets `""` back), so both call sites (`spawn_markers` and
  `sync_markers`) pick the right art with no separate wiring.
- **`MushroomMarker.corpse_kind`** — set before `add_child`, same
  convention as `species_id`/`cell`. `_rebuild_sprite` prefers
  `crushed_frame_for`/`bitten_frame_for` when it matches and the species
  has that art yet, falling back to the ordinary live look otherwise (the
  same has-or-doesn't gate `has_variants` already uses) — a species still
  missing its crushed/bitten sheet (fly_agaric/psylo/parasol as of this
  delivery) never shows a blank texture, just its live look a beat longer.
- **Real fungivory, finally reachable**: `MushroomMarker` has joined
  `DroppedItem.FORAGEABLE_GROUP_NAME` since an earlier phase (see that
  class's own doc comment), but `DecomposerMarker._nearest_food`'s `not
  (node is DroppedItem) or node.item_stack == null` guard silently
  excluded it again immediately afterward — a `MushroomMarker` extends
  `Node2D`, not `DroppedItem`, so it always failed that check. Confirmed
  dead code path, not a hypothetical: a decomposer could never actually
  reach a mushroom at all before this fix, the earlier group-join
  notwithstanding. Fixed by only gating a *real* `DroppedItem` on having a
  real `item_stack`; anything else in this forageable group is judged on
  distance alone. `MushroomMarker.take_bite(_amount)` then duck-types
  straight into `_step_feeding`'s existing `has_method("take_bite")`
  branch, unchanged — it defers to `WildMushroomPatch.bite(cell)` and
  frees the (live) marker on a real bite, so `sync_markers` builds the
  actual corpse marker fresh from the sim's own `corpse_kind` on its next
  tick, the same "the sim is the truth, the marker just mirrors it" shape
  `pick_up` already uses. No-op on a marker that is already a corpse
  itself (mirrors `Carcass.take_bite`'s own gate shape) — a decomposer
  doesn't re-bite what something already finished.
- **What this does NOT include**: only one bitten-art stage exists today,
  by the user's own explicit choice ("for a later stage I will add more
  bitten stages but now 1 bite is enough") — so a single bite already
  reaches the only bitten look there is, and nothing yet models a bitten
  mushroom being progressively consumed further or fully removed by
  repeated bites. A bitten (or crushed) corpse clears exactly like an
  ordinary spent site once its `SPENT_SECONDS` recovery runs out.

**Correction, 2026-09-06, same day: the bite half of this was replaced by
a concurrent session's independent build of the same request, merged
second.** Two sessions built "a bug bites a mushroom" from the same
report at the same time; this section describes the first one merged.
The second modeled a bite as a genuinely different shape, not a second
corpse cause: "mushrooms with a bitten flag have less value; weigh less
and render... in world and inventory, their title reads as e.g. Parasol
(bitten)" requires a bitten mushroom to stay a real, pickable item — a
corpse that replaces the live marker and is never picked up cannot
satisfy that. See [mushrooms.md's "Bitten by a
decomposer"](mushrooms.md#bitten-by-a-decomposer) for what actually
shipped. Concretely, superseded by the second session's version:
`WildMushroomPatch._corpse_kind` no longer takes `"bitten"` as a value
(crush() is now its only writer); `bite(cell)` marks a new, orthogonal
`_bitten: Dictionary` instead, WITHOUT erasing the cell from `_fruiting`
-- the mushroom never stops being fruiting/pickable, so `is_corpse`/
`corpse_kind` never apply to it at all. `MushroomMarker.take_bite`
(the duck-typed `has_method("take_bite")` catch used above) is gone,
replaced by `take_mushroom_bite()` -- a distinct name so a bitten
mushroom does NOT duck-type into the Carcass branch, and so
`DecomposerMarker._nearest_food`'s gate can name it directly (see
carrion.md's own correction on the same fix). `MushroomMarker.bitten:
bool` (not `corpse_kind == "bitten"`) drives the bitten sprite/display-
name branches, and `pick_up()` resolves to a real `"<species>_bitten"`
catalog item (`MushroomBiting.gd`) rather than nothing (the marker was
never reachable by `pick_up` under the corpse model, since biting froze
and replaced it). The crushed half above is UNCHANGED and still exactly
as described.

### FPS regression round 3: AntForagerMarker never got SimulationLod (2026-09-07)

Reported directly: "Can you fix performance to get it back to 60fps?"
Diagnosed the same way rounds 1-2 were (see the fps-regression-
investigation-and-fixes memory this doc's own earlier entries reference):
a real `--solo` session, aggregate per-class timing, `set_process(false)`-
style bisection by class.

`AntForagerMarker` turned out to be the one creature marker in the whole
codebase with no `SimulationLod` throttling at all — every sibling
(`DecomposerMarker`, `MillipedeMarker`, `CreatureMarker`, `FishMarker`)
already has it, and this file's own top doc comment even claims it
mirrors `DecomposerMarker`'s wander, but the actual `_lod_step`/
`_nearest_player_position` machinery was simply never added. Confirmed
live: FPS collapsed to 3-5, with ~1000-1300ms of CPU spent per 3-second
window inside `_sense_food_nearby` alone (three separate 3x3-chunk
world-area scans — `leaf_litter_near`/`grass_seeds_near`/`fruit_near` —
called every single frame, no cache, no throttle), across roughly 1000
concurrently-scouting foragers. That population scale is not a
coincidence: three deliberate tuning commits in the prior ~24h
(`MAX_CONCURRENT_FORAGERS` 3→6→15 — see "A real food economy" above;
`FORAGE_RADIUS_TILES` 1.0→2.0 — see "Thriving ant colonies" above;
scout/resolver WAVES instead of one-at-a-time dispatch — see "Cluster
recruitment" above) each independently raised the realistic standing
population and/or each forager's own unthrottled scouting lifetime,
compounding on top of a gap that had been silently there since this
marker was first built.

Two real fixes:

- **`_lod_step`/`_nearest_player_position`**, mirroring `MillipedeMarker`'s
  own implementation exactly (distance-based update coalescing — far-
  from-the-player foragers advance in fewer, larger steps; time is
  accumulated across skipped frames, never lost).
- **A new, dedicated `SENSE_INTERVAL_SECONDS` (0.2s) throttle on
  `_sense_food_nearby` specifically**, independent of the LOD gate above:
  even a full-rate (near-player) scout doesn't need to re-run three
  separate world-area scans every single frame at its own ~4.2px/s
  walking speed (`WALK_SPEED * SCOUT_SPEED_FRACTION`). The very first
  scouting step still senses immediately (`_sense_accumulator` starts
  already at the interval, not at zero) — only REPEATED re-checks are
  throttled — so no existing test needed to change at all.

Alongside this, a real, actively-firing crash was found straight from
the investigation's own session log: "Invalid access to property or key
'position' on a base object of type 'previously freed'" at
`EarthChunkManager.crush_ants_near`, on every single frame.
`_active_ant_foragers` is only pruned LAZILY, at the next
`_dispatch_forager` call (see that function's own doc comment) — a
forager that already completed its round trip and `queue_free()`'d
itself naturally could sit in the array as a stale, by-then-actually-
freed reference for a while, and `crush_ants_near` accessed
`marker.position` on every entry with no validity check at all. Fixed
with the identical `is_instance_valid(marker) or marker.is_queued_for_
deletion()` guard `_dispatch_forager`'s own pruning already used —
applied defensively to the shared `_crush_markers_near` caterpillar/
millipede/decomposer helper too, since it has the identical shape and
the same latent risk even though it hasn't been observed crashing yet.

**`PiscivoreBirdMarker` had the identical missing-LOD gap**, found
alongside the above (see `ecosystem_dynamics.md`'s "fish-eating birds"):
`nearest_fish_position` scans every loaded chunk's fish, completely
unscoped, with no throttle at all. A smaller-population contributor
than the ant swarm (at most one kingfisher per water chunk), but real —
fixed with the same `_lod_step` pattern.

**Honest result, not fully resolved**: measured before/after, `ant_
forager`'s own per-3-second-window cost dropped roughly 3x and FPS
roughly doubled (3-5 → 5-10) immediately after these fixes — real,
confirmed progress. But a longer `--solo` session (~2 minutes total)
showed FPS drifting back down again (to 5-7), with `ambient_flyer`'s own
per-call cost climbing over time even though its own live instance/call
count stayed exactly flat across that stretch — a differently-shaped
problem from either fix above (not a missing throttle; some per-call
cost creeping up the longer a session runs), not yet root-caused.
`ant_mound`'s own call count staying perfectly flat across that same
stretch rules out unbounded mound budding as the immediate driver of
THIS specific trend — but `_maybe_bud_ant_colony` having no upper bound
on mound count at all (only the initial seed is capped by `MAX_MOUNDS`)
remains a real, separate, undiscovered-extent gap worth a dedicated look
later.

### FPS regression round 4: two unscoped whole-world scans (2026-09-07)

Reported live, again, hours after round 3 shipped: "it still has only
4fps after a clean reboot and restart which should have 30-60fps," on the
user's own real, long-lived save (screenshot showed unusually dense leaf
litter — "more than any other screenshot in this project's history" —
plus two healthy Ant Mounds). The live hypothesis going in, offered
explicitly as unverified: that dense litter meant `LeafLitterField`
queries scale badly against a genuinely large accumulated leaf count,
paid repeatedly by every forager/decomposer/caterpillar/millipede in
range.

**Reproduced against the user's own real save, not a fresh one.** Godot
has no `--user-data-dir` isolation concern once accounted for: worktrees
and the main checkout already share one real `user://` (see the
`godot-tests-share-user-data-dir-across-worktrees` session note), but the
user's own game was still actively running at investigation time, so
reusing it live risked a second writer corrupting the save mid-session.
Fix: `--user-data-dir <path>` (a real Godot engine flag, not a project
one) pointed at a snapshot **copy** of the live `user://` directory
instead — same real accumulated state (mound populations, explored chunk
history), zero risk to the user's own session. Re-copied fresh from the
live save for each `--solo` run so before/after started from the same
real conditions.

**The leaf-litter hypothesis was refuted at the timescale that matters,
confirmed real at a longer one.** `LeafLitterField` is never persisted
across a save/load (`_leaf_litter_fields[chunk_coord] = LeafLitterField.
new()` at chunk load — see `EarthChunkManager`'s own doc comment) —
purely runtime state, rebuilt from empty every session regardless of how
dense the litter was when the screenshot was taken. A round-4 `PerfProbe`
(same aggregate-per-class-timing shape as round 2/3's own, reconstructed
fresh — the original `perf_probe.gd` was never committed) confirmed this
directly: `leaf_litter.total_leaves_world` sat at **0 for the first ~3
minutes** of a fresh `--solo` session on the exact same save, and every
leaf-litter-related cost (`step_leaf_litter`/`field_advance`/
`renderer_fill`/the three `_near` queries) summed to under 150ms of a
~3000ms window throughout — real, but nowhere near dominant. **The
dominant costs were two separate unscoped whole-world scans, unrelated to
leaf litter**, below.

Left running ~19 minutes on the *pre-fix* code, `total_leaves_world` did
climb from 0 to 2,361, and `step_leaf_litter`'s own cost climbed with it
(pushed 20ms→578ms per window; `field_advance` 20ms→420ms;
`renderer_fill` 9ms→150ms) — so the original hypothesis was right about
mechanism, wrong about timescale: on the user's *actual* long-played save
(hours, not minutes) this is a real and growing cost, just not the one
that explains a 4fps reading in the first few minutes of any given
session. Root cause (not yet fixed, see below): `LeafLitterRenderer.fill`
unconditionally rebuilds a chunk's *entire* MultiMesh buffer — two engine
calls per leaf, plus a fresh instance-dictionary allocation per leaf via
`instances_for_leaves` — every single frame, for every decorating chunk,
regardless of whether anything about that chunk's leaves actually changed
since the last frame. The vertex shader alone drives all visible
motion/sway once a leaf is pushed, so a long-settled, non-transitioning
leaf never needed re-pushing at all.

**Root cause 1 (the single largest cost): `AmbientFlyerMarker.
_scan_for_partners` walked `get_tree().get_nodes_in_group(FLOCK_GROUP)` —
every flyer in the whole loaded world — on every partner search.** This
*is* round 3's own flagged-but-unexplained "ambient_flyer's own per-call
cost climbing over time... not yet root-caused" anomaly, now closed: a
`PARTNER_SEARCH_INTERVAL` cooldown throttles *how often* any one flyer
scans, but not *what it scans* — each scan still walked the entire
population. Measured: `ambient_flyer._process` 700-730ms per ~3s window
pre-fix, the single largest tracked cost, against a population in the
thousands. Fixed with a new `EarthChunkManager.flyers_near` (mirrors
`leaf_litter_near`'s own 3x3-chunk-neighbourhood scan exactly, reading
the existing `_loaded_ambient_flyers` per-chunk buckets — no new
bookkeeping needed), queried at `SpiralFlight.NOTICE_RADIUS_PX` — test-
pinned as the widest of the three interaction radii, so it can never miss
a candidate any of the three narrower per-candidate checks would have
accepted. Falls back to the old unscoped walk when no `courtship_world`
is wired (a standalone marker built directly in a test), preserving
existing behaviour there exactly.

**Root cause 2: `EarthChunkManager.crush_ants_near` walked every key in
`_active_ant_foragers` — every mound with an active forager anywhere in
the whole loaded world — for every single creature's crush check, every
frame.** Unlike every sibling "near" query in this file (leaf litter,
worms, seeds, `_crush_markers_near` itself), which all scope to the 3x3
chunk neighbourhood around the query position, `crush_ants_near`'s own
doc comment had always flagged it as the one exception ("cannot share
`_crush_markers_near`'s own chunk-keyed lookup directly"). A forager can
only ever wander `AntColony.FORAGE_RADIUS_TILES` (2.0) from its own
mound — far inside a single `CHUNK_SIZE`=32 chunk — so nothing was ever
actually gained by scanning further. Measured: `crush.creature_loop`
(the whole per-frame crush pass, called once per `CreatureMarker`)
440-452ms per window from only 14-18 frames (25-31ms per frame). Fixed
by skipping every mound key outside the 3x3 chunk neighbourhood around
the crush position (one cheap `Vector2i` comparison per mound) before
paying for `markers.duplicate()` plus a full inner scan of that mound's
forager list.

**A live worry checked and laid to rest**: with `crush.creature_loop`
still costing something non-trivial even after fix 2, the next suspect
was round 3's own other flagged-but-undiscovered-extent gap —
`_maybe_bud_ant_colony` having no upper bound on mound count at all. A
temporary follow-up gauge (`ant_colony.mound_count`/
`active_forager_keys`/`active_forager_total`, removed with the rest of
the round-4 `PerfProbe` instrumentation) measured a **bounded, reasonable
~30 mounds and ~600-740 active foragers** at steady state on this real
save — not runaway growth. The unbounded-mound-count gap is still real
and still worth closing on its own terms eventually, but it is NOT what
was driving round 4's regression, and the remaining `crush.creature_loop`
cost at that population scale (now genuinely just "iterate ~30 mounds
plus scan the handful actually nearby, times however many creatures are
on screen, every frame") is in the range every other correctly-scoped
system in this file already operates at.

**Both fixed with real growth-rate/complexity-bound tests, not timing**
(`CLAUDE.md`'s own rule against eyeballed thresholds; timing assertions
are also just flaky): `test_crushing_an_ant_never_scans_a_mounds_
forager_list_in_a_distant_chunk` and `test_flyers_near_never_reaches_a_
distant_chunk_regardless_of_radius` each plant a mound/flyer many chunks
away and prove it is never visited/pruned/returned regardless of query
radius — the same call-observing idiom `test_earth_chunk_manager.gd`'s
own `_CountingPhaseGenerator` already established for "an expensive call
never happens." `test_scan_for_partners_pairs_using_only_what_flyers_
near_returns`/`_does_not_fall_back_to_the_whole_tree_group` pin the
`AmbientFlyerMarker` wiring itself the same way, with a counting
`courtship_world` test double.

**Measured before/after, live, on the identical real save** (fresh
`--user-data-dir` snapshot each side, same `--solo` methodology, steady-
state ~3-minute mark): total tracked per-window cost dropped from
**~1900ms of a ~3040ms window (~62%) to ~1120ms of a ~3030ms window
(~37%)** — measured at a HIGHER population on the after side (ant_forager
~11800→~23400 calls/window, ambient_flyer ~6000-8000→~12100-16200,
caterpillar/decomposer/millipede all roughly doubled too), so the real
per-unit-of-work improvement is understated by that raw comparison, not
overstated. Frame-processing rate (crush-pass calls per window, a direct
frame-count proxy) went from **14-18 frames per ~3s window (~5fps) to
36-37 (~12fps)** — roughly 2.2-2.6x, at higher load. Raw CPU-time/wall-
clock ratio stayed pegged near 100% on both sides (0.998 before, 0.982
after) — expected and not a contradiction: the process is still fully
CPU-bound either way, the fix means more USEFUL frames get processed
within that same saturated core, not that the core stops being
saturated. **Not a full return to 30-60fps** — see the two open items
below.

**Real, confirmed, explicitly out of scope for this round:**

- **Leaf litter's per-frame render/advance cost, growing with real
  session length** (see above) — a dirty-tracking or throttled-refill
  mechanism for `LeafLitterRenderer.fill`, careful not to reintroduce the
  "hides the fall animation behind a sync lag" problem the original
  `step_leaf_litter` doc comment explicitly designed around. Real,
  measured, growing — just not yet fixed. **Closed 2026-09-07, see "Leaf
  litter dirty-tracking" below.**
- **Sheer, bounded-but-large population scale.** `ant_forager` alone
  plateaued around 600-740 concurrent foragers across ~30 mounds on this
  save, `ambient_flyer` in the low thousands, caterpillar/millipede/
  decomposer each in the hundreds-to-low-thousands — all now correctly
  scoped and throttled, but still enough live instances that their
  summed *per-instance* cost is real. Whether these population targets
  are the right density for the intended experience is a design/tuning
  question, not a bug this round touched.
- **The unbounded ant-mound-budding gap itself** (`_maybe_bud_ant_colony`
  has no upper bound on mound count) — confirmed NOT the round-4 driver
  (mound count measured bounded at ~30 on this real save), but still an
  open, undiscovered-extent gap on its own terms.

### Leaf litter dirty-tracking: closing round 4's own deferred item (2026-09-07)

Round 4 (above) named this explicitly rather than fixing it: `EarthChunkManager.step_leaf_litter` called `LeafLitterRenderer.fill`
unconditionally every frame, for every chunk currently in decoration
range — rebuilding that chunk's *entire* MultiMesh instance buffer (two
engine calls per leaf via `MultiMesh.set_instance_transform_2d`/
`set_instance_custom_data`, plus a fresh instance-dictionary allocation
per leaf via `instances_for_leaves`) even for leaves that are fully
settled and not transitioning at all. `LeafLitterRenderer`'s own vertex
shader drives all visible fall/sway motion once a leaf's data has been
pushed once (see that file's own doc comment) — a long-settled leaf's
CPU-side data never actually needed re-pushing every frame, only when the
chunk's leaf *set* changes.

**Root cause confirmed, not just theorized.** Reproduced with the same
`--user-data-dir` snapshot-copy technique round 4 established (a private
copy of the user's own real save, `--solo --rendering-driver opengl3`,
never the live directory while a real session might be using it — see
round 4's own methodology note above): left running on the *pre-fix*
code, `leaf_litter.total_leaves_world` climbed 0 → 2,361 over ~19 real
minutes, and `step_leaf_litter`'s own per-window cost climbed with it
(~20ms → ~578ms; `field_advance` ~20ms → ~420ms; `renderer_fill` ~9ms →
~150ms) — real, and invisible to a short session because leaf litter is
never persisted across save/load (a fresh session always starts at 0
leaves, so this cost keeps resetting and re-growing rather than
accumulating across sessions the way a persisted population would).

**The fix: a generation counter, not a periodic throttle.**
`LeafLitterField.generation()` (`src/world/leaf_litter_field.gd`) is a
plain incrementing counter, bumped only when something about the field's
own *rendering-relevant* state actually changes — a leaf added, removed,
relocated, or dispersed (only on the branch that actually found and moved
a leaf; a miss changes nothing and must not look dirty), a settled leaf's
throttled wind-roll nudge, or a decay-tier transition (only on the frame
`season` actually changes value, not every subsequent frame the leaf
merely remains in that tier). `EarthChunkManager` tracks the generation it
last actually pushed per chunk (`_leaf_litter_filled_generation`) and
`step_leaf_litter` now only calls `fill` again once that value changes.
Deliberately **not** a periodic throttle (a `GRASS_REFRESH_INTERVAL`-style
multi-second cadence): `step_leaf_litter`'s own doc comment already
explicitly rejects that for this exact call site — a leaf's whole fall is
over in under a second (`LeafLitterField.TRANSITION_DURATION`), so *any*
sync lag here would hide the fall animation entirely, not just delay it
the way a slow-growing flower can tolerate. A chunk that IS changing still
refills the very same frame it changes, exactly as before this fix — only
a genuinely idle chunk's litter stops paying the rebuild cost.

**Two correctness subtleties the naive bump-point list misses, caught by
reasoning through the renderer's own doc comments rather than assumed
away, and each pinned by its own test:**

1. **A leaf currently `on_water` must always look dirty.** Every other
   leaf's fall/sway motion is driven entirely by the vertex shader once
   its data is pushed once — but a *floating* leaf is the one deliberate
   exception: `_advance_floating_leaf`'s own doc comment explains that its
   continuous downstream drift is computed on the CPU side, every single
   frame, with `transition_from` deliberately kept equal to `position` so
   the shader's own eased-transition offset stays at zero throughout (an
   uncorrected eased transition would show the leaf perpetually chasing a
   target that keeps moving away from it rather than gliding). A
   dirty-tracking scheme that only bumped on the discrete trigger list
   above would silently freeze a floating leaf in place the moment its
   chunk otherwise went idle, exactly the "hides real motion behind a sync
   gap" failure mode this whole fix exists to avoid. `advance()` now bumps
   the generation on every call for any leaf currently on water, so a
   floating leaf's chunk is refilled every frame it drifts, same as
   before this fix.
2. **The CPU-side transition-settle snap must itself be pushed once.**
   `transition_from`'s own doc comment explains why `advance()` snaps a
   completed transition's `transition_from` to exactly equal `position`
   once `TRANSITION_DURATION` elapses: `LeafLitterRenderer`'s packed
   `transition_start` is a *wrapped* fraction (`WRAP_PERIOD`-periodic, not
   a raw growing timestamp — see that file's own doc comment on why an
   8-bit-quantized packed clock has to wrap), and a long-completed
   transition's stale, un-snapped, nonzero packed offset could alias back
   to "just starting" once the wrapped clock eventually laps it, snapping
   the leaf visibly back to an old offset. The snap is what makes that
   structurally impossible — but only if the renderer actually *receives*
   the snapped (zero-offset) data. A dirty-tracking scheme that treated
   the settle snap as a no-op change would leave the stale, pre-snap data
   sitting in the MultiMesh forever once nothing else about that leaf ever
   changes again, silently reintroducing the exact aliasing bug the snap
   exists to prevent. The settle snap now bumps the generation too, so it
   gets pushed exactly once, after which the leaf never needs re-pushing
   again.

**Strict TDD**, mirroring round 4's own `test_crushing_an_ant_never_
scans_a_mounds_forager_list_in_a_distant_chunk`/`test_flyers_near_never_
reaches_a_distant_chunk_regardless_of_radius` call-observing idiom: a new
`_CountingLeafLitterRenderer` test double (matching `test_world_boss_
fitness.gd`'s own `_CountingPhaseGenerator` convention — count calls,
delegate to the real implementation via `super`) proves
`test_step_leaf_litter_does_not_refill_a_chunk_whose_leaves_have_not_
changed`: `fill` is called exactly once for a chunk across three
consecutive idle steps, not growing with elapsed step count, alongside
`test_step_leaf_litter_refills_a_chunk_once_a_new_leaf_actually_falls`
proving this is real dirty-tracking rather than an accidental throttle
that would also (wrongly) delay a fresh leaf's own fall. 16 further
`LeafLitterField`-level tests pin `generation()` itself: starts at 0;
bumps on every documented trigger, including the two subtleties above;
does *not* bump on a miss (consume/relocate/disperse finding nothing),
dead calm, an ordinary idle `advance()` call, or re-asserting a decay tier
the leaf is already in. All new tests confirmed red before implementation
(a parse-time "cannot infer type" error from calling a `generation()`
method that did not yet exist — GDScript's static `:=` inference makes an
undefined-method call fail the whole script's parse, not just the
assertion, which is itself a legitimate red for "the method doesn't exist
yet"), green after.

**Measured live, on the identical real save** (fresh `--user-data-dir`
snapshot, same `--solo --rendering-driver opengl3` methodology as round
4's own measurement above, ~21-minute run): `step_leaf_litter`'s own
per-window cost climbed from ~22ms (37 leaves) to a peak of ~650ms (1,183
leaves) over the first ~14 real minutes — then, unlike round 4's own
still-climbing trend, **plateaued** at ~525–650ms for the remaining ~7
minutes of the run even as `total_leaves_world` kept climbing a further
35%, from 1,183 to 1,596. That plateau is the fix's real structural
signature: cost is now bounded by how much litter is *currently changing*,
not by how much has *ever accumulated* — confirmed directly by
`refilled_chunks_this_step`, which read exactly 2 (of 9 decorating chunks)
for 417 of 430 measured windows across the whole run, i.e. 7 of 9
decorating chunks correctly paid zero refill cost for nearly the entire
session, regardless of how large `total_leaves_world` grew.

Absolute millisecond figures are **not** directly comparable ms-for-ms to
round 4's own numbers — this machine routinely runs many concurrent Claude
Code/Godot sessions at once (confirmed active during this very
measurement: `git worktree list` showed a dozen-plus other live
worktrees), and CPU contention alone can swing wall-clock timing
independent of any code change. The *qualitative shape* — bounded vs.
unbounded growth over time — is the meaningful signal here, not the
literal ms values, which is why the comparison above is framed as a
plateau against this run's own earlier climb rather than a subtraction
against round 4's differently-contended session.

**A real, honest, separate finding, not previously named.** The 2 chunks
that never stopped refilling did so on very nearly every single frame
throughout the run — the deterministic signature of at least one leaf
currently `on_water` in each (the only *unconditional*, every-`advance()`-
call generation bump this fix adds — see "Two correctness subtleties"
above), almost certainly a river or river-mouth plume within this save's
own spawn area. A chunk with genuinely ongoing floating-leaf activity
still pays a real, per-frame cost proportional to *its own* active
population — this is correct, not a bug (a leaf actually drifting
downstream must be redrawn every frame to look right, per this fix's own
`test_a_floating_leaf_bumps_the_generation_every_advance_even_with_
nothing_else_changing`) — and it is architecturally unavoidable at this
fix's per-**chunk** (not per-leaf) granularity: `LeafLitterRenderer.fill`
still rebuilds a chunk's *entire* buffer at once, so one actively-drifting
leaf costs as much as rebuilding every other, otherwise-idle leaf sharing
its chunk. A genuinely idle chunk — the literal round-4 finding — now
costs correctly close to nothing, proven both by this plateau and by the
`refilled_chunks_this_step` count above; a chunk that keeps changing does
not, and structurally cannot without a finer-grained (per-leaf
incremental) rendering update, which this fix does not attempt — real,
worth a future look if it is ever found to matter at ordinary play scale
(a played session's decoration range moves with the player rather than
sitting fixed on one spot for 20+ minutes the way this `--solo` methodology
does, so this specific cost may matter far less in practice than this
worst-case stationary measurement suggests), but out of scope here, which
stayed deliberately scoped to exactly the dirty-tracking mechanism asked
for.


### Floating-leaf cost at ordinary play scale: confirmed real, bounded with a waterlog-and-sink duration (2026-09-07)

The entry above left an explicit open question: does the floating-leaf
full-chunk-rebuild cost actually matter once decoration range moves with
the player, rather than sitting fixed near one river for 20+ minutes the
way that measurement's stationary `--solo` spawn point did? Investigated
directly rather than left as the "may matter far less in practice"
speculation above — **the speculation does not hold up.**

**Methodology: a `--solo` session that actually wanders, not a script that
reasons about one.** `scenes/world.gd`'s `--solo` gate was extended
(temporarily — never committed, reverted before this fix landed) with a
`--wander` flag: a watchdog re-picks a random heading via
`Input.action_press`/`action_release` (the same synthesized-input path a
real keyboard drives) roughly every 5 real seconds, or immediately if the
character's own position has stalled (walked into water/terrain) — a
self-correcting autopilot, not a scripted route, so it explores organically
rather than along a route chosen to prove a point either way. Run against
the SAME `--user-data-dir` real-save-snapshot methodology the entries above
already establish, with temporary instrumentation splitting
`step_leaf_litter`'s own cost into its two real components
(`LeafLitterField.advance()` vs `LeafLitterRenderer.fill()`) per 3-second
window, alongside decorating/"hot" (has ≥1 `on_water` leaf) chunk counts.

**Result: wandering does not reliably move decoration range away from
water — if anything, the opposite.** Rivers act as natural walking
corridors (water blocks/slows crossing, so the watchdog's own stall-
detection selects FOR headings that run alongside a riverbank over headings
that walk into one) — the same reason a real player tends to follow a
shoreline rather than repeatedly wade across it. Across a ~27-real-minute
session (534 measured windows): **at least one decorating chunk had a
floating leaf in 92.7% of windows** (39 of 534 read zero), with the
hot-chunk count itself frequently EXCEEDING the stationary baseline's own
steady 2-of-9 — modal value 3, a majority of windows at 2 or more, briefly
reaching all 9 decorating chunks simultaneously. Combined `advance()` +
`fill()` cost, once total world leaf population reached a scale comparable
to the stationary baseline's own 2,361-leaf endpoint (~2,150-2,220 leaves,
reached here over the longer, more realistic ~27-minute wander rather than
~19 stationary minutes — old chunks unloading as the player moves away
resets their own litter, per this doc's own "not persisted" scope note, so
a wandering session's total population grows more slowly but does still
reach a comparable magnitude), repeatedly read 400-490ms/window — squarely
comparable to the stationary plateau's own ~525-650ms, not the "far less in
practice" this doc's own prior entry hoped for. (One window read
1,196.5ms, well above either figure; treated as likely contention-inflated
per this doc's own established shared-machine caveat rather than a load-
bearing data point, since the surrounding windows already make the case on
their own.)

**A second, separate, previously-unattributed finding: `LeafLitterField.
advance()` — not `LeafLitterRenderer.fill()` — is consistently the LARGER
of the two cost components, roughly 2-4x fill's own share, in BOTH the
stationary and wandering measurements.** The round-4 entry's own numbers
already showed this (`field_advance` ~20ms→~420ms vs `renderer_fill`
~9ms→~150ms) without naming it explicitly. `advance()` runs once per
LOADED chunk every frame (measured here: up to 36 loaded against only 9
ever decorating) regardless of visibility — the dirty-tracking fix above
only ever gated `fill()`, never touched this loop at all, so a chunk's own
per-leaf aging/decay/prune cost keeps paying in full for every chunk kept
in memory for continuity, whether the player can see it or not. This is a
real, structurally distinct, still entirely open cost — named here rather
than silently folded into "the floating-leaf problem" it is easy to
conflate with, and explicitly NOT fixed by the change below (which bounds
on_water's own extra per-leaf cost and always-dirty behaviour, but does
nothing for the baseline per-leaf loop cost every loaded leaf pays
regardless of on_water status).

**The fix: a floating leaf waterlogs and sinks, the same real mechanism
that keeps a real stream's litter from drifting forever.** A freshly
fallen dry leaf floats at first on trapped air and its own waxy cuticle,
but progressively absorbs water through its cut petiole and stomata (the
"leaf conditioning"/leaching process stream ecology studies document) and
loses buoyancy within roughly a day of continuous immersion — the real
reason a stream's floating litter settles into a benthic "leaf pack"
rather than drifting indefinitely, and the specific real-world-groundable
question `leaf_litter.md`'s own "Floating on water" section left
unaddressed. `LeafLitterField.MAX_FLOAT_SECONDS` (one real-world day,
translated through the same real-year → compressed-game-time ratio
`LIFETIME` already uses) bounds how long any ONE leaf can keep forcing its
own chunk to look dirty every frame: `_advance_floating_leaf` now checks
`now - floating_since >= MAX_FLOAT_SECONDS` first, before any current
probing, and — if crossed — settles the leaf in place and flips `on_water`
false, exactly like the pre-existing "current dried up" sink path. A new
per-leaf `floating_since` field (set whenever `on_water` transitions
false→true at any of the four sites that can cause it — `add_leaf`,
`relocate_leaf_near`, `try_disperse_near`, `advance`'s own wind-roll —
deliberately left UNTOUCHED when an already-floating leaf is nudged to
another spot still on water, since a lateral nudge mid-water does not
un-waterlog it) tracks each floating episode's own real start, never a
stale value from a prior episode. A sunk leaf is not banned from floating
again — a genuine later current encounter starts a fresh clock and resumes
the same "always dirty while floating" contract, unchanged.

This does not, and is not intended to, fully close the gap measured above:
it bounds any SINGLE leaf's own worst-case floating duration (and the
`_advance_floating_leaf`-specific per-frame probe/drift cost that comes
with it), but a chunk with continuous new leaf-fall landing on the same
stretch of river can still have SOME leaf on_water at nearly any given
moment, and the `advance()` baseline-cost finding above is untouched
entirely. Both are named, explicit, deliberately out-of-scope follow-ups —
this fix stayed scoped to exactly the mechanism its own investigation
named: bounding an individual leaf's unbounded floating window.

**Strict TDD**: 7 new tests in `test_leaf_litter_field.gd` (confirmed red
first — a parse-time "cannot find member MAX_FLOAT_SECONDS" error, the
same legitimate whole-script-parse-failure red the round-4 fix's own tests
hit for an undefined `generation()` call) — the constant's own real-world-
grounded pinning, floating-before/after-the-threshold behaviour, the sink
frame's own settle-in-place contract, the post-sink "stops looking dirty
every frame" payoff (the actual point of this fix), and the
reset-vs-fresh-clock distinction across all three relocation call sites
(mid-water nudge keeps the original clock; a genuinely new floating episode
via relocation, dispersal, or the wind-roll each start a fresh one). All 82
tests in that file green after (75 pre-existing + 7 new), alongside
`test_leaf_litter_renderer.gd` (42/42, untouched) and `test_earth_chunk_
### FPS regression round 5: decomposer's own unscoped whole-world scan (2026-09-07)

Reported live, again, after rounds 1-4 above had all already shipped:
"es ist immer noch bei 4-10 fps ... wir brauchen 60+ da war es auch
schon" (still 4-10fps, need 60+, it was already like that before).
Investigated the same way rounds 3-4 established: a real
`--user-data-dir` snapshot of the user's own live save (never the live
save itself — it was actively in use), `--solo`, round 4's own
`PerfProbe` instrumentation temporarily re-applied (`git revert` of its
own removal commit, one conflict resolved to keep the leaf-litter
dirty-tracking fix's fill-gate intact) and EXTENDED with whole-frame
gauges this investigation hadn't needed before — `Engine.get_frames_
per_second`, `Performance.TIME_PROCESS`/`TIME_PHYSICS_PROCESS`,
`RENDER_TOTAL_DRAW_CALLS_IN_FRAME`/`RENDER_TOTAL_PRIMITIVES_IN_FRAME`,
`PHYSICS_2D_ACTIVE_OBJECTS`/`PHYSICS_2D_COLLISION_PAIRS`,
`OBJECT_COUNT`/`OBJECT_NODE_COUNT` — specifically to rule rendering and
the physics server's own internal step in or out before assuming the
cost was script-side again.

**Rendering and physics were ruled out directly, not assumed.** At
steady state (all 30 chunks loaded, ~20,000 nodes, ~50,000 objects):
draw calls held flat at 149-154, primitives at 8244-8254,
`PHYSICS_2D_ACTIVE_OBJECTS` at 1 and `PHYSICS_2D_COLLISION_PAIRS` at 0
throughout — none of the three scaled with population or spiked
alongside the frame-time spikes below, ruling both out as the dominant
cost this round.

**Root cause: `DecomposerMarker._nearest_food`'s own `Carcass`/
`CarcassGuts`/`DroppedItem.FORAGEABLE_GROUP_NAME` walk ran every single
frame for every decomposer still searching, not once.**
`CarrionForageBehavior.can_commit()` stays true on every frame past
`REHUNT_SECONDS` until a target is actually found — so `_step_seeking`'s
own `if _behavior.can_commit(): _nearest_food()` re-ran the FULL
unscoped `get_tree().get_nodes_in_group(...)` walk continuously for as
long as a decomposer had nothing nearby to eat. This is the identical
"one marker scans the whole world instead of a scoped neighbourhood"
anti-pattern round 4 above already found and fixed twice
(`AmbientFlyerMarker._scan_for_partners`, `EarthChunkManager.
crush_ants_near`) — a third, previously-undiscovered instance of the
same shape, missed by round 4 because it lives in an UNTHROTTLED search
trigger rather than a fourth unscoped scan of a new kind.

Measured directly: `decomposer._process` spiked to 1500-7800ms per ~3s
window (against a measured 0.15-0.25ms/call baseline at the SAME
population — 645-900 live decomposers, confirmed via a `count_instance`
gauge), erratic and population-DEcorrelated window to window — the
signature of "however many decomposers happen to be stuck searching
this particular frame", not a smooth cost that scales with total
decomposer count the way a real O(n) bug would.

**Fixed with a shared, class-level cache, not full per-chunk spatial
bucketing.** The three group lists are refetched at most once per
`FOOD_GROUP_REFRESH_SECONDS` (0.5s) of real wall-clock time (`Time.
get_ticks_msec`, injected for testability rather than read directly),
shared across every decomposer instance via a `static var` — not each of
potentially hundreds of them independently re-fetching the identical
whole-world lists. A pure PER-INSTANCE throttle (mirroring
`AmbientFlyerMarker.WORM_SNIFF_INTERVAL`) was considered and rejected:
at the very low frame rates this was actually reported at, one single
frame's own delta can already exceed a half-second interval, so a
per-instance cooldown checked once per frame barely suppresses anything
in exactly the condition that matters most — sharing the fetch across
every instance is what actually bounds the cost regardless of frame
rate. Full per-chunk bucketing, the shape round 4's own `flyers_near`/
`leaf_litter_near`/`trees_near` all use, was also considered and
explicitly NOT chosen: those all reuse an EXISTING per-chunk registry
`EarthChunkManager` already maintained for spawn/despawn tracking, but
`Carcass`/`CarcassGuts`/`DroppedItem`(fruit)/`MushroomMarker` spawn from
five separate, scattered call sites (creature death, player drops,
world events, the mushroom renderer's own per-chunk spawn) with no such
registry to reuse — building one from scratch is a materially larger,
riskier change than this fix, named here explicitly as a real,
smaller-scoped choice rather than silently passed off as the full
round-4-style treatment. A genuine follow-up, not ruled out, just not
this round's fix.

Cached entries are re-validated with `is_instance_valid`/`is_queued_
for_deletion` at read time — a live `get_nodes_in_group` call never
needed this (it only ever returns currently-valid nodes), but a cached
snapshot up to 0.5s stale can now hold an already-freed reference.

**Strict TDD**, mirroring round 4's own call-observing test-double idiom
(`test_earth_chunk_manager.gd`'s `_CountingPhaseGenerator`, `test_
ambient_flyer_marker.gd`'s `_CountingFlyerWorld`): a `_CountingTree`
stub standing in for the `SceneTree` proves one shared fetch serves 50
calls within the refresh window and a second real fetch only happens
once the window has genuinely elapsed — a real call count, not a timing
assertion (`CLAUDE.md`'s own rule against eyeballed thresholds, which
timing assertions always are). `test_still_finds_real_carrion_through_
the_shared_cache` is the end-to-end regression guard that the refactor
did not silently break real carrion-finding. 36/36 green in `test_
decomposer_marker.gd`.

**Real, confirmed, explicitly out of scope for this round**: the
materially larger per-chunk-bucketing alternative considered and
rejected above remains a real, cleaner long-term fix if the shared-cache
approach's own residual per-decomposer distance-check loop (still
O(cached group size) per decomposer, just no longer O(world) per
decomposer PER FRAME) ever becomes the next bottleneck at a larger
foragable-item population than this investigation measured against.


## Illustrated worm sprite: crawl, emerge, retreat, die

A real, hand-illustrated sheet (`assets/sprites/animals/worm.png`) replaces
`ProceduralWormSprite`'s drawn silhouette and the region-rect emergence
"reveal" trick described above with four real, separately-drawn animations
— the same "hand-drawn sheet, real illustrated art" upgrade this project
has already given ants, carrion bugs, sheep, wolves, and every songbird
(`IllustratedDecomposerSprite`/`IllustratedAnimalSprite`/
`IllustratedBirdSprite`). This is also the direct follow-up "Crushed
underfoot" named and deferred: the worm's fourth animation is its death,
and closing it required inventing a genuinely new piece of state this
codebase did not have anywhere yet (see "A corpse is new ground" below).

### The sheet

1536×1024px, a perfectly regular 8-column × 4-row grid (192×256px per
cell — 1536/8 and 1024/4 both exact), chroma-keyed opaque magenta
background like every prior illustrated-animal sheet. Four rows, each one
full named animation, top to bottom exactly as drawn:

1. **`crawl`** — ordinary ambient locomotion. A steady 8-frame loop, played
   whenever a worm is fully surfaced and not actively transitioning —
   replaces the old sub-tile `crawl_offset` wobble's total silence about
   the worm's own body motion (that wobble still applies to the sprite's
   *position*; this is what it now plays while wobbling).
2. **`emerge`** ("crawl out of earth") — a worm surfacing, drawn as a real
   growth: frame 0 is barely a nose above a bare patch of turned soil,
   frame 7 is the whole body out and lying flat. Plays while surfacing is
   *rising* (see "Direction, not just amount" below).
3. **`retreat`** ("crawl into earth") — the mirror image, but drawn as its
   own sequence rather than `emerge` played backward: frame 0 is a worm
   lying flat beginning to dip its head into loosened soil, frame 7 is
   just a small hole left in the ground. Plays while surfacing is
   *falling* under natural (weather-driven) conditions.
4. **`die`** ("get stepped on") — a real squash: a curled worm progressively
   flattens, widens, and pales across 8 frames into a motionless patch.
   Plays exactly once, on being crushed (never on being eaten — see below),
   and then **holds its own last frame** rather than disappearing — the
   one genuinely new animation shape in this codebase (see next section).

### Slicing: a known fixed grid, not content-gap detection

Every prior illustrated sheet in this codebase hand-measures its row
bands and hands them to `SpriteSheetSlicer.detect_frames`, which finds
individual frame boundaries by scanning for background-only columns. That
heuristic **fails on this sheet's own `die` row**: its first few frames
show the worm still curled into a loop, and the gap between the loop and
the body reads as background too — `detect_frames` with its default
divider width (1px) or a widened one (mirroring how `IllustratedBirdSprite`
fixed an analogous false-split in its own "sing" row's radiating
sound-lines) both fail here, because the sheet's *real* inter-cell gaps
range from as little as 1px (a pose that fills its whole cell edge to
edge) up to 30+px (a smaller pose with real padding around it) — there is
no single divider-width threshold that is reliably wider than every false
internal notch and narrower than every real inter-cell gap at once
(measured directly with `tools/probe_worm_sheet.gd` before writing any
slicing code, not assumed).

Since the grid itself is exactly regular, the fix sidesteps the whole
heuristic: `IllustratedWormSprite` slices the sheet directly from grid
arithmetic (`Rect2i(col * 192, row * 256, 192, 256)` for each of the 32
cells) and hands those rects straight to `SpriteSheetSlicer.normalize_frames`,
which finds each frame's own tight content bounding box regardless of
whether the outer rect it was given came from content detection or, as
here, from known geometry. All 32 cells were confirmed to hold real,
non-blank content this way before the slicing code shipped.

### Direction, not just amount

`EarthwormPatch.emergence_for(surfacing)` has always answered "how much of
the worm is above ground" — a pure function of the instantaneous
`surfacing` scalar, with no memory of which way it's currently moving.
The old region-rect reveal trick never needed direction: revealing more
of one static image as a worm rises and revealing less as it sinks are
the same operation run forward and backward. Real, separately-drawn
`emerge`/`retreat` art is not symmetric that way — picking the *right
row* now requires actually knowing whether surfacing is currently rising
or falling, which nothing in this codebase tracked before this pass.
`EarthwormPatch.advance` already computes exactly that comparison
internally (`target > level` decides whether a burrow's worm is being
pulled up or let back down); this pass has it also record the outcome
per-cell (`is_rising(cell) -> bool`) instead of throwing it away, so the
sprite layer can ask.

The full row-selection rule, per surfaced/transitioning cell:

- **Corpse** (see below) → `die`, frame held/advanced by how long ago it
  was crushed.
- **Emergence ≥ 1.0** (fully out, steady-state) → `crawl`, cycling on its
  own clock.
- **Emergence between 0 and 1, rising** → `emerge`, frame index scaled
  directly by emergence (0 → frame 0, 1 → frame 7).
- **Emergence between 0 and 1, falling** → `retreat`, frame index scaled
  by *how much has been lost* (`1 - emergence`) rather than by emergence
  itself, since `retreat`'s own art is drawn in the "going in" direction —
  frame 0 is fully out, frame 7 is nearly gone, the opposite mapping from
  `emerge`.

This only ever applies to *natural* (weather-driven) transitions.
`take()`/`crush()` still zero a burrow's surfacing instantly — an eaten or
crushed worm was never "gently retreating," so neither one plays the
`retreat` row; eating shows nothing further at all (the sprite is simply
gone, unchanged from before this pass) and crushing shows `die` instead
(next section).

### A corpse is new ground

No animation in this codebase before this pass ever played once and then
held its final frame as a **permanent** terminal state — every existing
"index a frame array off a progress value" site (`PiscivoreBirdMarker`'s
dive, illustrated character/tree growth stages) tracks a *live* progress
value the state machine keeps advancing forever, and the actual "creature
death" path (`CreatureMarker._die`) frees the marker outright and spawns
an unrelated `Carcass` node rather than leaving a death pose on screen.
`take()` and `crush()` both already reduce a worm to the *identical*
model state (`surfacing = 0`, `recovery = RECOVERY_SECONDS`) — the model
itself has never distinguished "eaten" from "crushed" once the call
returns, only the caller (which method it invoked) knows which happened.

This pass adds exactly the one bit that was missing: `EarthwormPatch`
now separately remembers *which* recovering burrows got there by being
crushed (`is_corpse(cell) -> bool`), set only by `crush()`, never by
`take()`. A corpse rides the **identical `RECOVERY_SECONDS` clock** as
ordinary recovery, deliberately reused rather than adding a second,
near-duplicate timer: the corpse lies exactly as long as its burrow is
empty, and clears the instant a new worm could occupy it again — a
narratively coherent rule (nothing else could be using that exact spot
while a squashed worm's remains are still in it), not an arbitrary
duration. `corpse_age_seconds(cell)` is derived from the same countdown
(`RECOVERY_SECONDS - remaining`) rather than a second counter, so the two
can never drift apart.

`EarthChunkManager._sync_worm_sprites` — which has always freed a
sprite the instant `is_surfaced(cell)` goes false — now also checks
`is_corpse(cell)` before freeing: a corpse's sprite survives the sync
that would otherwise have deleted it the moment `crush_worm_at` zeroed
its surfacing. The `die` row's 8 frames are spread across a real,
tested duration (not the whole 45-second recovery window — the squash
itself is quick, the *lying there afterward* is what takes the rest of
the window), and the last frame holds via the same `clampi(index, 0,
frames.size() - 1)` idiom this codebase already uses everywhere else a
continuous value indexes a bounded frame array — the difference here is
simply that nothing ever pushes `corpse_age_seconds` back down to 0
before the corpse itself clears, so the clamp's saturated state is the
last thing anyone ever sees of that worm.

### What this pass does NOT include

Named rather than silently dropped: no sway or idle-breathing animation
independent of the four states above (a `crawl`-cycling worm's only
motion is the existing sub-tile wobble plus its own walk frames — nothing
new here). No corpse decomposition/fade — a corpse disappears the instant
its burrow recovers, the same hard cutover every other worm-availability
transition in this file already uses, not a fade. Eaten worms are
unchanged by this entire pass: `take_worm_at` never shows `die`, and
never shows `retreat` either (it still vanishes on the same frame it's
taken, exactly as before) — only `crush_worm_at` reaches the new corpse
state at all.

### A corpse can be carried off (2026-09-07)

Reported live, directly: "crushing worms doesn't display their crushed
sprite last frame; instead they vanish.. they should stay in world and
still be able to picked up". The vanish half turned out to already be
fixed (the section above, same day it was reported here as `⬜`) —
almost certainly observed in a stale, pre-fix running instance. The
pickup half was a real, complete gap: nothing joined `DroppedItem.
GROUP_NAME` for a worm at all, live or dead.

`WormMarker` (`src/rendering/worm_marker.gd`) closes it, mirroring
`MushroomMarker.pick_up`'s exact shape (`ItemCatalog.make` + `inventory.
add` + "tell the sim, then `queue_free`"), with one addition: `pick_up`
is gated on `worm_world.is_corpse(cell)` up front. A live worm is
deliberately NOT pickable — becoming bait is `docs/concept/
aquatic_foraging.md`'s own separate, still-`⬜` "Worms as fish bait" pass,
not this one, so only a crushed corpse is a takeable item here.
`EarthwormPatch.take_corpse(cell)` clears `_crushed[cell]` alone,
deliberately leaving `_recovery[cell]` running: carrying the body off
does not heal the burrow any faster than an ordinary recovery would.

Every worm's sprite is a `WormMarker` from the moment it first surfaces
(the object is never recreated between then and corpse state, so it must
already be the pickable class), but `pick_up` only ever *does* anything
once `is_corpse` is true.

This also surfaced a real, independent crash: pickup lets something
OTHER than `_sync_worm_sprites`/`_crawl_worm_sprites` free a sprite that
`_worm_sprites` still has a dictionary entry for — a possibility that
never existed before pickup did. `_crawl_worm_sprites` runs every single
`step_worms` call and touched `.position`/`.texture` unconditionally;
`_sync_worm_sprites`'s own cleanup branch called `.free()` unconditionally
too — reproduced directly (mirroring `test_crushing_ants_does_not_crash_
on_a_stale_already_freed_entry`'s own ".free() the worst case" idiom): a
script error from the former, an outright engine crash from the latter.
Both now guard with `is_instance_valid` first, erasing the stale entry
instead of touching it — the exact pattern `crush_ants_near`/
`_crush_markers_near` already established for the identical shape of bug
(see "FPS regression round 3" above).

## Caterpillars: on trees, on the ground, green leaves only

Requested live: *"wire caterpillars which live on trees and on the ground
around them; they should also do groundforaging and eat green leaves
(spring, summer only)"*. A real caterpillar spends its whole larval life
doing exactly two things — eating foliage and moving to find more of it —
split across two real locations: up on a host plant chewing leaves, and
down on the ground travelling between them. Spring/summer only is real
biology too: a caterpillar is a growing-season life stage, not a
year-round presence, the same way this doc's own worms/ants are present
all year but a caterpillar specifically is not.

**Deliberately mirrors `DecomposerMarker`/`CarrionForageBehavior`
(ant/carrion bug), not `GroundForageBehavior`** (the robin/flyer module):
a caterpillar never flies, and `GroundForageBehavior`'s own `DESCENDING`
phase, `is_grounded()`, and `REHUNT_SECONDS`'s doc comment are all
explicitly about being airborne between bites — none of that means
anything for a creature that is on the ground (or a tree) the whole time.
`CaterpillarForageBehavior` (`src/gameplay/caterpillar_forage_behavior.gd`)
is a pure `SEEKING -> APPROACHING -> EATING -> SEEKING` state machine, no
engine dependencies, unit-testable headlessly like every other creature
behaviour in this codebase.

**The one real departure from its own template**: `CarrionForageBehavior`'s
`FEEDING` phase runs until the carcass is actually gone — there is no
timeout, because a carcass IS a depleting resource. A tree is not: nothing
in this codebase counts or depletes a live tree's leaves (no such resource
exists anywhere — see "What this does NOT include" below), so `EATING`
would never end on its own if it worked the carcass way, and a caterpillar
that found a tree first would simply never be seen doing the other half of
what was asked for. `EAT_SECONDS` gives it a real clock instead: eat for a
while, then move on — which is also, mechanically, the entire reason
"groundforaging" is something this creature is ever actually seen doing at
all, not just a phrase in the request.

**Two real food sources**, picked between by `CaterpillarMarker`
(`src/rendering/caterpillar_marker.gd`) by whichever is nearer, the same
"pick the nearest real thing" shape `AmbientFlyerMarker`'s own bird
forage already uses for worm/fruit/seed:

- **Real, in-season leaf litter on the ground** — the exact
  `nearest_leaf_litter_near`/`consume_leaf_litter_at` duck-typed
  `EarthChunkManager` ports `DecomposerMarker` already established for
  ants, reused rather than re-invented. Filtered to the leaf's own
  recorded season being spring or summer: `LeafLitterField`'s real 270-day
  decay lifespan means an old, brown, still-decaying autumn leaf can
  genuinely still be lying on the ground come the following spring or
  summer, and that is not what "eat green leaves" asked for. A caterpillar
  eats the green trickle `docs/concept/leaf_litter.md` already describes
  (`LEAF_SUMMER_TRICKLE_CHANCE`/`LEAF_SPRING_TRICKLE_CHANCE`), not the big
  autumn fall.
- **A real nearby tree** — `EarthChunkManager.trees_near`, the same query
  `AmbientFlyerMarker`'s own bird idle-rest already perches on (see this
  doc's sibling ecosystem_dynamics.md entry), reused rather than a second,
  near-identical "is there a tree nearby" query being written. Climbed
  (its own distinct `climb` animation, not the level `crawl` gait ground
  litter uses), and never removed or depleted — see the departure noted
  above for why.

**Season gating lives entirely at the spawn decision**
(`CaterpillarRenderer.spawn_caterpillars`, gated on both biome —
grassland/forest/rainforest, mirroring `AmbientFlyerRenderer.BIRD_BIOMES`
exactly, since "lives on trees" doesn't extend to desert/tundra/mountain
the way ants' wider carrion-adjacent `LAND_BIOMES` does — and season,
spring/summer only), not re-checked continuously at runtime. This is the
same accepted approximation every other ambient decoration in this
codebase already has: nothing re-validates a spawned butterfly's own
range/season eligibility continuously either, only at the chunk-load spawn
roll. A caterpillar chunk that stays loaded continuously across a season
boundary (a long single sitting rather than a reload) will keep foraging
into autumn rather than vanishing mid-season — named explicitly as a
known, accepted gap rather than silently left unhandled.

Real illustrated art (`assets/sprites/animals/caterpillar.png`, an
8-column x 4-row sheet sharing worm.png's exact grid dimensions) replaces
what would otherwise have been a from-scratch procedural silhouette —
this creature shipped with real art from the start, unlike ants/worms,
which both began procedural and were swapped later. Four real animations,
each confirmed against the actual sliced-and-despilled pixels before
shipping (see `tools/probe_caterpillar_sheet.gd`), not just an eyeballed
thumbnail: `crawl` (a flat, level inching gait — the travel/wander pose),
`climb` (rears near-vertical at its peak frames — moving up a trunk, not
level ground), `eat` (head held low throughout — the grazing pose, played
whether it's eating from a tree or the ground), and `rest` (progressively
flattens into a held, motionless pose).

### What this does NOT include

Named explicitly, the same convention every other appropriately-scoped
first pass in this doc uses:

- **No live-canopy leaf resource.** Nothing anywhere in this codebase
  counts or depletes a standing tree's foliage — a tree's canopy is purely
  an art state driven by the season clock (`TreePhenology`), with no leaf
  count of any kind (the only *countable* thing on a tree today is ripe
  fruit — `ChoppableTree._ripe_count`). Eating at a tree is real (gated on
  a real behavioural clock, ends and resumes for real, shown with real,
  distinct art) but purely non-depleting — a caterpillar visiting a tree a
  hundred times leaves it exactly as leafy as one visit did. Building a
  real, persisted, per-tree leaf-mass resource (with its own
  `ChunkSerializer` save format) is a genuinely separate, larger
  commitment, not something this pass silently almost-built.
- **No canopy-height offset.** A climbing caterpillar is drawn at the same
  trunk-foot ground level every other perch in this codebase already uses
  (the same level `AmbientFlyerMarker`'s own tree-perching idle rest
  lands a bird at) — it does not visually rise into the branches. No
  canopy-height field exists anywhere in this codebase to hook into yet
  (a real future enhancement, not invented here for either creature).
- **No pupation, no becoming a butterfly.** This is a standalone wired
  creature, the ant/worm shape, not the larval stage of
  `AmbientFlyerMarker`'s own existing butterfly life cycle
  (`src/gameplay/life_cycle.gd`) — the two are not connected. A
  caterpillar simply stops being spawned once a chunk reloads outside
  spring/summer; it does not transform into anything.
- **No `rest` trigger.** The sheet's fourth row (a settled, flattened
  idle) has real, confirmed art and a working `generate_textures("rest")`
  call, but nothing in `CaterpillarMarker` ever asks for it yet — the same
  "measured and available, not yet wired to a real trigger" gap this
  doc's own kingfisher-adjacent rows have had before being closed later.

## Caterpillars actually climb, and move a third as fast (2026-09-06)

Requested directly, watching a live game session: *"Caterpillars should
crawl up trees also they should be 66% slower"*, clarified immediately
after — *"1/3 of the speed"*. Two independent tweaks to the same creature,
landed together.

**Speed: `CaterpillarMarker.WALK_SPEED` becomes `14.0 / 3.0`** (not a
rounded `14.0 * 0.34` — "1/3 of the speed" is an exact fraction, so the
constant is too). Every other movement-timing constant in this file
already derives FROM `WALK_SPEED` rather than duplicating it —
`WANDER_DIRECTION_CHANGE_INTERVAL_SECONDS`'s own doc comment says so
explicitly ("keeps this in proportion automatically") — so ambient wander
and the committed walk to a food source both slow down in the same 3x
proportion with no second constant to touch.

**Climbing closes the "No canopy-height offset" gap named directly above**
(the previous pass's own "What this does NOT include"): a caterpillar
approaching or eating at a tree now visually rises up the trunk rather
than staying pinned to the same trunk-foot ground level every other perch
in this codebase uses. New `CaterpillarMarker._climb_height_px` rises
toward a new `CLIMB_HEIGHT_PX` (`TILE_SIZE`, 16px — roughly one tile's
worth up the trunk, not into the canopy proper: a real caterpillar grazes
low branches and the trunk itself at least as often as the crown, and a
modest climb reads clearly without this file needing to know anything
about `ProceduralTreeSprite`'s own canopy dimensions, a dependency this
class has deliberately never had) at the same `WALK_SPEED` pace ground
movement uses, for as long as `_target_is_tree` is true and the phase
isn't SEEKING — i.e. rising through the walk there (the same phase the
`climb` sprite pose is already shown for, see `_current_action`) and
holding through EATING, then settling back to 0 once the phase returns to
SEEKING. A leaf-litter visit never climbs at all: `_target_is_tree` stays
false the whole time, so the target height is always 0.

**Purely a sprite offset (`_sprite.position.y = -_climb_height_px`), never
the node's own `.position`** — the same "a plain position + a which-kind
flag is everything approach/eat need" reasoning the class doc comment
already draws for why a tree target needs no live node reference at all.
`_step_approaching`'s arrival check, `_nearest_food`'s distance
comparisons, and anything that might Y-sort a caterpillar in the future
all keep reading the real ground tile the caterpillar is logically
standing on — a caterpillar visually eight pixels up a trunk is still, as
far as every other system in this game is concerned, standing exactly
where it always was. Named, not silently accepted: a caterpillar climbing
a tall gap in a real forest can end up drawn slightly out of its usual
draw-order relationship with the trunk it's climbing — a minor visual
layering wrinkle, not a logic bug, and not attempted here.

New tests in `test_caterpillar_marker.gd` pin `_climb_height_px` actually
rising while approaching/eating at a tree, settling back to 0 once
finished, and staying at 0 for a leaf-litter visit throughout; `test_
caterpillar_forage_behavior.gd`/existing `test_caterpillar_marker.gd`
cases needed no changes — nothing about phase transitions, arrival
distance, or eating/bite timing moved, only how fast the walk covers
ground and where the sprite draws while it does.

## Millipedes: a dedicated autumn leaf-litter decomposer (2026-09-06)

Requested directly, reported live with a screenshot of an autumn floor
carpeted in fallen leaves: *"Leaves are too many in autumn what else
decomposes leaves I could add into the ecosystem to increase decomposition
rate?"* Investigated first, rather than assumed: leaf litter's only
non-seasonal removal sinks are ants (`AntColony`/`AntForagerMarker`, real
but heavily rate-limited — 2 mounds/chunk, a 5%-per-step forage roll, a
1-tile sense radius) and caterpillars — and caterpillars are structurally
incapable of ever touching the pile this complaint is actually about:
`CaterpillarMarker._is_green` only eats a leaf whose own recorded season is
`"spring"`/`"summer"`, permanently excluding every `"autumn"`-tagged leaf
(see "Caterpillars: on trees, on the ground, green leaves only" above).
Flies and earthworms have no relationship to leaf litter at all (flies
breed on rotting dropped food; worms are driven by soil moisture).
Meanwhile leaf-fall chance itself ramps from a 6% summer trickle to
effectively 100% per tree per tick by late autumn
(`EarthChunkManager.LEAF_AUTUMN_BASELINE_CHANCE`) — the removal side was
never provisioned to keep up with that at all.

**Real-world grounding.** Millipedes (Diplopoda) are among the most
important detritivores of a deciduous forest floor specifically — unlike a
carrion beetle or an omnivorous ant, they are near-exclusively
saprophagous: they eat dead, decaying plant matter (leaf litter above all),
not carrion, not fresh fruit, not live foliage. This is the opposite
restriction from a caterpillar's own green-leaf-only diet, and exactly the
gap nothing else in this ecosystem fills.

**Deliberately reuses `CaterpillarForageBehavior` directly, not a new
near-duplicate state machine.** That class's own `SEEKING -> APPROACHING ->
EATING -> SEEKING` cycle is already fully generic — nothing tree-specific
lives in the behavior itself, only in how `CaterpillarMarker` interprets
its own `_target_is_tree` flag (see above). A millipede has no second food
source and no climbing to interpret, so `MillipedeMarker`
(`src/rendering/millipede_marker.gd`) is a smaller sibling of
`CaterpillarMarker`: same `SEEKING`/`APPROACHING`/`EATING` phases, same
`AmbientFlyerMovement`-driven ambient wander, same
`nearest_leaf_litter_near`/`consume_leaf_litter_at` duck-typed
`EarthChunkManager` ports every ground decomposer in this doc already
shares — but with the season filter DROPPED entirely (any leaf, any
season, is real food) and no tree branch at all.

**Biome-gated at spawn, same set as caterpillars**
(`{"grassland", "forest", "rainforest"}`, `MillipedeRenderer` mirroring
`CaterpillarRenderer.CATERPILLAR_BIOMES` exactly) — wherever trees can grow
leaf litter to decompose, not the wider carrion-adjacent land set
`DecomposerRenderer`'s "bug" uses. No season gate at all (unlike
caterpillars): a millipede's whole reason for existing is to be present
when the autumn leaf pile actually happens, not absent for it.

**Real illustrated art from the start**
(`assets/sprites/animals/millipede.png`, an 8-column x 4-row sheet sharing
worm.png/caterpillar.png's exact grid dimensions — 1536x1024, 192x256 per
cell, confirmed directly against the PNG header). Four real animations:
`crawl` (a flat, level, many-legged gait — the travel/wander pose and what
approaching a leaf plays), `alert` (rears its front segments up, head
raised — played while EATING, a millipede pausing to feed), `curl` (rolls
into a defensive coil, a real millipede threat response), and `crushed` (a
level crawl transitioning into a flattened, splattered pose). Only `crawl`
and `alert` are wired to anything today — `curl` and `crushed` are
measured, confirmed-real, and available, not yet wired to a real trigger,
the same "available, not yet wired" gap this doc's own caterpillar `rest`
row and kingfisher-adjacent rows have had before being closed later.

### Generalized to millipedes too (2026-09-06)

The same `CrushMechanic` a worm and a caterpillar already share (see
"Generalized to caterpillars too" above) now has a third detection side:
**`EarthChunkManager.crush_millipedes_near(pixel_position,
momentum_kg_m_s) -> bool`**, sharing its actual body with
`crush_caterpillars_near` via a new private `_crush_markers_near` helper
rather than a third hand-copied implementation of the identical "resolve
the stepped-on tile, scan this chunk's own tracked markers by real
position, free anything that clears the threshold" logic — a millipede is
the same *shape* of victim a caterpillar already is (a real,
independently-positioned `Node2D`, not per-tile cell state like a worm), so
there is nothing here that needs its own copy the way the worm/caterpillar
split itself does. Wired identically to both existing calls, in the same
`World._client_process` block: the player's own
`_PLAYER_STEP_MOMENTUM_KG_M_S`, and every `CreatureMarker`'s own
`CreatureMass.mass_kg_for(species)`-derived momentum.

**Also feeds Karma** (see `docs/concept/karma_and_luck.md`): a crushed
millipede charges the same `Karma.WORM_OR_CATERPILLAR_CRUSH_PENALTY` a
crushed worm or caterpillar already does — the constant's own name
predates this third species, but the event it represents ("a small,
harmless decomposer died underfoot") is identical, and karma_and_luck.md's
own event table is updated to say so rather than silently reusing the
constant under a now-inaccurate name with no cross-reference.

### What this does NOT include

- ~~No timed death animation.~~ **Closed (2026-09-06, "build both — crushed
  sprite for all small animals").** `MillipedeMarker.crush()` now plays the
  real `crushed` row from frame 0, holds the final flattened frame, then
  frees itself — see "A real death treatment for every small victim"
  further down.
- **No `curl` trigger.** A real defensive reaction (fleeing/curling when
  the player approaches) would need this creature to sense threats at all,
  which nothing in `MillipedeMarker`/`CaterpillarForageBehavior` does
  today — named, not silently assumed.
- **No population/food-economy modeling.** Unlike `AntColony`'s real mound/
  food-store/growth loop, a millipede is the ant/worm/caterpillar shape:
  spawned once per qualifying chunk at load, wandering and eating
  independently, with no colony, no stockpile, no carrying-capacity
  feedback. A real "litter input -> detritivore biomass" model remains the
  same deferred follow-up this doc's own worm section already names.

### Generalized to ants too (2026-09-06)

Reported live: "ants are also not crushed when a player is walking over
them" — a real, confirmed gap: `AntForagerMarker`, the visible walking
ant every real forage/scout/resolver trip spawns (see "Ants at half
their old size, and finally hoverable" above), was the one victim shape
`CrushMechanic`'s per-frame pass never reached at all, even after
worm/caterpillar/millipede all got it the same day.

**`EarthChunkManager.crush_ants_near(pixel_position, momentum_kg_m_s) ->
bool`** is the fourth detection side — same `CrushMechanic.is_crushed_by`
physics, same "insufficient momentum is a no-op" contract every other
crush call already has. It does NOT share `_crush_markers_near`'s own
body the way `crush_millipedes_near` shares `crush_caterpillars_near`'s:
that helper scans one `chunk_coord -> Array` dictionary, but an ant
forager is tracked in `_active_ant_foragers`, keyed by each MOUND's own
GLOBAL TILE instead (a single chunk can hold up to `AntColony.MAX_MOUNDS`
mounds, each its own key — see `_dispatch_forager`) — so `crush_ants_near`
scans every currently-active forager across every loaded mound directly,
a small, already-capped-per-mound number (`active_forager_cap_at` tops
out at `AntColony.MAX_CONCURRENT_FORAGERS`), rather than trying to force
a chunk-keyed lookup onto a mound-keyed dictionary. Wired identically to
the other three calls, in the same `World._client_process` block: the
player's own `_PLAYER_STEP_MOMENTUM_KG_M_S`, and every `CreatureMarker`'s
own `CreatureMass.mass_kg_for(species)`-derived momentum.

**Also feeds Karma** (see `docs/concept/karma_and_luck.md`): a crushed
ant charges the same `Karma.WORM_OR_CATERPILLAR_CRUSH_PENALTY` a crushed
worm/caterpillar/millipede already does — the identical "a small,
harmless invertebrate died underfoot" event, and `karma_and_luck.md`'s
own event table is updated to say so.

**Both gaps this section originally named here are closed** (2026-09-06,
"build both — crushed sprite for all small animals"): `AntForagerMarker.
crush()` now plays a real death treatment (`IllustratedDecomposerSprite`'s
"ant" art has no dedicated crushed pose, so this reuses `SquashCrushEffect`'s
shared procedural fallback — see "A real death treatment for every small
victim" further down) instead of an instant `queue_free()`, and
`AntColony.forager_crushed(cell)` now subtracts one worker's worth of
abstract colony strength from the mound that lost it (floored at 0.0) —
still no effect on `record_forage_result`/the forage-success EMA
specifically (a crushed forager still simply vanishes mid-trip as far as
that separate signal is concerned), only on the raw population number
itself.

**Revised (2026-09-07): `AntForagerMarker.crush()` no longer applies
`SquashCrushEffect`'s own `VERTICAL_SQUASH` flatten, tint only.** Reported
live: "crushed ants should have the same size as normal ants... atm ants
seem to disappear." An ant's own live `marker_scale` is already tiny
(`IllustratedDecomposerSprite.ANT_WORLD_WIDTH` is 4.5px against a
several-hundred-pixel source frame — `scale.y` measured around 0.013 in
practice), so even `SquashCrushEffect`'s own RELATIVE squash (already
fixed once from an absolute overwrite that made a crushed ant balloon up
huge — see `SquashCrushEffect.VERTICAL_SQUASH`'s own doc comment) still
shrank it by another 65%, down to a fraction of a percent of its texture
height — effectively gone. `crush()` now sets `_sprite.modulate =
SquashCrushEffect.TINT` directly, skipping the flatten entirely: same
"no longer alive" tell, same footprint as a normal ant.
`CaterpillarMarker`/`DecomposerMarker` keep the full `SquashCrushEffect
.apply()` treatment unchanged — neither was reported, and neither
starts anywhere near this small.

### Generalized to bugs too (2026-09-06)

Asked directly, alongside mushrooms/ants: "a bug should count as a small
creature too." `DecomposerMarker` — the ambient carrion/fruit/leaf-litter
forager whose own `species` is `"ant"` or `"bug"` (see "Unifying the
duplicate ants first" above) — was the one remaining victim shape
`CrushMechanic`'s per-frame pass still had not reached, even after
worm/caterpillar/millipede/`AntForagerMarker` all got it.

**`EarthChunkManager.crush_decomposers_near(pixel_position,
momentum_kg_m_s) -> bool`** is the fifth detection side — same
`CrushMechanic.is_crushed_by` physics, same "insufficient momentum is a
no-op" contract every other crush call already has. Unlike
`crush_ants_near`, a `DecomposerMarker` IS tracked chunk-keyed, in
`_decomposer_markers`, the identical shape `_caterpillar_markers`/
`_millipede_markers` already are — so this shares `_crush_markers_near`'s
own body directly, the same way `crush_millipedes_near` already does,
rather than a fifth hand-copied scan. Wired identically to the other
four calls, in the same `World._client_process` block: the player's own
`_PLAYER_STEP_MOMENTUM_KG_M_S`, and every `CreatureMarker`'s own
`CreatureMass.mass_kg_for(species)`-derived momentum.

**Also feeds Karma** (see `docs/concept/karma_and_luck.md`): a crushed
bug charges the same `Karma.WORM_OR_CATERPILLAR_CRUSH_PENALTY` a crushed
worm/caterpillar/millipede/ant already does — the identical "a small,
harmless invertebrate died underfoot" event, and `karma_and_luck.md`'s
own event table is updated to say so. Applies identically whichever
species string this particular `DecomposerMarker` happens to be drawing
(`"ant"` or `"bug"`) — the crush check itself never reads `species` at
all, only position, the same way `crush_ants_near` treats every
`AntForagerMarker` alike regardless of which mound dispatched it.

**The corpse/recovery gap this section originally named here is closed**
(2026-09-06, "build both — crushed sprite for all small animals"):
neither the "ant" nor "bug" sheet has a dedicated crushed pose, so
`DecomposerMarker.crush()` reuses `SquashCrushEffect`'s shared procedural
fallback — see "A real death treatment for every small victim" further
down — instead of an instant `queue_free()`. Still no effect on whatever
it was doing (foraging a carcass, fruit, or leaf litter) beyond that one
instance disappearing mid-task — that part of the original scope cut
still holds.

### A real death treatment for every small victim (2026-09-06)

Asked directly, after the ant-crush investigation above confirmed the
missing sprite/population effects were deliberate scope cuts rather than
bugs: "build both — crushed sprite for all small animals and population
decrease." Every one of the five crush victims above (worm, caterpillar,
millipede, ant forager, decomposer/bug) now plays a real death treatment
before disappearing, instead of the instant `queue_free()` most of them
had:

- **Worm** — already closed, before this pass even started: `EarthwormPatch.
  crush()`/`is_corpse()`/`corpse_age_seconds()` play the real `die` row
  (see "Illustrated worm sprite" above) and hold a genuine 45-second corpse
  while the burrow recovers. Untouched here.
- **Millipede** — `millipede.png`'s row 4 `crushed` frames were real,
  measured, and delivered from the start (see "Millipedes: a dedicated
  autumn leaf-litter decomposer" above) but never wired to a trigger.
  `MillipedeMarker.crush()` now plays that row from frame 0, holding the
  final flattened frame (`_update_sprite` clamps rather than wraps once
  `_dying`), for `frame_count * FRAME_DURATION_SECONDS` before freeing.
- **Caterpillar, ant forager, decomposer/bug** — none of their three sheets
  has a dedicated crushed pose (`caterpillar.png`'s four rows are
  crawl/climb/eat/rest; neither `IllustratedDecomposerSprite`'s "ant" nor
  "bug" art has one at all). New shared `SquashCrushEffect`
  (`src/rendering/squash_crush_effect.gd`) is the procedural fallback for
  all three — three real call sites clears this codebase's own "three
  similar things beats a premature abstraction" bar. `apply(sprite)`
  flattens the sprite vertically (`VERTICAL_SQUASH = 0.35`) and tints it
  dark/reddish (`TINT`), applied to whatever frame the marker was already
  showing at the moment it died — no new art asset needed. Each marker's
  own `crush()` applies it once, stops all further forage/wander
  processing immediately, and frees itself after `LINGER_SECONDS` (2.0).

All five are wired through the same two chokepoints: `EarthChunkManager.
_crush_markers_near` (caterpillar/millipede/decomposer) calls
`marker.crush()` when the marker has one, falling back to `queue_free()`
for a test double that doesn't (so nothing outside this codebase's own
tests is affected); `crush_ants_near` (which cannot share that helper —
see its own doc comment) calls `AntForagerMarker.crush()` directly.

**Ant population, the second half of the ask.** `AntColony.
forager_crushed(cell)` subtracts `FORAGER_CRUSH_POPULATION_LOSS` (1.0 — one
worker, the smallest indivisible unit this abstraction can represent) from
the mound's own current colony strength, floored at 0.0 the same way
starvation already is. `crush_ants_near` calls it whenever a real
`AntColony` is registered for the crushed forager's own chunk, converting
the forager's GLOBAL tile key (`_active_ant_foragers`' own indexing) back
to the LOCAL cell `AntColony`'s own `_population` dict actually uses. A
crushed forager still never touches `record_forage_result`/the
forage-success EMA (that signal still just sees the trip silently
vanish) — only the raw population number moves.

**What this does NOT include**: no crushed-sprite art of any kind for
caterpillar/ant/bug beyond the generic squash-and-tint (a real bespoke
"flattened insect" illustration for any of the three, if wanted, is a
follow-up art delivery, not a code gap); no population effect for anything
other than ants (worm/caterpillar/millipede/bug have no equivalent
colony-strength number to move at all).

### Some birds eat caterpillars too (2026-09-06)

Asked directly, alongside the crushed-sprite/population work above:
"Also some birds (where it fits) should eat caterpillars." Real robins are
committed caterpillar-hunters — caterpillars, not worms, are what a robin
actually feeds its own chicks most of the time — so this adds
`FlyerDiet.FOOD_CATERPILLARS` to the robin's own diet entry alongside
worms and fruit (see "Bird diet, as a first-class concept" above), not a
new mechanism: it reuses the identical ground-forage descend/sit/peck
cycle a worm hunt already drives.

Deliberately **robin-only**, the same shape `FOOD_WORMS` already has: a
sparrow's granivore bill and a kingfisher's fish-only diet are both a poor
real-world fit for hunting insects, so this stays narrow rather than
spreading it across every songbird just because the machinery now exists
— the literal "where it fits" from the request.

**`EarthChunkManager.caterpillars_near`/`take_caterpillar_near`** mirror
`worms_near`/`take_worm_at`'s own shape exactly (same Chebyshev-in-tiles
radius check, same 3x3-chunk-neighborhood scan, same "eaten on real
arrival, re-checked here" contract) — reading from and removing out of the
same `_caterpillar_markers` tracking dict the crush mechanism above
already uses. `take_caterpillar_near` calls `queue_free()` directly, never
`crush()`: a bird's meal is an entirely different event from being crushed
underfoot, with no death animation of its own to play through.

`AmbientFlyerMarker` grows `caterpillar_world`/`_caterpillar_target` plus
`_fly_at_caterpillar`/`_take_targeted_caterpillar`/`_look_for_caterpillars`,
each a direct mirror of the worm-hunting trio — including reusing the same
`WORM_SNIFF_INTERVAL` throttle and `GroundForageBehavior.choose_worm`
scatter-pick fruit/seed/grass-seed already share under that same
historical name, rather than inventing same-shaped duplicates.
`AmbientFlyerRenderer._build_marker` sets `caterpillar_world` for any
species with `FlyerDiet.FOOD_CATERPILLARS`, guarding against creating a
second, redundant `GroundForageBehavior` when the same species (a robin)
already got one from the worm branch just above it.

**What this does NOT include**, named rather than silently dropped: a
caterpillar up a tree, mid-climb (see `CaterpillarMarker._target_is_tree`),
is never hunted — only a ground-based one is findable by
`caterpillars_near` at all. Real robins do glean insects off foliage too,
but that is a genuinely different targeting problem (perching on/near a
branch, not a ground descend-and-peck) from what this pass builds, and is
a real, deliberate follow-up rather than an oversight.
