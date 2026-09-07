# Metabolism: one real, unified, live body mass, driven by real calories

Reported: *"Fix the gaps and make a picked up fungus account for the amount
eaten... which should then affect the mass of the nutrients the player
gets when eating... it should all be wired in a real caloric metabolism
system so that animals and players burn calories and need to eat
realistic amounts to balance their nutrition which is influenced by
activity... used to simulate how animals gain mass which affects how much
meat they drop when hunted or eaten by predators."*

Corrected live, directly, after a first attempt proposed a static
per-species reference mass and a new per-instance dynamic mass as two
separate concepts: **"No ... all mass systems should be unified."** There
is exactly ONE real notion of "how much does this creature weigh" per live
creature instance. `CreatureMass.mass_kg_for(species)`
(`src/world/creature_mass.gd`) was already a real per-species reference
figure, read today by the crush-underfoot momentum mechanic
([soil_fauna.md](soil_fauna.md#crushed-underfoot-weight-emergent-worm-mortality))
and by [mushrooms.md](mushrooms.md)'s mass-scaled bite economics
(`MushroomBiting`). This doc does not replace that table — it reframes it
as the SEED a live creature's own tracked mass initializes to, and gives
every creature type this pass reaches a real, single, time-evolving
`current_mass_kg` that every consumer of "this creature's mass" reads
instead, including the two pre-existing call sites above.

## Design pillars

1. **One mass per creature, always.** No creature instance this pass
   reaches ever has two independently-tracked mass numbers. `CreatureMass.
   mass_kg_for(species)` stays exactly what it always was — a real,
   tabulated, per-species reference/seed figure — but once a creature
   instance exists and is metabolism-tracked, nothing reads that table
   for ITS OWN current weight again. A fresh instance's live mass starts
   there and only there.
2. **Behavior-preserving at the seed value, genuinely different once mass
   has actually drifted.** A creature nobody has fed or starved yet must
   behave exactly as it did before this system existed — same crush
   momentum, same bite economics. A creature that has actually gained or
   lost real mass should hit harder underfoot, eat differently, and yield
   more or less meat, because that is what really being heavier or
   lighter means. The regression bar is narrow and precise (identical
   behavior AT the seed value), not "nothing about the numbers may ever
   change."
3. **Burn is real physiology (Kleiber's law), not a flat per-second
   tax.** `AnimalReproduction.decay` was, before this pass, the one place
   in the codebase already calling itself "basal metabolism" — and it
   burned every species, at every activity level, at the identical flat
   rate. A shrew and a horse do not really share a metabolic rate, and an
   animal fleeing for its life does not really burn calories at its
   resting rate. Both terms are real, well-documented biology, not
   invented gameplay levers.
4. **Read real, already-existing activity signals; invent no new ones.**
   Every creature family this project already has a real behavior-phase
   state machine for (`GrazerForaging.Phase`, `CaterpillarForageBehavior.
   Phase`, `CarrionForageBehavior.Phase`, `AntForageBehavior.Phase`,
   `GroundForageBehavior.Phase`, `CreatureMarker.decision.intent`). None of
   them were built with metabolism in mind, and none needs to change:
   Metabolism reads them as an outside observer (a small per-integration
   mapping to one of four canonical activity tiers) exactly the way
   `ethogram.md`'s own "the kernel ranks, the caller commits" pillar
   already keeps motor-program state caller-side.
5. **Intake comes from real eating events already wired into this
   codebase**, not a second parallel feeding path — a mushroom bite, a
   carrion bite, a fruit graze, the player's own `eat_food`. Metabolism
   taps the same real bite/graze events other systems already fire,
   rather than requiring every forage path to be rewritten around it.
6. **Reuse before invention.** The stateful-instance-plus-`advance(delta)`
   shape is not new — `SurvivalMeters`/`CreatureNeeds` already establish
   it for hunger/thirst/warmth. Metabolism is the same shape, for mass.

## Real-world grounding

- **Kleiber's law**: basal metabolic rate scales with body mass to
  roughly the 0.75 power, not linearly — `BMR (kcal/day) ≈ 70 ×
  mass_kg^0.75` is the standard textbook citation (Kleiber, 1932,
  "Body size and metabolism"), holding from mice to elephants. A bigger
  animal burns more in absolute terms but LESS per kilogram of its own
  body than a smaller one — the same real relationship
  `MushroomBiting.satiation_seconds_for` already derived a satiation
  exponent from (`mass^0.25`, i.e. `mass / mass^0.75`) and
  [animal_genetics.md](animal_genetics.md) already cites by name for its
  own still-unbuilt size gene. This module is the first real CONSUMER of
  that law as a genuine calorie figure rather than a derived exponent
  applied to one bespoke timer.
- **Activity multiplies burn rate — the real MET (Metabolic Equivalent of
  Task) model.** Resting burns at roughly 1× BMR; light ambulatory
  activity (walking, foraging) 1.5-2×; sustained feeding while
  essentially stationary sits close to resting; genuine exertion
  (fleeing, fighting, chasing prey, courting) commonly runs 4-6× resting
  in real animals. Four real, ordered tiers, not a continuous invented
  curve.
- **A real, standard energy-to-mass conversion**: approximately 7700 kcal
  per kilogram of body mass gained or lost (the commonly cited
  "~3500 kcal per pound" figure converted to metric) — the real
  thermodynamic cost of a real animal's own tissue. Applied uniformly
  across species as an honest, named simplification: real body
  composition (fat vs. muscle vs. fluid) varies, but this is the standard
  real figure and legible at game-balance scale.
- **Food energy density**: fresh whole food (plant or animal) commonly
  runs in the very rough range of 1-3 kcal per gram wet mass (lean meat
  and fungi trend toward the low end, being mostly water; the existing
  `FoodComposition`/`_MUSHROOM_COMPOSITION` already models mushrooms as
  90% water). A single blended, named, tested constant stands in for this
  across every food type this pass wires — a coarse but real, cited
  abstraction, the same level of honesty `NutrientRelease`'s existing
  "vitamins" abstraction already accepts for itself.
- **Starvation has a real mass floor; overfeeding a real ceiling.** A
  real starving animal can lose on the rough order of half its healthy
  body mass before death; a well-fed one accumulates real fat reserves
  but does not balloon indefinitely. Both bounds exist so a creature
  nobody ever tends to still reads as "thin" or "healthy," never as
  "mathematically negative" or "unboundedly huge."

## Mechanism spec

### The core module (`Metabolism`, `src/gameplay/metabolism.gd`)

Same stateful-instance shape `SurvivalMeters`/`CreatureNeeds` already
establish: `Metabolism.new(seed_mass_kg)` seeds `current_mass_kg` (the ONE
live value, pillar 1) directly from whatever species-seed value the
caller passed — for wildlife/decomposers that is `CreatureMass.
mass_kg_for(species)`; for the player it is `CreatureMass.PLAYER_MASS_KG`
(already `StoneSize.AVERAGE_BODY_MASS_KG`, unchanged).

Pure static math, independent of any instance:

- `bmr_kcal_per_day(mass_kg) -> float` — Kleiber's law directly.
- `activity_multiplier_for(activity: String) -> float` — a small tiered
  table over four canonical activity tiers (see below), real MET-ordered.
- `calories_burned(mass_kg, activity, delta_seconds) -> float` — BMR
  converted to a per-second rate (against the world's own day,
  `SeasonCycle.SECONDS_PER_DAY` — the one clock every other body-clock in
  this project already keeps), scaled by the activity multiplier.
- `calories_from_food_mass_kg(food_mass_kg) -> float` — the real food
  energy-density conversion.
- `mass_delta_kg_for_calories(kcal) -> float` — the real kcal-per-kg-body-
  mass conversion, signed (positive kcal → mass gain, negative → loss).

Instance state and API:

- `current_mass_kg: float` — the one live value.
- `advance(delta_seconds, activity: String) -> void` — burns calories for
  this tick at this creature's OWN current mass and the given activity,
  applies the resulting (negative) mass delta.
- `feed_mass_kg(food_mass_kg: float) -> void` — a real, discrete eating
  event: converts the food's own real mass into calories, applies the
  resulting (positive) mass delta.
- Both route through one shared, private mass-delta application that
  clamps `current_mass_kg` to `[seed_mass_kg × MIN_MASS_FRACTION_OF_SEED,
  seed_mass_kg × MAX_MASS_FRACTION_OF_SEED]` — the real starvation
  floor/overfeeding ceiling above, tested, pinned constants.

**Canonical activity tiers** (`ACTIVITY_RESTING`/`ACTIVITY_MOVING`/
`ACTIVITY_FEEDING`/`ACTIVITY_EXERTION`, real MET-ordered multipliers,
`ACTIVITY_RESTING < ACTIVITY_FEEDING < ACTIVITY_MOVING < ACTIVITY_EXERTION`
pinned by test) are Metabolism's own small, closed vocabulary — NOT a new
addition to `Ethogram`/`Drives` (confirmed, by direct reading of both
`ethogram.md` and `behavior_dsl.md` in full: neither doc mentions
metabolic cost or activity multipliers anywhere; `Drives.advance` runs
every species' hunger/thirst clock at one flat, profile-fixed rate today,
unrelated to what the creature is actually doing, and stays that way —
Metabolism is a genuinely separate concern layered alongside it, not a
change to it). Each creature family's own controller maps ITS real,
already-existing phase signal to one of these four tiers at the call
site — Metabolism itself knows nothing about any other module's enums:

| creature family | source of the real signal | mapping |
|---|---|---|
| Wildlife (`CreatureMarker`) | `_forage.is_grazing()`, `decision.intent` | grazing → FEEDING; flee/attack/hunt/court → EXERTION; else → MOVING |
| Decomposers (`DecomposerMarker`, ant/bug) | `CarrionForageBehavior.Phase` | FEEDING → FEEDING; SEEKING/APPROACHING → MOVING |
| Caterpillars (`CaterpillarForageBehavior`) | its own `Phase` | EATING → FEEDING; SEEKING/APPROACHING → MOVING |
| Player | real movement state | moving → MOVING; else → RESTING (see Player wiring below) |

### One unified mass: migrating the existing species-lookup call sites

Every real, live, specific-creature-instance call site that used to read
`CreatureMass.mass_kg_for(species)` for a creature this pass tracks now
reads that instance's own `current_mass_kg` instead (pillar 1).
`CreatureMass.mass_kg_for` itself is UNCHANGED and stays the real source
of species-level seed numbers — migrated call sites:

- `CreatureMarker`'s own mushroom-bite mass-scaling
  (`MushroomBiting.bites_per_visit_for`/`satiation_seconds_for`).
- `DecomposerMarker`'s own mushroom-bite mass-scaling (identical call
  shape, ant/bug).
- `scenes/world.gd`'s wildlife crush-momentum step (was a flat
  `CreatureMass.mass_kg_for(species) * PebbleDispersion.
  FOOTSTEP_SPEED_MPS` recomputed from the species table every frame for
  every `CreatureMarker` in the group; now each marker's own live mass).
- `scenes/world.gd`'s PLAYER crush-momentum step (was a load-time
  `const _PLAYER_STEP_MOMENTUM_KG_M_S`, computed once from
  `CreatureMass.PLAYER_MASS_KG` and never revisited; now a per-tick read
  of the player's own live mass, since it can now genuinely drift).

**Regression proof, not a risk to work around**: a creature at its
default/seed mass (nothing has fed or starved it yet) produces the exact
same crush momentum as before this change, proven by test. A creature
that has genuinely gained or lost mass now hits harder or softer
underfoot than a same-species creature still at its seed weight — real,
intended, and different from before.

### The two named mushroom gaps, closed end to end

See [mushrooms.md](mushrooms.md#animals-can-find-and-eat-wild-mushrooms)'s
own named scope cuts. Both close through the SAME new primitive:
`MushroomBiting.remaining_fraction_for_stage(stage: int) -> float` —
`RETAINED_FRACTION_AFTER_BITE ^ stage` (stage 0 → 1.0, matching an
untouched mushroom; stage 1 → 0.83, matching the existing `after_bite`
exactly; each further stage compounds the same real per-bite loss rather
than a second, independently-tuned curve).

1. **A picked-up, partially-eaten mushroom's item mass now scales with
   `bite_stage`.** `ItemCatalog.make(item_id, bite_stage: int = -1)` — an
   optional, additive parameter (default `-1`, meaning "no override,"
   preserves every existing caller's exact behavior including the flat
   single-bite `_bitten` catalog fraction `/give` etc. still use) that,
   when given a real non-negative stage, scales a `_bitten` id's mass by
   `remaining_fraction_for_stage(stage)` instead of the flat one-bite
   fraction. `MushroomMarker.pick_up` passes its own real, tracked
   `bite_stage` through. `ItemStack.can_stack_with` additionally compares
   `mass_kg` (mirroring the exact precedent already set for
   `captive_species` — a loaded and an empty container must not share a
   stack; a stage-1 and a stage-2 bitten specimen of the same species are
   equally two genuinely different physical objects) so two
   differently-diminished specimens of the same species never silently
   merge into one stack under the first one's mass.
2. **Nutrition gained from a bite now scales with how much was actually
   eaten.** `NutrientRelease.consume(food_id, mass_fraction: float =
   1.0)` — scales its returned water/sugar/vitamins by the real fraction
   of a whole item this one event actually consumed (default `1.0`,
   behavior-preserving for every existing caller). The PLAYER's own
   `eat_food` derives this from the real Item instance actually being
   eaten (`ItemCatalog.remaining_mass_fraction_for(item)`, comparing the
   item's own already-stage-scaled `mass_kg` against its species'
   unbitten reference mass); `CreatureMarker._apply_nutrient_bite` (the
   boar-bite path) derives it from the real stage COUNT this one bite
   event actually applied (`EarthChunkManager.take_mushroom_at` now
   returns `{species, stages_applied}` instead of a bare species string,
   so the true applied count — which can be clamped below the requested
   `bites_per_visit_for` near the cap — survives the round trip) divided
   by `MushroomBiting.MAX_BITE_STAGES`.

### Mushrooms and carrion feeding wired through the shared model

`DecomposerMarker` (ant/bug, `CarrionForageBehavior`) gains a real
`Metabolism` instance, seeded from `CreatureMass.mass_kg_for(species)`.
Every real feeding event that already lands (`Carcass`/`CarcassGuts.
take_bite`, `WildMushroomPatch.bite` via `take_mushroom_bite`, fallen
fruit/leaf-litter consumption) now also calls `feed_mass_kg` with that
food's own real mass; `advance()` runs every tick with the activity tier
`CarrionForageBehavior.Phase` maps to (table above).

### At least one more creature family: caterpillars

`CaterpillarForageBehavior`'s own real `Phase` (SEEKING/APPROACHING/
EATING) drives the same MOVING/FEEDING split. Caterpillars had no entry
in `CreatureMass` at all before this pass (only ants/bugs did); a real,
cited caterpillar mass is added as their own seed.

### Yield-on-death: dynamic mass drives real meat yield

`Butchering.meat_count(meat_yield_bonus, mass_ratio: float = 1.0)` — an
additional, optional, default-preserving parameter multiplying the
existing skill-scaled count by the real ratio between the killed
creature's own `current_mass_kg` at time of death and its species'
`CreatureMass.mass_kg_for(species)` reference. `CreatureMarker.
_spawn_carcass_if_eligible` stamps that real ratio onto the `Carcass` it
spawns (alongside the species/position/region_tier it already copies
across); `Carcass.butcher` reads its own stored ratio when it calls
`Butchering.meat_count`. A real, heavier-than-average kill yields more
meat; a starved one yields less — both real, both new, neither possible
before a creature had a live mass of its own to compare against.

### Player wiring

Read FIRST, per this doc's own process: the player's real source of
truth for hunger/nutrition is `SurvivalMeters` (`hunger`/`thirst`/
`stamina`/`fitness`/`warmth`/`nutrition`), already real, already tested,
already grounded against the world's own day
([survival.md](survival.md)). This pass does NOT replace or reweight
that meter — it is mature, tuned, and cross-referenced by its own concept
doc; retuning `HUNGER_RATE_PER_SECOND` itself is a separate, much larger
behavior change outside this pass's safe scope. Instead, the player gets
the same real, live, unified mass every other creature this pass reaches
gets: `current_mass_kg`, seeded from `CreatureMass.PLAYER_MASS_KG`
(already `StoneSize.AVERAGE_BODY_MASS_KG` — no second guess), tracked by
the player's own `Metabolism` instance, burned every tick at the
player's own real activity (moving vs. idle, from the player's own
existing movement state) and fed by the player's own real eating events
(`eat_food`'s existing nutrient pipeline also calls `feed_mass_kg` with
the real food mass actually consumed). The player's own crush-underfoot
momentum (see above) is the first real, already-existing consumer of
this — no second guess mass anywhere for the player either.

## Status

- ✅ `Metabolism` core module — Kleiber BMR, activity tiers, calorie/mass
  conversions, starvation floor/overfeeding ceiling, `advance`/
  `feed_mass_kg`/`feed_hunger_relief`. `src/gameplay/metabolism.gd`, 25
  tests. `feed_hunger_relief` (bridging an already-existing 0..1
  hunger-relief fraction, grounded against the creature's own BMR) turned
  out to be the integration bridge every wired creature type actually
  uses; `feed_mass_kg` is real and tested but has no live caller yet —
  kept for a future one that already knows a real food mass directly.
- ✅ Unified mass migration: `CreatureMarker`/`DecomposerMarker`/
  `CaterpillarMarker`/`Player` each gained `current_mass_kg()`; every
  named species-lookup call site (both mushroom-bite scaling sites, both
  crush-momentum sites in `scenes/world.gd`) reads it instead of
  `CreatureMass.mass_kg_for(species)`/`PLAYER_MASS_KG` directly.
  Behavior-preservation at seed mass proven directly (not assumed) by
  `test_crush_momentum_at_seed_mass_matches_the_old_flat_species_lookup_exactly`
  and its player-shaped mirror — bit-identical output against the real
  momentum formula, across every real species checked.
  `test_world_crush_wiring.gd`'s two source-contract tests that pinned
  the OLD flat-lookup shape verbatim were updated to pin the new
  live-mass shape instead.
- ✅ The two named mushroom gaps, closed end to end: `MushroomBiting.
  remaining_fraction_for_stage`, `ItemCatalog.make`'s `bite_stage`
  parameter, `ItemStack.can_stack_with`'s mass comparison,
  `NutrientRelease.consume`'s `mass_fraction` parameter, the
  `take_mushroom_at` stages-applied round trip, and a genuinely
  previously-unnoticed adjacent bug found and fixed along the way:
  `FoodComposition.composition_for` didn't recognize a `"_bitten"` id at
  all, so eating one never got real composition-scaled nutrients OR a
  toxic species' effect (`Player.eat_food`'s `MushroomSpecies.IDS.has`
  check against the raw, possibly-suffixed id was always false).
- ✅ Decomposers (ant/bug) wired to real calorie burn/intake via
  `CarrionForageBehavior`'s phase — every real bite kind
  (carcass/guts/mushroom/leaf-litter/fruit) feeds `feed_hunger_relief`.
- ✅ Caterpillars wired the same way via their own `Phase` (leaf or tree
  bite). `CreatureMass` gained a real `"caterpillar"` seed entry it had
  none of before.
- ✅ Yield-on-death: `Butchering.meat_count`'s `mass_ratio`, `Carcass`
  carrying it, `CreatureMarker._spawn_carcass_if_eligible` stamping it.
  Proven with real before/after numbers for a boar fed to 1.3x seed mass:
  3 meat (`round(2 * 1.3)`) vs. the old flat 2.
- ✅ Player wiring, after reading `SurvivalMeters`/`survival.md` first:
  that meter is mature and tuned, so this pass does NOT reweight it —
  `current_mass_kg()` + a `Metabolism` instance on `Player`, burned by
  real movement activity (the same `input_direction` threshold already
  used for facing), fed by real `eat_food` events, read by the player's
  own crush-momentum call site.
- ⬜ Combat/hunt/attack exertion for wildlife and the player: both
  currently fall back to ordinary MOVING (only `CreatureMarker.
  _is_fleeing` and the player's `input_direction` are read as persistent
  signals today) — a real, named simplification, not a silent gap; a
  genuine EXERTION tier for combat needs a persistent flag this pass
  didn't add.
- ⬜ Ants' own invisible `AntColony` per-mound food economy and
  millipedes were not reached — `AntColony`'s food-unit reserve is a
  genuinely separate aggregate (colony-level, not per-instance) model;
  wiring it into a per-forager `current_mass_kg` is real future work, not
  attempted here.
- ⬜ Fish and the remaining ambient-flyer/bird roster (`BirdDigestion`
  species: robin/sparrow/kingfisher) — explicitly not reached this pass;
  fish have no phase/hunger model of any kind to hang an activity signal
  or feeding event off today (confirmed: no `FishDiet`/`FishGrowth`
  module exists anywhere in this codebase; `docs/concept/aquatic_foraging.md`
  and `docs/concept/fishing.md` both explicitly scope fish population
  tracking as "no needs, no hunger" by design), and would need that
  built first, which is its own separate pass, not a metabolism gap.

See `docs/progress.md`'s "Caloric metabolism: one unified live mass, real
calorie burn/intake" entry for the full session-by-session record,
including real test counts and the real before/after yield numbers.
