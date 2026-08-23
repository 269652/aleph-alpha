# Aleph-Alfa Emergent Simulation Architecture

## Purpose

This specification extends the existing Aleph-Alfa design into a unified substrate for emergent society, history, economy, exploration, dungeons, cities, factions, institutions, and player-generated mythology.

The core principle is:

> Persistent content must have a causal parent in the simulation.

A quest, dungeon, settlement, faction, city, boss, ruin, legend, or political conflict should exist because simulated actors, resources, ecology, infrastructure, and historical events made it possible.

The simulation is authoritative. LLMs are planners, interpreters, and presentation layers—not sources of world-state truth.

## Design goals

1. **Causality over decoration.**
2. **Composition over bespoke systems.**
3. **Persistence over respawn.**
4. **History over static lore.**
5. **Institutions over hard-coded factions.**
6. **Physical flows over abstract numbers where practical.**
7. **Aggregation for scale.**
8. **Deterministic simulation for authoritative state.**
9. **LLMs at semantic boundaries only.**
10. **Every major system must produce downstream consequences.**

## Substrate layers

### Layer 0: Physical world

Terrain, climate, weather, water, materials, time, spatial topology, construction.

### Layer 1: Biology

Flora, fauna, genetics, reproduction, disease, ecology, carrying capacity, migration.

### Layer 2: Individuals

Needs, skills, personality, memory, beliefs, relationships, inventory, property, obligations.

### Layer 3: Households

Family, dependents, shared resources, income, property, debt, inheritance, production, reputation.

### Layer 4: Organizations

Guilds, companies, militias, religious groups, cooperatives, criminal groups, schools, merchant associations.

### Layer 5: Settlements

Hamlets, villages, towns, cities, infrastructure, governance, markets, specialization, population.

### Layer 6: Regions

Trade networks, migration corridors, ecological regions, political territories, resource dependencies.

### Layer 7: History

Events, causality, witnesses, memories, rumors, records, legends, ruins, artifacts.

### Layer 8: Players

Construction, combat, diplomacy, discovery, breeding, invention, leadership, destruction, intervention.

## Core generic mechanisms

The highest-leverage mechanisms are:

- needs
- resources
- relationships
- memory
- obligations/contracts
- institutions
- event causality

Do not implement every proposed feature as an isolated subsystem if it can emerge from these primitives.

## Entity model

All persistent entities should have:

- stable ID
- creation event
- current state
- location or scope
- owners/members where applicable
- relationships
- dependencies
- historical event references
- last simulation tick
- provenance/debug metadata

## Provenance

Every generated persistent entity should be explainable.

Example:

```text
City C17
  created_by:
    settlement S4 crossing population threshold
  growth_causes:
    bridge B8
    iron mine M2
    caravan route R5
  current_dependencies:
    grain V9
    iron M2
    timber F3
  major_history:
    drought E22
    guild_strike E41
    dragon_attack E88
```

## Event sourcing

Important state transitions should produce compact immutable events.

An event should contain:

- event_id
- timestamp
- type
- location
- primary actors
- secondary actors
- causes
- inputs
- outputs/consequences
- importance
- visibility
- witnesses
- evidence references

Do not event-source every low-level movement. Event-source meaningful changes.

## Simulation authority

The authoritative loop is:

```text
observe state
→ identify pressures/opportunities
→ generate candidate actions
→ select actions
→ deterministic validation
→ execute
→ emit events
→ update memories/beliefs
→ update aggregates
→ persist
```

LLM planning may occur between observation and action selection, but an LLM may never directly mutate authoritative state.

## Time and aggregation

Use multiple simulation frequencies:

- real-time: player-near interactions
- minute/hour: local NPC actions
- daily: household/economic routines
- weekly: institutional and settlement aggregates
- seasonal: ecology/agriculture
- yearly: demographics, inheritance, long-term infrastructure
- historical catch-up: unloaded regions

Every system must define an aggregation strategy before it is considered production-ready.

## Emergence invariant

A system is successful when removing its bespoke content generator does not destroy the world's ability to produce interesting outcomes.

For example, if quests are disabled, NPC needs and events should still create problems. A quest presentation layer can then expose those problems to players.

## Anti-patterns

Avoid:

- arbitrary quest spawns
- immortal static factions
- city prefabs with no causal origin
- dungeon rooms disconnected from history
- boss spawns disconnected from ecology
- LLM-authored facts that contradict simulation state
- global instantaneous markets
- global instantaneous knowledge
- permanent NPC occupations
- magic numbers without provenance
- features that produce no downstream consequences

## Observability requirements

Every emergent system needs:

- event log
- cause chain inspection
- entity history
- state snapshot
- dependency graph
- aggregate metrics
- deterministic replay support
- debug commands

A developer should be able to answer:

> Why does this city exist?

> Why is this item expensive?

> Why did this NPC migrate?

> Why did this dungeon appear?

> Why is this faction hostile?

> Why did this village collapse?

without asking an LLM.
