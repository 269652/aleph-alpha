# Traveling Merchants: Where A Village's Gold Actually Comes From

Compiled from a direct report in play: *"all villagers have 0 gold; they
need a way to earn income... I'd suggest traveler merchants which buys
goods like fish, meat, hide, beams etc. — then the villagers can trade
with each other once they have a way to earn money."*

Two separate problems sit behind that observation, and only one of them
was a bug.

**The bug** (fixed 2026-09-16, see [Status](#status)): villagers *were*
earning. `NpcEconomy`'s producer faucet and `VillageWages`' subsistence
wage both worked — into a `Wallet` created fresh inside `NpcEconomy`, on an
`NpcMarker` regenerated from scratch on every chunk load. The persistent
`Household` wallet never received a coin, so a villager's whole working
life evaporated the moment the player walked away and every readout
honestly said zero.

**The design gap**, which this doc is about: even with that plumbing
fixed, the village's gold comes from nowhere. `NpcProduction.
YIELD_TO_GOLD_RATE` conjures a coin per food unit gathered, whether or not
anyone ever buys it. That is a placeholder, and it is why a village's
wealth has never meant anything — there is no outside world paying for
what the village makes, so gold is neither scarce nor earned.

A traveling merchant is the outside world, arriving on foot.

## Design pillars

1. **Gold enters a village by being paid for something real.** A merchant
   buys goods that genuinely exist in the settlement's own market and
   removes them from it. No stock, no sale, no gold. This replaces a
   faucet that paid for production nobody consumed with a faucet that pays
   for production somebody carries away.
2. **The merchant is a visitor, not a fixture.** They arrive, trade, and
   leave. A village's income is therefore *lumpy* — a good week is a week
   a merchant came — which is what makes a granary, a surplus and a
   warehouse worth having, and what makes the [village growth
   ladder](village_growth.md) feel earned rather than scheduled.
3. **They buy what a village actually produces.** Fish, meat, hide, beams,
   planks — the real outputs of `NpcProduction`'s producer occupations and
   the sawmill's own chain. Nothing on the buy list is an item the village
   cannot make, and nothing the village makes is unsellable.
4. **The gold lands where it can be spent.** Payment goes into the
   settlement purse (`NpcEconomy.PURSE_META`, already real, already what
   `VillageWages` pays subsistence out of) rather than to one villager, so
   it reaches non-producers through the wage path that already exists. A
   village earns collectively and pays its people from what it earned.
5. **Nothing is conjured and nothing vanishes.** A sale moves goods out and
   gold in, at one price, both sides recorded. The same "creates and
   destroys nothing" discipline `VillageWages.deposit`/`take_home_of`
   already keeps for the levy split.
6. **Tuned values are tested functions.** Every price, cadence and
   quantity below is pinned by a test against the behaviour it produces,
   per this project's no-manual-tuning rule.

## Real-world grounding

- **The itinerant buyer is the oldest rural economy there is.** A village
  that fishes, hunts and saws timber does not carry its surplus to a city;
  a dealer walks a circuit, buys at the farm gate below town price, and
  carries it away. That price gap is his living and the village's only
  cash.
- **Cash was scarce and lumpy.** Pre-industrial rural households were not
  short of *food* — they were short of *coin*, which arrived a few times a
  year when something was sold. Lumpy income is not a game concession; it
  is the historical shape.
- **He buys what travels.** Hide, salted meat, dried fish and sawn timber
  keep and are worth carrying. This is why the buy list is what it is,
  rather than "everything".

## Mechanism — arrival

`MerchantVisit` (pure, static, the same shape `VillageImmigration` and
`SettlementGathering` already use): given elapsed time, how much sellable
stock a settlement holds, and a per-settlement carry, it answers whether a
merchant arrives now.

- **Gated on something to buy.** No sellable stock ⇒ no visit. A merchant
  does not walk to a village with nothing in it.
- **Cadence** is a rate per day (`VISITS_PER_DAY`), raised by how much
  sellable stock has piled up — a village sitting on a surplus is worth
  the detour. Carry-the-fraction between steps, so a short step loses
  nothing, exactly like the gathering and immigration models.
- Deliberately **not** tied to the existing `CaravanTrip`, which is a
  settlement-to-settlement *resupply of goods* with no gold in it. This is
  a different transaction in the opposite direction.

## Mechanism — the sale

`MerchantVisit.purchase(stock, prices, capacity)` returns what is bought
and what is paid, and never mutates its inputs:

- Only ids on the **buy list** are considered, worst-price-last so a
  merchant fills his cart with the valuable goods first.
- He carries a finite `CART_CAPACITY` in whole units — a village with an
  enormous surplus sells what fits, and the rest waits for the next visit.
  This is what keeps a hoard from turning into a windfall.
- Price per unit is the item's **farm-gate** price: deliberately *below*
  what the same item sells for at a player-facing shop (`Shop.CATALOG`),
  because the merchant's margin is his reason to exist. Test-pinned
  against that catalog so the two can never invert.

The settlement's market loses exactly the goods bought; its purse gains
exactly the gold paid.

## Mechanism — surplus, not stock

A merchant buys a village's **surplus**. He does not buy the timber it cut
for its own next house.

This is not a refinement; it is the difference between a trade route and a
village that can never build anything. `SettlementGathering` is the only
thing in the game that puts wood, stone or plant fibre into a settlement's
market, and `wood` is on the buy list — so before this rule a merchant
turned up every few minutes and took the timber away again. Measured on a
real loaded village (`tools/probe_village_growth.gd`): its stone climbed
steadily to 37 while its wood never once got past 2, its `house_small`
project sat `PLANNED` with nothing reserved for the whole run, and a
village that grew from 10 households to 31 built **not one house** for any
of them. That is the same emptiness reported from play as *"the warehouse
stays empty"*.

So the sale takes a **reserve**: what the village's own next building
really needs, read from the same `VillageGrowth.next_building` the ladder
walks and the same `CraftingRecipeBook` inputs that building is priced in
— never a second list of "protected goods", which would drift from what a
village is actually saving for. Only stock above the reserve is for sale,
and the same reserve gates the *visit*: a merchant does not walk to a
village whose every plank is already spoken for.

A village with a real surplus still sells it. A village saving for a house
keeps its wood, and the merchant comes back when there is more.

## Mechanism — a merchant buys the whole village, not one of its cupboards

Reported with the town panel open: *"The village produces way too much food
and the NPCs don't have an income"* — `Food feeds 387 of 16`, `Gold 1`,
`Happiness 62% (worst: income)`.

Both halves of that are one fault. A settlement keeps its goods in **more
than one container**, and the merchant could only ever see one of them:

| Container | What puts goods in it | Seen by the merchant |
|---|---|---|
| `VillageMarket.stock` | `NpcProduction` / `SettlementGathering` | **yes** |
| each structure's `StructureStock` | a carter's round, a mill, a bakery | **no** |

`SettlementFood` was taught to count the shelves
([milling_and_baking.md](milling_and_baking.md), "Food that counts"), which
is why the panel can truthfully report food for 387 households. The
merchant never was. So a village hauls its whole harvest into the warehouse
— which is exactly what the carter's round is *for* — and thereby puts it
beyond the reach of the only thing that turns goods into gold. It reads as
"too much food AND no income" because it is one fact: **the goods and the
buyer are in different cupboards.**

The rule:

> A merchant buys a settlement's **whole** surplus. Every container the
> settlement really keeps goods in is one view of one stock, and the sale
> is drawn back out of the real containers it came from.

`SettlementSurplus` is that, and it is pure: `combined(views)` adds the
containers up for the merchant to price, and `allocate(bought, views)` says
how much to take from each, in view order, never more than a container
holds. The caller does the moving — the same division `MerchantVisit`
itself already keeps, so a sale that cannot be completed has changed
nothing.

The market is drawn from **first**, deliberately. It is the abstract ledger
a village trades out of anyway, while a warehouse shelf is a real building
the player can walk up to and open; emptying the ledger before the shelf
means what the player can *see* is the last thing to go.

This does not merge the containers, and deliberately so — the "three food
containers, one eater" question
([milling_and_baking.md](milling_and_baking.md)'s own open list) is still
open. It says only that the merchant reads all of them, which is what makes
the gold faucet reach the goods a village actually has.

## Mechanism — he buys what the village actually makes

Design pillar 3 above states it plainly: *"Nothing on the buy list is an
item the village cannot make, and nothing the village makes is
unsellable."* It was not true, and it had not been true for a long time.

`BUY_LIST` was a hand-written const — `beam, plank, hide, wood, fish, meat,
fruit` — and a village kept growing past it. A herbalist's crop, a farmer's
wheat, gathered stone and plant fibre, and the raw log a woodcutter fells
all arrived in the game **after** that line was written, and not one of
them was ever added to it. A hand-written list of facts that live somewhere
else does not stay right; it stays written.

Measured (`tools/probe_village_purse.gd`) standing exactly where
`_step_merchant_visits` stands, on a real village after 1200 simulated
seconds:

| item | units | kind | the merchant |
|---|---:|---|---|
| `herb` | 117 | food | **refuses** |
| `log` | 24 | material | **refuses** |
| `bucket` | 13 | tool | refuses (not produce) |
| `wood` | 10 | material | buys @1 |
| `wheat` | 5 | material | **refuses** |
| `stone` | 5 | material | **refuses** |
| `plant_fibre` | 1 | material | **refuses** |

One of nine ids was sellable, and all ten of those units were reserved for
the village's own next house — so `sellable_units` came out at **0**, no
visit ever accrued past 0.021 of one, and the purse read **0.0 gold with 8
of 8 villagers broke**. A merchant is the only faucet gold has, so a
village that makes nothing he buys has no income at all, ever. That is the
literal shape of the original report: *"all villagers have 0 gold"*.

The first fix put the field crops on the list by hand and added a test
that fails if a crop is added he will not buy. That closes the crop hole;
it does not close the **class** of fault, and the measurement above says
so — `log`, `stone` and `plant_fibre` are not crops, and were still
refused.

So the rule:

> The buy list is **derived from what a village's own producers make**, not
> named a second time. A second list of the same facts is free to drift
> from the first, and this one did — twice.

`MerchantVisit.village_produce()` reads the producers' own maps —
`NpcProduction.PRODUCER_ITEM_BY_OCCUPATION` (a farmer's, hunter's and
fisher's take), `VillageFarm.CROP_BY_OCCUPATION` (what a farmer and a
herbalist grow by default), `VillageCropChoice.SOWABLE` (what a village can
be *told* to grow, which is a different list), and
`SettlementGathering.gathered_item_ids()` (what spare hands gather) — and
`buy_list()` is that plus the raw timber a woodcutter fells and the worked
goods a village makes from those. Add an occupation, a crop or a gathered
material and it is sellable the same day it exists.

Prices follow the same discipline. The old table had eight separate entries
all reading `LOG_PRICE`, which was an unstated rule rather than eight
numbers; it is now stated once. Goods that have had **work** put into them
or that **keep and travel** — sawn `plank` and `beam`, and `hide` — carry
their own derived price in `KEEPING_GOOD_PRICES`. Everything else a village
makes is raw produce at `LOG_PRICE`, one raw log at the farm gate. So a new
crop needs no new number, and the existing pins hold: raw food still sits
under `VillageMarket.VILLAGE_LOCAL_FOOD_PRICE` and under `Shop.CATALOG`'s
prepared `cooked_meat`, and sawn timber is still worth exactly what its
logs were worth.

## Mechanism — the cart runs on the day the village lives on

`MerchantVisit.arrivals` divided its per-day rate by
`ConstructionCatchup.SECONDS_PER_DAY` (3600). That constant is documented
in its own file as the **offscreen catch-up** rate — *"one in-game hour
away is one day of progress, deliberately conservative"* — and the same
comment names its opposite: *"a build the PLAYER raised and is standing at
runs on the game's own day (`EarthChunkManager.SECONDS_PER_SIMULATED_DAY`,
60 seconds — what the ecosystem step, **the settlement step**, the
day/night cycle and every colony already run on)."*

`_step_merchant_visits` runs **from the settlement step**, for a village
the player is standing in. It was borrowing the absence clock for a village
that is present. This is the unfixed twin of a fault
[village_growth.md](village_growth.md)'s immigration model already had and
already corrected, in `test_village_immigration.gd`'s own words: *"It used
to be `ConstructionCatchup.SECONDS_PER_DAY` (3600), which is the offscreen
catch-up's day and was never this module's to borrow."*

One visit per 3600 seconds is one per **60 player-felt days**, against a
starvation window (`Starvation.seconds_to_die`) of 200 seconds — eighteen
times the window in which everyone who could not feed themselves was
already dead. Measured against that, with the buy list and the purse
already fixed, a real village held 811 sellable units, 22 of 22 villagers
broke, and a purse of 0.0 gold.

The day is a **parameter** of `arrivals`, defaulting to
`MerchantVisit.SECONDS_PER_DAY` (60), rather than a constant the function
reaches for — the same shape `ConstructionCatchup` already gives its own.
That keeps the distinction the catch-up rate exists for: a settlement being
integrated over an ABSENCE can still be paced at the conservative rate, and
the pacing is testable directly rather than inferred.

## Mechanism — a village does not sell the food its own people need

The reserve above protects what a village is **building**. Nothing
protected what it was **eating**, and while the only food a merchant bought
was fish, meat and fruit that was harmless — a village rarely stockpiles
those.

A herbalist's crop and a farmer's wheat have to be sellable, or those two
trades earn the village nothing at all. But a cart that can buy them, on
the village's own clock, settles a village's food at whatever level its own
draw balances at. Measured: a purse climbing 21 → 24 → 25 gold with market
food **0** at every sample, and the village dead by t=900.

The rule, and it is the construction reserve's rule pointed at the other
thing a village cannot do without:

> A village sells what is left once its own households are fed **until the
> cart comes again**.

`SettlementSurplus.larder_reserve` holds that back across whatever food the
village really has. The demand is `EstateConsumption.demand_for(census,
cover_days, season)` — what this settlement's actual estates eat, in this
actual season — and the cover is **derived, not picked**: he calls at most
`VISITS_PER_DAY` times a day when a village is barely worth the detour, so
`1 ÷ VISITS_PER_DAY` days is exactly the longest a village may have to wait
between sales. Retuning how often he comes retunes what a village keeps, by
itself.

A flat per-household figure was tried on a parallel branch and is **not**
what shipped: it shrinks as the village dies, which is a death spiral
rather than a brake.

## Mechanism — one purse, and it is the one the wage reads

`NpcEconomy.PURSE_META` is set on whichever **market object** is in hand,
and a settlement has two of them:

| object | what it is | who touched the purse |
|---|---|---|
| `Market` (`MarketStore.market_for`) | the persisted, per-settlement ledger | `_step_merchant_visits` **paid into it** |
| `VillageMarket` | the live stall villagers trade at | `_draw_subsistence_wage` **drew from it** |

Two tanks sharing one name. Every coin the merchant paid landed where
nobody could spend it, and every wage was drawn from a tank nothing ever
filled — the same *"two unrelated things called the market"* trap
`SettlementFood`'s own header was written about. The settlement step's
neighbouring comment says it plainly: *"live play essentially never stocks
that one"*.

The suite did not catch it, because its own fixture
(`_fund_village_as_a_merchant_would`) deposits into the `VillageMarket` —
**the test was more correct than the wiring**.

The merchant now trades with the live market and pays the purse the wage is
drawn from. He is shown the live market **first**, then the persisted
ledger, then the shelves, and the sale is drawn back out of whichever
container each unit was really in.

**Known gap, stated rather than implied:** a `VillageMarket` is rebuilt
from scratch on every chunk load, so a village's savings still die when the
player walks away — the defect [progress.md](../progress.md) already
records. Binding villagers to the persisted `Market` instead would fix
that, and was built and then dropped on a parallel branch, because
carrying both ends of one fix would split the tank again. Whichever end is
chosen, it has to be one tank.

## Mechanism — the merchant is the ONLY faucet

Asked directly: *"Gold should only be conjured by the travelling
merchant"*.

This file's own opening already claimed that — *"A village's gold used to
come from nowhere... A traveling merchant is the faucet that replaces
it"* — and it was not true. Two other places minted gold with nothing
behind it:

| Faucet | What it did | Standing |
|---|---|---|
| `NpcEconomy._earn` | a coin per food unit gathered, whether or not anyone bought it | **closed** |
| `_collect_estate_tax` | credited the purse and debited **nobody** | **closed** |

The rule now, and it is an invariant rather than an aspiration:

> The settlement purse gains gold from **one** place: a merchant paying
> for goods he takes away. Everything else that moves gold is a
> **transfer** — it must debit exactly what it credits.

### A producer is paid like everyone else

`_earn` split a conjured coin between the purse and the producer's own
wallet. With it gone, a producer draws from the purse through the same
`_draw_subsistence_wage` every other villager uses — which was already
written for this and says so: *"Deliberately NOT gated on occupation... in
practice a working producer's own take-home already covers the price, so
this only ever fires for them once their work has genuinely stopped
paying."* That parenthesis is simply no longer true, and the mechanism
underneath needed no change at all.

What a producer's work earns the village is now the **goods**, which the
merchant pays for. That is the whole point: a hunter feeds the village by
filling the warehouse, not by minting a coin as the arrow lands.

### Tax is a transfer, so it must be taken from somebody

`estate_tax_for` says what a village is *owed*. What it can actually
**collect** is bounded by what its households hold, and the coins really
leave their wallets. `VillageWages.tax_debits` is that, and it is pure: a
list of balances and a whole-coin demand in, one debit per household out,
never more than a household has, summing to no more than is owed.

Two details that are rules rather than conveniences:

- **Whole coins only, with the remainder carried.** A `Wallet` holds
  integer gold and a kossaet owes 0.25 a day, so collecting per step would
  round a real debt to nothing or to four times itself. The fraction
  carries per settlement — the same carry-until-it-crosses-a-whole-unit
  idiom `NpcEconomy._take_home_carry` already runs on.
- **A village collects what is there, not what it is due.** Households
  short of coin pay what they have and the rest is simply not collected;
  the shortfall is not banked as arrears. A debt a household can never pay
  is a number that only ever grows, and it would make the purse's balance
  a fiction again.

## Mechanism — what the gold is for

Once a purse has real money in it, the paths that spend it are already
built:

- `VillageWages.pay_subsistence` draws a wage from the purse for any
  villager who cannot afford a meal — so a merchant's visit feeds the
  blacksmith, not just the fisher who caught the goods.
- `VillageMarket.buy_meal` is villager-to-villager trade, already real,
  and previously starved of buyers with money.
- The [growth ladder](village_growth.md) already spends *material*;
  gold gives a later pass something to price construction labour in.

## Status

- ✅ **The persistent-purse bug** (2026-09-16).
  `NpcEconomy.bind_household_wallet` makes a villager's own `Household`
  wallet the one they earn into and spend from, carrying over anything
  already in hand. Wired through `NpcMarker.setup_economy` and
  `VillageRenderer`, resolved by
  `EarthChunkManager.household_wallet_for_villager`. Tested in
  `test_npc_economy.gd`.
- ✅ **The cart itself** (2026-09-16). `MerchantVisit` decides arrival
  (`VISITS_PER_DAY`, with a carry so a visit is never lost to step
  granularity), how much of a village's surplus one cart draws
  (`SURPLUS_DRAW`, capped at `CART_CAPACITY`), and what each good is worth.
  Wired into the settlement step through
  `EarthChunkManager._step_merchant_visits`, so gold now arrives because
  somebody bought something. Every price is derived rather than picked: a
  beam is `LOG_PRICE × 2 × (SagewerkProduction.LOG_COST_PER_BEAM /
  LOG_COST_PER_PLANK)`, riding the mill's own real 3:1 conversion, and raw
  food sits under `VillageMarket.VILLAGE_LOCAL_FOOD_PRICE` and
  `Shop.CATALOG["cooked_meat"]` — `shop.gd` states plainly that `CATALOG`
  is the only place an item has a price, so inventing one here would be a
  number with nothing behind it.
- ✅ **Hide has a supply now** (2026-09-16). Design pillar 3 above claims
  "nothing on the buy list is an item the village cannot make", and until
  villagers hunted real animals that was false of exactly one entry: hide
  was a live price with nothing behind it. A hunter's kill now credits
  `Butchering.HIDE_COUNT` into the village market, deliberately unpaid at
  the kill, precisely so the cart is what a hide is worth anything to (see
  [npc.md](npc.md#work-against-the-real-world-not-against-a-number)).
- ✅ **The faucet is closed** (2026-09-20). `NpcEconomy._earn` is gone and
  `_collect_estate_tax` debits what it credits, so the merchant really is
  the only place gold enters a settlement (see "the merchant is the ONLY
  faucet" above). `NpcProduction.YIELD_TO_GOLD_RATE` still exists as a
  constant but no longer mints: a producer draws from the purse through the
  same `_draw_subsistence_wage` every other villager uses. Guarded by
  `test_gold_has_one_faucet.gd`, which scans the source so a new caller of
  `_set_purse` cannot quietly reopen it.
- ✅ **He buys what the village actually makes** (2026-09-20). `BUY_LIST`
  was a hand-written const that a growing game outgrew — `herb`, `wheat`,
  `log`, `stone` and `plant_fibre` were all unsellable, which on a real
  measured village left exactly one sellable id and a purse of 0.0 gold
  with 8 of 8 villagers broke. `MerchantVisit.buy_list()` is now derived
  from the producers' own maps (`village_produce()`), and prices are one
  stated rule rather than a table: goods that keep carry their own derived
  price, everything else a village makes is raw produce at `LOG_PRICE`.
  Pinned by `test_merchant_visit.gd`'s
  `test_everything_a_villages_own_producers_make_is_sellable`, which reads
  the producer maps directly, so a new crop or occupation cannot be
  silently unsellable again.
- ✅ **One purse, and it is the one the wage reads** (2026-09-20). The
  merchant paid into the settlement's persisted `Market` while the
  subsistence wage drew from the live `VillageMarket`'s own meta — two
  tanks sharing one name. He trades with the live market now and pays the
  purse the wage comes out of. The savings still die on a chunk reload,
  which is a gap this file states rather than implies.
- ✅ **The cart runs on the village's own day** (2026-09-20). `arrivals`
  divided by `ConstructionCatchup.SECONDS_PER_DAY` (3600), the offscreen
  catch-up's day, while `_step_merchant_visits` runs from the settlement
  step for a village the player is standing in — the unfixed twin of the
  fault `VillageImmigration` already corrected for itself. One visit per 60
  player-felt days against a 200-second starvation window meant a village
  measured at 811 sellable units still had 0.0 gold and 22 of 22 villagers
  broke. The day is a parameter of `arrivals` now, defaulting to
  `MerchantVisit.SECONDS_PER_DAY` (60), so a background integration over an
  absence can still keep the conservative rate.
- ✅ **A village keeps back what it eats** (2026-09-20). Making a
  herbalist's and a farmer's crops sellable — which they must be, or those
  trades earn the village nothing — put a village's own food on the cart.
  `SettlementSurplus.larder_reserve` holds back what this settlement's real
  estates eat in this real season (`EstateConsumption.demand_for`) over a
  cover of `1 ÷ VISITS_PER_DAY` days — the longest a village may wait
  between sales, derived rather than picked.
- 🚧 **The faucet is open and the famine is not closed.** Measured: gold
  really flows now, where every sample used to read 0.0. A village can
  still die, and the remaining cause is the gap
  [milling_and_baking.md](milling_and_baking.md) already lists — *"three
  food containers, one eater… nothing ever moves food between them"*.
- 🚧 **Food income is still not conditional on a sale.** A producer's take
  reaches the village as GOODS and is paid for only when a cart buys it,
  which is the honest loop — but a village still has to survive the gap
  between visits, and the granary/purse depth that makes a bad week
  survivable is not designed yet.
- ⬜ Everything else in this doc is specified here first and implemented in
  the slices that follow; each entry moves to ✅/🚧 as it lands, and
  [progress.md](../progress.md) carries the ledger.
