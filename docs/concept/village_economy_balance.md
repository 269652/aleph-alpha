# Village economy balance: wages, labour-priced exports, and a larder that is kept

Reported with the town panel open, in one breath: *"The whole economy is
not properly balanced... Farmers produce herbs, but all houses are at 0%
herbs... Also the city makes not enough money to pay each worker's income,
so the price for goods when selling to the travel merchant needs to be
based on per capita work output. The city should generate double the income
through export goods than it costs to pay all workers. Also the city should
always keep a minimum stock; enough to keep feeding the population."* And,
a moment later: *"Distribution of food to houses is also only at 60%, which
should saturate at 100% to get happy villagers."*

Four complaints, and every one of them is a real, measurable fault in how
the pieces that already exist are joined. None of them needs a new
building, a new good or a new villager. This doc is the spec for joining
them properly, and it is grounded in a measurement rather than in the
panel.

## What was measured

`tools/probe_village_economy.gd`, on the first real village east of Berlin
(chunk (678,128): ten households — two farmers, a herbalist, a fisher, two
carters, a lumberjack, a hunter, a guard, a nurse — with a farmhouse, a
fisher's hut, a sawmill, a warehouse and a hall), 1200 simulated seconds,
sampled every 150:

| seconds | herb on the stall | herb on the shelves | herb satisfaction | food satisfaction | food on the shelves | purse | wallets | broke | worst need |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|
| 150 | 0 | 13 | 0.00 | 0.33 | 15 | 0.0 | 0 | 10 of 10 | income |
| 300 | 3 | 21 | 1.00 | 0.57 | 23 | 0.0 | 0 | 10 of 10 | income |
| 450 | 0 | 22 | 0.00 | 0.55 | 24 | 0.0 | 0 | 10 of 10 | income |
| 600 | 0 | 23 | 0.00 | 0.90 | 25 | 20.0 | 0 | 10 of 10 | income |
| 750 | 0 | 43 | 0.00 | 1.00 | 45 | 1.0 | 0 | 10 of 10 | income |
| 900 | 0 | 21 | 0.00 | 0.53 | 23 | 1.0 | 0 | 10 of 10 | income |
| 1050 | 0 | 23 | 0.00 | 0.78 | 25 | 19.0 | 0 | 10 of 10 | income |
| 1200 | 0 | 17 | 0.00 | 0.42 | 19 | 1.0 | 0 | 10 of 10 | income |

Read across the columns, the four complaints are three faults:

1. **The herbs are real and nobody can reach them.** The herbalist's crop
   sits on the farmhouse shelf — 13, 21, 43 units — and the estate draw
   (`EarthChunkManager._draw_estate_basket`) reads only the two markets. The
   one sample where three herbs happened to be on the stall reads
   `herb 1.00`; every other sample reads `0.00`. A household's station
   basket asks for a *tenth* of a herb a day; a village holding forty of
   them is not short, it is looking in the wrong cupboard. This is the same
   fault `SettlementFood` and the merchant were each cured of
   ([traveling_merchants.md](traveling_merchants.md), "a merchant buys the
   whole village, not one of its cupboards"), one reader further along.
2. **The larder is sold down to seventy-five seconds of food.** The food on
   the shelves saws between 45 and 19: it climbs, the cart comes and takes
   twenty, the village eats. What the cart leaves is exactly the reserve —
   23, 25, 25 — and that reserve was `EstateConsumption.demand_for(census,
   2.5 days)`, a basket priced on the **3600-second economy day** handed a
   cover measured in **60-second lived days**. Ten households really eat
   `FOOD_PER_HOUSEHOLD` (1.2) a piece per 30-second assessment
   ([settlement_food_calibration.md](settlement_food_calibration.md)), so
   25 units is two assessments. The food *satisfaction* swings with it —
   0.33 to 1.00 and back — which is the "only 60%" the report saw: not a
   village short of food, a village whose food is carried off every few
   minutes and whose "full larder" line (`FOOD_STOCK_PER_HOUSEHOLD_TARGET`,
   4.0) is a number left over from before the draw was recalibrated.
3. **Twenty gold a visit, and it is gone the same tick.** The purse reads
   0 → 20 → 1 → 1 → 19 → 1. A visit pays `CART_CAPACITY` (20) units at
   `LOG_PRICE` (1); ten hungry villagers each draw one subsistence wage (2)
   and spend it on a meal, and the wallets read 0 again. Nobody is ever
   *paid* — the only wage in the game is the meal a villager cannot afford
   — so the income need (`HouseholdWellbeing`, ten meals in hand) can never
   rise off the floor, and `worst: income` is permanent.

## Design pillars

1. **A worker is paid for a day's work, not fed when found starving.** The
   subsistence wage stays as the safety net it is; a *living* wage is what a
   household earns, every assessment, out of the village purse.
2. **The world pays for a village's surplus what that surplus cost in
   labour — twice over.** The merchant's unit price is derived from the
   village's own per-capita work output, so a village that exports what it
   makes earns `EXPORT_INCOME_TO_WAGE_BILL_RATIO` (2) times its wage bill.
   That margin is the whole request, stated as a number the code holds.
3. **A village keeps the food its people eat until the cart comes again.**
   The minimum stock is the real draw over the real cover, and nothing —
   not the cart — sells below it.
4. **A household eats from the village, not from one of its cupboards.**
   Every shelf its people can eat off is a shelf its baskets are drawn
   from.
5. **Gold still has one faucet.** Every mechanism here is either the
   merchant's sale or a transfer that debits exactly what it credits
   ([traveling_merchants.md](traveling_merchants.md), "the merchant is the
   ONLY faucet"); the guard test that scans the source for a third faucet is
   unchanged.
6. **Every number is derived or test-pinned**, per this project's rule.
   The wage is meals at the market's own price; the cover is the cart's own
   cadence; the reserve is the granary's own draw; the price index is an
   arithmetic identity over the wage bill.

## Real-world grounding

- **The labour theory of value is the oldest price theory there is**, and
  the one a subsistence economy actually runs on: a good is worth the
  labour that made it, and an itinerant buyer who wants the village to
  keep producing pays enough that its workers can live on the sale. What
  the merchant of [traveling_merchants.md](traveling_merchants.md) paid
  before was a *farm-gate* price — a unit of labour's product for a coin —
  and that is the right *relativity* between goods (a beam is still six
  logs) but not a level a village can pay wages from.
- **A village's stock is a store against the interval between sales.** A
  household that sells at market once a fortnight keeps a fortnight of
  bread. The reserve is not a hoard; it is the interval, in food.
- **Cash was short, wages were real.** Pre-industrial villagers were paid
  in coin for a day's labour and bought their bread with it; the bad weeks
  were the ones nobody bought anything. That is exactly the shape below:
  lumpy income from the cart, a steady wage out of the purse, and a purse
  that can run dry.

## Mechanism 1 — The living wage

`VillageWages.keep_per_assessment()` is what one household's meals cost
over one settlement assessment: `SettlementState.FOOD_PER_HOUSEHOLD`
(1.2, measured) at `VillageMarket.VILLAGE_LOCAL_FOOD_PRICE` (2) — 2.4 gold.
Anchored to the assessment, the clock the draw itself was measured on, so
no day-length constant enters.

`VillageWages.living_wage_per_assessment()` is the keep times
`LIVING_WAGE_KEEP_MULTIPLE` (2): *a day's work earns a day's keep and as
much again to put by.* The multiple is pinned by the property it produces
rather than by its value — a paid household that buys its meals saves
exactly its keep — and by what that does to the readout the report was
looking at: `HouseholdWellbeing.INCOME_MEALS_FOR_FULL` (ten meals) is
reached from an empty wallet inside a bounded number of lived days.

`VillageWages.wage_bill_for(household_count, assessments)` is the whole
village's bill. Every household is a worker — one villager to a household,
every villager with a trade — so the bill is households times the wage.

**The payment is a transfer.** Every assessment,
`EarthChunkManager._pay_village_wages` moves whole coins from the purse
into household wallets through `NpcEconomy.pay_wage_from_purse`, which
debits the purse and credits the wallet in one call, the same "cannot
half-happen" shape `WagePayment.pay` keeps. Rules, each deliberate:

- **Whole coins, remainder carried** per settlement — a Wallet is integer
  gold and a wage is 4.8 a step. The same idiom the tax already runs on.
- **The poorest are paid first**, deterministically (balance, then
  household id): when the purse cannot cover the whole bill, it is the
  household with nothing in hand that gets the coin.
- **A village pays what it has, not what it owes.** An unpaid wage is not
  banked as arrears. The tax already refuses to keep a debt a household
  can never pay; a debt the *purse* can never pay is the same fiction from
  the other side.
- **Paid after the cart, in the same assessment**, so gold that arrives
  this tick is in a wallet this tick.
- **Loaded or not.** The purse an unloaded settlement trades into is the
  purse its wages come out of, the same object `_step_merchant_visits`
  already pays — one rule onscreen and offscreen.

## Mechanism 2 — The merchant pays labour value

Asked for in as many words: *the price for goods when selling to the
travel merchant needs to be based on per capita work output.*

The merchant measures the village's output at his own gate, and needs no
production hook to do it: the sellable surplus he is shown (above the
construction reserve and the larder, priced at the base prices
`MerchantVisit.price_of` already derives) is what the village's work
accumulated since his last call. Per capita per day, that **is** the
village's net work output.

`MerchantVisit.price_index(labour_value, surplus_value)`:

```
labour_value = EXPORT_INCOME_TO_WAGE_BILL_RATIO × wage bill since his last call
index        = max(1, labour_value / surplus_value)          (1 when there is no surplus)
unit price   = base price × index
```

Which is, per unit, `2 × wage ÷ per-capita output` in base-value terms:
the labour-value price, floored at the farm gate so a village whose output
is worth more than its bill is paid for its output rather than for its
bill. A beam is still six logs — the base prices keep every relativity
[traveling_merchants.md](traveling_merchants.md) derived; the index moves
the level.

**The cart carries what it takes.** When the index is above the floor,
paying the village its labour value means taking the whole surplus, and
he does — the whole surplus above the *minimum stock*, food and fuel
alike (mechanism 3), which is why that stock had to cover the woodpile. When the surplus is worth more than that at base, he takes enough
units to cover the labour value and never fewer than `CART_CAPACITY` — so
the fixed cart is a floor on a visit, not a ceiling on a village's income,
and a hoard still cannot become a windfall: what a hoard earns above the
labour value is its base value, exactly as before.

**Since his last call** is `MerchantVisit.cover_seconds()`
(`SECONDS_PER_DAY ÷ VISITS_PER_DAY`, 150 seconds — the longest a village
worth the detour waits) on a first visit, and the real interval after,
**capped at the cover**: a village that had nothing to sell for a season
is not owed a season's wages when it finally has one herb; it is owed the
round.

**The consequence, stated plainly.** For a village that exports what it
makes, export income is exactly twice its wage bill. For a village that
eats most of what it makes, the surplus is small, the index is high, and
the same twice-the-bill arrives for fewer units — a herb can fetch forty
gold at the gate while a meal of it costs two on the stall. That inversion
is not a bug; it is what "double the wage bill from exports" means for a
village whose exports are a tenth of its output, and the alternative is
the purse in the table above.

## Mechanism 3 — The minimum stock

`SettlementGranary.larder_reserve_for(household_count, assessments)` is
the granary's own `subsistence_draw` — the real per-assessment eating —
over a horizon in assessments. The horizon is the cart's cover, converted
on the assessment clock: `ceil(MerchantVisit.cover_seconds() ÷
SETTLEMENT_STEP_INTERVAL)` = 5 assessments. Ten households keep
`round(12) × 5 = 60` units, against the 25 the basket-on-the-wrong-day
arithmetic kept.

The rule is [traveling_merchants.md](traveling_merchants.md)'s own — "a
village sells what is left once its own households are fed until the cart
comes again" — with the eating finally measured on the clock the cover is
measured on. `SettlementSurplus.larder_reserve` spreads it across whatever
food the village really has, unchanged.

**And the woodpile.** The minimum stock is the whole *subsistence* basket,
not food alone. `wood` is the fuel every hearth burns
([village_estates.md](village_estates.md), mechanism 1) *and* a good on
the buy list, and once the cart carried a village's whole surplus
(mechanism 2) it stripped the pile every visit — measured: fuel
satisfaction 0.00 at three of eight samples, and the roster fell from ten
households to six through the estate ladder's exodus.
`SettlementSurplus.minimum_fuel_for` keeps what the households burn over
the cover (`EstateConsumption.demand_for` over the cover on the economy
day it is priced in, in this season) rounded up, **plus one whole unit of
shelf granularity**: the estate draw takes whole units off the pile, so a
pile holding exactly the burn reads empty the moment its unit is taken.
Ten cottagers burn a fifth of a log over a round and keep two.

## Mechanism 4 — A full larder is a day's meals in store

`HouseholdWellbeing.FOOD_STOCK_PER_HOUSEHOLD_TARGET` was 4.0: one
assessment's draw, from when the draw was 4. The draw is 1.2 now
([settlement_food_calibration.md](settlement_food_calibration.md)) and the
target was never revisited, so "full larder" meant three and a third
assessments of food for no reason anybody could state.

It is **a day's meals per household**: the measured draw over the two
assessments in the day the village lives on — the same sixty seconds its
schedule, its ecosystem step, its settlement step and its cart all run on
— `FOOD_PER_HOUSEHOLD × 2` = 2.4, pinned to that derivation. The card's
own "feeds N of M" line reads the same draw, so a village that feeds all
its households with a day in hand reads 100% here too, and the same
reading feeds the estate layer's food satisfaction, the wellbeing's food
need, hunger's drag on productivity and the immigration gate.

**Deliberately not the cart's whole cover.** The first cut made the target
the minimum stock per household (mechanism 3, 6.0), on the appeal of one
number with one meaning — and measured on the real village it was wrong:
a village holding a day or two of food read its households below
`EstateAscension`'s subsistence floor, and lost four of ten to the
ladder's exodus while every belly in it was full. The estate layer reads
food's satisfaction off *stock*, not off the flow of meals
([village_estates.md](village_estates.md), known gaps), and a stock target
that only a village at its full reserve can meet turns that known gap into
an exodus. A day's meals is the horizon the village's own day gives it; a
village that keeps its minimum stock still reads full, with more than a
day in hand (test-pinned in both directions).

## Mechanism 5 — Households draw from the whole larder

`EarthChunkManager._draw_estate_basket` reads the live market, the
persisted market **and the larder shelves** — `_settlement_larder_stocks`,
the same `STRUCTURE_MEAL_SOURCE_IDS` set a villager may eat off and the
food reading already counts — as one stock, and the draw is taken back out
of them in that order: stall, ledger, shelves. What the player can walk up
to and open is the last thing to go, the same rule the merchant's sale
keeps. Shelves count in whole units like the persisted market, so the
fraction is carried exactly as it already is for that market.

A herbalist's forty herbs on the farmhouse shelf are, from now on, forty
herbs the cottagers have.

## Mechanism 6 — the works keep up with the mouths

Asked directly, after the after-measurement above: *"fix the food
production deficit so a fed village keeps its stock."*

### What was measured, second pass

The same village, with the probe extended to count harvests and to ask
the assembly what it would build (`tools/probe_village_economy.gd`,
`tools/probe_field_room.gd`):

| fact | measured |
|---|---|
| farming households | 2 farmers, 1 herbalist, each with a six-bed field; 1 fisher with a pond |
| farmhouses standing | **3** (at (20,19), (24,19), (6,24)), with fields |
| farmhouses the settlement *counts* | **1** — `_standing_building_ids_in_chunk` deduplicates by id, so `_settlement_building_counts` cannot count a second farmhouse at all |
| harvest onto the farmhouse shelves | 299 units in 20 lived days over 3 fields: **5.0 per field per day** |
| the yield the roster is sized by | `FIELD_YIELD_PER_WORK_BLOCK` 278 per 900 s = **18.5 per field per day** |
| meals eaten | 10 households × 2.4 = 24 a day |
| the assembly's vote with the food reading at 0.00 | **a trade hall** |
| room for another field | 499 of 509 clear farmhouse origins fit a field; both walkers find one |

So the deficit is not room, and not a village too poor to build. It is
three faults, each a number the village reasons with that is not the
number the world produces:

1. **The food works are gated on the wrong people.** Mechanism 7 of
   [village_estates.md](village_estates.md) lets a village petition for
   another farmhouse while fewer stand than its demand asks for — and then
   asks `VillageLabor.can_staff`, which wants a *husbandman*. But a field
   is worked by whoever's **trade** it is: `VillageFarm` hands a farmer
   their field whatever their estate, and the only field this village had
   was being worked by a cottager. A village nobody has yet risen in can
   never pass that gate, so it votes for a trade hall while it starves.
   ✅ **Fixed**: the assembly state carries `field_hands`, the households
   whose trade works a field, and the next farmstead is wanted while one of
   them stands without a field (`test_village_assembly.gd`). A caller that
   has not counted keeps the estate gate.
2. **Farmhouses are not counted.** ✅ The settlement's building count
   deduplicated, so "outnumbered" was judged against one farmhouse however
   many stood — with fault 1 fixed alone the village would have voted for
   a fourth. `_settlement_building_counts` now counts the records that
   stand (`test_earth_chunk_manager_building_counts.gd`).
3. **The roster is sized against a yield the field does not give.** ✅ The
   stub-world measurement behind `FIELD_YIELD_PER_WORK_BLOCK` is 3.7× what
   a real field yields once the walk to it is in the day: a villager's two
   work blocks are 27.5 s of a 60 s lived day, and the walk between the
   cottage on the street and the field behind the farmhouse, at about
   1.25 tiles a second, eats most of it — the beds stood mostly empty
   (`tools/probe_field_timeline.gd`), and the water a tank at its drinking
   reserve refuses ([village_water.md](village_water.md) mechanism 3) is a
   smaller loss behind that. So the roster reads the real figure:
   `VillageFarm.FIELD_YIELD_PER_LIVED_DAY` 5.0 over
   `SECONDS_PER_LIVED_DAY` 60, and `SettlementFoodDemand
   .yield_per_producer_per_assessment` is 2.5 — a field hand feeds two
   households, a founding five needs three, a village of ten needs five
   (`test_settlement_food_demand.gd`).

### What the fix is

- **The count is real.** `EarthChunkManager._field_hands_for_settlement`
  counts, off the settlement's own regenerated roster, the households whose
  trade works a field, and `_village_assembly_state` hands it to the
  assembly as `field_hands` (`test_earth_chunk_manager_field_hands.gd`).
- **The founding roster is founded once.** `SettlementGenerator` staffs the
  founding ten to their own demand, then picks the carter and the sawyer,
  and only then conscripts the grown village's larger demand — from
  newcomers, never the wagon or the saw. A single pass off the end of the
  whole roster reached the founding carter and handed the wagon to somebody
  else on every reload (`test_settlement_generator.gd`).
- **A growth farmhouse is sited where its field fits.**
  `VillageRenderer.farm_plot_with_field` is the one search for a
  farmstead's plot — the next frontage with room for a field and its fence
  (`_field_fits_at`, [village_farms.md](village_farms.md)), the outskirts
  when the streets are full — and both the founding placement and
  `EarthChunkManager._growth_site_for` ask it, against the landmarks and the
  ground a project is already rising on
  (`test_earth_chunk_manager_farm_growth_site.gd`). A farmhouse the
  assembly votes itself was sited by the plain frontage ladder before,
  which is a farmhouse with nowhere to sow waiting to happen.

### What it costs in ground

Five farmsteads for ten households is the historical ratio, and it is
paid in frontage: each is a 3×2 house on the street with a fenced 3×2
field behind it, so the last street of a founding village is now a belt of
farms right up to the chunk's south edge. Two packing tests measured it,
and a third caught the belt packing two farmsteads yard to yard on the
outskirts with no column for the rail line their fields share — the
search keeps one clear column or row between two yards now
(`VillageFarm.yards_touch`, [village_farms.md](village_farms.md)).
A village of fourteen with its food works really standing has a plot or
two of frontage left, where it used to have four (the growth test that
asked for a house after a rung now asks for a farmstead, which the
outskirts can always take). And a mill's spur is three columns wide at
most and cannot lane through a field, so timber that appears *beyond* the
farm belt is timber the village cannot reach: **0 of 12** stub villages
healed a mill from a forest on their south edge, **12 of 12** from one on
their north. The heal test paints its timber on the north; the south
case is a known gap below.

## Interaction with other docs

- [traveling_merchants.md](traveling_merchants.md) — the cart, the buy
  list, the base prices, the reserve and the one-faucet rule this builds
  on. Its "farm-gate below town price" pins hold for the **base** price;
  the level a village is paid at is this doc's index.
- [village_estates.md](village_estates.md) — the baskets and the draw
  mechanism 5 widens, and mechanism 6's tax, which pays into the purse the
  wage now comes out of.
- [village_growth.md](village_growth.md) — the wellbeing needs mechanism 4
  recalibrates and mechanism 1 finally funds.
- [settlement_food_calibration.md](settlement_food_calibration.md) — the
  measured draw every number here is anchored to.
- [village_warehouse.md](village_warehouse.md) — the shelves mechanism 5
  reads.
- [hud.md](hud.md) — the settlement card's food and gold rows, which
  now describe a village that keeps food and pays wages.

## Status

- ✅ **Mechanism 1 — the living wage** (2026-09-20).
  `VillageWages.keep_per_assessment` / `living_wage_per_assessment` /
  `assessments_to_full_purse` / `wage_bill_for` / `wage_payouts`, pure and
  pinned by the properties they produce (`test_village_living_wage.gd`,
  14 tests); `NpcEconomy.pay_wage_from_purse` is the one transfer out of
  the purse and `EarthChunkManager._pay_village_wages` runs it after the
  cart each assessment (`test_earth_chunk_manager_village_wages.gd`, 9:
  conservation, whole coins, carried fraction, poorest first, no arrears,
  the income need lifted off the floor, paid the same tick as the sale).
  The one-faucet guard (`test_gold_has_one_faucet.gd`) is unchanged and
  still passes.
- ✅ **Mechanism 2 — the labour-value price** (2026-09-20).
  `MerchantVisit.EXPORT_INCOME_TO_WAGE_BILL_RATIO`, `labour_value_for`,
  `price_index`, `unit_price_of`, `surplus_value`, and
  `purchase(stock, reserved, labour_value)` (`test_merchant_visit.gd`, 48
  — every earlier pin holds at a labour value of 0). The manager counts
  assessments since the last paid visit and caps the interval at the
  round (`test_earth_chunk_manager_merchant_labour_value.gd`, 4: a first
  call pays for one round, the next for the labour since, the cap, and a
  village that exports what it makes earning at least twice its bill).
- ✅ **Mechanism 3 — the minimum stock** (2026-09-20).
  `SettlementSurplus.cover_assessments` / `minimum_stock_for` /
  `minimum_fuel_for`, simulated against the granary's own `catchup`
  (`test_settlement_surplus.gd`, 24); the merchant's reserve is
  `EarthChunkManager._merchant_reserve_for`, pinned through the step
  (`test_earth_chunk_manager_village_larder.gd`, 5: the food and the
  fuel are handed to the cart as its reserve, and it never sells below
  either).
- ✅ **Mechanism 4 — a full larder is a day's meals** (2026-09-20).
  `HouseholdWellbeing.FOOD_STOCK_PER_HOUSEHOLD_TARGET` 2.4, pinned to the
  derivation and to "a village at its minimum stock reads full"
  (`test_household_wellbeing.gd`, 31).
- ✅ **Mechanism 5 — the draw over the larder shelves** (2026-09-20).
  `_draw_estate_basket` / `_take_from_settlement_stock(..., shelves)`
  (`test_earth_chunk_manager_estate_larder_draw.gd`, 6: forty herbs on a
  farmhouse shelf read 1.00 through the real step, the goods really
  leave, stall before ledger before shelf, a sawmill is nobody's larder,
  fractions carried, no debt).

- ✅ **Mechanism 6 — the works keep up with the mouths** (2026-09-20).
  The trade-worked gate (`VillageAssembly` `field_hands`,
  `test_village_assembly.gd`, 48), the real farmhouse count
  (`test_earth_chunk_manager_building_counts.gd`, 3), the real-field
  yield (`VillageFarm.FIELD_YIELD_PER_LIVED_DAY`,
  `test_settlement_food_demand.gd`, 16), the founding-first conscription
  (`test_settlement_generator.gd`, 33), the field-hand count off the
  roster (`test_earth_chunk_manager_field_hands.gd`, 3) and the
  field-aware growth site (`VillageRenderer.farm_plot_with_field`,
  `test_earth_chunk_manager_farm_growth_site.gd`, 3). The measurement is
  under "Measured after, second pass" below.

### Measured after

The same probe, the same village, both fixes in (the table under "What
was measured" is the before):

| seconds | roster | herb on the shelves | herb satisfaction | fuel satisfaction | food satisfaction | food on the shelves | purse | wallets | broke | worst need |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|
| 150 | 10 | 7 | 1.00 | 1.00 | 0.29 | 9 | 384 | 64 | 0 of 10 | food |
| 300 | 10 | 20 | 1.00 | 1.00 | 1.00 | 22 | 624 | 210 | 0 of 10 | work |
| 450 | 10 | 13 | 1.00 | 1.00 | 0.54 | 15 | 864 | 338 | 0 of 10 | work |
| 600 | 10 | 26 | 1.00 | 1.00 | 1.00 | 28 | 1104 | 474 | 0 of 10 | work |
| 750 | 10 | 24 | 1.00 | 1.00 | 1.00 | 26 | 864 | 610 | 0 of 10 | work |
| 900 | 10 | 9 | 1.00 | 1.00 | 0.38 | 11 | 1104 | 750 | 0 of 10 | work |
| 1050 | 10 | 5 | 1.00 | 1.00 | 0.21 | 7 | 1344 | 902 | 0 of 10 | food |
| 1200 | 10 | 0 | 1.00 | 1.00 | 0.00 | 2 | 1584 | 1066 | 0 of 10 | food |

- **Herb reads 1.00 at every sample** where it read 0.00 at seven of
  eight: the shelf is the households' now.
- **The purse climbs 384 → 1584 and the wallets 64 → 1066**, nobody
  broke, where the purse read 0 → 20 → 1 and every wallet 0. "Worst:
  income" does not appear once; happiness peaks at 0.76 against 0.64.
- **Food reads 1.00 at three samples** where it never did, and the cart
  never touches it — the shelves never reach the 60 units ten households
  keep, so nothing is for sale.

### Measured after, second pass

The same probe and the same village with mechanism 6 in. The roster the
chunk now founds is three farmers, a herbalist and a fisher — five
producers for ten households — with four farmhouses and a fisher's hut
standing where there were two fields and a pond:

| seconds | roster | food on the shelves | food satisfaction | harvested so far | herb on the shelves | purse | wallets | broke | worst need |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|
| 150 | 10 | 40 | 1.00 | 38 | 38 | 0 | 0 | 10 of 10 | income |
| 300 | 10 | 37 | 1.00 | 80 | 35 | 240 | 150 | 0 of 10 | work |
| 450 | 10 | 42 | 1.00 | 139 | 40 | 480 | 282 | 0 of 10 | work |
| 600 | 10 | 45 | 1.00 | 195 | 43 | 720 | 416 | 0 of 10 | work |
| 750 | 11 | 19 | 0.64 | 226 | 17 | 369 | 509 | 0 of 11 | work |
| 900 | 11 | 4 | 0.08 | 269 | 2 | 633 | 655 | 0 of 11 | food |
| 1050 | 11 | 6 | 0.15 | 327 | 4 | 897 | 803 | 0 of 11 | food |
| 1200 | 11 | 8 | 0.23 | 360 | 6 | 1161 | 977 | 0 of 11 | food |

- **A fed village of ten keeps its stock.** For the whole first half the
  shelves hold 37–45 units and food reads 1.00 at every sample, where the
  first pass read 0.29 → 1.00 → 0.54 → 1.00 → 0.38 → 0.21 → 0.00 and
  ended at 2 units. Four fields brought in 360 units over twenty lived
  days: 4.5 a field a day, the number the roster is now sized by.
- **The deficit comes back with the eleventh household**, and it is a
  producer who cannot produce. The newcomer's trade is fisher, so the
  demand counts them (six producers wanted, six present) and the assembly
  wants no farmhouse (four field hands, four farmhouses) — but a fisher's
  works is a pond beside their house, and a pond is dug at founding and on
  a later visit (`_dig_fisher_ponds_if_missing`), never in play. The
  probe's field report shows them with no pond and no shelf. Eleven mouths
  on four fields and one pond is what drains the shelves from 45 to 4.
  That is [village_ponds.md](village_ponds.md)'s gap, named below, not a
  fault in the count.
- **Herb reads 1.00 throughout**; fuel read 0.00 at two samples (450 and
  600 s) while a trade-hall project started and took its wood, and the
  purse fell once, 720 → 369, at the sample the newcomer arrived, then
  climbed again at the old rate. Neither is root-caused here; both are
  recorded so the next measurement starts from them.

### Two regressions the measurement found, and closed

The first cut of mechanisms 2 and 4 measured worse than the before on one
column: the roster fell **10 → 7 → 6** and recovered only to 9.

1. **The cart stripped the woodpile.** A cart that carries the whole
   surplus took every `wood` above the construction reserve, and `wood` is
   the fuel every hearth burns: fuel satisfaction read 0.00 at three of
   eight samples, the cottagers' subsistence fell below the floor, and
   the ladder's exodus fired. Mechanism 3 keeps the woodpile too.
2. **A target the size of the whole reserve turned a stock reading into an
   exodus.** With the full larder at 6.0 a village holding a day or two
   of food read its households below the floor while every belly was
   full. Mechanism 4 is a day's meals.

With both closed the roster holds at 10 through the whole run.

### One fault found on the way

`EarthChunkManager._collect_estate_tax` looked every household up with
`HouseholdStore.household_for`, which resolves a *member's* entity id and
answered null for every household id — so from the day the tax became a
transfer it had debited nobody and credited nothing, and its own test
stayed green only because the fixture's stock drew a merchant who funded
the purse instead. Fixed to `get_household`, pinned against the wallets
by a direct-call test, and the old test restated as the accrual it can
honestly show through the step.

## Known gaps, stated rather than papered over

- **A fed village eats what it grows — closed for the village as
  founded, open past it.** The first pass found ten villagers who could
  all afford a meal eating more than one farmhouse and a pond grow;
  mechanism 6 sizes the works to the mouths and the second measurement
  holds its stock. Past the founding ten the works must keep growing
  with the village, and today they do not when the newcomer is a fisher:
  a pond is dug only at founding or on a later visit
  ([village_ponds.md](village_ponds.md)), so an immigrant fisher counts
  as a producer and produces nothing until the chunk is next loaded. The
  estate layer also still reads food's satisfaction off stock rather
  than off the flow of meals ([village_estates.md](village_estates.md)'s
  own gap), so a village growing exactly what it eats holds no stock and
  reads short; mechanism 4 keeps the target as low as the day allows.
- **The yield is the commute's.** A field hand feeds two households
  because the walk between cottage and field eats most of the work
  window, not because a field grows little. Housing the farmer at the
  farmstead, or dropping the midday walk home, would lift the yield
  toward the stub world's 18.5 a day and cut the farm belt to a third —
  the lever for a village that wants its frontage back. The water a tank
  at its drinking reserve refuses is the smaller lever behind it.
- **A household's stored occupation ignores conscription.** The
  household store keeps the trade an identity rolled, the roster the
  village works by conscripts field hands over it, and the two disagree
  for exactly the conscripted households (the probe's household list
  shows two carters and two farmers where the roster has one and three).
  Production follows the roster, so the shelves are right; the census,
  the labour supply and the spare-capacity rule read the store, so they
  are wrong by the conscripted few.
- **The farm belt walls the south.** A mill's spur is three columns wide
  at most and cannot lane through a field, so timber that appears beyond
  the belt of farmsteads on a village's last street is timber a later
  visit cannot reach (0 of 12 stub villages healed a south-side mill,
  12 of 12 a north-side one). A growth farmstead sited on the outskirts
  has its doorstep laid but not the spur `farm_plot_with_field` returns;
  its villager walks the open ground home.
- **Meal gold is a sink.** A meal bought on the stall or off a shelf
  destroys its coin; it does not return to the purse. With the wage
  bill covered twice over by exports that is affordable, and routing the
  takings back would be a second transfer this pass does not need. Noted
  because it is the obvious next place to close a loop.
- **The purse still dies on a chunk reload**, both tanks — the gap
  [traveling_merchants.md](traveling_merchants.md) already records. Wallets
  are persisted with their households; the purse they are paid from is
  not.
- **One household is one villager**, by construction, so the bill is per
  household. A house that really held two would need the wage multiplied
  by its residents, the same caveat the draw already carries.
