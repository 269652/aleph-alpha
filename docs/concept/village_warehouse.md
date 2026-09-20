# The village warehouse

Asked directly: *"Villages should also always build a Warehouse to keep
stocks."*

A `warehouse` already existed before this doc: a real `BuildingCatalog`
entity (3x3 — 4x3 until 2026-09-17, see building.md's "Building
sheets"; wood 22 + plant_fibre 6, 42 labour hours, capacity 0), classed
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
a village that loses its warehouse loses the headroom with it — but it is
applied **only while the settlement's chunk is loaded**. Not being able to
see a village must never read as "it has no warehouse". Without that guard
every settlement the player was not standing in had its market clamped to a
household's corners and everything above silently discarded, because the
structure scan answers "nothing stands here" for an unloaded chunk.

And it is read straight off the chunk's own building records rather than
through `has_structure_near`, which walks every modification of nine chunks
once per placeable id in the catalog. Occasionally, for a build decision,
that is affordable; every settlement every step it is not, and it gets worse
as villages pave themselves — reported live as the frame rate decaying over
time. Overflow is
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

## Mechanism 4 — The carter

Asked directly, with the empty store in shot: *"The warehouse also needs to
bind a worker which then collects all ressources from every production
building"*, and then corrected, with the wagon in shot: *"It should be a
real NPC pulling the cart, not an additional sprite"*.

Both halves matter, and the correction is the design. A village's hauling is
a **trade**, not a spawned walker: `carter` joins the occupations a villager
can be born to, and a carter works the store's round exactly the way the
lumberjack works the mill, the farmer works their beds and the fisher works
their pond — an `NpcMarker` work step that overrides the schedule's
decorative workspot, built on the same `LogisticsBehavior` phase machine the
placeable-scale worker already uses. Nothing about the round is reinvented;
what changes is who walks it.

This answers the open question Mechanism 3 left standing — *"whether hauling
should belong to an occupation instead — a carter, a porter"* — the way the
report does.

- **The round.** From whichever producer has the most waiting on its shelf,
  to the store's own door, and back. A carter with nothing to fetch keeps
  the ordinary schedule, like every other villager whose work has nothing
  in it today.
- **What they carry it in** is the Bollerwagen (Mechanism 5), which is the
  point of the trade existing: the goods ride on the cart, not in the
  carter's hands.
- **A named consequence.** A villager's trade is rolled from
  `NpcIdentity.OCCUPATIONS` by index, so adding one re-rolls every
  villager's trade in every village in an existing world. Names, houses and
  seeds are unchanged; who does what shifts. That is the price of a trade
  being a real trade rather than a special case bolted beside them, and it
  is stated here rather than discovered.

## Superseded — The store binds its own porter

*Kept for the record; replaced by Mechanism 4 above.* The first pass spawned
a `LogisticsMarker` per (store, producer) pair — the same worker the
`sagewerk`→`storage` placeables use. It worked, and it was the wrong shape:
a second kind of person, drawn with a placeholder sprite, walking beside the
villagers who already live there. The `LogisticsMarker` keeps its original
job (the single-tile placeables); a village's own store is a carter's.

Asked directly, with the empty store in shot: *"The warehouse also needs to
bind a worker which then collects all ressources from every production
building"*, and *"the warehouse stays empty"*.

This answers the open question Mechanism 3 left standing — *"whether hauling
should belong to an occupation instead — a carter, a porter"* — and it
answers it the way the report does: **the store binds the worker, not the
producer.** A village's mill, farmhouse, smith and brewery each keep their
own output on their own shelf, and a porter the warehouse itself employs
walks the round and carries it in.

It is the `LogisticsMarker` the Sägewerk/Storage pair already uses, bound to
a whole-building warehouse and a whole-building producer instead of the two
single-tile placeables. Nothing about the walk, the cart load or the
put-it-back-on-failure is reinvented: one porter per (warehouse, producer)
pair within the store's own reach, spawned when either is raised and
despawned when either goes.

**A porter carries whatever is waiting.** The existing worker hauls one
named item id, because the Sägewerk has exactly two outputs and the caller
knows them. A village producer's shelf is not a fixed list — a farmhouse
holds whatever crop its farmer sows, a mill holds logs on the way to
becoming beams — so naming the goods in advance would be inventing a
catalogue that drifts from what the buildings really hold. A porter with no
item id named takes the largest load waiting on the shelf and comes back for
the rest.

**Why this is what was missing.** The whole logistics system was wired for
`sagewerk` → `storage`, the two single-tile placeables. A real village
raises a `sawmill` and a `warehouse`, which are whole-building catalog
entities, and `place_building` staffs nobody at all — so every village
producer filled its own shelf and nothing ever moved it. The store was
empty because nobody was carrying.

## Mechanism 5 — The Bollerwagen

Asked directly, with the art in hand: *"I added a cart sprite with a
Bollerwagen; please wire it and make the Warehouse Worker use it to move
heavy ressources to the warehouse.. it should be so that the ressources are
actually loaded inside the wagon which has an inventory; so if the worker
leaves it somewhere it's actually full of ressources... once in the
warehouse he unloads"*.

**The load is on the cart, not in the worker.** That is the whole point and
the whole design: `CartLoad` is a real `item_id -> count` store that lives on
the cart's own node. A cart standing in a field is a cart with the timber
still in it — leave it behind, unload it later, come back to it tomorrow.
Nothing about the goods is bookkeeping held on the person.

**Who pulls it** is the carter of Mechanism 4, a real villager — corrected
in play once the first pass gave the wagon to a spawned walker: *"The cart
is not being pulled by a worker, but by a floor tile???"*, and then *"It
should be a real NPC pulling the cart, not an additional sprite"*. One wagon
per carter, spawned with the village and freed with it.

- **Capacity.** A cart carries six of the porter's own armfuls
  (`LogisticsMarker.CARRY_CAPACITY`), which is also more than the 12 wood
  the growth ladder's cheapest rung needs — a cart that could not bring
  home a whole small house's timber in one trip would not be worth pulling.
  Both relationships are test-pinned rather than the number asserted.
- **Loading.** At the producer the carter fills the cart until the shelf is
  bare or the cart is full. A load that will not fit is left on the shelf
  rather than destroyed.
- **Unloading.** At the store the cart is emptied into the warehouse's own
  `StructureStock` — all of it, every item id it is carrying, in one
  arrival.
- **Drawing it.** `assets/sprites/vehicles/cart.png` is a magenta-divided
  sheet, measured as 4 rows × 5 columns: the rows are the four views (rear,
  east, west, front) and the columns are a roll cycle — measured, the
  difference from column 0 grows monotonically across the row, which is an
  animation rather than five unrelated variants. The wheels turn only while
  the cart is moving. The bands are pinned explicitly, the same call
  `illustrated_structure_sprite.gd`'s own `explicit_frame_image` was added
  for.

## Mechanism 6 — The cart is a thing you can take hold of

Asked directly, once the wagon was rolling: *"The cart should also be a real
entity with hitbox and clicking on it shows the popup with inventory and the
player should also be able to grab/pull it"*.

A cart that a carter pulls past you and that you cannot touch is scenery with
an animation. Three things make it an object instead, and they are three
different systems — being in the way, answering a question, and changing
hands — so they are specified separately.

### It is in the way

A `StaticBody2D` on the ground floor's own collision layer
(`EarthChunkManager.GROUND_FLOOR_COLLISION_LAYER`), a child of the cart so it
moves and is freed with it. Exactly the shape the well's own hitbox already
uses (`VillageRenderer._solid_body_for`) and for the same reason: the thing
IS what is in the way, so a separately-tracked body would be one more thing
to keep in step.

Sized off the drawn frame, not off a constant: a cart is `WIDTH_TILES` of
road wide and stands on its own wheels, so what stops you is the box at its
foot rather than a column of air above it.

### It answers the cursor

The cart joins `HoverTargetFinder.GROUP_NAME` and answers
`get_display_name()` and `get_hover_actions()` like every other interactable
in the world. Its name says what is in it — an empty cart and a loaded one
are different things to walk up to — and its one action is on the
`primary_action` context slot, which is exactly what that slot is for:
*"What they do is decided by whatever is under the cursor and the state it is
in"*.

### Clicking it shows what is in it

A left-click opens the same readout a building opens (`HousePanel`), because
the question is the same question and the panel is already a pure consumer of
a Dictionary — it renders what it is handed and reaches for nothing else.
`CartMarker.report()` hands it a title, a subtitle naming who has the shaft,
its `stock`, and `CartLoad.CAPACITY` as `storage_capacity`, and the existing
inventory tab draws the load.

The panel grows exactly two seams for this: an explicit `title`/`subtitle`
override, used when a report carries one. Nothing that already opened it
changes — a building carries neither key and keeps the building naming it
always had.

A cart under the cursor wins over the building underneath it. A cart is
standing ON a village's paving and often beside its store; a click that read
through it to the warehouse would make the wagon unclickable exactly where
carts spend their time.

### It changes hands

`held_by` is whoever has the shaft, and `pulled_toward` follows them. The
rules are the rules of a real handcart:

- **Only a person may take the shaft at all.** `take_hold` refuses anything
  outside `CartMarker.PULLER_GROUP`, forced or not — the group every real
  person in this world joins, villagers and the player alike. Reported three
  times in the same words (*"the cart is not being pulled by a worker, but by
  a floor tile???"*, *"It should be a real NPC pulling the cart, not an
  additional sprite"*, *"The cart is still town by a floor tile instead of an
  actual dedicated worker NPC"*), so the answer is a rule rather than another
  round of corrected wiring: a thing that is not a person **cannot** pull a
  cart, and no future caller can reintroduce one that does. The
  placeable-scale `LogisticsMarker` has had its cart machinery removed
  outright; it carries in its arms.
- **A carter only ever takes a FREE cart.** `take_hold(who)` fails when
  somebody else has it.
- **The player's hold displaces.** `take_hold(who, true)` always succeeds. A
  villager is not going to wrestle the player for a wagon, and the alternative
  — the player being refused by an NPC's claim — is the kind of rule that
  reads as a bug.
- **A carter who has lost the shaft drops the round** rather than walking it
  empty-handed: no shelf is emptied into a cart the carter is not holding, so
  goods are never moved into thin air.
- **Letting go parks it.** `let_go(who)` releases only if `who` really holds
  it, and a parked cart stays exactly where it was left, still loaded — which
  is Mechanism 5's whole point, now reachable by the player as well.
- **A carter reclaims a parked cart** on their next round. A wagon abandoned
  in a field is village property again the moment nobody is holding it.

## Mechanism 7 — The store is where the goods really are

Reported in play: *"The FarmHouse seems to be harvesting something but none
of it makes it into storage... it's always 0"*.

It was true of both places you could look. A farmer cut wheat onto their
farmhouse's own shelf — and then, at the end of every work block, carried the
**whole shelf** into the village's abstract ledger
(`NpcEconomy.record_real_harvest`, which credits the market and pays the
farmer in one call). So a farmhouse you clicked was empty, a store you
clicked was empty, and the carter of Mechanism 4 arrived at a shelf somebody
had already emptied into thin air.

The village's goods have to be somewhere you can point at. So:

- **A harvest goes on its producer's own shelf and stays there.** The
  end-of-block carry is gone for any village that HAS a store — the shelf is
  the carter's to empty, which is the whole reason the trade exists. **Every
  producer**, not just the farmhouse: the sawmill had the identical carry
  (`haul_sawmill_stock_to_village`, run off the clock from `_step_timber`),
  and it was reported in exactly the same words with the mill's own panel in
  shot reading *"Stored: 0 / 60, Beam x0, Log x0"* — *"The sawmill also
  doesn't produce beams or plangs or logs"*. It produced them all along.
- **The villager is paid at the work**, not at the delivery — at the scythe
  for a farmer, at the saw for a sawyer. They did the work; the pay is for
  the work. `record_harvest_wage` is `record_real_harvest` with the stocking
  taken out.
- **The carter's arrival at the store is what credits the village's
  sellable stock.** One credit, at the moment the goods really get there —
  so nothing is counted twice, and the market's numbers describe a pile that
  exists. **The credit is the pile itself now** (corrected 2026-09-20): see
  "One credit meant one" below.
- **A village with no store keeps the old behaviour exactly.** The producer
  carries their own shelf in and is paid and credited in one go, as before.
  That is not a leftover: a hamlet too cramped to raise a store (pillar 1's
  caveat) still has to eat, and `VillageRenderer` already tells every
  villager whether their village has a store door, so the villager can tell
  which world they are in without asking anybody.

**What this does not change.** Gold. `record_harvest_wage` pays exactly what
`record_real_harvest` paid, at exactly the same moment, so no villager earns
more or less than before and the levy split is untouched. What moved is
*where the goods are* between the field and the market.

## One credit meant one, and two later changes made it two (2026-09-20)

Mechanism 7's rule is *"ONE credit, at the moment the goods really get
there — so nothing is counted twice, and the market's numbers describe a
pile that exists."* It stopped being true, without anybody touching it.

`_unload_the_cart` put the load on the store's shelf **and** called
`NpcEconomy.record_delivered_goods`. That was one credit when it was
written, because the shelf was invisible to every food reading in the game.
Two things landed afterwards:

1. [milling_and_baking.md](milling_and_baking.md)'s *"Food that counts"*
   taught `SettlementFood` to count structure shelves — so the pile on the
   shelf became a credit in its own right.
2. Hauling was switched on, so `NpcEconomy._stock` routes that second
   credit into the **carter's own hands**, which `deliver_load` later
   empties onto the stall.

N units delivered became N on the shelf plus N on the stall. Food invented,
by a rule written to prevent exactly that.

**The pile on the shelf IS the credit.** `SettlementFood` counts it, the
settlement card reads it, and `MerchantVisit` buys off it.
`record_delivered_goods` is gone rather than merely unused, so there is no
way back in. What reaches the stall reaches it by the leg below, out of
that same shelf.

## Mechanism 8 — The stall is the shop window of the store

A market stall is not a warehouse. It is the shop window of one: filled
each morning from the store behind it and holding about a day's trade —
which is exactly why a village can look *"out of bread"* at the stall while
its granary is full.

That leg did not exist, and it is the one
[milling_and_baking.md](milling_and_baking.md) already named as open work:
*"Three food containers, one eater… nothing ever moves food between them."*
Measured (`tools/probe_food_containers.gd`), every container printed
separately over a 600-second watch of a real village:

```
  seconds farmhouse warehouse    STALL  ledger  hands  carts
      100         5         0        0       0      0     12
      200        15        12        9       0      0      2
      300         3        16        0       0      0      2
      400        23        13        0       0      0      2
      500        22         9        0       0      0      8
```

The chain works right up to the store — a farmhouse fills, a carter's round
empties it onto a cart, the cart empties into the warehouse — and the
**stall**, which is what `VillageMarket.buy_meal` actually sells from, is
empty at every sample but one. (And that one was the double credit above,
not the chain working.)

`StallRestock` is the leg, pure and static like everything else here:

- **A stall holds one day's eating for the village**, derived rather than
  picked: `households × SettlementState.FOOD_PER_HOUSEHOLD`, and that
  constant is already pinned to the hunger clock by its own test. Retuning
  what people eat retunes the stall with it.
- **Only the shortfall**, never the whole target again — a stall that drew
  a full day on every settlement step would pull the store empty one step
  at a time.
- **Real units move.** Whatever reaches the stall is withdrawn from the
  store's own shelf, so the village holds exactly what it held before, in a
  different place. Never more of an id than the shelf has.
- **A village with no store has no shop window to fill**, and keeps the
  behaviour it always had: its producers carry their own take in
  (`haul_stock_to_village`), exactly as Mechanism 7's last bullet already
  rules.

Measured after both halves, on the same watch:

```
  seconds farmhouse warehouse    STALL
      200        17         0       12
      300        12         7        2
      400        10        21        0
      500         7        15       10
```

The stall peaks at exactly 12 — ten households times a day's ration — and
the farmhouse backlog falls from 22–23 to 7–10, because the food is moving
through rather than piling up at the end of the chain.

## A store its own people may eat from

Reported live with a stocked store in shot: *"there's still not enough
food even though the warehouse is full"*. Both halves of that sentence
were true at once, and the two halves of the codebase disagreed.

A settlement's food **assessment** counts every `StructureStock` standing
in its chunk (`EarthChunkManager._settlement_structure_stocks` →
`SettlementFood.carrying_capacity`), so the grain a carter hauls in really
is food the village has. An individual villager's **meal** came from
`STRUCTURE_MEAL_SOURCE_IDS` — a hand-written list of `bakery` and
`storage`, written before this building existed and never grown to include
it. The village was fed on paper while its people starved beside a full
store.

The warehouse is now one of the places a villager may eat from. The list
stays hand-written, because the meal search scans *for* ids — which is
exactly how it drifted — so what is pinned is the behaviour rather than
the list: *what the settlement counts as food is what its people can eat*
(`test_earth_chunk_manager_village_meals.gd`). The next store added here
fails a test rather than starving a village quietly.

### ...and the same split, one layer up

The settlement's own food FIGURE had the identical flaw.
`SettlementFood.food_stock` documents its third argument in its own words
as *"a Storage holding hauled bread, a Bakery with loaves still on its
shelf"* — shelves people eat off — but
`EarthChunkManager._settlement_structure_stocks` handed it **every** shelf
in the chunk. A farmhouse is where a harvest waits for the carter, not a
place anybody eats.

Measured on a real village (`tools/probe_village_famine.gd`) whose hunger
was pinned at 1.00 and whose worst-off villager was 174 of 200 through
the starvation window:

```
settlement Market : 0
VillageMarket     : 0
structure shelves : 234   (three farmhouses; nobody could eat any)
```

234 units over twelve households is 19.5 each against
`VillageImmigration.FED_THRESHOLD` of 2.0, so the village read as richly
fed and kept drawing households into a famine.

Fixing the CALLER rather than the immigration gate repairs every reader at
once — the gate, the settlement's GROWING/DECLINING status, the food
shortfall a build decision acts on, and the settlement card's own "feeds
N of M" — instead of narrowing one and leaving five believing a different
number.

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

- ✅ **Mechanism 4 — the carter.** `carter` is a real entry in
  `NpcIdentity.OCCUPATIONS`; `VillageCart` decides whose shelf is worth
  walking to, `LogisticsBehavior` decides when each leg of the round ends,
  and `NpcMarker._step_cart` owns the world effect — the same three-part
  split the sawyer and the farmer already keep. `VillageRenderer` hands each
  carter the store that really stands, the producers on their round and a
  wagon of their own. `SettlementGenerator` conscripts one carter when a
  roster rolled none: measured over the 75 real grassland villages in rows
  0–5, 7 of them (9.3%) had a store nobody could ever empty, and 0 do now.
  The `LogisticsMarker`-based store porter is **removed**; that class keeps
  its original job, the single-tile `sagewerk`→`storage` placeables.

  **Corrected 2026-09-19, and it took three separate causes.** Reported with
  the readout open at "Stored: 0 / 240": *"The porter is moving products
  (beams, logs) from the sawmill to the warehouse but unloading doesn't put
  anything into warehouse.. storage is still 0 and goods just vanish"*.
  Nothing vanished — the beams were on the wagon, and the wagon kept being
  turned around. Measured on a real village first
  (`tools/probe_village_store_round.gd`, which reads the same
  `building_inventory_at` the popover draws): **one delivery in ten simulated
  days, a full wagon — twenty-four beams — still parked at the end**, and the
  readout at 12 of 48.

  1. A carter mid-round was **not counted as being on real work**, so every
     thirst steered them to the well instead of the store, and thirst comes
     up about every seventeen seconds. `is_on_real_work` now includes the
     round, exactly as it already included the farmer's field.
  2. A dropped round **threw its leg away**. The round is still dropped off
     the clock and the wagon still stands where it stopped (Mechanisms 5 and
     6, unchanged), but the carter now picks up the leg they were on rather
     than walking back out to a shelf they had nearly reached the evening
     before. A village is wider than a work block is long.
  3. A loaded wagon now **heads for the store before another shelf**
     (`LogisticsBehavior.resume_carrying`). Without it the next block topped
     up a wagon that had never been emptied, which is how it ended full.

  After, on the same village: **four deliveries, an empty wagon, and all 48
  beams in the readout.** The end-to-end proof is that measurement rather
  than a unit test, and `test_npc_marker_cart.gd` says so where the test
  would otherwise sit: a stub world delivers either way (tried both with the
  carter living at the store and away from it), so a test claiming it would
  prove nothing. What the tests pin is each of the three mechanisms.
- ✅ **Mechanism 5 — the Bollerwagen.** `CartLoad` (pure) and `CartMarker`
  (the node that holds the load, trails its puller and turns to face the
  way it is going). Spawned with the village, so it is freed with the chunk
  — a leak there was the measured cause of a reported framerate decay
  (`tools/probe_node_growth.gd`).
- ✅ **Pillar 4's other half — goods LEAVE by being carried too**
  (2026-09-20). Asked for directly: *"the builders should carry materials
  to the site"*. A settlement's construction material leaves
  `VillageMarket.stock` the moment a project starts
  (`SettlementConstruction.try_start`) and lands in that project's own
  `reserved_material` — and used to arrive nowhere. The site's builder now
  walks it out of the store he is standing next to: `ConstructionHaul`
  decides the load, `ConstructionWorkerMarker` walks the round, and
  `EarthChunkManager` hands him this store if one is within his own
  village (`CONSTRUCTION_STORE_REACH_TILES`). The caveat under pillar 1
  reaches here as well, and decides the same default: a village with no
  store has nowhere to fetch FROM, so its builder works the plot with the
  material already deemed to be there. See
  [building.md](building.md), "And he carries the material".
- ✅ **Mechanism 6 — a real object.** `CartMarker` carries a `StaticBody2D`
  on the ground floor's own collision layer, joins the hover group with a
  name that says what is in it, and offers Take Hold / Let Go on the primary
  context slot. `report()` hands `HousePanel` a title, a subtitle naming who
  has the shaft, its load and `CartLoad.CAPACITY`; the panel grew exactly two
  seams for it (`title`/`subtitle` overrides), and a building carries neither
  key so nothing that already opened it changed. `World._on_world_clicked`
  prefers a cart within half its drawn width over the building underneath,
  and `Player.toggle_cart_hold` takes the nearest one within `LASSO_RANGE` by
  force, or lets go of the one already held.

## Known open questions

- **What counts toward the ceiling.** Mechanism 2 caps stock as a whole. A
  per-item or per-kind ceiling (grain and iron do not share a shelf) is the
  obvious refinement and is deliberately not attempted first.
- ~~**Who hauls.**~~ Answered by Mechanism 4: hauling is an occupation. Every
  villager keeps Mechanism 3's wiring for their own hands, but the store's
  round belongs to the carter.
- **A village with more than one store.** Mechanism 4's handout gives every
  carter the FIRST store in the chunk. Villages raise one, so this has never
  mattered; a second one would want the round split rather than doubled.
