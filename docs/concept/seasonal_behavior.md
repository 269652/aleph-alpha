# Seasonal Behavior: Every Live Species Responds to Its Own Real Winter

Requested live: *"revisit every animal/species and wire/implement proper
season behaviour/activity... ants may stay in their mound and eat the food
accumulated over the year... a bear goes hibernating... wild bees die and
hatch again in spring... just make it realistic and biologically
motivated."*

This closes a real, wide gap: the game already has a real deterministic
calendar ([`SeasonCycle`](../../src/world/season_cycle.gd)) and three
species (ants, honeybees, earthworms) with a genuine, tested cold-weather
mechanism, but most of the ~25 other live species have zero season
awareness at all, and the three that do have a real, precisely-diagnosed
gap (see "Ant/honeybee forager cold-gate" below). This doc is deliberately
one doc covering every species rather than one per mechanic, because the
real point is comparison: a bear's winter and a wild bee's winter and a
sheep's winter are genuinely different biological strategies, and the
mechanism spec below is organized by STRATEGY SHAPE precisely so that
stays visible instead of getting lost across a dozen small docs.

## Design pillars

1. **Match the real strategy, not one blanket "winter mode."** True
   hibernators (bear) stop entirely. Brumating reptiles (snakes) go
   inactive but can rouse on an unseasonably warm day. A wild bee
   generation dies and its replacement overwinters as brood, not as an
   adult. A sheep does none of that — it just has a harder time finding
   food. Applying one mechanism to all of these would be the reskin this
   project's own precedent (`bees.md`'s "two real, biologically distinct
   bees, not one mechanic reskinned twice") explicitly warns against.
2. **Reuse the real signal that already exists.** `EarthwormPatch.
   COLD_CUTOFF`/`MILD_WARMTH` and the `dormancy_multiplier_at` shape it
   seeded are already shared by ants, bees, and (for body-temperature
   regulation) every `CreatureMarker` via `ambient_warmth()`. New
   mechanisms read the SAME signal rather than inventing a second notion
   of "how cold is it."
3. **Close a real gap before adding a new flag.** Where an existing
   system already ALMOST produces the real behavior (tall-grass growth
   already slows in winter; ant/bee dormancy already throttles food
   burn), the fix is finishing that chain, not bolting a parallel one on
   top of it.
4. **Determinism**, the same standing rule every patch-sim/colony in this
   project already follows — a season transition must be exactly
   reproducible from the same seed and elapsed time, not a live dice roll
   with no record.
5. **Right-size new species to the mechanism they actually need.** A
   grass frog's brumation looks like an earthworm's activity toggle, not
   a bear's decision-ladder state; a blackbird's real gap is a diet
   shift, not a new hibernation mechanic. Forcing every new species
   through the same architecture would be the wrong abstraction for at
   least half of them.

## Real-world grounding, by strategy

- **True hibernation (endotherm, deep torpor for the whole cold season)**:
  a bear builds fat reserves over summer/autumn and then does not forage,
  drink, or move meaningfully until spring — metabolism drops
  dramatically for weeks at a time, not day by day.
- **Brumation (ectotherm dormancy)**: snakes go inactive and shelter in
  cold weather, similar externally to hibernation, but lighter — a
  brumating reptile can rouse and briefly move on an unusually warm
  winter day, unlike a hibernating mammal.
- **Colony dormancy (eusocial insects)**: honeybees cluster and live off
  stored honey; ants cluster deep in the mound and live off stored food.
  The colony does not "hibernate" as a unit walking away from the world —
  it keeps consuming its own stockpile at a throttled rate, and (the real
  gap here) stops sending workers out to forage in earnest.
- **Generational die-off / overwintering brood**: most solitary bees and
  most temperate butterflies do not have adults that survive freezing
  winters at all. The population persists as eggs/larvae/pupae sealed in
  a nest cell or chrysalis, and a NEW generation of adults emerges the
  following spring.
- **Permanent resident, activity-only response**: an earthworm is never
  created or destroyed by the weather — the same individuals stay put all
  year; only how close to the surface they sit changes with soil
  temperature. A ground beetle sheltering and slowing down in cold soil,
  and a frog burying into mud/leaf litter through winter, are the same
  strategy shape, just applied to a different physiology.
- **No dormancy, real forage hardship instead**: most quadruped herbivores
  do not hibernate at all — winter is harder because there is
  genuinely less to eat, not because the animal goes anywhere or does
  anything different in kind.
