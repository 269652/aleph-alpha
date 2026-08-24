## Trade: what one settlement can't make, another already has

`docs/concept/regional_trade.md` is real and ✅: when a settlement has a
genuine production shortfall, `RegionalTrade`/`Market`/`MarketStore` find
the nearest real settlement with genuine surplus and
`EarthChunkManager._attempt_regional_resupply` ships the goods — real
supply/demand pricing (`Market.price_for`), real distance
(`RegionalTrade.distance_between`), a real safety margin
(`RegionalTrade.has_surplus`), a real `/why`-inspectable event. This spec
does **not** re-solve any of that — it answers the one thing
`regional_trade.md` deliberately left as a shape, not a scene: today a
resupply is an instant off-screen ledger transfer between two `Market`
Dictionaries. Nothing is ever physically IN TRANSIT — this project's own
load-bearing "what you see is what's real" pillar (`disease.md`,
`woodworking.md` both lean on it too) says that shouldn't stay invisible.
This spec makes the SAME real transfer a real, walkable, raidable trip.

This is the third spec from a design-brainstorm session (see `disease.md`
and `geology.md` for its siblings) — a compiled, build-ready doc, not yet
implemented. It also closes a second, still-open gap: `docs/concept/
infrastructure.md` names "Traffic heatmaps, inter-settlement routes,
market nodes" as unbuilt and ties it to `docs/emergence/
07-implementation-roadmap.md` Phase 8 ("repeated movement creates
infrastructure") — a physical caravan is the traffic that gap was waiting
on.

### Design pillars

- **Extend `regional_trade.gd`, don't duplicate it.** The shortage/surplus
  detection, the distance math, the safety margin, the real
  supply-responsive price — all real, all tested, all live. This spec adds
  exactly one new real thing: a physical carrier for a transfer that
  already knows exactly what to move, from where, to where.
- **A caravan is a real NPC walking a real path, not a hidden ledger
  transfer.** This project's load-bearing "what you see is what's real"
  pillar (`disease.md`, `woodworking.md` both lean on it too): the stock
  movement `_attempt_regional_resupply` already computes correctly still
  happens — it happens WHEN a real caravan physically arrives, carried by
  the exact daily-schedule walk/pathfind machinery `NpcMarker` already
  runs, just given a distant waypoint instead of a local one.
- **Roads are earned by trade, not placed for it.** `infrastructure.md`'s
  own "worn, not placed" philosophy, extended to the one case its own
  Status section already flags as the reason `PathScarring` stays
  player-only today ("nothing yet needs [creature-driven wear] enough to
  justify the cost") — a small, bounded number of caravans walking fixed,
  repeated inter-settlement routes is exactly that missing justification.
- **Trade carries real risk.** A caravan en route is a real, ambushable
  target, reusing `RegionDifficulty`'s existing danger-by-distance signal;
  a raided caravan's goods scatter as real, lootable ground items via the
  same `WorldItemBus` mechanism a felled tree or a butchered carcass
  already uses, rather than a number quietly zeroing out off-screen — and
  a raided shipment genuinely fails to arrive, a real consequence
  `_attempt_regional_resupply`'s instant version could never have.

### Real-world grounding

- **Comparative advantage is why trade exists at all.** Real regional trade
  is driven by settlements specializing in what their local geography
  favors — this project already ties farmer/hunter/fisher yield directly
  to real local biome/population numbers
  (`vegetation_growth_model.gd`/`herbivore_population_model.gd`); a
  mountain-adjacent village that just got a real ore export
  (`geology.md`'s just-drafted mining pass) and a grassland village with
  food surplus but no ore is comparative advantage playing out with numbers
  this project already computes, not an invented trade-flavor stat.
- **Price arbitrage is the actual real mechanism.** Real traders profit off
  a price gap between where a good is abundant and where it's scarce, minus
  the real cost of moving it — not off a fixed universal price. That gap
  (and a real transport cost eating into it) is the entire reason a
  merchant makes the trip instead of everyone just paying the same price
  everywhere.
- **Historical trade routes were worn, not built first.** The Silk Road,
  Roman trade roads, and countless medieval market routes all began as the
  literal path repeated caravan traffic wore into the ground — infrastructure
  followed the trade, the trade didn't wait for infrastructure. Exactly the
  order this spec's own mechanism runs in.
- **Caravan raiding is real, well-documented trade risk** across essentially
  every historical trade network with real value moving between settlements
  — the risk this spec's raid mechanic models is not a game invention.

### Mechanism spec

#### A resupply spawns a caravan instead of teleporting (extends `EarthChunkManager.step_regional_trade`)

`_attempt_regional_resupply` already does every real decision correctly —
which item, how much, which supplier, by what distance. The only change:
instead of moving the stock immediately, it moves the stock OUT of the
supplier's `Market` right away (the goods are really gone, really in
transit — the supplier can't get raided for stock it no longer holds) and
spawns a `CaravanMarker` carrying `{item_id, need, destination_settlement_id}`,
rather than crediting the shortage settlement's `Market` in the same call.
The transfer's real destination-side `add_stock` only happens once that
caravan actually arrives (see below) — a real trip with a real duration
and a real chance of failing, not an instant, unconditional guarantee the
way today's version always is.

#### The caravan (`CaravanMarker`, a new dedicated walker — not `NpcMarker`)

Mirrors `DecomposerMarker`'s own precedent for exactly this kind of
problem: a "wrong shape for the full roaming-wildlife/villager AI stack"
mover that just needs to walk from A to B and do one thing on arrival,
built as its own small node rather than shoehorned into `NpcMarker`'s
daily-schedule machinery (which belongs to a different, per-villager
system — `NpcEconomy`/`VillageMarket` — and has no notion of an
inter-settlement trip at all). Real start/end world positions come from
the exact lookup `EarthChunkManager.find_nearest_village` already uses —
`RegionalTrade.chunk_coord_of(settlement_id)` into
`SettlementGenerator.generate_settlement(...).landmarks.well` — so a
caravan walks toward the same real "well" landmark a player teleporting
there would land on, real terrain in between, at a plain constant walk
speed. Arriving calls `_market_store.market_for(destination_settlement_id)
.add_stock(item_id, need)` — the exact call `_attempt_regional_resupply`
used to make instantly, now made for real, on arrival.

#### Roads are worn by real caravan traffic (extends `PathScarring`)

`PathScarring.step_on(tile)` already exists, already wears/decays/
thresholds correctly, and is explicitly scoped player-only today for cost
reasons. A caravan walking a small number of fixed, repeated
inter-settlement routes is a bounded, second real caller of that exact
same function — no new wear model needed. A route two settlements trade
over often enough visibly wears toward `infrastructure.md`'s (not yet
built) trail/road tiers precisely because real trips actually happened
over it, the same causally-grounded, `/history`-inspectable event chain
player paths already get.

#### Trade risk (reuses `RegionDifficulty` and `WorldItemBus`)

A caravan's risk along its route scales with `RegionDifficulty.tier_at`
the same way creature and disease pressure already do — a real, higher
chance of a raid event in HARD-tier stretches. A successful raid doesn't
silently delete the caravan's goods: they scatter as real, lootable ground
items via the same `WorldItemBus.item_dropped` signal a felled tree or a
butchered carcass already uses — a raided caravan is a real scene to
stumble on and loot, first-come-first-served, not a quietly zeroed number.

#### The player's own role

None of the above needs the player — settlements trade with each other
autonomously, the same way ecology and (per `disease.md`) disease already
run without requiring player involvement. A caravan is a real, physical,
lootable-if-raided actor in the world, so the player already has a real
role for free: stumble on one and decide whether to help escort it through
a dangerous stretch or rob it — no new player-facing market UI required
for THIS pass. Actually letting the player buy/sell against `Market`
directly (today it's read only by `regional_trade.gd`/production code, no
player-facing path exists at all — a real, separate addition, distinct
from `shop.gd`'s fixed catalog and from `VillageMarket`'s NPC-only food
stock) and getting paid to escort/guard a caravan (waits on `npc.md`'s own
not-yet-built hiring/wage system) are both natural future extensions,
explicitly deferred, not part of this pass.

### Status

- ⬜ Not yet implemented — compiled design spec from a brainstorming
  session, the deliverable of that conversation, not code.
- ✅ Resolved (not actually open): multi-good generalization. `Market.stock`
  is already a plain `item_id -> int` Dictionary, not food-specific — a
  caravan carrying ore or timber needs no new market shape, just an
  item_id `_attempt_regional_resupply` already names correctly.
- ✅ Resolved (not actually open): candidate-settlement bounding.
  `_attempt_regional_resupply`'s existing nearest-real-surplus loop over
  `_known_settlement_ids()` already IS the bound — a caravan is spawned
  from its decision, not a second search a caravan runs on its own.
- ⬜ Open question: does a caravan need a real, ticking node the whole time
  it's in transit — including while its route runs through chunks nobody
  is near — or does the trip stay an abstract timer (matching this
  project's established "detail scales with player proximity" pattern for
  per-chunk sims) until the player is actually close enough to the route
  for a real walking node to matter? Affects whether `CaravanMarker` needs
  its own lightweight always-ticking existence outside `EarthChunkManager`'s
  normal chunk-load lifecycle. Worth resolving before implementation.
- ⬜ Open question: if a shortage resolves on its own (a local producer
  restocks) before an already-departed caravan arrives, does it still
  deliver (the goods aren't wasted, just now a bonus surplus) or turn
  back? Recommend "still deliver" as the simplest correct behavior — a
  turned-back caravan needs a real return-trip destination decision this
  spec doesn't otherwise need — but not decided here.
- ⬜ Not in this pass, by design: player hiring/escort-for-pay and direct
  player market access (see The player's own role above), the trail/road
  tier thresholds themselves (waits on `infrastructure.md`'s own
  not-yet-built tiers — this spec only supplies the traffic that would
  wear them in).
