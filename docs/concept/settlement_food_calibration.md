# Settlement food: what a village eats, and what its land gives

*Asked for directly, after a measurement showed the obvious implementation
would make things worse: "Erst Granary-Raten rekalibrieren, dann alles
ableiten" — recalibrate first, then derive everything.*

A village's food model has two halves, and until now **neither was measured
against the other**. Demand was a constant whose own comment admitted it was
unmeasured; supply multiplies one shared rate against three quantities that
are not in the same units. Anything built on top — the roster a village is
founded with, carrying capacity, GROWING/DECLINING, caravans, quests — is
built on that gap.

## What the gap actually is

**Measured** (`tools/probe_village_demand.gd`, real settlement chunks near
Stuttgart). A village of five households draws **20 food units per
assessment** under the old constant. What one producer of each trade really
brings in on the same land, per assessment:

| trade | per assessment | reads |
|---|---|---|
| farmer | 0.16 – 0.27 | `vegetation_density_near`, a 0–1 **density** |
| hunter | 0.94 – 1.63 | `herbivore_population_near`, a **headcount** |
| fisher | 0 … 1481 | `fish_population_near`, a **headcount** |

`NpcProduction`'s own doc comment says why, in as many words: it keeps the
three producers "on one rule rather than three independently-guessed
magnitudes" by applying one `PRODUCTION_RATE_PER_SECOND` to each. One
*rule*, yes — but 0.05 × a density and 0.05 × a headcount are not comparable
numbers, so the resulting magnitudes differ by four orders of magnitude.

The consequence is not academic. A roster rule that staffs food producers
until demand is met would give **all-hunter villages inland** (no farmhouse
anywhere, which is the exact thing that was reported) and **one-fisher
villages** beside water. That is why the roster work stopped and this
started.

## Design pillars

- **One rule for onscreen and offscreen.** `SettlementGranary`'s own header
  already states this for gathering: "an offscreen villager therefore
  gathers at exactly the rate an onscreen one does, because it is one rule
  and not two." The same has to hold for **eating**, and it did not: a
  loaded villager eats on `NpcNeeds`' clock, while an unloaded settlement
  was charged a constant nobody had ever compared to it.
- **Derive, or say plainly that you guessed.** Every number here is either
  read off something the game already simulates, or a test-pinned
  measurement of it. A number that is neither does not get to stay.
- **One number, one meaning.** A quantity of food read as a count of
  assessments is two meanings for one number, and it silently couples a
  recalibration to an unrelated anti-flicker window.
- **Recalibrate before deriving.** Building the demand-driven roster on top
  of an uncalibrated supply model would have shipped a plausible-looking
  rule whose behaviour came from an arithmetic error.

## Real-world grounding

A subsistence village's food economy balances on two rates: how much a
person eats, and how much the land renews. Neither is a stock. A household
does not eat "a quarter of the granary" — it eats a meal, several times a
day, and the granary is what is left over. A forager does not take "a
fraction of the standing herd" either — sustainably, they take a share of
what the herd *replaces*. That is why a standing stock and a renewal rate
are different quantities, and why comparing a grass density with a deer
count only means something once both have been turned into food per unit
time.

## Mechanism

### Demand: what a household really eats

`Ethogram.drive_profile("", "villager")`'s hunger entry is the whole input:

```
rise_seconds 50.0    threshold 0.5    meal 1.0
```

A villager's hunger rises from 0 to 1 over 50 world-seconds and reads as
urgent at 0.5, so a fed villager is hungry again **25 seconds** later, and
one meal (`VillageMarket.FOOD_UNITS_PER_MEAL`, one whole unit) takes it back
to zero. An assessment is `SETTLEMENT_STEP_INTERVAL`, **30 world-seconds**.

Run against the real `NpcNeeds` clock for 200 assessments: **240 meals**,
exactly **1.2 food units per household per assessment**.

`SettlementState.FOOD_PER_HOUSEHOLD` said **4** — a **3.33× overstatement**
of what a village actually eats. It is 1.2 now, written as a literal because
GDScript cannot call into another script from a const initialiser, and
pinned to the real clock by
`test_a_households_draw_is_what_its_own_hunger_clock_really_eats` (which
runs the measurement) and
`test_the_draw_follows_the_villagers_own_hunger_profile` (which ties it to
the ethogram entry, so retuning hunger fails there rather than quietly
leaving the settlement economy priced against the old pace).

**One household is one villager today.** The founding roster gives each
villager a house of their own, so this is a per-villager draw wearing a
per-household name. A house that really held two (`BuildingCatalog.
capacity_of` allows up to three) would need this multiplied by its
residents, and nothing does that yet.

### The coupling that had to go first

`EarthChunkManager.SETTLEMENT_STATUS_DWELL_STEPS` — how many consecutive
assessments a status must hold before it counts as news — **was**
`FOOD_PER_HOUSEHOLD`. A quantity of food read as a count of assessments; its
own comment had to admit in capitals that "MEALS AND ASSESSMENTS ARE NOT THE
SAME UNIT". So recalibrating what a household eats would have silently
retuned an unrelated anti-flicker window.

It is `SETTLEMENT_STATUS_DWELL_DAYS` (2) times the assessments in a
simulated day now: a status that holds through two whole day-night cycles of
the village's own life is the village changing, not the band boundary being
brushed. The value is unchanged at 4 — deliberately, so the decoupling
changed no behaviour and the recalibration can be judged on its own.

## Status

- ✅ **The dwell window is a stretch of world time**, not a food quantity.
  Same value, no behaviour change, no coupling.
- ✅ **`FOOD_PER_HOUSEHOLD` is measured**: 1.2, off the villagers' own hunger
  clock, pinned by two tests — one that runs the measurement and one that
  ties it to the ethogram profile it comes from.
- ✅ **`ASSESSMENT_SECONDS` is declared where it is used and pinned across
  the seam** to `SETTLEMENT_STEP_INTERVAL`, which `SettlementState` cannot
  import (that module is preloaded by the manager, so the dependency runs
  one way only).
- 🚧 **The supply side is still incommensurable.** `NpcProduction` applies
  one rate to a 0–1 density and to two headcounts. Turning all three into
  food-per-second means reading each resource's own **renewal** rather than
  its standing stock — `VegetationGrowthModel`, `HerbivorePopulationModel`
  and `AquaticPopulationModel` each already have one. Not attempted yet;
  this doc exists so the next pass starts from the measurement rather than
  re-deriving it.
- 🚧 **The demand-driven founding roster** waits on that. The rule itself is
  short — staff food producers until the village's own draw is covered, and
  let the land pick the trade — but it is only meaningful once a farmer's
  yield and a fisher's are the same kind of number.
- 🚧 **A household is assumed to be one villager.** True today by
  construction, and nothing enforces it.