- **Caching**: non-hibernating rodents (squirrels, mice) survive winter by
  eating what they cached earlier in the year, not by any change to their
  own physiology.
- **Diet shift, not dormancy (birds)**: birds don't hibernate. A
  blackbird stays active year-round in most of its range but shifts from
  insects toward fruit/berries when insects are scarce in winter — a
  behavioral change, not a physiological one.

## Mechanism spec

### Ant/honeybee forager cold-gate (closes a real, diagnosed gap)

`AntColony`/`BeeColony` already throttle stored-resource depletion via
`dormancy_multiplier_at()` (floored at `DORMANCY_FLOOR := 0.2`, reading
`EarthwormPatch.COLD_CUTOFF`/`MILD_WARMTH` against a per-cell warmth EMA).
What they do NOT do: `should_forage()` in both files is a flat
`PixelNoise`/`FORAGE_CHANCE` roll with no warmth term at all, so a fully
dormant mound/hive still sends foragers out at the ordinary rate — the
literal opposite of "cluster deep in the mound and barely feed at all."
Fix: fold `dormancy_multiplier_at(cell)` into the forage-attempt roll
(lower multiplier -> lower chance a tick actually launches a forager) in
both files identically, the same "same shape, deliberately separate
files" precedent `bees.md` already established for `AntForageBehavior`/
`BeeForageBehavior`.

### Wild bee die-off / re-hatch

`WildBeePatch` has no seasonal behavior at all today (confirmed: no
warmth tracking, no `COLD_CUTOFF` reference in the file). A real solitary
bee's autumn-to-spring cycle is a population EVENT (die-off then
re-emergence), not a smooth activity gate — so this needs a genuinely
different mechanism than the ant/bee dormancy multiplier above, matching
this doc's first design pillar. Each nest site gains a hidden brood
count, credited from the season's own foraging success; going into
winter, visible `residents` drops to zero (an empty-looking nest hole,
no foragers to see or catch); coming out of winter, `residents` re-hatches
FROM the carried brood count (inheriting how good last season was, not
resetting to a fixed seed every year).

### True butterfly season-gated spawn window

Monarch/swallowtail/blue morpho are purely decorative (no population to
gate mid-life the way the wild bee mechanism above does) — the honest,
right-sized fix is a spawn-time gate, exactly mirroring the existing,
proven `CaterpillarRenderer.ACTIVE_SEASONS := {"spring": true, "summer":
true}` precedent (checked once at chunk load, not per-frame). Butterflies
get `{"spring": true, "summer": true, "autumn": true}` — real adult
butterflies fly well into autumn — with winter excluded, so no live adult
flies over a snowed-in meadow. Giving butterflies a REAL population that
this event could instead operate on is a separate, already-named gap
(`ecosystem_dynamics.md`'s Open Questions: "there is still no predation
pressure on [true butterflies] to make an aggregate number mean
anything") — not solved here.

### Decomposer "bug" cold-slowdown

`DecomposerMarker` has no aggregate economy at all (stateless per-chunk
spawn, no colony object) — the right-sized fix is throttling the
INDIVIDUAL marker's own wander/forage cadence via the identical
`ambient_warmth()`/`COLD_CUTOFF` read `CreatureMarker` already performs
every frame for body temperature, mirroring `EarthwormPatch`'s
activity-only shape (population never changes, only how active/visible
each individual is) rather than inventing a colony class for one more
species.

### Herbivore winter-forage-realism fix (the highest-leverage change)

`SeasonCycle.growth_modifier()` already throttles real tall-grass
maturation in winter (`EarthChunkManager.step_tall_grass`), and
`EarthChunkManager.grass_near()` already only returns mature patches — so
a search against REAL grass is already seasonally honest. The break: when
a hungry grazer finds nothing via that real search, `CreatureMarker.
_look_for_a_bite()`'s `FOOD_UNDERFOOT` fallback grants a full day's BMR
(`feed_hunger_relief(1.0)`) regardless of season, on any food-capable
biome tile — silently defeating the seasonal throttle the rest of the
chain was already built to produce. Fix: scale the underfoot bite's
relief fraction by the current `growth_modifier`, so grazing bare winter
ground genuinely yields less than a lush summer meadow. This is the
single highest-leverage change in this whole doc: it gives every
herbivore species, present and new, real winter hardship using plumbing
that already exists end-to-end, with no per-species code.

**Explicit scope cut**: no starvation-death path is added here. Mass
already drops under sustained deficit (`Metabolism`/`current_mass_kg()`),
which is a real, if quiet, consequence; whether hunger should ever kill a
creature outright is a separate, bigger design decision than "seasonal
behavior," named here rather than decided by default.

### Squirrel scarcity-driven eat-vs-cache shift (revised from "cache preference")

**Corrected on implementation, not as originally scoped.** Both species
have a "caching" mechanic, but reading `SquirrelNutCaching`/`SeedCaching`
in full shows neither is a personal, retrievable food store an animal
could later "prefer" over fresh foraging: caching here means real
scatter-hoarding SEED DISPERSAL — a picked-up nut/seed is carried a short
distance and either eaten outright or buried as a new planting site
(`try_plant_seed_at`), never as a stockpile the same animal returns to
draw down. `SeedCaching` (mouse) additionally has no eat-vs-cache branch
at all — a mouse's grass seed is ALWAYS re-cached (redistributed onto the
same ground-seed pool foraging already reads from), never eaten in place,
a deliberate existing design choice, not a gap. Building a genuine
per-individual "remembers and returns to its own cache" mechanic would be
a materially larger, new feature — spatial cache-location tracking this
file's own pure, stateless functions were never built for — not a cheap
extension, and not attempted here.

