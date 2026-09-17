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

   The caveat under pillar 1 reaches here too, and it decides the default.
   A village with no store has nowhere to carry to, so its producers keep
   stocking it where they stand, exactly as they always did. Carrying is
   what a store BUYS a village, not a tax every village pays; otherwise
   "this site had no room for a warehouse" would have quietly meant "this
   village starves".

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

**The store goes up before the works, and the order is load-bearing.** The
store stands on a fixed reserved plot beside the square and cannot move; the
sawmill is sited wherever there is timber and a clear road spur back to the
street, and that spur is searched for against what is already standing.
Placed the other way round, a spur laid first gets CUT — raising the store
lifts every road cell under its footprint and puts back only its doorstep
(`place_building_over_roads`), so a mill whose spur happened to run across
the reserved plot was left with no road home. Found by
`test_the_real_sawmill_is_walkable_back_to_the_street_on_road`, and it is
worth naming why no stub-world test could have seen it: `StubWorld`'s
`build_at_global` records road cells into a different dictionary from the
one `modification_at_global` reads, so paving and placement never actually
collide there the way they do against the real world.

**A reload raises it too.** `_recover_existing_village` never runs the
founding placement at all, so a village founded before there was such a
thing as a store would have come back storeless forever, and pillar 1 would
only ever have been true of villages founded after this pass. The hall is
raised on reload for the same reason.

**The store takes street frontage, and farmsteads move to the outskirts.**
That is the intended consequence, not a side effect: prime ground beside
the square goes to the building that has to be beside the square, and a
farmstead belongs on the edge with its field anyway (`outskirt_plot` exists
for exactly that, and `village_farms.md` already prefers it for a village
hemmed in by water).

It is worth recording because of what it exposed. `next_street_plot` stops
finding room for a farmhouse, so every farmstead now searches the whole
chunk — and `_field_fits_at` asked `VillageRenderer._is_street_row` about
every cell of every candidate field ring, which recomputed the entire
`VillageLayout.skeleton`, scan for a dry square and all, **per cell**. One
founding made 106,722 skeleton calls; village founding went from 29s to
415s on a real chunk load, a 14x regression. The store did not cause that
— it walked the village onto a path that had been quietly quadratic all
along. `VillageRenderer` now caches the skeleton and the ground predicate
for the life of one founding (both derived from ground, which does not move
while a village is being built), and founding is back to parity: 30s, with
`spawn_village` itself down from 25.6s to 4.4s and 10 skeleton calls.

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
BODY_PLANS['villager'] is all it takes to add a behaviour here"* — and this
is the first behaviour actually added that way, which is the claim finally
being tested.

- **The channel:** `WAREHOUSE`, beside `MARKET`/`HOME`/`WATER`. The address
  a loaded villager steers toward, reported by the caller exactly as the
  well already is.
- **The drive:** burden. Unlike hunger or thirst it does not rise on a
  timer; its gain is what the villager is actually carrying, reported by
  the caller. That keeps the ethogram's contract (a drive is a gain in
  0..1) while making "I am full" the thing that presses. It is deliberately
  a STEP and not a ramp: the haul wiring is the only one listening on the
  store, so any gain above zero fires it, and a ramp would send a villager
  off with one apple in hand and they would never work again.
- **The priority:** below the survival drives and above company. A villager
  does not starve holding a sack, and does not stop for a chat with one.

Nothing here replaces the abstract stock. A deposit is still
`VillageMarket.add_stock`; what changes is that something walked there
first.

### Four things building it settled

**An unreported need used to press hardest of all.** `BehaviorKernel` reads
a gate that is absent from the drive vector as WIDE OPEN — right where it
was written, since the mammal adapter publishes every drive it runs, so an
absent one means "this wiring is ungated". Burden is the one villager gate
nothing publishes: it is on no clock, so `Drives.gains()` has never heard of
it and never will. Left alone, every villager within sight of a store would
have set off to haul an imaginary load, ahead of ever taking a drink.
`VillagerBehavior` now reads an unreported need as pressing nobody — the
same contract its stimuli already kept for places, where a channel the
caller did not report is simply not there.

