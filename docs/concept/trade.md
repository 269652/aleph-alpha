# Trade

[regional_trade.md](regional_trade.md) already makes settlements resupply
each other's real shortfalls from real surplus -- but today that transfer
is instant: stock vanishes from one market and appears in the other in the
same call, with no travel, no time, and no risk. That doc's own Status
section names the gap directly: "Should a resupply be gradual... once
there's a real reason (travel time, trade-route capacity) to model that
lag?" This doc is that reason, built strictly ON TOP OF
`regional_trade.gd`/`Market`/`MarketStore` -- it does not reinvent price
signals, shortage detection, or supplier selection, all of which stay
exactly as regional_trade.md already specifies.

## Design pillars

1. **The supplier's loss is real the moment it decides to help.** Once the
   nearest-surplus settlement is chosen, its stock is gone immediately --
   the goods are really committed, really on the road, and really exposed
   to whatever happens next. Nothing about *deciding* to trade is
   speculative; only the *delivery* is still pending.
2. **The shortage settlement's gain is only real once the goods actually
   arrive.** A real caravan (`CaravanTrip`, pure math + `CaravanMarker`,
   the engine glue) walks the real straight-line route between the two
   settlements' own "well" landmarks at ordinary on-foot NPC pace. The
   destination market is credited, and the "shipped" event becomes real,
   only when that walk actually finishes -- not at dispatch.
3. **Roads are earned by trade, not just by footsteps.** PathScarring
   (see [infrastructure.md](infrastructure.md)) already wears grass into
   dirt paths from repeated player movement. A caravan is a second real
   caller of the exact same `step_on` -- a trade route that runs often
   enough starts to look like one, the same "repeated real traffic creates
   real infrastructure" mechanism, now driven by commerce instead of only
   the player's own feet.
4. **A shipment in transit is a real target, not a guaranteed delivery.**
   [ecosystem_dynamics.md](ecosystem_dynamics.md)'s `RegionDifficulty`
   already grades how dangerous a region is by distance from the world's
   spawn point. A caravan's route inherits that same real danger gradient:
   the more dangerous of its two endpoints' tiers sets a real, per-trip
   chance the shipment is raided along the way. A raided caravan's goods
   scatter into the world exactly like a felled tree's or a smashed
   stone's drop (`WorldItemBus`) -- never silently deleted, and never
   silently delivered anyway.

## Mechanism

`EarthChunkManager._attempt_regional_resupply` still picks the nearest
real-surplus settlement exactly as regional_trade.md specifies, and still
deducts the supplier's market stock in that same call. What it does next
is new:

- Resolves both settlements' real "well" landmark world positions
  (`SettlementGenerator.generate_settlement(...).landmarks.well`, the same
  lookup `find_nearest_village` already uses to turn a settlement into a
  real teleport target).
- Computes a real per-trip raid tier: the WORSE of the supplier's and the
  shortage settlement's own `RegionDifficulty.tier_at` -- a route is only
  as safe as its most dangerous stretch, not just its destination.
