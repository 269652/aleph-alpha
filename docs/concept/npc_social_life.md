# NPC Social Life — a villager is an animal with a job

Asked for directly: *"We need to improve the NPC AI Behaviour by an order of
magnitude ... they should socialize; talk; share rumours; trade goods; give
quests; cater for their needs; stroll; idk"*.

## What this is not

Not a second AI. This world already has a real, tested, drive-driven
behaviour engine — the ethogram ([ethogram.md](ethogram.md)): `Drives` is a
multi-drive clock, `BehaviorKernel` turns drives plus stimuli into one
intent, and `Ethogram.BODY_PLANS` is the wiring table each species is read
from. Every land mammal in the game runs on it.

Not new authoritative content either. A rumour is already a real
`MemoryRecord` of a real `Event` ([npc.md](npc.md), `memory_store.gd`,
`rumor.gd`). A shortfall is already real `Market` state. A quest is already a
stateless projection over that (`quest.gd`). Talking to a villager is already
a real pipeline ([dialogue.md](dialogue.md)). **None of it is missing. It is
simply not connected to anything a villager does.**

## The gap, stated precisely

`Ethogram.BODY_PLANS["villager"]` has **one drive and zero wirings**.
`BODY_PLANS["mammal"]` has two drives and **seven** wirings. So a deer
decides what to do from what it needs and what it can sense; a villager walks
a fixed four-block schedule (`NpcPlanner.plan_day` →
`NpcSchedule.current_entry`) with exactly one interrupt in it — hunger —
hand-written into `NpcMarker._process`.

That is the whole order of magnitude. A villager needs the ethogram it never
got, and the social substrate needs a villager who acts on it.

## Design pillars

1. **A villager is an animal with a job.** The same `Drives` clock, the same
   `BehaviorKernel`, the same wiring table — a villager's inner life runs at
   the same pace as every other creature's because it is the same code. A
   second NPC-only decision engine would drift from the first within a month.
2. **The schedule says where you would BE; drives say what you DO.** The
   four-block plan stays as the day's backdrop. Drives interrupt it — which
   generalises the one hand-written hunger interrupt already in
   `NpcMarker._process` rather than replacing it with something new.
3. **Nothing is invented that the simulation does not already know.** A
   rumour passed in a conversation is a real memory of a real event. Goods
   that change hands are real stock. An ask is a real shortfall. Switch the
   social layer off and every underlying fact is still true — the same
   discipline `quest.gd` already holds itself to.
4. **If it happens, you can see it happen.** Two villagers exchanging a
   rumour stop walking, stand together and face each other for a real number
   of seconds. Invisible bookkeeping is not behaviour; `step_npc_encounters`
   already propagates memory between villagers who are merely *scheduled* to
   the same landmark, and no player has ever seen it.
5. **Derived over persisted.** Relationships and meetings are re-derived from
   seeds, positions and already-persisted state wherever that is honest, the
   same property `VillageFarm`'s field ownership has.

## Real-world grounding

People do not run errands in a fixed order. They get thirsty, they stop to
talk when they pass a neighbour, they linger when they have nothing pressing,
and they carry what they heard to the next person they meet. Gossip is the
oldest information network there is, and it is *bounded by who actually meets
whom* — which is why [02-history-memory-rumors.md](../emergence/02-history-memory-rumors.md)
insists knowledge is "geographically constrained by travel, trade,
institutions, kinship" and that "remote NPCs do not receive instantaneous
global information".

A village is small enough that everyone meets everyone eventually, and that
is exactly what makes a rumour's *path* through it interesting.

## Mechanism

### The villager ethogram

`BODY_PLANS["villager"]` gains the drives and wirings it never had.

| drive | what raises it | what satisfies it |
|---|---|---|
| `hunger` | time (already real) | a meal (already real) |
| `thirst` | time | drinking at the well |
| `rest` | time awake | being home at night |
| `company` | time alone | a real conversation |

