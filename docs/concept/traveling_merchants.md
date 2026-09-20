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
- 🚧 **The gold faucet is narrowed, not closed.** A producer is still paid
  `NpcProduction.YIELD_TO_GOLD_RATE` per food unit the instant it is
  gathered or taken, whether or not a cart ever buys it — the faucet this
  doc exists to make honest. What changed is that a second, real income
  path now exists beside it and that the one good with no local buyer
  (hide) goes through the cart alone. Making food income conditional on an
  actual sale is the next slice, and it needs a village to survive the gap
  between visits first (a granary, or a purse deep enough to ride out a
  bad week).
- ⬜ Everything else in this doc is specified here first and implemented in
  the slices that follow; each entry moves to ✅/🚧 as it lands, and
  [progress.md](../progress.md) carries the ledger.