**Full hands gather nothing.** Not "the surplus is discarded": every unit a
producer gathers costs the region a real herbivore, crop or fish through
`NpcEconomy`'s own depletion calls. A producer who kept working with nowhere
to put the take would go on killing for units nobody can hold. The walk to
the store is what makes room, which is the point.

**Carrying is opt-in, from the ground rather than the plan.**
`NpcEconomy.carry_limit` defaults to 0.0 — do not carry, stock the village
where you stand — and is raised only for a villager whose settlement really
has a store. That is the same shape mechanism 2 gave `storage_capacity`, for
the same reason: a limit that depends on which buildings stand belongs to
whoever knows that. It also keeps pillar 1's caveat honest in the one place
it matters most — a cramped village with no store must still be stocked, or
"no room for a warehouse" would quietly become "famine". `VillageRenderer`
reads the door off `buildings_in_chunk`, not off `VillageLayout`: the plan
and the ground disagree on purpose, and a reloaded village never re-runs
the founding placement at all.

**How big a load is.** One villager's trip is a quarter of what a village
keeps without a store — four trips fill a storeless village, forty fill one
with a roof. That second ratio is the tuned number, and it is tuned by what
it says about the BUILDING: a store that took one trip to fill would not be
worth raising, and one that took a thousand would make hauling the only
thing anybody ever did.

## Status

- ✅ **Mechanism 1 — standing from founding.** `VillageLayout` reserves the
  plot, `VillageRenderer` raises it — at founding and on reload, and ahead
  of the sawmill so the mill's road spur is routed around it rather than
  cut by it — and the ladder rung is gone. See the caveat under pillar 1 for
  what "always" honestly means on a cramped site.
- ✅ **Mechanism 2 — the roof is the limit.** `VillageMarket.storage_
  capacity` clamps `add_stock`, defaulting to INF so no existing caller
  changed behaviour, and `EarthChunkManager`'s settlement step sets it every
  step from the ids actually standing — so losing the warehouse loses the
  headroom. `capacity_for_structures` keeps that decision testable without
  building a world.
- 🚧 **Mechanism 3 — goods are carried in. Built, tested, and switched
  OFF in a live village** (`NpcMarker.HAULING_CARRY_LIMIT` is 0.0).
  Reported immediately after 0.0.2: *"no stock gets produced anywhere"*.
  Turning carrying on puts the villager's hands in the middle of a chain
  another pass had just built — `_step_farm` empties the farmhouse straight
  into `record_real_harvest`, which with a carry limit goes to the hands
  rather than the market — and a producer who GATHERS stops dead once their
  hands are full, because `_gather` takes nothing more. Nothing caught it:
  every marker a test builds sets no `warehouse_position`, so `carry_limit`
  stayed 0 and both sides passed honestly in isolation.

  What follows is all real and all still there; only the caller that opts a
  live villager in is off. `Ethogram` gained the
  `WAREHOUSE` channel and the `DRIVE_BURDEN` gate (wired under every
  survival need, over company, and with no `drives` profile entry so no
  clock can raise it); `VillagerBehavior` gained the `HAUL` intent purely by
  that wiring existing. `NpcEconomy` holds the take in `carried` until
  `deliver_load`, and `NpcMarker` walks a loaded villager to
  `warehouse_position` and empties their hands on arrival —
  `VillageRenderer` hands every villager the door of the store that really
  stands in their chunk.

## Known open questions

- **What counts toward the ceiling.** Mechanism 2 caps stock as a whole. A
  per-item or per-kind ceiling (grain and iron do not share a shelf) is the
  obvious refinement and is deliberately not attempted first.
- **Who hauls.** Mechanism 3 gives every villager the wiring. Whether
  hauling should belong to an occupation instead — a carter, a porter —
  is a question for once it is visibly running.
