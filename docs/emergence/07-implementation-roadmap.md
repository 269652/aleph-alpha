# Aleph-Alfa Emergent Systems Implementation Roadmap

## Objective

Implement the emergent society/history substrate without derailing the existing MVP. Dependency-first: do not implement cities, religions, wars, or MMO-scale systems before lower-level causal primitives are stable.

## Phase 0 — Baseline and instrumentation

Inventory current ECS/domain model, tick ownership, authoritative state, and persistence. Add stable IDs, event type registry, event persistence, entity-history queries, cause-chain debugger, deterministic seed/replay, snapshot tests, and simulation metrics.

**Exit:** any major entity can be inspected and its changes explained.

## Phase 1 — Event and causality substrate

Implement `Event`, `EventStore`, importance, cause/consequence links, queries, indexes, deterministic ordering, serialization, unloaded-region replay, and retention rules.

**Exit:** generic A → B → C causal chains work.

## Phase 2 — Memory, beliefs, and information

Implement memory records, beliefs, evidence, rumors, source types, confidence, and social transmission. Facts remain authoritative; beliefs are projections.

**Exit:** NPC A can tell NPC B about an event and B receives a lower-confidence representation.

## Phase 3 — Households and property

Implement household membership, shared inventory, property ownership, estates, inheritance, and household budgets. Integrate NPC birth/death/reproduction and settlement systems.

**Exit:** families own property, consume/produce resources, and pass property to descendants.

## Phase 4 — Contracts and obligations

Implement contracts, obligations, states, failure, debt, collateral, and reputation effects. Start with employment, supply, construction, trade, and loans.

**Exit:** agreement failures create deterministic social/economic/history consequences.

## Phase 5 — Local production economy

Implement production recipes, sites, local markets, supply/demand, inventory flows, transport cost, and businesses. Integrate existing materials/crafting.

**Exit:** a resource shortage can raise prices and cause downstream production failure without scripted events.

## Phase 6 — Institutions

Implement institutions, membership, goals, assets, rules, leadership, and relationships. Start with guilds, cooperatives, militias, merchant companies, and criminal groups. Use formation/stabilization/dissolution hysteresis.

**Exit:** NPCs can independently form and dissolve an institution.

## Phase 7 — Settlement simulation

Implement carrying capacity, growth, decline, specialization, and dependencies using food, water, housing, jobs, safety, health, infrastructure, trade, and institutional complexity.

**Exit:** villages grow, stagnate, decline, and recover from real pressures.

## Phase 8 — Infrastructure networks

Implement traffic heatmaps, routes, roads, bridges, ferries, market nodes, condition, and maintenance. Repeated movement creates infrastructure; broken infrastructure changes trade.

## Phase 9 — Towns and cities

Implement multi-dimensional city metrics: density, specialization, institutional complexity, infrastructure, trade connectivity, administrative capacity. Support contraction and abandonment.

## Phase 10 — Dungeons, ruins, and history-derived POIs

Implement historical POIs, ruins, dungeon lifecycle, occupants, archaeology, and evidence. At least three independent causal sources must be able to create a dungeon.

## Phase 11 — World bosses

Implement exceptional-organism detection, boss state, territory, event chains, and legacy. Integrate genetics/ecology. Boss emergence and defeat must permanently affect the world.

## Phase 12 — Emergent quests

Refactor quests into projections of household, institution, settlement, ecology, infrastructure, history, and economy problems. Disabling quests must not remove the underlying problem.

## Phase 13 — Governance and politics

Implement governance models, legitimacy, policies, political groups, representation, taxation, and enforcement. Governance changes actual decisions and resource flows.

## Phase 14 — Regional trade and migration

Implement regions, trade networks, migration flows, dependency graphs, and resource corridors. A regional shock should alter multiple settlements.

## Phase 15 — Technology and cultural diffusion

Implement knowledge, techniques, transmission, adaptation, traditions, and recipe variants. Technologies spread through social/economic channels and acquire regional variation.

## Phase 16 — Religion, festivals, legends

Implement belief communities, rituals, festivals, sacred sites, legends, and cultural memory. Major events can create traditions without authored narrative chains.

## Phase 17 — Polities, wars, civilization

Only after local society is stable. Implement territory, law, military organizations, war, treaties, diplomacy, and civilization analytics by reusing existing institutions, contracts, logistics, resources, and history.

## Phase 18 — Player legacy

Implement historical figures, founded institutions, monuments, artifacts, lineages, and legends. Player actions should remain causally visible after the original character is gone.

## Claude Code execution protocol

For every phase: inspect repository → read relevant docs → locate existing implementation → identify reusable abstractions → plan → implement a vertical slice → add scenario test → run targeted tests → run full tests → inspect diff → update docs → proceed.

Every feature needs unit tests, deterministic simulation tests, persistence tests, integration scenarios, and regression coverage. Unloaded-region behavior must be specified.

## First proof-of-concept

Implement this complete chain before cities:

```text
NPC household
→ owns land
→ grows food
→ sells surplus
→ contracts a blacksmith
→ blacksmith forms guild
→ guild negotiates for iron
→ mine collapses
→ iron shortage
→ prices rise
→ household suffers
→ guild petitions settlement
→ event history records the entire chain
```

## Required scenario suite

- economic cascade
- ecological cascade
- institution formation/dissolution
- settlement growth/collapse
- road emergence
- dungeon emergence
- boss emergence
- rumor propagation
- historical investigation
- player legacy

## Performance

Every subsystem must document per-tick cost, per-entity cost, indexes, aggregation strategy, unloaded behavior, and persistence footprint. Avoid global O(N²) social queries; use spatial neighborhoods, relationship indexes, event indexes, dirty flags, aggregates, and sampled candidate selection.

## LLM boundary

LLMs may propose NPC plans, summarize history, phrase dialogue, generate descriptions/names, and interpret constrained social context. They may not directly create resources, mutate prices, invent ownership, teleport entities, declare cities/bosses, or override deterministic rules. All outputs are constrained actions validated by the simulation.
