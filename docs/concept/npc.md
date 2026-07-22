We need a novel uniquer unprecedented NPC system. 

Similar to minecraft there should be procedural generated NPC populations; villages and so. 

Similar to magic we need a custom NPC behaviour DSL which will allow us the use LLMs to statically generate individual NPC personalities and behaviours in a way that makes NPCs an order of magnitude more intelligent than in current games in a way that doesn't require runtime LLM invocation for predetermined behaviour and personality. 

It also should allow players to hire and instruct NPCs to perform custom work for them using the DSL.

## AI-native NPCs

NPCs are individuals, not quest dispensers.

- **Identity**: each NPC has a name, occupation, a small set of personality
  traits, a driving need/goal, and relationships to a handful of other NPCs.
  Backstory/personal-history depth starts minimal and is allowed to grow
  organically through logged events rather than being hand-authored upfront.
- **Planning architecture** (cost- and latency-aware by design):
  - Once per in-game day, one LLM call produces a rough schedule for that
    NPC: a sequence of `{time block, location, activity}` entries, informed
    by their personality, current needs, relationships, and a summarized
    memory of recent events.
  - **A cheap local FSM/pathfinder executes that plan tick-by-tick with zero
    LLM involvement.** This is the key cost lever — most of an NPC's
    "thinking" is just following yesterday's plan.
  - The LLM is called again only on: day rollover (new plan), a significant
    interrupt (combat, meeting a notable NPC/player, a need crossing a
    critical threshold), or a live dialogue exchange with a player.
  - Significant events get appended to a persistent memory log per NPC,
    which feeds back into future planning and dialogue — this is what lets
    an NPC "remember" what you did to them.
- **Self-determination**: NPCs are not permanently welded to their starting
  role. A blacksmith whose needs/relationships/plan drift over time might
  stop smithing and do something else — the simulation doesn't forbid it.
- **Quests**: NPCs generate requests from their actual current needs (get me
  resource X, protect me from Y, deliver a message to Z) rather than a fixed
  quest-giver script. Exact quest-template design is deferred — see
  [overview.md](overview.md#open-questions-to-resolve-during-mvp-work-not-blocking-day-1).

## Hiring & instruction

- **A separate instruction DSL, not the magic DSL.** Player-authored NPC
  instructions use their own task/goal/condition language (e.g. "if
  inventory has >20 wood, haul to base; otherwise chop nearest tree") —
  distinct from [magic.md](magic.md)'s spell DSL since the domains are too
  different to share a language, but built with the same design philosophy:
  small composable primitives, and a constraint layer (an "instruction
  complexity budget," analogous to spell mana cost) that keeps players from
  scripting an NPC into an absurdly optimal, game-breaking routine.
- **Hiring requires both a wage and a relationship.** Hired work is paid on
  an ongoing basis out of [economy.md](economy.md)'s currency — no
  one-time buyout — and *which* NPCs are even willing to be hired depends
  on existing trust/relationship state built through quests and dialogue
  (see Identity/memory-log above). This makes the AI-native identity system
  actually matter mechanically: a stranger won't work for you at any price,
  but an NPC whose quest you completed, or whose child you helped, will.
- Child-NPCs (see [players.md](players.md)) are the one exception to the
  relationship gate — a player's own child starts at maximum trust with
  them by default, instructable via this same DSL from the moment it grows
  up.

See [factions.md](factions.md) for how individual NPC relationships
aggregate into settlement-level reputation, and
[festivals.md](festivals.md) for how the daily-planner architecture
produces emergent village-wide events.

## Lifecycle: villagers age, reproduce, and die

NPCs aren't just individuals within one fixed lifetime — a village has
real generational history. Ordinary villagers (not just player characters)
age over time, can have children with each other using the same
DNA-cross/needs-minigame model [players.md](players.md) defines for
players, and eventually die of old age. This extends the
self-determination pillar above across generations, not just within one
NPC's lifetime — a blacksmith's trade might pass to their child, or might
not, depending on how that child's own traits/relationships develop.

- **Villages can genuinely dwindle or die out**, not just via a single
  sharp disaster. If birth rate can't keep up with death rate under
  sustained bad conditions (drought — [weather.md](weather.md), famine,
  war), a settlement's population can decline to nothing over real
  in-game time, same causally-grounded logic as
  [exploration.md](exploration.md)'s abandoned-settlement POIs — those
  ruins can now come from slow demographic collapse, not only a single
  wipe-out event.
- Reuses [world.md](world.md)'s existing "population exists wherever
  conditions make it viable, and that can shift over time" philosophy,
  applied to people instead of wildlife.

### Open questions

- Aging pace — real-time-days-per-life-stage vs. some faster abstracted
  clock, since a literal human lifespan would outlast most play sessions'
  relevance.
- Does village population have any equilibrium/growth-cap mechanic (so a
  thriving village doesn't grow unboundedly and become a performance
  problem), similar to carrying capacity in [world.md](world.md)'s
  wildlife model?
