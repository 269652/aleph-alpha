## Exploration: points of interest seeded by world-sim history

No doc currently covers dungeons, ruins, or other explorable points of
interest. Rather than scattering generic procedural dungeons, POIs are
**seeded by the world simulation's own history** — exploration becomes
reading the planet's past, not generic loot-piñata content.

- **Abandoned settlements**: an NPC village (see [npc.md](npc.md)) that
  the ecosystem/climate sim ([world.md](world.md)) or a
  [disaster](weather.md) genuinely wiped out or displaced leaves real
  ruins behind — the buildings, and possibly logged fragments of what
  happened to its NPCs, are discoverable, not decorative dressing with no
  underlying cause.
- **Monster lairs**: a den or territory tied to where a
  [world boss](worldbosses.md) emerged and lived, discoverable as a
  dangerous, loot-rich POI even after the boss itself is dealt with (or
  while it's still active, as the boss's home turf).
- **Ancient groves**: an [ancient tree](flora.md#ancient-trees-emergent-legendary-flora)
  that's survived generations of drought and disease is a discoverable,
  non-combat POI of its own — a landmark and resource destination rather
  than a threat.
- **Procedural but causally grounded**: placement/density of POIs still
  comes from procedural generation, but is weighted by actual simulated
  events (a region with a history of droughts is more likely to have a
  starved-out ruin; a region with a long-lived apex predator lineage is
  more likely to have an old lair) rather than being uniformly scattered.
- Loot from POIs feeds [items.md](items.md)'s rarity vocabulary the same
  way world bosses and crafting do.

### Puzzle content stays emergent, not hand-authored

Decided in a 2026-07-16 brainstorm crossing this design against Zelda- and
Hammerwatch-style puzzle/set-piece dungeons: **no hand-placed puzzle rooms,
switches, or bespoke mechanisms exist anywhere** — that would break the
project's "nothing is hardcoded, everything emerges from composed primitives"
principle (see [synthesis.md](synthesis.md)).

Instead, a POI can still gate its loot behind a genuine obstacle, because that
obstacle is just a **procedurally-seeded application of the same physical
grammar** [materials.md](materials.md) and [magic.md](magic.md) already define
— nothing bespoke to author or maintain:

- A collapsed passage that only enough momentum (a heavy enough thrown/pushed
  object, or a strong-enough bloodline) can clear.
- A flooded chamber that needs a `Freeze`-class force to cross, or a burning
  one that needs the reverse.
- A sealed door whose material simply has a hardness/toughness threshold
  higher than an ordinary tool, forcing the player to bring (or make) the
  right material or force to break it.

A POI's generator picks from this existing vocabulary of verbs/thresholds at
creation time, seeded by the same causally-grounded history weighting
described above (an old flood-ravaged region biases toward "flooded vault"
obstacles; an old fire-scarred one biases toward "burnt-sealed" ones) — so
ruins read as genuinely guarded without a single hand-designed puzzle
existing in the game.

### Open questions

- How much actual simulated history needs to be logged/retained to seed
  POIs meaningfully, versus how much is "plausible enough" procedural
  dressing generated at POI-creation time rather than true simulation
  replay?
- POI density/pacing — how often should a player stumble on one, and does
  that scale with world size (per [overview.md](overview.md)'s eventual
  whole-Earth-scale goal)?
- Exact vocabulary/difficulty curve for procedurally picking which physical
  obstacle(s) gate a given POI's loot tier.
