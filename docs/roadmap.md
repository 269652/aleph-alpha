# Roadmap

Solo/part-time, Godot, 2D top-down pixel art. Each phase should end in
something actually playable/observable, not just infrastructure. Phases build
strictly on top of each other — later phases (multiplayer, economy, eras,
multi-planet) are deferred until the single-player core is solid, per
[concept/overview.md](concept/overview.md#non-goals-for-now).

Per this project's `CLAUDE.md`, every phase is built strict TDD: write a
failing test first (red), minimum code to pass (green), refactor only while
green. This applies to simulation logic (growth rules, population dynamics,
NPC plan execution, chunk save/load) as much as to gameplay code — most of
this is plain deterministic logic and is very test-friendly.

---

## Phase 0 — Foundations / tech spikes

Goal: de-risk the unknowns before building gameplay on top of them.

- Godot project scaffold, tile-based rendering, camera/player movement.
- World-gen spike: heightmap generation + hydraulic erosion pass to carve
  rivers/lakes; climate banding (temperature/moisture by latitude,
  elevation, water proximity) → biome classification per cell.
- Toroidal wrap: confirm movement/rendering/camera all correctly wrap on
  both X and Y at a small test map size.
- Chunk format + save/load: define the on-disk chunk representation, confirm
  a chunk can be saved, unloaded, and reloaded with player-made changes
  intact.
- Day/night clock: a global time-of-day value driving a per-tile sunlight
  value (function of latitude + time + season placeholder).

**Definition of done**: a small toroidal world generates once, looks
biome-plausible, saves/loads chunks correctly, and has a visible day/night
cycle. No gameplay yet.

## Phase 1 — Living ecosystem MVP

Goal: prove the "boars live where boars thrive" pillar.

- Per-cell vegetation model: sunlight + moisture → growth rate → density,
  spreading to eligible neighbor cells, capped by carrying capacity.
- Regional/aggregate herbivore population model: reproduction/migration/death
  as a function of local vegetation density and water access.
- Regional/aggregate predator population model: same, tracking prey density.
- Promotion rule: when a player is near a region, spawn individually
  simulated/rendered creature agents consistent with that region's current
  aggregate population; despawn back to aggregate when the player leaves.
- Basic time-lapse test: run the simulation for N simulated days with no
  player present and confirm population distributions shift sensibly with
  e.g. a simulated drought (this is exactly the kind of deterministic logic
  strict TDD suits well).

**Definition of done**: you can walk the prototype map and observe different
creatures naturally clustered in different biomes, with no hand-placed
spawners; a scripted drought/resource-removal test visibly shifts where
creatures are found afterward.

## Phase 2 — NPC AI MVP

Goal: prove the daily-plan NPC architecture at small scale (5–10 NPCs, one
village).

- NPC data model: identity, personality traits, current needs/goals,
  relationships to a few other NPCs, persistent memory log.
- Daily planner: one LLM call per NPC per in-game day → a schedule of
  `{time block, location, activity}`.
- Local executor: FSM + pathfinding that walks the schedule with zero LLM
  calls during normal execution.
- Interrupt handling: define the small set of events that trigger an
  out-of-cycle replan (combat, meeting a notable NPC/player, a need crossing
  a threshold) and confirm they actually trigger a replan in a test.
- Live dialogue: a minimal player-facing conversation flow that calls the
  LLM with the NPC's identity + relevant memory as context, and appends the
  outcome back into that NPC's memory log.
- LLM backend: stand up against a local model first for cheap/fast dev
  iteration; keep the integration point backend-agnostic so a hosted API
  (e.g. Claude) can be swapped in for higher-quality planning/dialogue later.

**Definition of done**: a small village of NPCs visibly goes about
self-directed daily routines, remembers a player interaction across an
in-game day boundary, and reacts differently to being, say, attacked vs.
greeted.

## Phase 3 — Core gameplay loop

Goal: make it a game, not a simulation demo.

- Player stats/inventory/equipment scaffolding (standard RPG systems).
- Combat: Hammerwatch-style real-time arena combat — movement, cooldown
  abilities, hit/damage resolution.
- Tactical layers: knockback into hazards, spreadable fire/oil, elevation via
  layered tiles, vegetation-density-driven concealment (reusing Phase 1's
  vegetation data).
- Building: Terraria-style tile placement/destruction, persisted via the
  Phase 0 chunk system; a built structure survives a save/reload and player
  leaving/returning.

**Definition of done**: a player can fight through a small encounter using at
least one tactical/environmental mechanic beyond plain damage trading, and
can build a small persistent structure that's still there after a
save/reload.

## Phase 4 — Emergent quests

Goal: replace "kill 10 boars" with need-driven requests.

- Minimal quest-template set derived from NPC needs (fetch / protect /
  deliver, per concept/overview.md's open question) with LLM-generated flavor
  text/dialogue layered on top of template logic (not raw LLM-authored quest
  logic, to keep it debuggable/non-exploitable).
- Reward/consequence hooks back into the NPC's relationship/memory state.

**Definition of done**: at least 2 distinct quest template types are
generated organically from NPC state in the Phase 2 village, without any
hand-placed quest-giver script.

## Phase 5+ — Post-MVP expansion (sequenced, not yet detailed)

Each of these is a substantial project in its own right and should get its
own design pass (and likely its own roadmap doc) once Phases 0–4 are solid:

1. **Multiplayer**: shared persistent world, netcode, small-scale co-op
   first, before any MMO-scale claims.
2. **Economy & society**: player-driven villages, trade, MMO-scale social
   structure on top of a working multiplayer base.
3. **Era progression**: medieval → industrial → AI boom → space, and the
   reincarnation mechanic that transitions a player between them.
4. **Multi-planet/galaxy**: spacecraft, procedural planet generation, planet
   rarity tiers, claiming a home planet, space logistics/import of tech.
5. **Full planet scale**: expand the generated map from Phase 0's prototype
   region toward whole-Earth scale, using the same systems — this is a
   content/performance scaling exercise, not a new architecture, per
   concept/world.md's design intent.

---

## Emergence substrate — detailed phasing for the social/historical layer

`docs/emergence/*.md` (00 architecture, 01 society/institutions, 02 history/
memory/rumors, 03 contracts/property/economy, 04 settlements/cities/
infrastructure, 05 dungeons/bosses/exploration, 06 emergent-gameplay catalog,
07 its own dependency-ordered roadmap, 08 a Claude Code execution brief) is a
second, approved concept-doc set specifying the causal substrate under
society, history, economy, settlements, and dungeon/boss content: the
principle is *"persistent content must have a causal parent in the
simulation"* — a quest, dungeon, faction, city, or legend exists because
simulated actors and events made it possible, not because a content generator
placed it.

This section threads that spec's own 18-phase roadmap
(`docs/emergence/07-implementation-roadmap.md`) into *this* roadmap, mapped
onto what already exists in `src/` and `docs/concept/*.md` today, so work can
actually start rather than stay a second unintegrated plan.

### Relationship to Phases 0–5+ above

**This is substrate, not a new milestone bolted after Phase 5+.** The
existing roadmap phases are ordered by *player-facing* milestones (playable
loop → NPC AI → combat/building → quests → multiplayer → MMO-scale economy).
The emergence phases are ordered by *causal dependency* (don't build cities
before the primitives a city is made of) and are almost entirely
single-player-simulable: NPCs already exist and interact with each other
without any player present, so the event/memory/household/institution
substrate below can and should start now, well ahead of "Phase 5+ #2:
Economy & society... MMO-scale," which is the *player-facing, multiplayer*
expression of a substrate this section builds first. Concretely: Emergence
Phases 0–9 (event substrate through settlement simulation) have no
multiplayer dependency and slot into ongoing Phase 2 (NPC AI) and Phase 4
(emergent quests) work; Emergence Phases 10–18 (dungeons/bosses onward)
likewise slot into Phase 4/5+ as their design docs (`worldbosses.md`,
`quests.md`) already partially describe. Only genuinely player-vs-player
concerns (a player faction's standing, player-run markets across clients)
stay gated behind real multiplayer as roadmap Phase 5+ #1 already specifies.

**Existing concept docs already cover parts of several emergence phases in
this project's own terminology, grounded in systems that already exist**
(`predator_population_model.gd`'s carrying capacity, `evolution.md`'s fitness/
rarity sim, the NPC replan-interrupt architecture, the loaded/unloaded
simulation-fidelity split). Where a phase below already has a concept doc,
implementation must reconcile with it rather than duplicate it — the
emergence docs formalize the general mechanism; the concept doc supplies this
project's specific, already-partially-built expression of it.

| Emergence phase | What it builds | Existing concept-doc overlap | Existing code to build on |
|---|---|---|---|
| 0 — Baseline & instrumentation | Stable entity IDs, event type registry, entity-history queries, cause-chain debugger, snapshot tests, sim metrics | none (new infrastructure) | `PlayerSave`/`ChunkSerializer`'s `FileAccess.store_var`/`get_var` persistence convention; `EarthChunkManager` as the natural home for a shared store |
| 1 — Event & causality substrate | `Event`, `EventStore`, importance, cause/consequence links, deterministic ordering, retention | none (new infrastructure) | same as above; console command pattern (`/season`, `/weather`) for `/why`, `/history` |
| 2 — Memory, beliefs, information | NPC memory records, confidence, rumor transmission | `npc.md`'s "Memory, beliefs, and rumor propagation" (2026-08-24: specified in detail — `MemoryRecord`/`MemoryStore`, propagation over existing landmark proximity, decay, and the fix to `quests.md`'s rumor hand-wave — not built) | `npc_identity.gd`, `npc_planner.gd`, `npc_schedule.gd`, `src/emergence/event.gd`/`event_store.gd` |
| 3 — Households & property | Household membership, shared inventory, property, inheritance | `npc.md`'s lifecycle (aging/reproduction/death — 🚧 designed, not built) | `npc_identity.gd`, `settlement_generator.gd` |
| 4 — Contracts & obligations | Contract lifecycle, debt, reputation effects | `npc.md`'s hiring ("wage + relationship gate," designed not built) | `economy.md`'s currency faucets |
| 5 — Local production economy | Recipes, sites, local markets, supply/demand | `economy.md` (currency only so far), `crafting.md`/`resources.md`/`materials.md` | existing crafting/materials systems |
| 6 — Institutions | Guilds, militias, formation/dissolution hysteresis | `factions.md` (deliberately *aggregate reputation, no separate faction entity* — an institution here is the first real organizational entity; must not duplicate the aggregate-reputation model, should sit alongside it) | — |
| 7 — Settlement simulation | Carrying capacity, growth/decline/specialization | `quests.md`'s "closed loop" (settlement born → grows → risk rises → destroyed/dwindles → migration seeds next), `npc.md`'s village population open question | `settlement_generator.gd`, `predator_population_model.gd`'s carrying-capacity idiom |
| 8 — Infrastructure networks | Traffic → trail → road, bridges, condition | `building.md`, `transportation.md` | — |
| 9 — Towns & cities | Multi-dimensional city thresholds, contraction | `04-settlements-cities-infrastructure.md` only so far | — |
| 10 — Dungeons/ruins/history POIs | Historical-POI lifecycle, archaeology | `exploration.md`'s abandoned-settlement ruins (designed) | — |
| 11 — World bosses | Exceptional-individual promotion, legacy | `worldbosses.md` (🚧 designed in detail: emergent-stats + one-shot LLM phase-authoring, village-endangerment attractor — not built) | `evolution.md`'s fitness/rarity sim |
| 12 — Emergent quests | Quests as projections of real problems | `quests.md` (🚧 designed in detail: promotion/quorum/representative, village endangerment, supply/demand quests — explicitly "nothing implemented" per its own status note) | — |
| 13 — Governance & politics | Legitimacy, policy, taxation | `01-society-and-institutions.md` only so far | — |
| 14 — Regional trade & migration | Trade networks, migration corridors | `world.md`'s "population exists wherever conditions make it viable" | — |
| 15 — Technology & cultural diffusion | Knowledge transmission, regional variants | none yet | — |
| 16 — Religion, festivals, legends | Belief communities, sacred sites | `festivals.md` (referenced by `npc.md` as an eventual daily-planner byproduct) | — |
| 17 — Polities, wars, civilization | Territory, law, war, diplomacy | roadmap Phase 5+ #2/#3 (era progression) | gated behind real multiplayer per Phase 5+ ordering above |
| 18 — Player legacy | Historical figures, monuments, lineages | none yet | `death.md`'s reincarnation mechanic is an obvious future tie-in |

**Status of the phases above**: tracked mechanism-by-mechanism in
`docs/progress.md`'s own "Emergence substrate" section, not duplicated here —
this table is the dependency map, progress.md is the ledger.

**Definition of done for Emergence Phase 0/1**: any entity recorded in the
event store can be inspected (`/history <entity_id>`) and any recorded
event's causes traced (`/why <event_id>`) without reading source code or
asking an LLM, a save/load round-trip is lossless and deterministic, and at
least one real, already-live gameplay moment (not a synthetic test fixture)
emits a real event visible through those commands during ordinary play. Met,
and now the foundation Phases 2–7 build on — see `docs/progress.md` for
current status phase-by-phase. Phase 7 (settlement simulation) was the first
later phase with a genuinely automatic live trigger of its own, not just a
callable, tested mechanism; Phases 4 (contracts), 5 (local production
economy), and 6 (institutions) now share that same trigger — extended into
`step_settlements` itself rather than each growing a separate one — so
every phase through 7 has a real automatic path, not only a tested
mechanism waiting to be called. Phases 8 onward remain callable-mechanism-or-
unstarted, same as before.

---

## Working notes

- Every phase's simulation logic (growth curves, population dynamics, plan
  execution, chunk persistence, quest template resolution) is deterministic
  and unit-testable — write the test first per `CLAUDE.md`, before any
  implementation.
- LLM-dependent behavior (planning, dialogue) is harder to unit-test
  directly; prefer testing the *scaffolding* around it (does an interrupt
  correctly trigger a replan call, does a plan get correctly parsed and
  executed, does memory get correctly appended) with a stubbed/fake LLM
  response, rather than asserting on real model output.
