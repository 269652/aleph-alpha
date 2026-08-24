## Geology: what's under the ground is a real place, not a deeper number

Today's stone/ore (`StoneSize`'s Wentworth scale, `LiftableStone`/
`SmashableStone`/`MinableOre`, `OrePlacement`) is entirely surface-level —
a rock is a rock lying on the ground, with no depth dimension at all. This
spec gives the world an actual underground: real strata, ore that forms
where real geology says it should, tunnels a player can dig and has to
brace against real collapse, and hazards that genuinely escalate with
depth. Compiled from a design-brainstorm session (see `disease.md` for the
sibling spec from the same conversation), not yet implemented.

### Design pillars

- **Reuse the layer-hiding mechanism buildings already have**, don't
  invent a new spatial system. A building interior is already hidden
  until the player walks in (`_roof_layer`/hidden-cell reveal); a cave
  entrance is the exact same problem pointed at rock instead of a room.
- **Ore forms where real geology says it should.** Copper in old
  volcanic/mountain contexts, coal in dense-vegetation/lowland contexts,
  iron broadly but richer with depth — tied to the biome data this
  project already computes (`BiomeClassifier`), not an invented "geology
  biome" layered on top.
- **Digging is real work with a real cost, not free depth.** An
  unsupported tunnel can genuinely collapse — real mining engineering's
  actual concern (roof span vs. support spacing) — which also gives
  `beam`/`plank` (built this session, zero consumers so far) their first
  real job: shore up a tunnel or risk it caving in.
- **Depth is a real risk/reward/difficulty curve, and those move
  together.** Loot, risk, reward, AND difficulty all escalate in lockstep
  with each layer down — richer ore AND real escalating hazard (foul air,
  water-table flooding) AND a genuinely harder dig (denser rock, a
  stronger tool-tier gate) at the same time, never one axis alone. "How
  deep do I dare go" is a real decision because every answer costs more
  and pays more, not a grind timer with a rarity dial at the end of it.

### Real-world grounding

- **Ore genesis is a real, well-documented geological story, not
  randomness.** Porphyry copper deposits form in volcanic/igneous
  intrusion zones — real-world copper mining is disproportionately a
  mountain/volcanic-terrain activity. Coal forms from ancient organic
  matter (swamp/dense-vegetation) buried and compressed over geological
  time — real coal basins correlate with what were once lush, low-lying,
  densely vegetated regions. Iron is comparatively widespread (banded iron
  formations are ancient and common), but genuinely purer/richer deeper,
  where it hasn't weathered.
- **Timber shoring is real mining history**, not a game abstraction —
  wooden support props/beams are literally what kept real mine tunnels
  from collapsing for most of mining history, which is exactly what this
  project's own new `beam` item already is.
- **Foul air is a real, historically deadly hazard** (blackdamp/afterdamp:
  oxygen-depleted or CO-laden air pooling in poorly-ventilated deep
  workings) — real grounding for a depth-scaled stamina/survival cost.
- **Water table flooding is real and genuinely local**: how deep you can
  dig before hitting groundwater depends on how close you are to existing
  surface water — a mine near a river or coastline floods at a shallower
  depth than one in arid high ground, a real, free coupling to terrain
  this project already generates from real elevation data.

### Mechanism spec

#### Entering the underground (reuses the existing indoor-layer mechanism)

A cave/mine entrance, placed deterministically and sparsely (mountain/
rocky-biome-weighted, matching where real cave systems actually form),
hides the surface `_roof_layer`-style and reveals a new underground
`TileMapLayer` for that chunk — the same reveal-on-entry mechanism a
building interior already uses, pointed at rock instead of a room.

#### The underground itself: real, distinct layers, not one depth number

Real stratigraphy isn't a smooth gradient — it's a sequence of genuinely
different zones, and this models it as exactly that: **discrete named
layers**, each its own `Strata` instance (mirroring the established per-
chunk patch-sim contract — `TallGrass`/`FlowerPatch`/`EarthwormPatch`:
one instance per chunk, deterministic `PixelNoise`-seeded, a grid of
cells each either solid rock, an ore deposit, or already-open tunnel),
not one grid with a depth axis inside it. Getting from layer N to layer
N+1 is a real, discrete transition — a shaft or stairway the player digs
or finds, reusing the SAME reveal-on-entry mechanism the surface→Layer-1
cave entrance already uses, recursively: layer N hides itself and reveals
layer N+1 the same way the surface hides itself for a cave.