`company` is the new one and it is what makes a village read as a village: a
villager who has not spoken to anyone in long enough will go and find
somebody, in preference to standing on their workspot.

Channels a villager senses, on the same basis as any other body plan:
`COMPANY` (another villager in reach), `WATER` (the well), `FORAGE` (the
stall/market), `HOME`.

### Choosing what to do

`VillagerBehavior.decide(context)` — the sibling of `CreatureBehavior`,
built on the same `BehaviorKernel.decide` — takes this villager's drives and
the stimuli around them and returns one intent:

- `seek_company` — walk to a villager in reach
- `drink` — walk to the well
- `rest` — go home
- `eat` — the existing hunger interrupt, now one wiring among several rather
  than a special case
- `stroll` — the kernel's own `wander`: nothing pressing, so move about the
  village instead of standing still

Work is not an intent here. Work is what the schedule already says, and a
villager with no urgent drive does their job — the intent layer only
*overrides* the schedule, exactly as `_step_hunt` and `_step_farm` already
override the walk target for a hunter with a real animal in reach and a
farmer with a real field.

### A meeting is a real thing that takes real time

When two villagers are both free and within reach of each other, they stop,
face each other, and hold a conversation for a real number of seconds. While
it lasts neither walks. That is the visible half of pillar 4, and it is the
hook everything social hangs off — the same "find → position → reach → act"
shape `_step_hunt` and `_step_farm` already use.

What actually happens in one:

- **A rumour passes.** One villager's memories are offered to the other
  through the existing `Rumor.retold`/`MemoryStore` path, which already
  decays confidence and degrades source type per hop. This replaces
  schedule-derived grouping with a real meeting — the propagation rule is
  unchanged, only its *trigger* becomes something a player can watch.
- **The relationship moves.** Two villagers who talk know each other better.
  This is the thing `rumor.gd` names outright as its missing input: *"there
  is no real trust/relationship weighting yet, since npc_identity.gd has no
  relationships to weight by"*. Dimensions follow
  [01-society-and-institutions.md](../emergence/01-society-and-institutions.md)'s
  own list; the first slice carries **familiarity** and **trust**, and decays
  them unless reinforced, as that doc requires.
- **Goods change hands.** A villager holding more of something than they need
  and a neighbour short of it settle it between them at the market's own
  price, through real stock — no new economy, just the existing one running
  between two people instead of between a person and a stall.

### Quests come from asks, and asks come from shortfalls

`quest.gd` already projects a household's real production shortfall into a
player-facing quest, and `dialogue.md`'s `household_ask` topic already says
the sentence out loud ("Bren asking you for three rock"). What has never
existed is the step between: a villager *offering* it and the player
*accepting* it. That is `QuestOffer`/`NpcAsk` — the ⬜ item
[dialogue.md](dialogue.md) has carried since it was written.

## Status

Written before implementation, per CLAUDE.md. Each entry is corrected against
the code as it lands.

- ✅ **The villager ethogram.** `BODY_PLANS["villager"]` carries real
  receptors, four drives and four wirings. `COMPANY`/`MARKET`/`HOME` join the
  one shared channel basis rather than becoming a villager-only side channel,
  which is what lets a villager be decided by the same `BehaviorKernel` every
  other body plan runs on. Hunger is untouched on purpose — a whole famine
  chain hangs off its exact pace — and the wiring order puts it first,
  deliberately *not* the mammal order, because a villager who stopped for a
  drink on the way to buy food is a villager that chain no longer describes.
  Tiredness is one world day and company is one schedule block, both pinned
  to those sources rather than eyeballed. `test_ethogram.gd` 47/47.
