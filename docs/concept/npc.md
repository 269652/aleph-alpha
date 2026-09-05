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

## Memory, beliefs, and rumor propagation

Formalizes the "persistent memory log" named above (Planning architecture)
into this project's own terms — the concrete, project-specific expression of
[docs/emergence/02-history-memory-rumors.md](../emergence/02-history-memory-rumors.md)'s
general mechanism that `docs/roadmap.md`'s Emergence-substrate table already
expects here, the same relationship [quests.md](quests.md) has to
`worldbosses.md`.

- **Fact vs. belief.** The event/causality substrate
  ([docs/emergence/00-emergence-architecture.md](../emergence/00-emergence-architecture.md),
  `EventStore`) stays exactly as-is — ground truth, append-only, untouched by
  this. A memory record never overwrites an event; it's a separate,
  deliberately-less-authoritative record one entity holds *about* one event.
  Many different NPCs can each hold their own, possibly contradictory,
  memory of the same event.
- **What a memory holds**: which event, the holder, believed actors/
  location/outcome (start equal to the real event, may diverge later),
  confidence (0–1), emotional salience, source type, recency, and a
  distortion accumulator.
- **Source types** (unchanged from `02`): firsthand, witnessed, trusted
  testimony, stranger testimony, inference, written record, rumor.