The real, buildable, still-genuinely-seasonal mechanism this file's own
existing doc comment already implies: *"caching becomes common mainly
once immediate hunger is satisfied... or a mast glut exceeds what can be
eaten right away."* The inverse holds too — real forage scarcity should
push a forager toward eating what it finds right now rather than
investing effort in a cache for later. `SquirrelNutCaching.
nut_consumption_chance_for`/`nut_is_consumed` gain an optional
`growth_modifier` term (the same signal the herbivore forage-realism fix
above reuses) that nudges consumption UP as real forage gets scarcer —
real, cheap, and grounded in this module's own pre-existing reasoning.
**Mouse is explicitly out of scope for this specific mechanism** (no
eat-vs-cache branch to nudge); a mouse's own seasonal hardship already
comes from the shared `FOOD_UNDERFOOT`/`FOOD_SEED` forage-realism fix
above, the same as every other `CreatureMarker` species.

### Bear hibernation / snake brumation (new total-override state)

The one genuinely new architecture piece. **Implemented differently from
this section's own first draft, on reading the real decision code**:
`CreatureBehavior.decide()` doesn't return an intent picked from a plain
ordered if-chain a new case could slot into — it delegates to
`BehaviorKernel.decide()` running `Ethogram.BODY_PLANS["mammal"]`'s
wirings, a scored competition between drives (hunger/thirst/fear/
courtship), with its own dedicated ladder-order test coverage
(`test_ethogram.gd`). Dormancy is not another drive competing for
priority inside that kernel — it's "is this creature even active right
now at all," the same KIND of question `CreatureMarker.is_rooted()`
already answers for a frozen/rooted creature. So it's built at that exact
precedence instead: a new `_step_dormancy()` runs every `_process()`
frame (in both directions, so a dormant creature can also wake), and a
dormant creature early-returns immediately after the existing
`is_rooted()` check — before `_behavior.decide()` is ever called, the
same "total override, no AI decision this frame" precedence rooted/
knockback already have. This never touches the ethogram kernel or its
pinned ladder-order test at all.

Species are gated via a new house-style Dictionary (mirroring the
existing `VENOMOUS_SPECIES` pattern) — `bear` for mammalian hibernation,
`venomous_snake`/`nonvenomous_snake` for brumation. The warmth signal is
this creature's OWN smoothed reading of `ambient_warmth()` (the SAME call
`CreatureMarker` already makes for body-temperature regulation — no
second warmth source), settled via a delta-scaled exponential time
constant (not a fixed-rate-per-call EMA like `AntColony.record_warmth` --
that's called on a fixed real-time refresh interval, already effectively
time-based; this runs once per variable-length frame, so the blend factor
itself must scale with delta to stay framerate-independent) against
`EarthwormPatch.COLD_CUTOFF`, the same real winter-soil reading every
other cold-weather mechanism in this game already keys off. **Deliberate
simplification**: both are modeled as the same observable "inactive and
sheltered" mechanic rather than distinguishing true hibernation from
brumation at the physiological level (e.g. a brumating snake occasionally
rousing on a warm winter day) — the distinction real biology draws is finer than this
pass implements, named here rather than silently assumed identical.

### Blackbird: new species, real population, real diet shift

