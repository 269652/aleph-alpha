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
- ✅ **The larder is derived from it too** (2026-09-20). A village's
  minimum stock (what the cart never sells below) is this draw over the
  cart's cover in assessments, and a household's "full larder" is this
  draw over a lived day — `FOOD_STOCK_PER_HOUSEHOLD_TARGET` had been left
  at one assessment of the *old* draw. See
  [village_economy_balance.md](village_economy_balance.md).
- ✅ **`ASSESSMENT_SECONDS` is declared where it is used and pinned across
  the seam** to `SETTLEMENT_STEP_INTERVAL`, which `SettlementState` cannot
  import (that module is preloaded by the manager, so the dependency runs
  one way only).
- ✅ **One currency.** `vegetation_density_near` returns a per-CELL MEAN
  while the other two return chunk TOTALS, and one rate was applied to all
  three alike. `NpcProduction.standing_food` multiplies the mean back up by
  `CELLS_PER_REGION`, so all three are chunk totals in food units. That they
  ARE the same unit is not assumed: `NpcEconomy._deplete_continuous` already
  spends one unit of vegetation density, one herbivore or one fish per food
  unit gathered, so the game's own accounting says a cell's density unit, a
  deer and a fish are each one food unit.
- ✅ **Each resource is scaled by its own renewal.** The single invented
  `PRODUCTION_RATE_PER_SECOND` (0.05, "chosen for reasonable pacing" by its
  own comment) is gone. A forager sustainably takes a share of what the
  resource REPLACES, and all three are logistic populations whose growth
  rate per day is already written down —
  `VegetationGrowthModel.GROWTH_PACE_PER_DAY`,
  `HerbivorePopulationModel.GROWTH_RATE_PER_DAY`,
  `AquaticPopulationModel.GROWTH_RATE_PER_DAY`. A logistic population's
  **maximum sustainable yield is r·K/4**; textbook, not picked here. The
  standing stock stands in for K because `EcosystemSimulation` seeds a
  region at equilibrium, and a worked-down region therefore yields less,
  which is the right direction and is exactly what land health already reads.
- ✅ **A producer reaches part of a region, not all of it.** Without this
  the drip handed ONE villager a whole 1024-cell chunk's sustainable yield:
  measured, 1152 food per work block against the 225 a real worked field
  yields, so a farmer was five times better off not farming. Each trade's
  reach is the one this codebase already measured for that trade's own real
  work — `VillageFarm.FIELD_REACH_TILES` for a farmer, `HuntableQuarry.
  SEARCH_RADIUS_PX` for a hunter, `NpcMarker.CAST_DISTANCE_PX` for a fisher
  — as a disc, capped at the region. **Two independent anchors agree**: at
  the farmer's own field reach the drip lands at about a seventh of a real
  field's 225 per work block, which is the "about eight times the drip it
  replaces" [village_farms.md](village_farms.md) already stated as the
  design intent before any of this.

**Measured after both halves** (`tools/probe_village_demand.gd`, the same
real chunks), per assessment against a draw of 6 for five households:

| village | farmer | hunter | fisher |
|---|---|---|---|
| (660,136) | 0.219 | 0.021 | 0.000 |
| (654,137) | 0.228 | 0.022 | 3.029 |
| (659,138) | 0.320 | 0.031 | 1.764 |
| (649,153) | 0.185 | 0.018 | 0.000 |

Comparable at last, and the ratios say something true: a farmer out-forages
a hunter about ten to one on ordinary grassland, and a fisher beats both
where there is real water and yields nothing where there is not.

🚧 **A hunter cannot be a village's staple**, and that is a finding rather
than a tuning: `EcosystemSimulation.herbivore_capacity_at` feeds
`HERBIVORES_PER_VEGETATION_UNIT` (20) a per-cell MEAN density, so a whole
chunk supports about **one deer**. That is the same class of unit error
fixed above, one level down — but `HERBIVORES_PER_VEGETATION_UNIT` was
calibrated against the mean, so correcting the input means retuning the
constant by ~1000× and moving every creature spawn, predator population and
hunt in the game. Deliberately not attempted here.

**The drip is a supplement; real work is what feeds a village.** At 0.22 per
assessment against a draw of 6, no amount of foraging feeds five households
— and that is correct. A real worked farmhouse yields ~225 per work block,
about 7.5 per assessment, which covers six. That is the number the founding
roster reasons about, not the drip.

## The roster, finally driven by demand

`SettlementFoodDemand` (deliberately not `SettlementDemand`, which is City
Hall's own recipe-graph step and has nothing to do with food):

- **How many.** `producers_needed(household_count)` is the village's own
  subsistence draw over what one producer's real work brings in
  (`VillageFarm.FIELD_YIELD_PER_WORK_BLOCK`, measured by a real villager
  over a real field, not described in a comment). A founding five needs
  **one** — the old hardcode's answer, for the first time for a reason —
  and a village that outgrows one field needs a second.
- **Which trade.** `trade_for(region)` is whichever of farmer, herbalist and
  fisher yields most *here* — only askable at all because the three are
  finally the same kind of number. Land with real water is worked by a
  **fisher**, who digs and stocks a pond; ordinary grassland by a **farmer**,
  who raises a farmhouse.
- **A hunter is not one of them**, and that is a measurement rather than a
  preference. A hunter brings in about **0.02** food units an assessment
  against a draw of **6** — a whole chunk supports roughly one deer (see the
  honest gap about `HERBIVORES_PER_VEGETATION_UNIT` above). Counting one
  while sizing the roster against a *farmhouse's* yield says a village is
  fed when it is not. Hunting stays a real occupation and a real way to eat;
  it is not what a village is founded on.

  **How far that reaches**, measured over 4000 raw rosters
  (`tools/probe_roster_food_trades.gd`): **93.3 %** already roll a farmer, a
  herbalist or a fisher and are left exactly as they rolled; **5.2 %** would
  have been read as fed on a hunter alone and now get a conscript; **1.4 %**
  roll nobody at all and always did. So conscription touches about one
  village in fifteen, and the hunter rule about one in twenty.

  *Correction to an earlier note in this file:* the village at (657,145) was
  cited as evidence for this and is not. Its `wanted_by=0` farmhouse is
  explained by its producer being a **fisher**, who works a pond rather than
  a farmhouse — correct behaviour, not the fault. The rule stands on the
  0.02-against-6 measurement.
- **Which villagers.** Conscription comes off the END of the roster and
  only takes villagers who are not already feeding the village, so it stays
  deterministic per chunk and leaves the earlier founders exactly as they
  rolled.

The region every caller reads is the **seeded** one
(`EarthChunkManager.seeded_region_for_chunk`), a pure function of terrain:
the village is founded with the same roster on every visit, and the live
ecology cannot make a roster drift with the weather.

🚧 **A village founded before this keeps its buildings but not its roster.**
Buildings are persisted and rosters are not, so an existing save's farmhouse
may now belong to a village whose food producer the land made a fisher.
Nothing repairs that; the next farmhouse the village raises will match.
- 🚧 **A household is assumed to be one villager.** True today by
  construction, and nothing enforces it.
