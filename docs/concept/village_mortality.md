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

- ✅ **Mechanism 1 — starvation is time at the top of the drive.**
  `Starvation`, pure and static, measured in hunger CYCLES rather than
  days — there are two day-lengths in this codebase and a mortality clock
  written against the wrong one either kills instantly or never kills at
  all. The window is pinned by what it produces (longer than one cycle;
  short enough that a village with nothing to eat really loses people),
  never chosen. `test_starvation.gd` 16/16, `test_npc_needs.gd` 14/14.
- ✅ **Mechanism 2 — dying where you can see it.** `NpcMarker.
  _step_starvation`, beside the hunger interrupt. `test_npc_marker.gd`
  102/102 — including the case that a HUNTER in a region full of game
  feeds itself off its own work and correctly never starves, which the
  famine chain already depended on.
- ✅ **Mechanism 3 — a death is a departure with a reason.**
  `record_villager_death` goes out through the same `npc_departed` event
  the estate exodus already appends, so the census, the tier, the ladder
  and the settlement card all see it with no new plumbing.
  `test_earth_chunk_manager_village_mortality.gd` 5/5.
- ✅ **Mechanism 4 — villagers follow the roster.**
  `VillageRenderer.reconcile_villagers`, stepped per settlement.
  `test_village_renderer.gd` 150/150.

### Measured on a real village (`tools/probe_village_famine.gd`)

```
  seconds   roster   standing  hungriest market food  starved/win
        0       10         10       0.30          0      0/200
      300       11         11       0.83          6      0/200
      450       12         12       1.00         14     12/200
      600       12         12       1.00          0    151/200
      750       12         12       1.00          0    189/200
      900       12         12       1.00          0    102/200
```

Two claims, both from that run. **Newcomers really do move in**: the
roster grew 10 → 12 and the villagers standing there tracked it exactly at
every sample, which is the gap
[village_growth.md](village_growth.md) recorded. And **the window behaves
as pillar 3 asks**: the worst-off villager reached 189 of 200 — eleven
seconds from death — and then fell back to 102 as food arrived. That
fallback IS the mechanic: the cart of grain saving somebody.

Run four windows long, the famine actually closes, and the village
survives it:

```
  seconds   roster   standing  hungriest market food  starved/win
     1200       12         12       1.00          0    174/200
     1500        7          7       1.00          0    117/200
     1800        9          9       1.00          0    181/200
     2400       13         13       1.00          0    181/200
```

Five villagers starve between 1200 and 1500 — the whole loop, end to end:
they die, the roster drops, the village takes new households in, and the
newcomers appear on the street. `standing` equals `roster` at **every
single sample** across both runs, through five deaths and six arrivals,
which is the strongest form of the claim mechanism 4 makes. The village
ends larger than it started.

A first, unfaithful cut of that probe stepped only the settlements and
the villagers, so nothing in the village could ever GROW food, and it
reported a total wipe-out. Recorded here because the number was wrong in
the direction that would have caused a panicked retune of a constant that
was fine.

### Known gaps, stated rather than papered over

- 🚧 **A newcomer gets no specialist's ground until the chunk reloads.**
  Fields, ponds and the carter's round are handed out in bulk passes over
  the whole village; re-running those against a village mid-life is a
  different change from this one. They work the general trades meanwhile.
- 🚧 **Only DEATH removes a villager.** A household that leaves through
  the estate exodus still has its villager standing there until the chunk
  reloads. The reconcile is additive on purpose: culling markers to match
  a shrunken roster has to pick somebody arbitrary, and the one it picked
  would be as likely to be the farmer you were watching as anybody.
- ⬜ **Nothing is left behind.** No corpse, no grave, no estate. What a
  dead villager leaves is a question [death.md](death.md) has not answered
  for NPCs, and inventing one here would be inventing a mechanic nobody
  asked for.
- ⬜ **An unloaded village neither starves nor buries.** The same honest
  limitation immigration already carries, for the same reason.
- ✅ **A village in permanent famine no longer draws people into it.**
  Seen in the same run and not introduced by this doc's work: `market
  food` sat at 0 and `hungriest` at 1.00 from t=600 while
  `VillageImmigration` kept admitting households. The gate was counting
  234 units of food on farmhouse shelves that nobody could eat — 19.5 per
  household against a `FED_THRESHOLD` of 2.0. Fixed in
  [village_warehouse.md](village_warehouse.md)'s own terms: the
  settlement's larder is what its people can eat.
- 🚧 **Farm output still has no route to anybody's plate.** The reason
  those farmhouses were full: `NpcMarker.HAULING_CARRY_LIMIT` is `0.0` —
  hauling is wired but deliberately switched off until delivery is proven
  to complete in a running village (see its own note). So a harvest
  accumulates on the farmhouse shelf and reaches no market. The village in
  the run above survives on foraging and the producers' regional drip, not
  on its own farms.

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
