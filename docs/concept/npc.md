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
  Personality is DNA derived (`NpcGenome`, same "continuous 0..1 gene per
  trait, seeded" shape `TreeGenome` already uses for trees): each of the 8
  named traits gets its own independent gene, and the trait that rolls
  highest is the NPC's expressed `personality_trait` -- a real genotype
  underneath one visible phenotype, not a single flat categorical roll with
  nothing behind it. Deliberately kept as a plain `String -> float`
  Dictionary rather than fixed fields, since that shape already slots
  directly into the existing `dna_crossover.gd` utility unchanged -- once
  villagers can have children at all (see Lifecycle below), two parents'
  genomes crossing into a child's is a natural follow-up, not a new
  mechanism. This also gives other systems a continuous strength to read
  instead of a yes/no category match -- e.g. which house blueprint a
  villager builds (`HouseBlueprint.choose_blueprint_id`, see
  [building.md](building.md#a-blueprint-catalog-not-one-box)) is nudged by
  how strongly their dominant trait actually rolled, not just which name it
  happened to land on.
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
  quest-giver script. See [quests.md](quests.md) for the full mechanism,
  including when several NPCs' matching needs promote into one
  settlement-level quest offered by a representative.

### Minimal talk interaction (placeholder for live dialogue)

The full "live dialogue exchange" above needs the real LLM-backed planner
(see the divergence note below) and doesn't exist yet. Until it does, a
villager isn't mute: standing near one shows a proximity prompt (whatever
key is actually bound to "talk," rendered dynamically so a rebind never goes
stale) and pressing it produces one deterministic, personality/need-flavored
greeting line built from that NPC's own `NpcIdentity` — a "hello" the game
can render honestly today, not a branching conversation. This is explicitly
a stand-in for the real system, not a scaled-down version of it: no memory
of the exchange, no quest hooks, no branching, nothing persisted. It exists
so an NPC feels like *someone* to approach even before the Live Dialogue
System (`docs/progress.md`) is built, the same relationship Basic Merchant
Shopping has to a real shop UI.

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

## Settlement growth: migration toward player-built structures

The dwindling side of the lifecycle above has a growth counterpart: a
player-built structure cluster (see [building.md](building.md)) is itself a
habitability signal — free shelter and, for specialty infrastructure like a
forge or dock, a specific pull for a specific occupation-need. An NPC's
existing replan-interrupt (a need crossing a critical threshold triggers an
out-of-cycle plan, per above) gets one more possible resolution: relocate,
not just cope in place. A settlement that loses population from disaster or
[village-endangerment](quests.md#village-endangerment-the-attractor-mechanism)
is the preferred migration source when one exists nearby; a generic
wandering-NPC pool covers the rest. A player-grown settlement that crosses
the same population/infrastructure thresholds a procedurally-seeded one
would is, mechanically, a real settlement — same representative/quorum
quest machinery, same wealth-driven risk exposure, same ruin fate on
failure. Full mechanism, including the migration floor and the active-invite
option, in [quests.md](quests.md#settlement-growth-migration-and-player-founded-villages).

### Current implementation status (divergence note)

A first real slice exists (see `docs/progress.md`'s NPC section for the full
breakdown): procedural village placement (`settlement_generator.gd`,
sparse/deterministic per chunk), villager identity (`npc_identity.gd`: name/
occupation/personality (now DNA derived via `npc_genome.gd`, see Identity
above)/need, no relationships yet), and the planning
architecture's cheap-local-FSM half fully working (`npc_marker.gd` walks a
daily schedule, sharing the player's own `CharacterView` walk cycle --
`NpcMarker.setup(world, tile_size)` gives it the same water-awareness
`CreatureMarker` has, so a villager's animation switches to swimming while
crossing water and to idle while stationary, not just a frozen walk pose)
-- but the "one LLM call plans the day" half is a
deterministic stand-in (`npc_planner.gd`'s `Planner`/`FakeNpcPlanner`, same
split as [worldbosses.md](worldbosses.md)'s `PhaseGenerator`), not a real
LLM call yet. No *live* dialogue yet (see "Minimal talk interaction" above
for the one-line placeholder that exists today), no instruction DSL, no
memory log, no self-determination/role drift, no lifecycle (aging/
reproduction/death), no faction/festival wiring. Villagers can be bought
from at a fixed shared price list (`shop.gd`) -- the "shopping" half of
villages works, "hiring" does not. Every merchant villager also gets a
personal trading stand next to their own house door now (`VillageRenderer`,
same sprite as the shared village-square stall), not just the one shared
landmark every merchant used to route to -- so a multi-merchant village
reads as several villagers who each trade, not one central shop. A house's
placement is also now water-aware (`VillageRenderer._find_dry_origin`, see
[building.md](building.md#one-system-two-builders)): a chunk's dominant
biome only gates the whole chunk, not every individual cell, so a
grassland-dominant chunk can still have a pond cutting through it, and a
house whose ring-layout anchor would land there is nudged to nearby dry
ground instead of stamped into the water.

### Open questions

- Aging pace — real-time-days-per-life-stage vs. some faster abstracted
  clock, since a literal human lifespan would outlast most play sessions'
  relevance.
- Does village population have any equilibrium/growth-cap mechanic (so a
  thriving village doesn't grow unboundedly and become a performance
  problem), similar to carrying capacity in [world.md](world.md)'s
  wildlife model? Now also covers player-grown settlements — migration
  ([quests.md](quests.md#settlement-growth-migration-and-player-founded-villages))
  is one more growth vector into this same unresolved number.