Blackbird already has full illustrated art and a `FLYER_WORLD_SCALE`
entry (`ambient_flyer_renderer.gd`) — it is commented out of
`BIRD_SPECIES_POOL` pending exactly this work. Rather than reusing the
now-retired flat decorative-cap shape bees used to have, this mirrors
Robin/`SparrowPopulationModel` exactly: a new `BlackbirdPopulationModel`
with carrying capacity from real fruit/invertebrate density, wired into
`EcosystemSimulation`, `ChunkEcologyCatchup.advance`, and
`ChunkSerializer.save_ecology`/`load_ecology` (one more appended float,
the same old-saves-default-0.0 convention robin/sparrow/kingfisher
already use). Real biology: blackbirds are year-round residents that
shift toward fruit when insects thin out in winter — `FlyerDiet`'s
existing multi-food-per-species table gains a season-weighted preference
for blackbird specifically. Robin/sparrow keep their current flat diet
weighting; retrofitting the same shift onto them is a named follow-up,
not done in this pass.

### Grass frog: new species, brumating, decorative-but-real

The most novel "new species from nothing" piece in this doc, and
deliberately the last one built, so every pattern above is proven first.
A frog's real winter strategy (bury into mud/leaf litter, inactive) is
architecturally closer to `EarthwormPatch`'s "activity toggles with cold,
headcount is fixed" shape than to a hunting/grazing `CreatureMarker` or a
population-tracked bird — so it is built as a lightweight, per-chunk
capped presence near water/damp ground (the same proven shape
`AmbientFlyerRenderer` already uses for butterflies), whose
visibility/catchability toggles with the same cold-gate signal
`EarthwormPatch` established, rather than a full predation-fed aggregate
population. Graduating it to a real population later is named as a
follow-up, the same honest scope cut this project already keeps for
other decorative-but-real presences.

## Explicit deferred follow-ups (named, not silently dropped)

- Robin/sparrow winter diet-shift (blackbird gets the mechanism first;
  retrofitting the other two is separable).
- Fish cold-water reduced feeding/metabolism.
- Arctic fox winter coat-color change (needs new art/palette-swap support
  that does not exist yet).
- Grass frog graduating from decorative-but-real to a full predation-fed
  aggregate population.
- Starvation-as-a-death-path for any herbivore.
- Distinguishing true hibernation from brumation at the physiological
  level (occasional warm-day rousing for brumators).

## Status

