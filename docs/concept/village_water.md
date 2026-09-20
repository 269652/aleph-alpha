# Village Water: the well trip as an errand you can watch

Reported live, with the square in shot: *"All NPCs walk to the well at the
same moments... and it's not visible what they are doing."*

Both halves are true, and they are one bug wearing two faces. Measured
before changing anything (`tools/probe_well_crowding.gd`), on a real
twelve-villager roster:

```
morning  busiest spot holds 2 of 12
midday   busiest spot holds 2 of 12
evening  well x10                     busiest spot holds 10 of 12
night    home x12
```

Ten of twelve, every evening, and the activity they are all performing is
`socialize` — a word with no verb behind it. `FakeNpcPlanner` gives every
non-guard villager the same evening entry, and every villager's time blocks
turn over on the same tick, so the village empties into the square at once
and then stands there.

The fix asked for is not a stagger bolted onto the timetable. It is to give
the trip a **reason**: *"each NPC should have a bucket in its house
inventory, and when they get water they should carry the empty bucket to the
well and bring back a full bucket, which they pour into their house's water
tank, tracked as a distinct resource, and then drink from their house's
stock — or use it to water crops in the case of a farmhouse."*

A village whose people go to the well **when their own house runs dry**
staggers itself, because no two houses run dry at the same moment. The
crowd is a symptom of the errand being fake.

## Design pillars

1. **A trip to the well is an errand, not a timetable entry.** Nobody is
   scheduled to the well. A villager goes when their household's tank is
   low, and comes home when the bucket is full. Who is at the square at any
   moment is therefore an *output* of the simulation rather than a row in a
   table, and it spreads out for free.