- Derives a deterministic, hash-based raid roll from the trip's own real
  identity (`CaravanRaid.roll_for`, salted per purpose: "did it get raided
  at all" vs. "where along the route") -- no `RandomNumberGenerator` state,
  the same reproducible-from-real-inputs discipline `DesertScrub` already
  uses for its own seeding.
- Builds a pure `CaravanTrip` (origin, destination, departure world-age,
  tier, raided flag, raid fraction) and a thin `CaravanMarker` Node2D that
  is driven BY that pure trip, never simulates its own movement.
- Logs a real `regional_trade_departed` event immediately (supplier and
  shortage settlement named, item tagged) -- the trade is real and
  `/why`-inspectable from the moment it departs, even before it resolves.

Every real slice of world time (`World._step_ecology_fine`, after
`advance_world_age`), `EarthChunkManager.step_caravans` advances every
active `CaravanTrip` to the current world age: it moves the trip's marker,
records `PathScarring.step_on` for each new tile the trip's real position
crosses, and resolves the trip exactly once:

- **Raided** (the trip's precomputed raid fraction of the route has been
  reached): the shortage settlement is never credited. The carried goods
  scatter into the world via `WorldItemBus.item_dropped` at the raid
  position, and a real `regional_trade_raided` event is logged.
- **Arrived** (the full route has been walked): the shortage settlement's
  market is credited with the shipment, and the real
  `regional_trade_shipped` event is logged -- the same event type
  regional_trade.md already named, now firing on real arrival instead of
  at dispatch.

A settlement's production shortfall can name several missing items in one
`step_regional_trade` pass (e.g. a blacksmith short both rock and stick for
a `stone_pickaxe`) -- each missing item dispatches its OWN independent
caravan, with its own independent raid roll, so one item's shipment being
raided never blocks or couples to another's.

## Status

- ✅ Deferred, real-travel-time delivery: the supplier's stock is real gone
  at dispatch, the shortage settlement's credit and the `shipped` event are
  real only on arrival (`caravan_trip.gd`, `EarthChunkManager.
  step_caravans`/`_attempt_regional_resupply`/`_resolve_caravan_arrival`).
- ✅ Real raid risk scaled by the real `RegionDifficulty` gradient
  (`caravan_raid.gd`), with real scattered-goods consequences on failure
  (`_resolve_caravan_raid`, `WorldItemBus`) instead of a silent loss.
- ✅ A second real `PathScarring.step_on` caller: a caravan's route wears
  real ground the same way player footsteps already do
  (`_caravan_path_scarring`).
- ✅ `step_regional_trade` and `step_caravans` are both wired into
  `World._step_ecology_batch`/`_step_ecology_fine` -- this system runs in a
  real session, not only under test.
- 🚧 Caravan wear uses its OWN `PathScarring` instance
  (`EarthChunkManager._caravan_path_scarring`), separate from
  `World._path_scarring`'s private player-tracking one. Both are real and
  tested, but a caravan's worn tiles are not yet folded into the same
  rendered dirt-path pass the player's own footsteps already drive
  (`World._step_path_scarring`) -- a real, scoped follow-up, not a silent
  gap.
- ⬜ `CaravanMarker` art is a minimal placeholder silhouette
  (`ProceduralCaravanSprite`), not a real pack-animal/cart depiction --
  same "no unique found-treasure traversal items" scope
  [transportation.md](transportation.md) already keeps for vehicles: no
  cart/wagon system exists yet, so a caravan is a porter on foot.
- ⬜ Gradual/partial shipments (a trip delivering SOME of its cargo before
  a raid, or splitting one need across multiple smaller trips) --
  regional_trade.md's own open question about a trade-route CAPACITY, as
  opposed to just a travel-time lag, is still open.

## Open questions (from regional_trade.md, revisited)

- **"Does a caravan need a real always-ticking node even far from the
  player, or stay an abstract timer until the player is near its route?"**
  Decided here: `CaravanTrip`'s progress is a pure closed-form function of
  world age, so it needs no per-frame ticking of its own at all --
  `step_caravans` reads `_world_age_seconds` (already advanced elsewhere)
  and resolves whatever's due. Its `CaravanMarker` IS a real, always-live
  Node2D for the trip's whole duration regardless of chunk load/player
  proximity (unlike DecomposerMarker's per-chunk lifecycle) -- defensible
  because caravans are rare (one shortage-driven dispatch, throttled by
  `REGIONAL_TRADE_INTERVAL`), not a per-chunk population, so the live-node
  count stays small. Worth revisiting only if concurrent caravan counts
  ever grow large enough for that to matter.
- **"Does an already-departed caravan still deliver if the shortage
  resolves itself first?"** Decided here: yes, unconditionally. A trip's
  fate (raided or not, and where) is sealed at departure -- re-checking the
  shortage settlement's CURRENT need before crediting would let a shortage
  that fluctuates mid-transit silently cancel or resize a shipment that's
  already, physically, on the road. An over-delivered settlement just ends
  up with real surplus of its own, which is itself a real input to a
  FUTURE regional-trade resupply elsewhere -- not a bug, the same
  "structural consequence, not scripted" pillar regional_trade.md's own
  design pillar 3 already commits to.
- Third-party/trade-hub intermediaries: still open, unchanged from
  regional_trade.md -- not needed while nearest-neighbor resupply stays
  the whole network.
