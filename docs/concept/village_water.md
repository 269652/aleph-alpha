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
- **The field.** A farmhouse pours everything above a drinking **reserve**
  onto its crops, so a farm empties its tank faster and its people are seen
  at the well more often. The reserve is what stops a farm watering itself
  into a drought — people before plants, which is also how it really worked.

## Mechanism 4 — The schedule stops sending everybody to the square

`FakeNpcPlanner`'s evening entry becomes the villager's **own home**, not
the well. The well is reached by errand or not at all. A guard still holds
the gate; everyone else's evening is their own.

This is the half that fixes the crowd, and it is a deletion rather than an
addition — the crowd was a line in a table saying "go here now", and the
table stops saying it.

## Status

(filled in as this is built)

## Interaction with other docs

- [npc.md](npc.md) — the planning architecture this errand runs beside.
- [village_estates.md](village_estates.md) — the household stock and the
  simulated-day cadence water follows.
- [ethogram.md](ethogram.md) — the thirst drive this finally gives a
  consumer.
- [farming.md](farming.md) — the crops a farmhouse's surplus waters.
- [hydrology.md](hydrology.md) — where the water in the ground came from.
  This doc is about the bucket, not the aquifer.
