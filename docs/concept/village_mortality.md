# Village Mortality: a population you can watch change

Asked for directly: *"now make the npcs move in and make them starve and
die if they don't have food"*.

Two halves of one thing. A village's population already rises and falls in
the ledger — [village_growth.md](village_growth.md) mechanism 3 admits
households, and `EstateAscension`'s exodus removes them — but **nothing
you can see changes when it does**. The villagers standing in a chunk are
a snapshot taken when it was rendered: nobody is spawned when a household
arrives and nobody is removed when one leaves, so the settlement card and
the street disagree until the chunk reloads. That gap was reported live:
*"there still run around more NPCs than the number displays"*.

This doc is about closing it from both ends, and about giving the falling
end a cause a player can understand: hunger that is never answered.

## Design pillars

1. **The street is the readout.** A village's population is something you
   count by looking, not a number on a card that the world lags behind.
   Whatever the roster says, that many villagers stand there.
2. **Death has a cause you watched.** A villager does not vanish on a die
   roll. They starve because there was no food, after visibly failing to
   find any, for long enough that a player could have intervened.
3. **Starving is slow, and it is survivable.** The window between "hungry"
   and "dead" is long enough to cross a village with a loaf. A mechanic
   that kills faster than a player can react is a punishment, not a
   simulation.
4. **One clock, not a new one.** Hunger is already `Ethogram`'s villager
   drive, already rising on the shared lived-experience clock
   ([ethogram.md](ethogram.md)). Starvation is what that drive does when it
   is left at the top, not a second meter beside it.
5. **A death is a household event, not just a missing sprite.** The person
   who dies owned a house, held a purse and counted toward the tier. All of
   that has to follow them out, or the village is haunted by exactly the
   ghost owners [village_growth.md](village_growth.md) already had to fix.
6. **Nothing dies off-screen that the player could not have seen.** An
   unloaded village is not silently culled. The same honest limitation
   immigration already carries (it only runs while the chunk is loaded)
   applies to mortality, and for the same reason: guessing at what happened
   somewhere nobody was is the invented number this project's rules forbid.

## Real-world grounding

Famine does not kill on the day the granary empties. It kills weeks later,
and it kills the people who were already thinnest — which is why the
threshold here is *time spent at the top of the drive*, not the drive
itself. A village with a bad season loses people slowly and visibly, and a
cart of grain arriving in the middle of it saves them. That is the shape
worth simulating: the intervention window is the mechanic.

## Mechanism 1 — Starvation is time at the top of the hunger drive

`Starvation`, pure and static, beside `HouseholdWater`:

- `STARVING_LEVEL` — the hunger level at which a villager is no longer
  merely hungry but starving. Above `NpcNeeds.HUNGRY_THRESHOLD`, because
  "looking for food" and "dying for want of it" are different states.
- `DAYS_TO_DIE` — how many simulated days at or above that level kill.
  Pinned by the window it produces, never chosen: long enough to cross a
  village with a meal, short enough that a village with no food really does
  lose people within a season.
- `advance(starved_days, hunger, days)` → the new starved-days total, reset
  to zero the moment hunger drops back below `STARVING_LEVEL`. **Eating
  clears it outright**: a villager who gets a meal is not still dying from
  last week.
- `is_dead(starved_days)` → whether it has gone on too long.

The clock lives on `NpcNeeds` beside the drive it reads, so it advances on
exactly the same `advance(delta)` every villager already ticks, and a
villager with no world still ages normally.

## Mechanism 2 — Dying is a thing that happens where you can see it

`NpcMarker` checks its own needs each frame, the same place the hunger
interrupt is already decided. A villager who has starved long enough:

- tells the world (`record_villager_death`), and
- leaves.

No corpse. A villager is not a creature and
[carrion.md](carrion.md)'s loot table is not the right vocabulary for a
person; what a dead villager leaves behind is a question
[death.md](death.md) has not answered for NPCs yet, and inventing an
answer here would be inventing a mechanic nobody asked for.

## Mechanism 3 — The world lets them go properly

`EarthChunkManager.record_villager_death(settlement_id, seed_value)` does
what a departure does and no less: the household leaves the roster through
the SAME `npc_departed` event `_record_household_departure` already
appends, so `_households_in_settlement`, the census, the tier, the growth
ladder and the settlement card all see it with no new plumbing — and the
roof they owned stops counting as one of ours, exactly as
[village_growth.md](village_growth.md)'s ghost-owner fix arranged.

A death is a departure with a reason, not a second mechanism beside it.

## Mechanism 4 — Villagers follow the roster, both ways

The reconcile that closes the reported gap, in the same shape
`_reconcile_chunk_creatures` already uses for animals: once per settlement
step, the villagers standing in a loaded village are brought into line with
the settlement's real roster.

- A household on the roster with nobody standing for it gets a villager —
  **they move in**, visibly, while you watch.
- A villager whose household is gone is freed.

The newcomer is the deterministic `NpcIdentity` at their own index
(`SettlementGenerator`'s per-index seed, which already continues past the
founding roster), so who arrives is the same on every visit and a reload
does not swap them for somebody else.

## Status

(filled in as this is built)

## Interaction with other docs

- [village_growth.md](village_growth.md) — arrivals, the census, and the
  ghost-owner fix this leans on.
- [ethogram.md](ethogram.md) — the hunger drive starvation reads.
- [npc.md](npc.md) — the needs-and-economy loop that decides whether a
  villager finds a meal at all.
- [village_estates.md](village_estates.md) — the exodus, the other way a
  household leaves.
- [death.md](death.md) — the player's own mortality, deliberately not
  extended to NPCs here.
