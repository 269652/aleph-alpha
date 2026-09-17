# The village warehouse

Asked directly: *"Villages should also always build a Warehouse to keep
stocks."*

A `warehouse` already existed before this doc: a real `BuildingCatalog`
entity (4x3, wood 22 + plant_fibre 6, 42 labour hours, capacity 0), classed
civic beside `city_hall`, and rung 3 of `VillageGrowth`'s ladder behind a
four-household threshold. What it did NOT have was any connection to stock
at all — `VillageMarket.stock` and `SettlementGranary` ran entirely
abstractly and neither knew nor cared whether a warehouse stood. It was a
building that looked like storage.

This doc makes it storage, and makes it unconditional.

## Design pillars

1. **Every village has one, from the moment it exists.** Not a rung, not a
   threshold, not something a poor village fails to afford. A settlement
   keeps a store the way it keeps a well: it is part of what "a village"
   means here, not a reward for growing into one. The ladder's four-
   household gate is removed rather than lowered, because a gate that is
   always open is a gate that lies to the next reader.

   **One honest caveat on "always", found by building it.** The reserved
   plot sits on prime ground beside the square — ground a house might have
   needed. On a cramped site, claiming it can tip the layout from "houses
   everyone" to "houses all but one", and a site that cannot house its whole
   roster is founded NOWHERE at all. Reserving a store would then have
   quietly deleted villages from the world, which is far worse than a
   village without one. `VillageLayout.layout` therefore plans twice: with
   the store, and — only if that failed to house everybody — without it. A
   roomy site gets both. A cramped one houses its people and goes without.
   Caught by `test_a_building_already_occupying_ground_keeps_later_ones_
   off_it`, which founded nothing the moment the reservation was added.
2. **Storage is somewhere, not nowhere.** Before this, a settlement's stock
   had no location: it was a number on a market object. A warehouse gives it
   an address, and that address is what the other two pillars hang off.
3. **A roof is a limit.** Stock is bounded by the building that holds it. A
   village without a warehouse could only ever keep what a household could
   stuff in a corner; with one it keeps a real surplus. This is what makes
   the building matter rather than decorate.
4. **Goods arrive by being carried.** Stock that teleports into a number is
   not stock kept in a warehouse. A villager with a full load walks it to
   the door. Reuses the ethogram every other villager behaviour already runs
   on — hauling is a drive like thirst, answered by an address like the
   well — rather than a second, parallel movement system.

## Real-world grounding

A granary is the oldest civic building there is, and it predates the town
hall in most real settlements: Catalhoyuk had storage bins before it had
anything that could be called an institution. Storage is what turns a
harvest into a year, and a village that cannot store cannot over-winter.
That is why pillar 1 refuses the threshold: a settlement small enough to
lack a store is a settlement that does not survive its first bad season, so
it is not a stage real villages pass through.

The capacity rule in pillar 3 is the same reason: pre-industrial storage
limits were structural, not economic. You could not keep more grain than you
had roof for, however good the harvest, which is exactly why surplus years
drove building rather than hoarding.

## Mechanism 1 — It stands from founding

`VillageLayout` already reserves a `civic_plot` on the plaza for the
`city_hall`. It now reserves a second plot for the warehouse on the same
plaza, and the village is generated with the building already standing, the
way its houses and its well are — not queued, not paid for, not owed.

`VillageGrowth` drops `warehouse` from `LADDER_BUILDING_IDS` and
`WAREHOUSE_MIN_HOUSEHOLDS` goes with it. A rung that is satisfied before the
ladder is ever consulted is not a rung; leaving it in would make
`next_building` return a target the village already has, which is precisely
the bug `present_building_ids` exists to avoid.

## Mechanism 2 — The roof is the limit

`VillageMarket` gains a stock ceiling. `add_stock` is the one seam every
deposit already passes through, so the cap lives there: stock is clamped,
and the overflow is simply not kept.

- **Without a warehouse:** a small ceiling — what a village can keep in its
  houses. Enough to live hand to mouth, not enough to bank a season.
- **With one:** the warehouse's own contribution, so a village that has one
  can carry a real surplus.

The ceiling is a property of the settlement's buildings, not a constant, so
a village that loses its warehouse loses the headroom with it. Overflow is
discarded rather than queued: a full store turns a producer away, which is
the pressure that makes the building worth having.

This deliberately does NOT touch `SettlementFood.carrying_capacity`, despite
the name. That function asks how many HOUSEHOLDS the food on hand can feed;
this one asks how much stock the village may hold at all. Two different
questions that happen to share an English word, and conflating them would
put a famine chain that is already real and already tested on top of a brand
new mechanic.

## Mechanism 3 — Goods are carried in

A villager carrying a load walks it to the warehouse door and deposits it
there. This is a wiring on the villager ethogram, not a new system:
`VillagerBehavior` says so in its own header — *"Adding a wiring to
BODY_PLANS['villager'] is all it takes to add a behaviour here"*.

- **The channel:** `WAREHOUSE`, beside `MARKET`/`HOME`/`WATER`. The address
  a loaded villager steers toward, reported by the caller exactly as the
  well already is.
- **The drive:** burden. Unlike hunger or thirst it does not rise on a
  timer; its gain is what the villager is actually carrying, reported by
  the caller. That keeps the ethogram's contract (a drive is a gain in
  0..1) while making "I am full" the thing that presses.
- **The priority:** below the survival drives and above company. A villager
  does not starve holding a sack, and does not stop for a chat with one.

Nothing here replaces the abstract stock. A deposit is still
`VillageMarket.add_stock`; what changes is that something walked there
first.

## Status

- ⬜ **Mechanism 1 — standing from founding.** Not yet built.
- ⬜ **Mechanism 2 — the roof is the limit.** Not yet built.
- ⬜ **Mechanism 3 — goods are carried in.** Not yet built.

## Known open questions

- **What counts toward the ceiling.** Mechanism 2 caps stock as a whole. A
  per-item or per-kind ceiling (grain and iron do not share a shelf) is the
  obvious refinement and is deliberately not attempted first.
- **Who hauls.** Mechanism 3 gives every villager the wiring. Whether
  hauling should belong to an occupation instead — a carter, a porter —
  is a question for once it is visibly running.