2. **The bucket is the explanation.** What a villager is doing is
   answerable by looking at them: they carry an empty bucket one way and a
   full one back. No label, no icon, no UI — the same standard
   [building.md](building.md) already holds a resident to ("it IS the same
   person" because it is the same dressing).
3. **Water is a household stock, exactly like the food already is.** It is
   poured into the *house*, tracked on the house, drunk from the house. A
   bucket is a vessel for moving it, never the place it lives.
4. **No new drive, and no new clock.** `Ethogram`'s villager profile already
   defines thirst, and `npc_needs.gd` says in its own header that it
   simulates hunger only because *"thirst has no villager-side consumer;
   simulating an unused thirst would misrepresent what this pass does."*
   **This is that consumer.** Water is drawn on the same simulated-day
   cadence [village_estates.md](village_estates.md)'s baskets already use.
5. **A farmhouse drinks last.** Water above what the household needs to
   drink goes on the field. That is what makes a farm's well trips more
   frequent than a cottage's — an emergent difference, not a per-occupation
   table.
6. **Tuned values are tested functions.** Tank capacity, draw per head and
   the trip threshold are pinned by what they *produce* — how often a
   household of a given size has to send somebody — never typed in as
   numbers somebody liked.

## Real-world grounding

A village well is not a social club, and a household did not visit it on a
schedule. It visited when the tank in the kitchen was low, which depended on
how many people drank from it, whether there was stock to water, and how hot
the week had been. The yoke and the two buckets are the iconic image of the
errand precisely because the *carrying* is the visible, laborious part —
you could tell at a glance who was going and who was coming back.

That asymmetry is the whole of pillar 2: an empty bucket and a full one look
different, and that difference is the entire UI this feature needs.

## Mechanism 1 — Water is a level on the house

A house's tank is **one number on its own building record** — the same
persistence idiom `guild_days_open` already uses (see
[mage_guild.md](mage_guild.md)): no new store, no new save format, and it
travels with the building through a chunk round trip.

`HouseholdWater`, pure and static:

- `TANK_LITRES` — what a house holds.
- `DRAW_PER_HEAD_PER_DAY` — what one villager drinks.
- `draw_for(heads, days)` → litres consumed.
- `level_after(level, heads, days)` → the new level, never below zero.
- `trip_is_due(level)` → whether somebody must go, at `TRIP_THRESHOLD_SHARE`
  of a full tank. Not at zero: a household that waits until it is dry has a
  thirsty day while somebody walks.
- `starting_level(seed)` — **the anti-crowd mechanism.** A new house starts
  somewhere between the trip threshold and full, chosen from its own seed,
  so two houses raised on the same day do not run dry on the same day and
  never re-synchronise afterwards. Staggering is a property of the initial
  condition, not a jitter applied to a queue.

## Mechanism 2 — The errand is a state machine you can see

`WaterErrand`, pure: given where a villager is and what they are carrying,
what are they doing next.

```
AT_HOME ──tank low──▶ TO_WELL ──arrived──▶ DRAWING
   ▲                  (empty bucket)      (at the well)
   │                                           │
POURING ◀──arrived── TO_HOME ◀──filled─────────┘
(at the house)      (full bucket)
```

- `carried(state)` → `""`, `BUCKET_EMPTY` or `BUCKET_FULL`. This is what the
  renderer hangs in the villager's hand, and it is the whole of pillar 2.
- `next(state, ...)` → the following state, so the walk is driven by arrival
  rather than by a timer.
- A villager mid-errand is **not** re-planned onto another location by the
  day rollover: an errand outranks a timetable, or the bucket gets abandoned
  halfway across the square.

## Mechanism 3 — What the water is for

- **Drinking.** The household draws `DRAW_PER_HEAD_PER_DAY` per member per
  simulated day, on the estates' own cadence.
- **The field.** A farmhouse waters its beds out of everything above a
  drinking **reserve**, so a farm empties its tank faster and somebody is
  seen at the well for it far more often. The reserve is what stops a farm
  watering itself into a drought — people before plants, which is also how
  it really worked.

### The farmhouse is the one building that holds a tank with nobody in it

`BuildingCatalog.capacity_of("farmhouse")` is 0: a farmhouse is a
workplace, not a home, and nothing drinks there. It holds a tank anyway,
because its **field** drinks. `EarthChunkManager._holds_a_tank` is
deliberately a separate rule from `_drinkers_in_house` rather than a
widening of it — folding the two together would have a building with no
residents drinking for somebody who does not exist.

### The field is billed per VISIT, and priced per DAY

A farmer at a bed waters it **and the beds around it**
(`NpcMarker._water_the_beds_around` — one trip with a can wets the ground
you are standing on, not one plant). So the unit *charged* is the visit:
`LITRES_PER_TENDING` out of the farmhouse's tank, once per
`_work_field_cell`. Pricing tiles would make a wide field cost more than a
narrow one for the same walk, which is not how a furrow works.

But the unit *priced* is the **day**, and this is where the first cut of
this feature went wrong badly enough to be worth writing down.
`LITRES_PER_TENDING` was originally pinned against the premise that a
living field is tended "more than once a simulated day" — reasoned from
`FarmPlot.MIN_WATER_GRACE_SECONDS` (45 s) being shorter than a simulated
day (60 s). The premise is true and nearly useless: `tools/
probe_farm_water.gd` counts **5.7 and 6.1 tendings a day** on the two
working farms of a real twelve-villager village. The bill was more than
four times what it should have been; the farmhouse ran dry almost at once,
the beds stopped being watered, and `tools/probe_village_farming.gd` went
from 164 wheat harvested to 24 on the same village. Every unit test passed
the whole time.

So `TENDINGS_PER_SIMULATED_DAY` is a **measured** constant, and the cost
is pinned through the rhythm it produces rather than through the visit:

- `field_draw_per_day()` — what a working field takes in a day.
- `days_between_farm_trips()` — one bucket's worth, over that.
- `days_between_household_trips(heads)` — the same for people who only
  drink.

The tests demand a farm reach the well **oftener than a household** and
**not spend the day walking there**, and that one bucket lifts a farmhouse
clear of the level that sent somebody. Those are facts about the errand a
player watches; the litre figure is just what satisfies them.

`HouseholdWater.can_water_crops(level)` is false once the tank is down to
the reserve, and then **the beds are not watered at all**. That refusal is
the mechanism, not a failure case: an unwatered bed withers
(`FarmPlot.grace_seconds`), so the farmhouse running dry is a thing the
player watches happen to the crop.

A farmer with **no** farmhouse — a village that has not raised one — keeps
the free drip they always had. There is no tank to bill it to, and failing
closed there would kill every such field rather than send anybody anywhere.

### So the errand serves two buildings

`NpcMarker._thirsty_building` asks, in order:

1. their own house, if `water_trip_due_at` says so — **people before
   plants**, the same order the reserve keeps;
2. the farmhouse they work, whose field drinks out of its own tank.

The chosen building is **latched** in `_errand_target` when they set out.
Re-reading it each frame would let a villager change their mind halfway
across the square, and the bucket in their hand would silently change what
it was for. While carrying a full bucket for the farmhouse, `"home"`
resolves to the farmhouse — they walk the water to the field, not to their
own kitchen.

A farmhouse is due **sooner** than a household is
(`farm_trip_is_due`, `TENDINGS_IN_HAND`), because a field that stops being
watered withers where a household that runs low is merely thirsty. It is
also **seeded off its own floor** (`farm_starting_level`): seeded from the
household's floor, three farms in four were raised already needing a trip,
which would have lost the whole anti-crowd stagger for farms on the day it
shipped.

### The bucket is the household's, not the villager's

Every building that holds a tank keeps exactly one `bucket` in its own
stock (`EarthChunkManager.stock_household_buckets_in`, stepped per chunk
beside the drinking). Asked for directly: *"each NPC should have a bucket
in its house inventory"*. It is stepped rather than seeded at placement so
a house raised before any of this existed gets one the first time its
village is stepped — no migration, and no new field on the record.

## Mechanism 4 — The schedule stops sending everybody to the square

`FakeNpcPlanner`'s evening entry becomes the villager's **own home**, not
the well. The well is reached by errand or not at all. A guard still holds
the gate; everyone else's evening is their own.

This is the half that fixes the crowd, and it is a deletion rather than an
addition — the crowd was a line in a table saying "go here now", and the
table stops saying it.

## Status

- ✅ **Water is a level on the house.** `HouseholdWater`, pure and static;
  one `water_litres` number on the building's own record, surviving a
  chunk round trip. Capacity, draw, threshold and the drinking reserve are
  all pinned by the errand they produce (`test_household_water.gd`).
- ✅ **The starting level staggers the village.** A new house starts
  between its own threshold and full, off its own seed. Measured: twelve
  households make 27 trips over a season, about one each every 5.3 days,
  and the busiest day sends 4 of 12 (`tools/probe_well_crowding.gd`).
- ✅ **The errand is a state machine you can see.** `WaterErrand`; an empty
  bucket out and a full one back, `carried()` as the whole UI. An errand
  outranks the timetable and ranks below the hunger interrupt.
- ✅ **The schedule stopped sending everybody to the square.** The evening
  entry is each villager's own haunt (`NpcPlanner._evening_haunt`).
  Measured: evening went from `well x10` (busiest 10 of 12) to
  `gate x5, home x3, stall x2, well x2` (busiest 5 of 12).
- ✅ **A villager walks it.** `NpcMarker._step_water_errand`; they set out
  when their own tank is low, fill at the well, walk back and pour.
- ✅ **The bucket is a real catalog item** (`item_catalog.gd`, a `tool`),
  and every tank-holding building keeps exactly one in its own stock.
- ✅ **The farmhouse holds a tank and its field drinks from it.** A
  tending visit is billed to the farmhouse; down to the reserve it cannot
  water at all. The cost is pinned to a **measured** tending rate
  (`tools/probe_farm_water.gd`, 5.7–6.1 visits a simulated day), after the
  first cut — pinned to a reasoned one — cut the same village's harvest
  from 164 wheat to 24.
- ✅ **The bucket is in their hand.** `ProceduralItemSprite` draws the
  pail, empty and full (the same pail; water standing at the brim is the
  only difference), and `NpcMarker._sync_carried_item` puts it in the
  `CharacterView` tool slot. Until this, `carried()` said what a villager
  was holding and nothing showed it.
- ⬜ **Nobody washes, brews or waters livestock with it.** Only drinking
  and crops draw on a tank. The village's trades have their own inputs and
  are not plumbed into this.
- ⬜ **The well itself is inexhaustible.** Nothing tracks what the square's
  well or the aquifer under it holds; see
  [hydrology.md](hydrology.md), which this doc deliberately does not reach
  into.
- ⬜ **The player has no tank.** `Player` neither drinks nor fetches; this
  is a villager mechanism only.

## Interaction with other docs

- [npc.md](npc.md) — the planning architecture this errand runs beside.
- [village_estates.md](village_estates.md) — the household stock and the
  simulated-day cadence water follows.
- [ethogram.md](ethogram.md) — the thirst drive this finally gives a
  consumer.
- [farming.md](farming.md) — the crops a farmhouse's surplus waters.
- [hydrology.md](hydrology.md) — where the water in the ground came from.
  This doc is about the bucket, not the aquifer.