- ✅ **`VillagerBehavior`** — villager context → intent, over
  `BehaviorKernel`, keeping no private copy of the wiring table and no
  opinion of its own about priority (wiring order *is* the priority). It is
  fed `Drives.gains()`, not raw levels: a gain is 0 below a drive's own onset
  and 1 at its threshold, which is what stops a villager who is
  one-thousandth hungry from walking to market forever. It answers `NOTHING`
  when no drive is pressing *and* when nothing is around to answer the one
  that is — the schedule then simply stands, which is pillar 2.

  Measured, not assumed: over a real `NpcNeeds` clock the first need of a
  villager's day is **a drink**, because thirst rises faster than hunger
  (0.03 against 0.02 in the shared mammal profile). Found by a test that
  assumed hunger came first; kept as its own test, because it is the
  behaviour rather than the accident. `test_villager_behavior.gd` 13/13.
- 🚧 **`NpcMarker` acts on the intent.** `_step_needs` is the third override
  beside `_step_hunt` and `_step_farm`, and deliberately the last of them:
  real work against the real world outranks a need, so a hunter mid-chase
  finishes the chase. A thirsty villager walks to the well and **drinking
  really answers it**; a tired one goes home and resting answers it — a need
  answered on arrival is what stops a villager standing at the well forever.
  With nothing pressing the layer returns null and the schedule simply
  stands. `test_npc_marker.gd` 41/41.

  **Divergence from the spec above, deliberate:** hunger is *not* routed
  through the wiring layer and keeps its dedicated interrupt in `_process`.
  That interrupt carries two guards a famine chain was measured into — a
  producer who feeds itself from its own harvest, and a villager with their
  own field — which this generic layer has no way to express. Its own gain
  is withheld from the villager context so the two layers cannot steer at
  once. Hunger being first in the wiring order keeps the two consistent.

  Still open in this slice: `stroll` (the kernel's `wander`) is not wired, so
  a villager with nothing pressing still stands on their scheduled spot.
- ✅ **A real meeting.** A lonely villager walks to the nearest neighbour
  within `COMPANY_REACH_PX`; on arrival BOTH stop, face each other and stand
  for `CONVERSATION_SECONDS`, and the conversation is what answers the
  company drive. Both sides are put into it, or it reads as being talked
  *at*. A conversation that has started runs to its end — a villager does not
  walk off mid-sentence because quarry wandered past — which at four seconds
  costs a hunter at most four seconds of a chase.

  Found by a test rather than reasoned about: "arrived" was one pixel, which
  is right for a doorstep and impossible for a person, because two villagers
  never occupy the same pixel. Talking reaches a tile — what "close enough to
  speak to" means on this grid. `test_npc_marker.gd` 47/47.
- ⬜ **Rumours pass in meetings**, through the existing `MemoryStore`/`Rumor`
  path.
- ⬜ **Relationships** — familiarity and trust between two villagers, moved by
  meetings, decaying unless reinforced, and weighting what a rumour does.
- ⬜ **Goods change hands** between a villager with a surplus and a neighbour
  with a shortfall.
- ⬜ **A villager offers a quest** from a real shortfall, and the player can
  accept it.

## Interaction with other docs

- [ethogram.md](ethogram.md) — the drives/wirings/kernel this is built on.
  This adds a body plan's worth of content to it, not a new engine.
- [npc.md](npc.md) — the schedule, the planner, hunger, and "Memory, beliefs,
  and rumor propagation", whose propagation trigger this replaces with a real
  meeting.
- [dialogue.md](dialogue.md) — the player-facing conversation pipeline. A
  villager-to-villager meeting is the same event seen from outside; the quest
  offer here is that doc's own open item.
- [quests.md](quests.md) — quests as projections of real problems.
- [economy.md](economy.md) — the prices a between-neighbours trade settles at.
- [01-society-and-institutions.md](../emergence/01-society-and-institutions.md)
  — the relationship dimensions and decay rule.
- [02-history-memory-rumors.md](../emergence/02-history-memory-rumors.md) —
  rumour propagation, and why it must be bounded by who actually meets whom.
