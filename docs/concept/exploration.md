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
  underlying cause. A settlement that lost an endangerment fight to a
  [world boss](quests.md#village-endangerment-the-attractor-mechanism) is
  one specific, legible cause among these — the unresolved quest itself
  becomes the ruin's discoverable "what happened here" fragment.
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

### Status

The emergence substrate (`docs/emergence/05-dungeons-bosses-exploration-
content.md`, `docs/roadmap.md`'s Emergence Phase 10) built the **causal/data
layer only** — a real `ruin_formed` entity, `EventStore.link_cause`-linked
back to whatever real event actually caused it, satisfying "Creation causes
must be stored" and making "why does this ruin exist" a real,
`/history ruin:<key>`-inspectable question. **No physical ruin structure is
generated or rendered in the game world yet** — everything this doc
describes above (actual decayed buildings, monster lairs, ancient groves,
ecosystem-history-weighted placement, materials-gated obstacles) is still
future work; the substrate only proves a ruin's real, causally-grounded
*existence*, not its appearance.

Three independent, real causal sources exist today (the Phase 10 exit
criterion: "At least three independent causal sources must be able to
create a dungeon"), each mapped to one of `docs/emergence/05`'s own named
"Dungeon sources" categories rather than invented to hit a number:

- **Historical catastrophe**: a settlement's real, automatic decline
  (Phase 7, food-driven).
- **Ecological transformation... overgrown ruins**: nature reclaiming a
  worn path (Phase 8) — literally the named phenomenon, not an analogy.
- **Social transformation... abandoned prisons**: a dissolved institution's
  old headquarters (Phase 6).

Two of the three ride on ALREADY-automatic triggers (settlement decline,
path reclamation); the third (institution dissolution) is real and wired,
but its own root trigger — `dissolve_institution` — still has no automatic
call of its own (Phase 6's own pre-existing, documented gap, not new to
this phase). "Occupants," "archaeology," and physical obstacle-gating are
all explicitly future slices — none of the systems they'd need (creature
spawning tied to a location, a puzzle/obstacle-verb generator, world
bosses) exist yet either.

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
- When physical generation eventually lands, does it read the real
  `ruin_formed`/`causes` data already recorded, or does it need richer
  spatial/structural state the current causal-only entity doesn't carry?
