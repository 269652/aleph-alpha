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

`DesertScrub` and `TundraLichen` shipped as fully-tested sims that nothing in
live gameplay ever calls (see `progress.md`). This mechanic is deliberately
wired the whole way: chunk load creates the population, `World._process` steps
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
- ⬜ Other soil fauna (insect larvae, snails) — the table and the patch-sim
  contract both extend to them, nothing else is needed structurally.


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

**Size.** An earthworm is about ten centimetres, the same as a crocus is tall,
and is drawn at the size that makes true. It was set by eye back when every
flower shared one invented height; once flowers were pinned to the player's own
scale the worm was suddenly longer than several of them and read as a snake
lying in the grass.
