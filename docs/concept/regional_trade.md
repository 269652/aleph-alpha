# Regional Trade

A settlement's economy doesn't stop at its own market. Once more than one
real settlement exists, what one settlement lacks and another has too much
of is the seed of the plainest possible trade network — per
`docs/emergence/07-implementation-roadmap.md`'s Phase 14: "Implement
regions, trade networks, migration flows, dependency graphs, and resource
corridors. A regional shock should alter multiple settlements." Settlement
growth via NPC *migration* is a separate, already-designed concern — see
[quests.md](quests.md#settlement-growth-migration-and-player-founded-villages)
— this doc is specifically the trade-network half.

## Design pillars

1. **One real edge before a graph.** A trade "network" here is the
   smallest possible one: a single settlement resupplying a single other
   settlement's real, already-discoverable shortage
   ([quests.md](quests.md)'s Production need source, Emergence Phase 12).
   Dependency graphs and resource corridors are aggregations *over* real
   trade edges, not a separate structure to invent before any real edge
   exists.
2. **Reuse the shortage/surplus signals this project already has.** A
   settlement's shortfall is already a real, live-projected `Quest`
   (Phase 12); its surplus is already real `Market` stock (Phase 5). No
   new "who needs what" or "who has extra" tracking is invented — this
   doc only adds the cross-settlement CONNECTION between two numbers that
   already exist independently.
3. **A regional shock is a real, structural consequence, not a scripted
   one.** Because supply moves FROM a real settlement's own stock TO
   another's, draining a supplier to help a neighbor is the same real
   mechanism that could later leave the supplier short itself — "a
   regional shock alters multiple settlements" falls out of moving real
   stock between real markets, not a bespoke propagation system.

## Trade networks: nearest-supplier resupply

When a settlement has a real production shortfall (a household's
occupation-grounded recipe is missing a specific item — Phase 12's own
`Quest.production_shortfall_quests_for`), the NEAREST other real settlement
holding genuine SURPLUS of that exact item ships enough to cover it. "Real
surplus" means holding more than the shortfall needs by a real safety
margin (`RegionalTrade.MIN_SURPLUS`) — a settlement never trades away its
own last reserve down to the exact edge just to help a neighbor.
"Nearest" is real Euclidean distance between the two settlements' own
chunk coordinates (the same key `EntityRef.for_settlement` already derives
a settlement's identity from — no second position to track). The transfer
is a real, `/why`-inspectable `regional_trade_shipped` event naming both
settlements and the item.

## Migration

Fully specified already in
[quests.md](quests.md#settlement-growth-migration-and-player-founded-villages)
(habitability pull, replan-based push, a migration floor before a location
is eligible, player-invite acceleration) — not repeated or re-scoped here.
See Status below for what's actually built of it.

## Status

- ✅ Trade networks: nearest-supplier resupply is real
  (`regional_trade.gd`, `EarthChunkManager.step_regional_trade`),
  automatic, and live-verified.
- ✅ The resupply itself is no longer instant — see
  [trade.md](trade.md), which builds directly on top of this doc's own
  supplier-selection/surplus math to give a dispatched resupply a real
  travel time, a real caravan, and real raid risk along the way. This
  doc's own supplier-selection and surplus math are unchanged; only WHEN
  the shortage settlement is actually credited moved.
- ⬜ Dependency graphs / resource corridors — real aggregations over trade
  edges once enough of them exist; this slice only builds the one real
  edge, not the aggregation layer on top.
- ⬜ Migration flows — `quests.md`'s own design is unbuilt (needs the
  replan-interrupt architecture and a real habitability/push signal,
  neither of which exist yet).
- ⬜ Regions as a first-class grouping (a named cluster of nearby
  settlements) — not needed for nearest-neighbor resupply to work, and not
  built; would matter once dependency-graph aggregation is real.

## Open questions

- Should a resupply be gradual (partial shipments over several steps,
  i.e. a trade-route CAPACITY) rather than resolving a shortage fully in
  one trip? [trade.md](trade.md) answers the travel-TIME half of this
  question (a resupply now has a real single-trip delay); splitting one
  need across multiple smaller shipments is still open.
- Does regional trade ever need a THIRD-PARTY intermediary (a trade hub
  settlement) once more than two real settlements commonly coexist, or
  does nearest-neighbor resupply stay sufficient indefinitely?
