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
reassigns an NPC out-of-cycle" mechanism. [npc_role_consensus.md](npc_role_consensus.md)
specs WHICH idle NPC gets picked once several are eligible (a real,
tested theory-of-mind consensus function) — genuinely reachable only once
this replan-interrupt architecture itself is real, which it is not yet
anywhere in this codebase.

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

### Work against the real world, not against a number

Reported in play: *"the hunter doesn't hunt, the fisher doesn't fish ...
hunting and fishing should be simulated against the real world, just like
lumberjacking and everything else."*

That is exactly right, and the codebase already says so about itself. The
fish-catch hook's own doc comment notes that a caught fish "actually
depletes the region it came from -- **unlike land hunting**". A hunter
today walks to a decorative prop four tiles from their door, stands on it,
and food appears in the village market; no animal is approached and none
dies. `NpcEconomy._deplete_discrete_unit` handles only the fisher, and
even that decrements a regional aggregate rather than taking a real fish.

**The Lumberjack is the pattern to follow, and it is already built.**
`LumberjackBehavior` is a pure phase machine (`SEEKING → APPROACHING →
FELLING → CARRYING → DEPOSIT`) with no engine dependency, and
`LumberjackMarker` owns the world effect: it scans
`ChoppableTree.GROUP_NAME` for a real standing tree, walks to it, and
swings with the SAME `take_damage()` loop `Player._chop_step` uses. An NPC
swinging an axe is not a separate mechanic; it is the same one with a
different caller.

Hunting and fishing become the same mechanic with two more callers:

- **The hunter** scans `CreatureMarker.GROUP_NAME` for a real, living,
  huntable animal in range, walks to it, and damages it with the same
  `CreatureMarker.take_damage` the player's own weapon calls. When it
  dies, that is where the meat comes from — a real animal that was
  standing there a moment ago and now is not.
- **The fisher** walks to real water and takes a real `FishMarker` through
  the hook that already exists for the player's own rod, which frees the
  fish and records the harvest against its chunk's aggregate population.

What this replaces, and why it is better than what is there:

1. **Yield stops being conjured.** `NpcProduction.yield_per_second` reads
   the real regional headcount, which is good, but the food it produces
   appears without anything being taken. After this, a hunter's output is
   the animals they actually killed.
2. **Depletion becomes real for land, not just water.** The gap the fish
   hook's own comment names is closed from the other side.
3. **It is visible.** The reported complaint is that nothing happens. A
   villager walking out to a deer and bringing it down is the thing that
   was missing, and it costs no new art — `CreatureMarker` and the walk
   cycle are already there.

**Deliberately unchanged at the time:** the farmer. There was no real
"crop entity" to harvest the way there is a tree, an animal or a fish —
`vegetation_density_near` is a field, not a thing standing in the world —
so a farmer kept reading it. Inventing a crop entity to make the third
producer symmetrical would have been exactly the premature system this
doc's own framing warns against.

**Resolved 2026-09-17 by [village_farms.md](village_farms.md)**, and not by
inventing that entity: a village farmer now works real `FarmPlot` tiles
that already existed for the player's own hand-tilled farming, on ground a
real `farmhouse` building owns. The herbalist joins them on the same
mechanism, growing herbs. Both are paid for what their own field actually
yielded (`NpcEconomy.record_real_harvest`), and the regional drip is off
for the whole work block while a villager has a field — the same rule a
real hunt already follows. A farmer with no farmhouse still falls back to
`vegetation_density_near` exactly as before, so nothing that depended on
the aggregate lost it.

**Named limitation to design around:** a villager can only hunt what is
LOADED. Creatures and fish exist as nodes only in loaded chunks, so an
unloaded settlement cannot take real quarry. The regional-aggregate path
stays as the fallback for those, which keeps an unloaded village fed
without pretending it killed anything — the same two-fidelities split
[ecosystem_dynamics.md](ecosystem_dynamics.md) already draws between
individual and aggregate simulation.

#### Status — built, and how it actually landed