- **Propagation reuses existing NPC proximity, not a new social model —
  built and automatic** (`EarthChunkManager.step_npc_encounters`,
  `NpcEncounter.group_by_shared_landmark`). NPCs meet at a settlement's
  shared landmarks (well/stall/gate) on their daily schedule
  (`npc_schedule.gd`) — that existing contact point is where memory
  propagates: when one NPC tells another about an event, the listener gets
  a new memory record for the same event, confidence and source type both
  stepping down by one hop (firsthand → the listener gets trusted/stranger
  testimony, not firsthand). No new movement, scheduling, or social-graph
  code required — it reads real, already-live `NpcMarker` schedule/position
  state directly, exactly as this section originally predicted. Each
  meeting exchanges the pair's single most-recently-formed memory
  (bidirectional), not an exhaustive dump. Trust/relationship-weighted
  decay is still deferred — `npc_identity.gd` has no relationships yet
  (Phase 3's own documented scope) — so propagation currently runs at a
  flat one-hop step regardless of who is talking to whom.
- **Decay.** An unreinforced memory's confidence/salience fades over time,
  the same "decay unless reinforced" principle relationships already assume
  above. Shape only for now — the exact decay function is a tuned constant,
  not eyeballed, pinned by a test once it exists (per this project's no-
  manual-tuning rule).
- **Content distortion deliberately deferred.** `02` also describes believed
  *content* itself mutating through retelling (a "telephone game" where
  *who* did something changes, not just how confident you are about it).
  Real, but unproven gameplay payoff yet — this pass keeps believed actors/
  location/outcome equal to the source event and only decays confidence/
  salience; content mutation is a real follow-up once a scenario actually
  needs it, not a missing piece of this one.
- **The player isn't a first-class belief-holder yet.** Rather than model
  player cognition as another citizen of the memory graph,
  [quests.md](quests.md#resolution-warning-surprise-and-autonomous-defense)'s
  rumor signal is answered directly: a nearby NPC holding a sufficiently
  confident/salient memory of a threat-to-their-settlement event is what a
  quest-offer/rumor UI queries. Modeling the player's own beliefs as memory
  records is a natural extension once there's an actual reason to need it
  (a rumor the player mishears, say), not required for the mechanism to
  work today.

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

## Needs and the local production economy

The lifecycle section above says famine can hollow out a village; this
section is the mechanism that makes famine possible at all, and the
scaffolding [economy.md](economy.md) is waiting on ("needs actual numbers
once the production systems it depends on are built").

- **NPCs get real hunger**, not just villagers-as-scenery. Same shape as
  [creature_needs.gd](../../src/gameplay/creature_needs.gd) (hunger rises
  per second, `is_hungry()`, `feed()`) — and, since
  [ethogram.md](ethogram.md) slice 3, literally the same clock: both are
  facades over `Drives` with their numbers as ethogram drive profiles
  (`villager` is the mammal pace, hunger only) — a genuinely new wiring, since
  `NpcMarker` carries no needs state today, but the identical pattern
  already proven for wild/tamed animals, not a new design.
- **Occupation decides how a need gets met, not just where an NPC stands
  during the day.** Today `occupation` only picks a work-location tag
  ([npc_planner.gd](../../src/world/npc_planner.gd)); this is the missing
  half — what actually happens at that location:
  - **Producer occupations** (farmer, fisher, hunter — hunter is a new
    addition to the existing occupation list, since gathering wild game is
    a distinct role from tending fields) gather real food while working,
    reading the SAME numbers the player's own foraging already uses rather
    than a parallel economy stat:
    - farmer → [vegetation_growth_model.gd](../../src/world/vegetation_growth_model.gd)'s
      `effective_capacity` (a real drought measurably lowers a farmer's
      yield, the same number that visibly thins wild vegetation)
    - hunter → [herbivore_population_model.gd](../../src/world/herbivore_population_model.gd)'s
      `carrying_capacity` (regional game scarcity is the same number
      wildlife density already runs on)
    - fisher → the aquatic population model's own yield, mirrored the same
      way (no separate "fisher abundance" stat invented)
  - **Non-producer occupations** (blacksmith, merchant, guard, herbalist,
    and a new **nurse**, added per this pass — village healthcare/care
    role) do not gather food. They eat by BUYING it, out of their own
    wallet, from whichever village producer has stock — this is what
    makes specialization real rather than cosmetic: a blacksmith who never
    farms only keeps smithing because someone else's hunting keeps them
    fed.
  - **Local trade is NPC-to-NPC, not just player-to-shop.** [shop.gd](../../src/gameplay/shop.gd)
    today is player-buy-only from one fixed catalog; this needs the
    genuinely new half — a producer's real surplus becomes real stock a
    fellow villager can buy with real gold, at a village-local price
    (not the player-facing shop's fixed list), so food actually moves
    from the hunter's hands to the blacksmith's.
- **This is the two-faucet economy from [economy.md](economy.md) actually
  running**, at village scale, before any player market exists: a
  producer earns gold from what they gather, a non-producer spends gold
  to eat, and a bad season (real weather, real vegetation/game decline)
  is now something a village can genuinely go hungry from — the causal
  chain the Lifecycle section's famine-driven decline needs underneath it,
  even before aging/reproduction/death themselves are built.
- **Deliberately NOT in this pass**: the instruction DSL,
  hiring/negotiated wages, relationships/trust, lifecycle
  (aging/reproduction/death), migration, and the real LLM-backed planner all
  stay exactly as documented above — this section is the
  needs/production/local-trade floor those systems will eventually stand on,
  not a replacement for any of them.

  **Two items on that list have since been partly built** (see
  [dialogue.md](dialogue.md), which needed them):

  - *Wages.* `VillageWages` gives a village a shared purse: producing
    households pay a levy into it and non-producers draw a **subsistence
    wage** — exactly one meal at the market's own live price. This exists
    because hunger was otherwise an occupation constant (only 3 of the 8
    occupations have any gold source, so the other 5 were permanently broke
    and therefore permanently hungry, which carries no information). It is
    *not* hiring: nobody negotiates, nobody chooses an employer, and the
    rate is derived from the occupation census rather than bargained.
  - *Memory/rumor is now wired off this economy.* `Event.witnesses` and
    `MemoryStore.witness_event` already existed but were set at only two of
    eighteen event sites, so villagers held nothing but founding trivia.
    Production outcomes, settlement status/tier/specialization changes,
    institutions and caravans now name the settlement's villagers as
    witnesses, which is what gives them anything to know or gossip about.

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
This same replan-interrupt shape is what
[timber_construction.md](timber_construction.md#deciding-what-to-build-and-who-builds-it-design-from-a-follow-up-brainstorm-session)'s
own Builder assignment reuses — an idle NPC picking up construction duty
ad hoc, not relocating, but the identical "a need crossing a threshold
reassigns an NPC out-of-cycle" mechanism.

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

The "Needs and the local production economy" section above is now real
end-to-end (see `docs/progress.md`'s NPC section for the full breakdown):
every villager has real hunger (`npc_needs.gd`); farmer/hunter/fisher gather
real food while working, reading the exact `vegetation_growth_model.gd`/
`herbivore_population_model.gd`/aquatic-population numbers named above
through two new thin `EarthChunkManager` accessors
(`vegetation_density_near`, `herbivore_population_near`, mirroring the
pre-existing `fish_population_near` exactly) rather than an invented stat --
a real drought (depressed moisture, same biome/temperature) measured 93.8%
lower yield for both farmer and hunter in a real probe; a per-settlement
`village_market.gd` holds real stock a non-producer buys from with real gold
at a tested village-local price, distinct from `shop.gd`'s global catalog.
A handful of judgment calls the spec left open are now decided and
documented in-code (`npc_economy.gd`'s own doc comment has the full
reasoning): a producer self-feeds for free from their own currently-active
production rather than paying into the market, gated on genuinely nonzero
yield right now so a severe enough collapse can still starve a producer
too; the village market is NPC-only, the player keeps using `shop.gd`;
nurse's work tag resolves to the shared "well" landmark rather than a new
building; settlement occupation balance is left to chance (not guaranteed),
so roughly a tenth of settlements roll no producer at all and every
resident there genuinely struggles -- a deliberate choice matching
[world.md](world.md)'s existing "population exists wherever conditions make
it viable" philosophy, not an oversight. Still exactly as scoped out by that
section's own "Deliberately NOT in this pass" line, minus the two items
that section now records as partly built (a subsistence wage from a shared
village purse, and memory/rumor genuinely wired off this economy via event
witnesses): no instruction DSL, no hiring or negotiated wages, no
relationships/trust, no lifecycle/death consequence for sustained hunger yet,
no migration, no real LLM-backed planning.

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
