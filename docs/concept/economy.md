## Economy

An in-game currency and economic system: buy/sell resources, hire NPCs or
players, and a premium currency purchasable with real money.

### Regular currency: earned from what you make, not just quests

Currency enters the economy roughly equally from two faucets:

- **Selling to the market** (NPC and, later, player, via the
  [auction house](labor_skills.md#the-auction-house)) — crafted goods
  ([crafting.md](crafting.md)), gathered resources
  ([resources.md](resources.md)), tamed/bred creatures
  ([pets.md](pets.md)/[evolution.md](evolution.md)), and crystallized spell
  gems/scrolls ([magic.md](magic.md) — [items.md](items.md#spells-as-items)).
  This ties the economy directly into every production system already
  designed, instead of being a separate quest-reward faucet bolted on top.
  Crafted-goods pricing carries a quality premium tied to the crafter's own
  labor-skill tier, not just a flat per-item-type price.
- **Quest/bounty rewards** from NPCs' need-driven requests
  ([npc.md](npc.md)) — the classic MMO faucet, still meaningful, just not
  the only one.

Currency is spent on: hiring NPCs (wages, see
[npc.md](npc.md#hiring--instruction)), buying resources/goods from other
players, other players' crafted/tamed goods, and **compiling a designed
spell into a permanently known one** — a gold sink priced exponentially in
the spell's size ([magic.md](magic.md)'s compilation-gate brainstorm), so
spellcrafting is a real, recurring drain on the same currency the rest of
the economy earns, not a free character-building action.

### Premium currency: convenience and rarity, never power

Real-money-purchasable premium currency buys DNA rerolls
([dna.md](dna.md)), extra lives/soul stones ([death.md](death.md)),
cosmetics, and convenience (extra storage, faster travel) — **explicitly
never** stat power, spell atoms, or gear directly. This keeps monetization
consistent with the rest of the design's tone: rare/optimal things are
always earnable in-world too, premium currency just buys a faster or
more certain path to them, never a path that doesn't otherwise exist.

### Prices are local — ✅ built (2026-08-27)

`docs/emergence/03-contracts-property-economy.md` says plainly: *"Markets are
local buyer/seller matching systems... Do not use one global price."* The shop
was the last thing violating that — one flat `Shop.CATALOG` every merchant
everywhere sold from, while `Market` sat beside it simulating real
supply-and-demand prices that nothing ever read.

The two now meet, and the seam needed **no new number**, which is why it was
worth doing this way round:

- `Shop.CATALOG` is the **base price in absolute gold**. It always was.
- `Market.price_for` is a **dimensionless scarcity multiplier**, exactly `1.0`
  at `Market.REFERENCE_STOCK`. It always was.
- So the price is `round(base × multiplier)` — `Shop.market_price_of`. A
  village holding healthy stock charges precisely what the flat catalog charged
  before this existed, and every deviation from that is a real shortage or a
  real glut the NPC economy produced through `Market.produce` running real
  `CraftingRecipeBook` recipes.

Buying is a real transaction against real stock, per `03`'s invariant 4
("Money does not create physical goods"): a purchase draws the item **out** of
that settlement's market, and an item the market has none of cannot be bought
at any price. A sold-out village is a real reason to travel.

The merchant's market is resolved from the merchant themselves —
`EarthChunkManager.merchant_market_near` — because `_loaded_villages` is keyed
by chunk and a chunk is exactly what `EntityRef.for_settlement` names a
settlement by. On first access it is stocked via `Shop.stock_initial_goods`,
which is not flavour: `MarketStore.market_for` creates a fresh **empty**
market, and an empty market prices at twenty times the catalog. Seeding at
`REFERENCE_STOCK` is what makes an untraded village charge the old price.

**Food is seeded once; tools and blueprints restock** (2026-09-13, reported
directly: *"the food should be actually consumed and not stay at 20 cooked
meat"*). The merchant's market is the same `Market` that
`SettlementState`/`SettlementFood` count as the village's own food stock,
and `stock_initial_goods` used to refill any item that hit zero whenever the
player came near — so its 20 cooked meat were five households of permanent
carrying capacity that no villager ever ate. Now villagers do eat from the
village's stores (`EarthChunkManager.buy_village_meal_near`: the Market
first, then a Bakery/Storage shelf, at the flat local meal price —
scarcity pricing is what the *player* pays), and the shop's **food** is the
merchant's opening inventory only, seeded once per market
(`Market.shop_food_seeded`, persisted) and never refilled by the shop: what
the village eats is gone until its own economy — producers, the granary,
trade, the bakehouse ([milling_and_baking.md](milling_and_baking.md)) — puts
food back, and its price climbs with scarcity like everything else. Tools
and blueprints keep restocking when sold out: the merchant trades those in
from afar, and nothing else in the game supplies them.

This closes the second half of this doc's own open question below — pricing
for *market goods*. Hiring wages are still open.

### Selling — ✅ built (2026-08-27)

The other half of the faucet, and the point where what the player produces
becomes a strategy rather than a number. `Shop.sell` pays the local price and
pushes the goods into that village's real stock — so selling is buying's exact
mirror: it moves the price *down* instead of up. Dump forty units on one
village and you crash what it pays for the forty-first; carry them somewhere
short of it and you get paid over the odds. Neither is a rule written to
reward or punish anyone, both fall out of `Market.price_for`.

**The spread.** A merchant buys low and sells high — `Shop.MERCHANT_SPREAD`.
The number is not asserted anywhere and is not the point. What is pinned is
the property that makes any spread legitimate:
`test_buying_then_selling_back_always_loses_money` sweeps every stock level
from 1 to 40 and requires the round trip to lose money at each. That sweep is
load-bearing rather than thorough-looking: the ratio between adjacent prices
is tightest at *low* stock (the price halves from stock 1 to stock 2), which
is exactly where a plausible spread stops being arbitrage-proof and the shop
becomes a money printer. Anything at or above 0.5 breaks there.

**A merchant only buys what they deal in.** `Item` carries no value field, so
`Shop.CATALOG` is the only place in the game an item has a price at all —
paying for a hide or a log would mean inventing a number with nothing behind
it. Today that makes `cooked_meat` the real sell-side loop: hunt, cook, sell,
and (since `record_death` landed) pay for the hunting in the ecosystem's own
books. **⬜ Remaining:** giving materials real values so the rest of what a
player gathers can be sold. That is its own piece of work and wants a grounded
source for the numbers, not a table someone typed.

**The verb** is its own rebindable action (`sell`, default `Y`) rather than a
third meaning stacked onto the trade key, which already branches two ways. It
is registered in `Player.MOMENTARY_ACTIONS` — a tap-length verb that is not
would be silently swallowed at the frame rates seen in real play, which is the
bug `InputLatch` exists to fix.

**⬜ Not built:** a sell-side UI. Selling picks the first catalog item in the
bag; there is no way to choose, and no list of what a merchant wants.

### Households buy a basket, and pay tax on what is left — ✅ built (2026-09-19)

[village_estates.md](village_estates.md) is the other half of this doc's
own loop, and the half it has been missing: what the *NPC* side of the
economy actually buys, and where a settlement's money comes from.

- **Demand is a basket, not a number.** Each of the four estates consumes
  a fixed basket of real goods per household per day — food and firewood
  for everyone, then bread and candles, then leather, then beer and honey
  as standing rises. `EstateConsumption` removes those units from the
  settlement's real stock every step, so demand is a *flow* against the
  same `Market`/`VillageMarket` `Shop.market_price_of` prices from. A
  village that runs its beer down is a village whose beer gets dearer, by
  the scarcity multiplier that was already there.
- **Firewood is seasonal.** The fuel term doubles in winter and halves in
  summer off the real `SeasonCycle`, so the price of `wood` in a village
  has a real annual shape without anybody writing one.
- **Income scales with provision.** `VillageWages.estate_tax_for` pays into
  the SAME purse the subsistence wage already comes out of, at a rate that
  rises with standing and falls to nothing for a destitute household. That
  answers half of this doc's own last open question — *"price/exchange-rate
  design for hiring wages"* — for the settlement side at least: a village's
  wage bill is now funded by a real, derived tax rather than by producer
  levy alone.
- **The brewery has a product.** `brew_beer` (3 wheat → 1 beer, gated on
  the brewery) is the first thing the growth ladder's own top rung has ever
  made, and it competes with `bake_bread` for one crop.

Still open on this doc's own list: real values for raw materials, so the
rest of what a player gathers can be sold.

### Open questions

- Should premium currency ever be tradeable for regular currency between
  players (WoW-token/EVE-PLEX style)? Would give a legitimate
  currency-buying outlet and let time-rich players earn it without paying,
  at real economy-design cost — not decided, worth revisiting once a player
  market actually exists (roadmap Phase 5+).
- Price/exchange-rate design for hiring wages and market goods — needs
  actual numbers once the production systems it depends on are built.