Both halves are live. `ForagerBehavior` is the pure phase machine
(`SEEKING → APPROACHING → TAKING`), `HuntableQuarry` is the pure rule set,
and `NpcMarker` owns the world effect. One skeleton runs both quarry kinds;
only four things differ (`_find_quarry` / `_quarry_position` / `_reach` /
`_take_quarry`), because a deer and a trout are approached, lost and given
up on identically and writing that twice is how the two drift apart.

- ✅ **The hunter** scans the real creature group, walks to a living wild
  animal and strikes it with the same `take_damage()` a wolf's own bite
  calls. Four exclusions, each grounded rather than chosen: **not a
  predator** (`NpcProduction` pays a hunter by `herbivore_population_near`,
  so prey is what a hunter takes), **not a world boss** (`BossAggro` would
  wake it into the village), **nothing the player has a stake in** — the
  broader line `CreatureMarker.is_player_invested` already draws, so an
  animal the player has fed even once or has on a rope is off the list
  well before `Taming.is_tame`'s threshold ([taming.md](taming.md)) — and
  **alive and still really here** (a creature killed earlier in the frame
  stays in its group until the frame boundary).
- ✅ **The fisher** walks to the water and casts through the two hooks the
  player's own rod and a diving bird already use —
  `nearest_fish_position` and `catch_nearest_fish`, the latter of which
  frees the real fish and books the harvest against its chunk's aggregate
  by itself.
- ✅ **Yield is no longer conjured while real quarry is there.** What the
  kill is worth is `HuntableQuarry.meat_yield_of`: exactly the
  `Butchering.meat_count` a player butchering that same carcass would cut
  out of it, against the animal's own live mass relative to its species
  reference ([metabolism.md](metabolism.md)). A well-fed deer feeds the
  village better than a starved one. No skill bonus — SkillTree's
  `meat_yield` nodes are the player's to earn.
- ✅ **The hide reaches the market too, unpaid.**
  `MerchantVisit.BUY_LIST` has bought hides since it was written, and until
  a hunter took one no hide ever reached a village market for a cart to
  find. A kill now credits `Butchering.HIDE_COUNT` — flat, not mass-scaled,
  because `Butchering`'s own shape is flat: a starved deer is a thinner
  deer, not a smaller one. Deliberately **not** paid for at the kill: a hide
  feeds nobody and no villager buys one, so there is no local sale to pay
  for, and its value arrives when a cart buys it out of the market
  ([traveling_merchants.md](traveling_merchants.md)). Paying at the kill
  would be the conjured faucet that doc exists to close, pointed at a
  second good.
- ✅ **No number in the hunt was invented.** Every constant is borrowed
  from something already live and test-pinned to it, never copied as a
  literal: the search radius and arrival distance from the Lumberjack's
  own, the strike damage from `CreatureMarker.ATTACK_DAMAGE` (a villager
  bringing a deer down does what a wolf does to the same deer), the
  look-around and strike intervals from `LumberjackBehavior`, and the rod's
  reach from `Player.FISH_CATCH_RADIUS` — a villager's rod is the player's
  rod.

Four decisions this section did not originally specify, recorded here
because the code took them:

1. **The regional drip is off whenever quarry is within REACH, not only
   while a villager is committed to one.** Paid only for committed time, a
   hunter would still draw most of their income from a number: the drip
   runs at `PRODUCTION_RATE_PER_SECOND × the regional headcount`, which
   across a look-around interval and a walk outruns a real deer several
   times over, and hunting would have stayed decorative. The fallback is
   for a region with no loaded quarry in it — not a top-up for the seconds
   between one kill and the next.
