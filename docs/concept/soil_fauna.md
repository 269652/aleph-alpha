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
- ⬜ Insect larvae, snails, and any other soil fauna beyond ants — the table
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

1. Is given a genuine target position (still found the same way —
   `grass_seeds_near`/`fruit_near` within `FORAGE_RADIUS_TILES`, see
   "Pheromone trails" below for how it's chosen when more than one
   candidate exists) and **walks there for real**, at the same
   `WALK_SPEED` it always animated at.
2. **Takes the seed/nut only on real arrival** (`take_grass_seed_at`/
   `take_fruit_at`), re-checked at that moment — something else (a mouse,
   a bird, simple bad luck) may have taken it first in the time the ant
   spent walking, in which case the trip comes back empty. This is the
   actual, meaningful sense in which foraging is now real rather than
   scripted: the walk has a causal effect that can fail, not a guaranteed
   one animated after the fact.
3. **Walks back to the mound**, not onward to a cache point out in the
   field — a genuine change from the old geometry, and a more accurate
   one: real ants carry a harvested seed *toward the nest*, discarding the
   processed remnant in a midden near the entrance, not out where they
   found it. The cache/consume roll (`AntColony.windfall_is_consumed` for
   windfall; grass seed always survives to be planted, exactly as before)
   and the resulting `plant_grass_at`/`try_plant_seed_at` call now happen
   at the mound, using `carry_distance_tiles`/`carry_direction` from the
   *mound's* position rather than the pickup's.
4. Frees itself once home, the same one-shot-per-trip lifetime as before.

`AntForageBehavior` (new, pure, no engine dependency, mirroring
`CarrionForageBehavior`'s shape) owns the two phases this needs —
`APPROACHING` (walking to the target, arrival resolves found-or-not) and
`RETURNING` (walking home, arrival resolves cache-or-consumed) — simpler
than its siblings because there is no `SEEKING` phase: the mound already
found a real, reachable candidate before dispatching anyone, exactly as
before. `AntForagerMarker` now takes a duck-typed `_world` reference (the
same contract shape `FishMarker`/`PiscivoreBirdMarker` already use) so it
can make these calls itself, plus the owning `AntColony` and mound `cell`
so the cache roll at arrival reads the colony's own deterministic
per-(cell, step) carrier seed, sampled live at the moment it's actually
needed rather than captured stale at dispatch time.

### Pheromone trails: recruitment to a known-good source

Real ants recruit nestmates to a food source with a **trail pheromone**: a
successful forager lays it down as it returns to the nest, it evaporates
over real time, and other foragers read it as a bias toward a *known*
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

**Where it plugs into foraging, concretely.** `FORAGE_RADIUS_TILES`
doubles (1.0 → 2.0 tiles — still comfortably under `SeedCaching.
PICKUP_RADIUS_TILES`, the ordering `test_ant_forage_radius_is_shorter_
than_rodent_pickup_radius` already pins, just not AT the old value), which
matters here specifically because it is what makes more than one candidate
food item plausible within reach at once. When there is more than one,
`PheromoneField.best_candidate_index` scores each by distance **and** the
trail concentration already sitting at it, and the mound sends its forager
to whichever scores highest — a location the colony has recently foraged
successfully (and therefore already marked) can beat a marginally closer
but never-visited one, exactly the real recruitment effect. A successful
forager deposits at the food's own position the moment it picks its find
up (marking "there was food here, worth checking again"), read by the
*next* dispatched forager's own candidate scoring, not by anything this
one does for the rest of its own trip.

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
   (`active_forager_cap_for`, `MAX_CONCURRENT_FORAGERS` = 3), replacing
   the old hardcoded "one forager in flight at a time." A young or
   food-poor colony still reads exactly as before — one ant, one trip at
   a time — while a large, well-fed one visibly has two or three workers
   out at once, the same "aggregate population promotes to visible
   individual markers" pattern `FishRenderer`'s own `target_count`
   already uses for fish.
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
- **Leaf litter is a separate forage source this mound simulation does not
  see.** [leaf_litter.md](leaf_litter.md) adds a fallen-leaf ground item
  alongside fallen fruit/nut, picked up by the VISIBLE `DecomposerMarker`
  ants/bugs ([carrion.md](carrion.md)) via the ordinary
  `DroppedItem.FORAGEABLE_GROUP_NAME` path with no changes needed there —
  but this invisible colony's own `_forage_windfall_near_mound` queries the
  fruiting model's abstract fruit/nut stock directly, never `DroppedItem`
  nodes, so it has no way to see a leaf item without a parallel query this
  pass does not build. Named there as a reasonable, separable follow-up,
  not silently dropped.
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
- **Not persisted, not catch-up integrated**, for the identical reason
  `EarthwormPatch`'s own burrows are not (see that section's Scope choices
  above): a reloaded chunk re-seeds its mounds deterministically, and a
  short-timescale, self-renewing local effect does not need
  `ChunkEcologyCatchup` fidelity.


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
