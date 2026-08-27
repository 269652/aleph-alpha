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

This closes the second half of this doc's own open question below — pricing
for *market goods*. Hiring wages are still open.

**Not built:** selling into the market from the shop UI. `Player`'s trade key
already sells gathered food into a villager's `VillageMarket` as a fallback
(see `_attempt_village_food_sale`), but there is no general "sell your goods
at the local price" verb, and no sell-side UI. That is the remaining half of
this doc's "Selling to the market" faucet, and it is ⬜.

### Open questions

- Should premium currency ever be tradeable for regular currency between
  players (WoW-token/EVE-PLEX style)? Would give a legitimate
  currency-buying outlet and let time-rich players earn it without paying,
  at real economy-design cost — not decided, worth revisiting once a player
  market actually exists (roadmap Phase 5+).
- Price/exchange-rate design for hiring wages and market goods — needs
  actual numbers once the production systems it depends on are built.