✅ Ant/honeybee forager cold-gate — `should_forage()` in both `AntColony`
and `BeeColony` now scales `FORAGE_CHANCE` by `dormancy_multiplier_at`,
closing the gap where a fully dormant mound/hive still sent foragers out
at the ordinary rate. New tests confirm cold sends measurably fewer
forage attempts than warm from the identical PixelNoise roll (a
deterministic-by-construction comparison, not a statistical one).
✅ Wild bee die-off / re-hatch — `WildBeePatch` gains `record_warmth`/
`_step_dormancy`: crossing below `EarthwormPatch.COLD_CUTOFF` banks the
current resident count as hidden `brood` and zeroes visible residents
(no foragers dispatched, `should_forage` short-circuits); crossing back
above it re-hatches residents directly from that banked brood, inheriting
last season's real success rather than a fixed reset. Wired into the
real running game via `EarthChunkManager._refresh_bee_warmth`, extended
to also feed `_wild_bee_patches` the same real climate+season signal
honeybee hives already get.
✅ True butterfly season-gated spawn window — `AmbientFlyerRenderer.
spawn_ambient_flyers` gains a trailing `season: String = "summer"`
parameter (default preserves every pre-existing caller's behavior, the
same convention `robin_population`/`sparrow_population` already
established) and a new `BUTTERFLY_ACTIVE_SEASONS := {"spring": true,
"summer": true, "autumn": true}` table, mirroring `CaterpillarRenderer.
ACTIVE_SEASONS`'s exact spawn-time-gate shape. Wired into the real game
via `EarthChunkManager`'s spawn call now passing `current_season()`.
✅ Decomposer "bug" cold-slowdown — `DecomposerMarker` gains a static
`activity_multiplier_for(warmth)` (same `EarthwormPatch.COLD_CUTOFF`/
`MILD_WARMTH` ramp, same `DORMANCY_FLOOR := 0.2` value as AntColony/
BeeColony/WildBeePatch, restated locally since this marker has no shared
economy base class to import it from) applied post-hoc to both wander and
approach movement, the same way toxic-mushroom Weakened already scales
movement without touching the shared `AmbientFlyerMovement` algorithm.
Reads real warmth via the SAME optional `_world.ambient_warmth()` this
marker already has wired for leaf-litter foraging (`EarthChunkManager`
already calls `.setup(self)` on every spawned decomposer) — no new
production wiring needed, only the marker's own behavior changed.
✅ Herbivore winter-forage-realism fix — new `EarthChunkManager.
current_growth_modifier()` (mirrors `current_season()`'s exact shape,
reusing `SeasonCycle.growth_modifier` — the SAME signal `step_tall_grass`
already throttles real grass maturation with). `CreatureMarker._take_
forage_bite`'s `FOOD_UNDERFOOT` case now scales `feed_hunger_relief` by
it instead of granting a flat full day's BMR regardless of season — the
hunger DRIVE is still fully satisfied (the animal did spend a real bout
grazing), but the real caloric/mass yield now honestly reflects how
little is actually growing right now. The highest-leverage change in
this whole doc: every herbivore, present and future, gets real winter
hardship for free, no per-species code.
✅ Squirrel scarcity-driven eat-vs-cache shift (revised scope — see the
mechanism spec section above for why "mouse cache-preference" as
originally worded does not map onto either species' real mechanism).
`SquirrelNutCaching.nut_consumption_chance_for`/`nut_is_consumed` gain an
optional `growth_modifier` term pushing consumption up as real forage
gets scarcer, grounded in this module's own pre-existing "caching becomes
common once hunger is satisfied" reasoning. Mouse gets no analogous
change (no eat-vs-cache branch exists for it); its seasonal hardship
already comes from the shared herbivore forage-realism fix above.
✅ Alpaca as a real, live grazer — wired into every table sheep/goat/camel
already sit in: `CreatureRenderer.HERBIVORE_SPECIES_POOL_BY_BIOME`
(grassland + mountain, real Andean range), `AnimalAnatomy.SPECIES`/
`_PROFILES` (own profile: longer neck than sheep, like a camelid, but no
hump and no headgear), `CreatureMass._REAL_MASS_KG` (65.0kg, a real cited
average), `IllustratedAnimalSprite._SHEETS` (real walk/eat art, measured
independently and landing on the same band positions wolf.png's own
measured entry uses — same generation template), `ProceduralAnimalSprite`
(fallback color + shape family), and `CreatureInfo`'s five stat/diet/
temperament tables. No bespoke seasonal code of its own — inherits
phases 5/6's real winter hardship automatically once spawnable, since
`FOOD_UNDERFOOT` is the shared generic fallback every herbivore already
funnels through. Verified with a real rendered frame (chroma-key cutout
confirmed clean via the existing "no leftover magenta" test), not just a
code trace.
✅ Bear hibernation / snake brumation — implemented as a total-override
early-return at `is_rooted()`'s exact precedence (see this section's own
revised writeup above for why, corrected from the original ethogram-
wiring plan on reading the real decision code), not a new ethogram
intent. New `CreatureMarker._step_dormancy()`, `HIBERNATING_SPECIES`/
`BRUMATING_SPECIES` tables, and a delta-scaled exponential warmth EMA
settling against `EarthwormPatch.COLD_CUTOFF`. `_process()` early-returns
immediately after `is_rooted()` while dormant — no movement, no AI
decision, sprite frozen on its last frame, exactly like being rooted.
✅ Blackbird: real population + real diet shift — new `BlackbirdPopulationModel`
(mirrors Robin/SparrowPopulationModel's exact shape; reuses robin's OWN
worm-density signal rather than inventing a new "fruit density" metric,
since real blackbirds and robins are both worm-hunting thrushes). Wired
through `EcosystemSimulation` (population/capacity/seed/record_bird_birth),
`ChunkEcologyCatchup.advance`, `ChunkSerializer.save_ecology`/
`load_ecology` (9th appended field), and `AmbientFlyerRenderer`
(`BIRD_SPECIES_POOL`/`BLACKBIRD_SPECIES_POOL`/`FLYER_RANGE`/
`MAX_BLACKBIRDS_PER_CHUNK`, both `spawn_ambient_flyers` and
`reconcile_bird_markers`) — the full chain sparrow's own persistence bug
history already proved necessary. Real diet shift: new `FlyerDiet.
eats_now(species, food, season)` — blackbird stops pursuing worms/
caterpillars/ants in winter (still eats fruit), read live in
`AmbientFlyerMarker._look_for_worms`/`_look_for_caterpillars`/
`_look_for_ants` via the world's own `current_season()`. Robin/sparrow
keep their existing flat diet weighting untouched.
⬜ Grass frog: brumating, decorative-but-real presence
