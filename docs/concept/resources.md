## Mineable resources

Resources are procedurally spread across the world and must be found and
mined, rather than handed to the player — same "exists where conditions
make it viable" philosophy as [world.md](world.md)'s ecosystem sim, applied
to geology and gathering instead of just wildlife.

- **Dynamic, not a one-time placement.** Ore veins and resource richness
  shift over the world-sim's timescale rather than being fixed forever at
  worldgen. Nonrenewable mineral deposits deplete permanently as they're
  mined (a played-out vein is gone) but slowly migrate/regenerate elsewhere
  on a long geological timescale; renewable organic resources (wood, fiber,
  herbs) follow the same fast plant-growth model [world.md](world.md)
  already defines for vegetation.
- Feeds directly into [crafting.md](crafting.md)'s blueprint DSL as
  material inputs, and (for organic/creature-sourced materials) into the
  DNA-quality-as-material-quality link described there.

### Open questions

- What's the right regeneration timescale for depleted mineral veins —
  should a played-out region ever meaningfully recover within one player's
  active lifetime, or is depletion effectively permanent in practice?
- Resource discovery/tooling: does finding resources lean on visible
  world-gen tells (surface ore hints, biome correlation) or dedicated
  prospecting tools/skills?
