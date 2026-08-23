# Claude Code Master Brief — Aleph-Alfa Emergent Substrate

## Mission

Extend Aleph-Alfa from a collection of simulation systems into a coherent emergent-world substrate. The target is not “more content”; it is a deterministic world whose physical, biological, social, economic, and historical processes continuously generate content.

## Read first

Read the existing concept, synthesis, NPC, world, economy, ecosystem, quests, exploration, worldbosses, materials, transportation, progress, and roadmap documents. Then read every document in `docs/emergence/`.

## Non-negotiable architecture

1. Simulation is authoritative.
2. LLMs are planners/interpreters, never world-state authorities.
3. Persistent content has causal provenance.
4. Systems compose rather than duplicate concepts.
5. Aggregation is mandatory for scale.
6. Important changes survive unload/save/load/time advancement.

## First milestone

Implement the smallest complete causal loop:

```text
household → property → production → market → contract → institution → resource shock → economic consequence → NPC response → historical event
```

Do not proceed to cities until this works deterministically.

## Developer tools

Provide equivalent inspection commands for:

- `inspect_entity <id>`
- `entity_history <id>`
- `why <entity_id>`
- `trace_event <event_id>`
- `inspect_settlement <id>`
- `inspect_institution <id>`
- `inspect_market <id>`
- `inspect_dependencies <entity_id>`
- `simulate_ticks <n>`
- `save_snapshot`
- `load_snapshot`
- `replay_from_snapshot`

## Required scenarios

Automate economic cascade, ecological cascade, institution formation/dissolution, settlement growth/collapse, road emergence, dungeon emergence, boss emergence, rumor propagation, historical investigation, and player legacy.

## Review questions

For every change ask: What state exists? What causes it? What consumes it? What consequences does it produce? How does it persist? How does it behave unloaded? How is it debugged? How is it deterministically tested? What happens when the entity dies? What happens when dependencies disappear? Can an existing primitive represent it? Does an LLM actually need to participate?

## Avoid premature complexity

Do not begin with full banking, realistic macroeconomics, legal codes, grand diplomacy, civilization-scale warfare, or full news media. Prove local causal loops first.

## Desired end state

The same substrate should eventually produce farming villages, mining towns, merchant guilds, political factions, cities, trade routes, wars, ruins, dungeons, legendary monsters, religions, festivals, historical mysteries, and player-founded institutions without bespoke content generators.

## Success test

The test is not how much content is generated. It is whether a developer can trace an interesting piece of content backward through a chain of real simulated causes.
