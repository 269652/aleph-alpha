# Player Trade

The NPC economy already trades with itself in real, physical terms:
[regional_trade.md](regional_trade.md) picks a real nearest-surplus
supplier for a real shortage, and [trade.md](trade.md) makes that transfer
a real walked shipment (`CaravanTrip`) with real travel time and real raid
risk. None of it reaches the player. `shop.gd` remains the player's only
buying path -- a fixed, global, non-per-settlement catalog with no selling
back and no connection to any real settlement's own `Market`/stock at all
(see `docs/progress.md`'s Economy section).

This doc is the player-facing counterpart: discovering a settlement makes
it a real trading partner with its own real, live prices (the same
`Market.price_for` every NPC producer already reads and moves); the player
stocks a **Warehouse**; and goods physically travel between warehouse and
settlement via a **Hauling Contract** -- a real NPC courier hired to walk
the route, exactly like a caravan, except player-initiated instead of
autonomous. A **Trade Route** is a Hauling Contract configured to redispatch
itself. Built strictly on top of `Market`/`MarketStore`/`StructureStock`/
the `CaravanTrip` travel-math shape -- this doc does not reinvent pricing,
stock, or route math, only who can trigger a shipment and where it starts.

## A naming note, read before anything else

**"Charter" is already a real, shipped word in this codebase** --
[player_citizenship.md](player_citizenship.md)'s `charter` item and
`/charter found <type> <counterparty_id>` command let the player found or
join an `Institution` (guild, cooperative, merchant company, ...). It has
nothing to do with transport. This doc deliberately calls the
hire-an-NPC-hauler mechanic a **Hauling Contract** instead -- which also
happens to line up with `contract.gd`'s own `TYPES` array already naming
`"transport"` as a documented contract type (see "Mechanism" below for how
literally that's taken). Nothing here is named "charter."

## Design pillars

1. **A settlement is a trading partner the moment it's discovered, not
   before.** No blind trading with a settlement the player has never
   found -- discovery is a real, checkable fact (`DiscoveredSettlements`),
   not just "is it on screen right now." Once discovered, it stays a valid
   trade target permanently (matching `ExploredTiles`' own "once explored,
   always explored" persistence model), even if the player walks away.
2. **One market, two customers.** A settlement's `Market` (real
   supply/demand stock, `price_for`) is already the single source of truth
   every NPC producer/consumer reads and moves. The player transacting
   against the exact same `Market` instance -- not a parallel player-only
   price table -- means a village genuinely short on rock is *also*
   expensive for the player to sell rock into, and *cheap* for the player
   to buy rock out of at that same village's own real shortage. No
   invented player-only economy sitting beside the real one.
3. **Nothing moves until someone real walks it there.** Exactly
   [trade.md](trade.md)'s pillar 2, extended to the player: a sale to a
   settlement is not a warehouse-to-market teleport. A Hauling Contract's
   goods leave the Warehouse's real stock at dispatch and only reach the
   settlement's real `Market` stock -- or the player's own `Wallet`, for a
   purchase -- when a real courier finishes a real walked trip. A shipment
   in transit is a real target for `CaravanRaid`'s same risk model, same
   as an NPC caravan.
4. **A Trade Route is a Hauling Contract that keeps saying yes.** No
   separate "route" simulation exists -- `TradeRoute.is_due` just decides
   whether it's time to dispatch another identical Hauling Contract, the
   same "decide WHEN, reuse the existing HOW" split every other autonomous
   system in this codebase already uses (see `ConstructionPriority` for
   the equivalent shape gating settlement construction).
5. **The Warehouse is `storage`, owned by the player's household, not a
   new building.** `"storage"` (`item_catalog.gd`) is already exactly this
   shape: a placeable, `StructureStock`-backed container, no skill gate.
   `HouseholdStore.form_household` already lets `PlayerIdentity.
   PLAYER_ENTITY_ID` own real property. A "Warehouse" is simply a
   `storage` structure whose tile is recorded as belonging to the player's
   household -- reusing what's real rather than inventing a second,
   near-identical container type.

## Mechanism

### Settlement discovery

`DiscoveredSettlements` (new, pure): `settlement_id -> world_age_discovered`.
`mark_discovered(id, world_age)`, `is_discovered(id) -> bool`,
`discovered_ids() -> Array[String]`. Deliberately does not decide WHEN a
settlement counts as discovered -- that's a real-world-position check
(distance to the settlement's own landmark, or `ExploredTiles` coverage,
once that's wired to the player's actual movement -- see
[wayfinding.md](wayfinding.md)'s own open gap) that belongs to a thin
glue call site in `EarthChunkManager`/`World`, not to this pure store.
Scaffolded here; the live wiring is listed under Status as not yet done.

### Getting a real price

`PlayerTradeOffer` (new, pure), given a settlement's real `Market`:

- `sell_price_for(market, item_id) -> float` -- what the player receives
  per unit selling INTO this settlement. Below `Market.price_for` (a real
  spread, `SELL_MARKUP_FACTOR`), the same "the house takes a cut" every
  real market has, so a player can't round-trip buy-low-sell-high the same
  settlement for free profit within one visit.
- `buy_price_for(market, item_id) -> float` -- what the player pays per
  unit buying FROM this settlement, above `Market.price_for` by the same
  named factor, mirrored the other direction.
- `can_sell(market, item_id, count) -> bool` -- always true (a settlement
  always has room to buy; its `Market.add_stock` has no cap today, same
  as every other real caller of it).
- `can_buy(market, item_id, count) -> bool` -- false if the settlement's
  own real stock can't cover it (`Market.stock_of(item_id) < count`) --
  the player can't buy out goods that structurally don't exist there yet,
  the same "no phantom output" discipline `StructureStock.remove_stock`
  already enforces.

No new price table, no per-item base price -- `Market.price_for`'s own
uniform-elasticity reference-stock math (see its own doc comment for why
that's deliberate) is the ONLY price signal; this module only adds the
buy/sell spread around it.

### Warehouse

A player-owned `storage` structure -- see pillar 5. Its `StructureStock`
(keyed by tile, exactly like every other placed structure today) is both
where a sale's goods are withdrawn from and where a purchase's goods are
deposited. A player may own more than one; a Hauling Contract/Trade Route
names which warehouse tile it dispatches from.

### Hauling Contract

`HaulingContract` (new, pure state machine, mirrors `LogisticsBehavior`'s
phase shape + `CaravanTrip`'s travel math):

```
DISPATCHED -> traveling (CaravanTrip-style progress_at/is_arrived) -> DELIVERED
                                                              \-> RAIDED (CaravanRaid, same risk model as trade.md)
```

Fields: `warehouse_position`, `settlement_id`, `settlement_position`,
`item_id`, `count`, `direction` (`SELL` or `BUY`), `unit_price` (the
`PlayerTradeOffer` quote **locked in at dispatch**, not re-read on
arrival -- same "a trip's fate/terms are sealed the moment it departs"
discipline `trade.md`'s own open-questions section already commits to for
NPC caravans, so a settlement's price swinging mid-transit can't
retroactively change what an already-departed shipment pays/earns),
`departure_age`, `raided`, `raid_fraction` (identical shape to
`CaravanTrip`, reusing `CaravanRaid.roll_for`/`is_raided` unchanged --
this is not a new risk model).

On dispatch: for a `SELL` contract, `count` units of `item_id` leave the
Warehouse's `StructureStock` immediately (mirrors `trade.md`'s "the
supplier's loss is real the moment it decides to help" -- the goods really
left the warehouse, they're really on the road). For a `BUY` contract, the
player's `Wallet` is charged `count * unit_price` immediately, same
reasoning. Nothing on the OTHER end resolves until the real walked trip
finishes:

- **Arrived, `SELL`**: the settlement's real `Market.add_stock` is
  credited, and the player's `Wallet` is paid `count * unit_price`.
- **Arrived, `BUY`**: `Market.remove_stock`-equivalent (a `Market.stock`
  deduction) fires, and the Warehouse's `StructureStock` receives the
  goods.
- **Raided**: the in-transit goods scatter into the world via
  `WorldItemBus.item_dropped` at the raid position -- same consequence a
  raided NPC caravan already has, not a silent loss and not a special
  player-only "goods are safe" exemption. For a `BUY` contract the
  player's payment was already spent at dispatch and is not refunded --
  the courier was paid to make the trip, not to guarantee its outcome.

A thin `HaulingMarker` Node2D (not scaffolded yet, see Status) would drive
visible movement off `HaulingContract`'s pure `position_at`/`is_arrived`
the same way `CaravanMarker` already drives off `CaravanTrip` -- no new
movement math needed there either.

### Trade Route (autotrading)

`TradeRoute` (new, pure): a saved Hauling Contract *template* --
`warehouse_position`, `settlement_id`, `item_id`, `count`, `direction`,
`interval_seconds`, `last_dispatched_age`. `is_due(route, world_age) ->
bool` is `world_age - last_dispatched_age >= interval_seconds` (or
`last_dispatched_age < 0.0` for "never yet run"). A glue call site (not
scaffolded yet) checks every saved route each real world-time step and
dispatches a fresh `HaulingContract` from any that's due -- the same
"cheap due-check every tick, real work only when due" shape
`ConstructionPriority`'s own settlement-build gating already uses.
Deliberately does NOT auto-cancel on insufficient Warehouse stock/
settlement stock -- a route that can't currently be fulfilled just skips
that tick's dispatch and tries again next interval, the same "a real
production failure caused by a real shortage, not a scripted event"
philosophy `Market.produce`'s own doc comment already commits to.

## Open questions

- **Where does a Hauling Contract's courier NPC come from?** An idle
  villager hired away from their settlement (a real wage, a real
  temporary absence from that settlement's own production loop -- richer,
  but couples this system to `npc_economy.gd`'s labor allocation)? Or a
  dedicated, player-owned courier the player recruits once and reuses
  indefinitely (simpler, no labor-market coupling, but a courier who never
  needs feeding/housing reads as less real than every other NPC in this
  game)? Not decided -- `HaulingMarker`'s eventual design depends on this,
  `HaulingContract` itself does not (it only needs a start/end position
  and a pace, same as `CaravanTrip`).
- **Multiple simultaneous Hauling Contracts per Warehouse**: does a second
  dispatch need to reserve/lock the stock the first already committed to
  in-flight, or is "insufficient stock at dispatch time just fails that
  one dispatch" (mirroring Trade Route's own skip-if-can't-fulfill
  answer above) enough? Leaning toward the latter -- no new reservation
  system needed if a failed dispatch is simply a no-op, not an error.
- **Does the player ever see the settlement's exact live price before
  committing**, or only find out after a contract resolves (more tension,
  closer to the real NPC economy where no one has a live price ticker)?
  Leaning toward showing it -- `PlayerTradeOffer`'s functions are already
  cheap, side-effect-free reads, so there's no real cost to querying one
  before dispatch.
- **Capacity per Hauling Contract**: a flat `count` cap (mirroring a real
  porter's carrying limit, similar in spirit to `LogisticsBehavior`'s
  `CARRY_CAPACITY`), or unbounded (a route just moves however much stock
  is available, letting `interval_seconds` alone govern throughput)? Not
  decided; affects whether large trades need to be split into several
  Hauling Contracts or Trade Route ticks.
- **Does discovering a settlement require a real proximity/visibility
  check, or is finding it via `/village`-style lookup enough to count?**
  Leaning toward requiring real proximity (reaching the settlement's own
  landmark, the same real position `find_nearest_village`/`CaravanTrip`
  already resolve to) -- a dev-console lookup existing is not the same as
  the player having actually been there, and Pillar 1 explicitly wants
  discovery to be a real fact about the player's own history, not a
  data-availability accident.

## Status

- ⬜ **Design only, nothing implemented yet** except where noted below --
  this doc exists so the pure logic can be built test-first against a
  real spec, per this project's TDD-first, concept-doc-precedes-code
  convention.
- ⬜ `DiscoveredSettlements` -- not yet scaffolded.
- ⬜ `PlayerTradeOffer` -- not yet scaffolded.
- ⬜ `HaulingContract` -- not yet scaffolded.
- ⬜ `TradeRoute` -- not yet scaffolded.
- ⬜ Live wiring: settlement-proximity discovery trigger, a
  `HaulingMarker` Node2D, Trade Route's per-tick due-check, and any
  in-world/UI surface for configuring a route or dispatching a one-off
  Hauling Contract -- none of this exists yet. Everything above is pure
  logic only, matching this project's usual order (pure/tested core
  first, thin engine glue after) -- see `civic_construction.md` for
  another currently-design-only doc following the exact same order, and
  `docs/progress.md` for what has actually landed by the time this is
  read (this Status block may be stale relative to that ledger).
- ⬜ Warehouse ownership tracking (which placed `storage` tiles belong to
  the player's household, as opposed to an NPC-built one) -- not yet
  scaffolded; depends on `HouseholdStore`'s existing `property` array, but
  no code writes a placed structure's tile into it yet.