2. **A hunter carries home the animal it killed**, so the carcass
   `CreatureMarker._die` leaves is removed at the kill site. Otherwise the
   same meat exists twice: once as village stock and once as a carcass
   anyone can walk up and butcher. Named simplification: the whole animal
   goes home, so the guts a real field-dressing leaves behind
   (`Butchering`'s third part, `CarcassGuts`) are not spawned. Wild deaths
   — predation, disease, age — still leave their carcasses untouched, so
   [carrion.md](carrion.md)'s chain keeps every input it had except the
   ones a villager personally killed and carried off.
3. **One fish is one food unit**, not a mass-scaled count the way a carcass
   is — a deliberate asymmetry with the hunter. There is no fish equivalent
   of `Butchering.meat_count` to read a real conversion off, and inventing
   one would be exactly the invented number this change exists to remove.
4. **Nothing is credited for a blow that does not kill, or a cast that
   lands nothing.** Half a deer is not half a meal, and a wounded animal
   that escapes fed nobody.

**Measured, not assumed** (`tools/probe_village_hunting.gd`, 40 chunk-widths
east of Berlin, real chunks, real settlements, real spawned creatures): of
**9 real hunter villagers, 6 (67%) had real quarry within reach** of where
they actually work, and **none saw no live quarry at all** — around 30
huntable creatures are loaded at any moment. The distance from a hunter's
workspot to the nearest real animal ran **16px / 244px / 419px**
(min/median/max) against a reach of **250px**.

That median lands within 3% of the reach, which is worth stating plainly
because the reach was not chosen for it: it is `LumberjackMarker`'s own
search radius, borrowed on the argument that a village worker ranges about
as far for an animal as for a tree, and test-pinned to it. The measurement
says that argument was right to within a rounding error. It also says the
feature is a coin flip per hunter rather than a certainty — the third that
misses sits at 250–419px and falls back to the aggregate, which is exactly
what the fallback is for. **The reach is deliberately NOT widened to
capture them.** Nothing principled sits at 419px; moving it there would be
tuning a constant to a sample, which is the thing this project's rules
forbid and the thing the whole borrow-and-pin discipline exists to avoid.

**And it really produces.** Re-run after the deadlock fix below, the same
hunter over 240 simulated seconds banked **2 meat and 1 hide** — exactly
one real animal, `Butchering.meat_count` plus `HIDE_COUNT`, taken from a
deer that was standing there and now is not. Against the **8.86 units** the
old conjured drip would have paid over the same stretch, so a real hunt is
roughly a quarter as productive as the faucet it replaces. That is the
point rather than a shortfall: the drip still runs for the 94.5% of ticks
where no quarry is in reach of where the hunter actually stands, so the
real hunt supplements the fallback rather than starving a village. Note the
gap between **67% of hunters having quarry in reach of their workspot** and
**5.5% of ticks having it in reach of the marker** — a villager spends most
of a day at home, asleep, or walking, and only half of it working at all.

✅ **A hungry producer works instead of queuing at an empty well** — found
by the probe above, and a pre-existing deadlock rather than anything this
change introduced. The hunger interrupt sends any hungry villager to the
well to buy a meal. Measured live: a real hunter went hungry about twelve
seconds in, with an empty village market and an empty purse, and then never
worked again for the remaining 227 simulated seconds — because the
interrupt fires every frame, and *not working is precisely what stopped
them producing the food they had been sent to buy*. The well had nothing on
it and never would. A village that fell into that state could not climb out
of it.

The interrupt now skips a producer who can feed itself from its own work
(`NpcEconomy.feeds_itself_from_work`, which is exactly the condition the
free self-feed already turned on, named rather than restated so the two
cannot drift). Working *is* eating for a hunter, so sending them to the
stall trades a meal they already have for one they have to buy. The
interrupt is for villagers who must BUY, which is what this doc describes
it as — and a producer whose region has genuinely collapsed is one of them
again, so the famine chain above stays intact.

🚧 **A fisher's dock is not sited at water.** `VillageRenderer` places
every personal workspot prop — a farmer's field, a blacksmith's forge, a
fisher's dock — on dry ground near that villager's own house, with no
notion of what the trade needs to be near. So whether a fisher ever
actually fishes depends on where the village happened to land relative to a
river or lake, not on anything the dock knows. The fallback keeps them fed
either way, and the fix belongs to whatever eventually sites work props by
what the work needs (the hunter has the same shape of problem and is less
exposed to it, since animals move and water does not). **Unmeasured**: the
probe covers the hunter's side only, so the rate at which a fisher has real
water in reach is currently a stated gap, not a number.

**Still open here:** a villager cannot hunt a species whose meat the world
has no `LootTable` entry for — they can *kill* it, and are paid the same
`Butchering` yield for it, but it leaves no carcass either way, so the
"carried home" rule is a no-op for most of the roster. Widening `LootTable`
past its four generic entries is [carrion.md](carrion.md)'s to do, not this
section's.

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