Each layer has its own real identity, escalating together (hardness, ore
table, hazard, and tool-tier gate all move together, not independently —
a real geological cross-section):

1. **Topsoil / regolith** — loose, weathered rock just under a cave
   entrance. Common ore only (roughly what today's surface `OrePlacement`
   already offers), low hazard, diggable with any pickaxe.
2. **Bedrock** — solid rock proper. Iron and coal in earnest, moderate
   foul-air onset, needs a real (not bare-hands-tier) pickaxe.
3. **Deep bedrock** — hard rock; copper and rarer finds. Structural
   collapse risk becomes a genuine concern here, not a formality, and
   water-table flooding becomes real. Gated behind a stronger pickaxe
   tier.
4. **Hydrothermal zone** (mountain-biome-linked, the deepest layer) —
   where real hydrothermal ore veins actually form (this project's
   richest possible find lives here, the real payoff for real risk):
   severe foul air, severe flood risk unless the chunk is dry/mountainous,
   and the highest collapse risk of any layer. The genuine "how deep do I
   dare go" ceiling.

#### Digging (extends `MinableOre`'s existing shape)

A solid rock cell is dug the same swing-driven way `MinableOre` already
works — pickaxe-gated (`Player._pickaxe_power`), yields stone (+ore, if
the cell holds one), and converts the cell to open, walkable tunnel.
`MinableOre` itself becomes the special case of "a rock cell that happens
to hold ore," not a separate mechanic.

#### Ore genesis (extends `OrePlacement`)

Which ore type a deposit-bearing cell holds is weighted by the SAME real
correlations named above, read from the chunk's own biome + depth:
mountain-adjacent and deep favors copper, forest/rainforest-adjacent and
mid-depth favors coal, iron stays broadly available but its yield purity
scales with depth. A pure, tested function of (biome, depth, seed) — the
same "real formula, not a roll from nowhere" standard every other
placement system in this project already holds to.

#### Structural support (`TunnelSupport`, pure, new)

A pure, tested function of how far a dug tunnel stretches without a
placed `beam`: `collapse_chance_for(unsupported_span) -> float`, rising
with span the way a real unsupported roof genuinely does. Placing a
`beam` at a tunnel cell resets the unsupported-span count from that
point — real mine-prop spacing, not a flat "safe forever" placement. An
actual collapse re-fills the affected cells with rock (the tunnel has to
be re-dug) and deals real damage to anyone standing in it.

#### Depth hazards

- **Foul air**: a pure `foul_air_at(depth) -> float` factor draining
  stamina regen (or survival meters, matching whatever `survival.md`'s
  existing scope covers) faster the deeper a player works without
  surfacing — real blackdamp/afterdamp grounding.
- **Water table**: `flood_risk_at(depth, distance_to_nearest_surface_water)
  -> float` — a mine dug near an existing river/coast (real elevation
  data this project already has) hits water at a shallower depth than one
  dug in arid high ground; crossing it either floods the tunnel (real
  hazard) or, treated as a resource instead of a hazard, could be the
  entry point for a future underground water mechanic (not scoped here).

### Status

- ⬜ Not yet implemented — compiled design spec from a brainstorming
  session, the deliverable of that conversation, not code.
- ⬜ Open question: does a dug-out tunnel persist across a chunk unload/
  reload the way surface chunk modifications already do (`chunk.
  modifications`), or does an underground layer regenerate deterministically
  like a fresh patch-sim on reload? Real player investment (shoring,
  clearing) argues for persistence; this project's existing precedent for
  ephemeral sim state (`soil_fauna.md`'s worm burrows, `carrion.md`'s
  carcasses) argues the other way for anything NOT explicitly built by the
  player. Worth resolving before implementation.
- ⬜ Open question: within-layer grid resolution — same tile size as the
  surface, or a finer grid for tunnels to read as genuinely narrow/carved
  rather than tile-blocky? (The cross-layer question — discrete named
  layers, not one continuous depth grid — is now resolved above; this is
  only about each individual layer's own cell size.)
- ⬜ Open question: how many shafts does a chunk get to the next layer
  down, and are they placed deterministically (findable, like the surface
  cave entrance) or only where the player digs one themselves? Affects
  whether "go deeper" is mostly exploration or mostly excavation — worth
  deciding before `Strata` is built, not guessed at here.
- ⬜ Not scoped: cave systems as pre-existing NATURAL open tunnels (real
  karst/water-erosion caves the player discovers rather than digs) — this
  pass covers player-dug tunnels only; naturally-generated cave networks
  are a real, separate follow-up.
