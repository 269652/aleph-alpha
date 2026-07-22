# Aleph-Alfa — Game Concept

## One-line pitch

An 8-bit, top-down MMORPG built on a real, mechanically-simulated planet — where
plants grow, animals populate biomes because they actually thrive there, and
every NPC is an AI-driven individual living a self-determined life — mixing the
scale/social depth of WoW, the collection/creature ecology of Pokémon, and the
build-anything sandbox of Terraria.

## Status

Concept + planning stage. No code yet. Solo/hobby, part-time development.
See [roadmap.md](../roadmap.md) for the phased build plan. This `concept/`
folder is the long-term vision bible — every system here is fair game to
flesh out fully regardless of what's in scope for the MVP; sequencing is
`roadmap.md`'s problem, not this folder's.

## Confirmed direction (as of this writing)

- **Team**: solo, part-time.
- **Engine**: Godot.
- **Art**: 2D top-down pixel art.
- **First build target**: single-player prototype of the core simulation +
  gameplay loop. Multiplayer, economy, and MMO-scale society come later, on
  top of the same systems (see Non-goals below).

---

## Non-goals (for now)

Explicitly *not* trying to solve these yet — they're real, but they're
post-MVP or open questions, not blocking the first playable build:

- Live plate-tectonics / fluid climate simulation (terrain is generated once).
- True spherical (non-toroidal) globe rendering.
- Multiplayer netcode, shared economy, player-driven society.
- Era progression / reincarnation mechanics.
- Multi-planet travel, procedural planet generation, planet rarity systems.
- Full BG3-grade emergent physics combat.
- Monetization / platform distribution.

## Open questions (to resolve during MVP work, not blocking day 1)

- Quest template design: what's the minimal set of need-driven quest shapes
  (fetch/protect/deliver/...) that feels good and is hard to exploit?
- How much of an NPC's memory log actually needs to feed back into the daily
  planning prompt before cost/context size becomes a problem?
- LLM backend choice for NPCs: hosted API (cost/latency at N NPCs) vs. local
  model (free, but weaker planning quality) — likely both, local for dev.
- Exact semantics of era-reincarnation once we get there: per-player or
  per-server era state? What (if anything) carries over across a "death"?
- PvP rules and how they interact with a persistent, buildable world.
