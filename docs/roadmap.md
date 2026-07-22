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
