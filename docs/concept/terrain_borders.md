# Terrain Borders

How the tile grid stops looking like a tile grid at a biome boundary. This
system has grown entirely through iteration (see `docs/progress.md`'s own
narrative history) without ever having a spec of its own; this doc is that
spec, written after the fact and kept aligned going forward per this
project's own [CLAUDE.md](../../CLAUDE.md) rule.

## Design pillars

1. **A border reads as a transition, not a seam.** Two biomes meeting at a
   hard pixel-grid edge is the thing every mechanism here exists to avoid —
   whether that edge runs along a cardinal side or diagonally through a
   corner.
2. **Exactly one side ever renders the transition.** Both sides dithering (or
   both sides carving) the same border doubles it into a mushy two-tile band.
   `TerrainRenderer.BLEND_PRIORITY` is the single ranking every mechanism
   below defers to for "whose job is this edge/corner."
3. **Baked into the opaque base tile, not a translucent overlay.** A
   screen-space or per-pixel overlay (the GPU `WaterFx` shore fade) can only
   ever soften what's drawn *under* it — it cannot change a hard square
   silhouette. Every mechanism here paints real pixels into the base
   `TileMapLayer` layer itself.
4. **Bounded atlas cost.** Every biome pair/direction/variant combination is
   a real, pre-generated tile occupying real atlas space and real one-time
   build cost (`docs/concept/art_resolution.md`'s boot-performance budget) —
   a mechanism's scope is deliberately kept to the SMALLEST set of ordered/
   unordered pairs that can possibly be real, never a blanket N×N.

## Two mechanisms, two different shapes of border

### Cardinal edges: directional dithered blend

Where a cell shares a full cardinal edge (N/S/E/W) with a differing biome,
the HIGHER-`BLEND_PRIORITY` side dithers its own texture over the lower one
along every such edge at once (`TerrainRenderer.dominant_blend_for` /
`atlas_coords_for_directional_blend`) — a soft, speckled fringe rather than a
flat colour swap. Water is excluded entirely: land never dithers toward or
from ocean on a cardinal edge (that transition is the GPU `WaterFx`
shore-distance overlay's own job — a land-side dithered fringe would fight
it, see `dominant_blend_for`'s own doc comment).

### Diagonal corners: carved quarter-circle

Where a cell's tile-grid CORNER (not a full edge) touches a different biome —
the two cardinal cells flanking that diagonal both differ from this cell —
a plain dithered blend can't express it (dithering is an edge concept). The
corner is instead CARVED: a rounded quarter-circle of the other biome's own
texture, composited directly into this cell's opaque base tile
(`TerrainRenderer.corner_direction_for` / `atlas_coords_for_corner`,
`ProceduralTerrainSprite.generate_corner_image`).

Three real shapes, three atlas families (`_corner_linear` routes to whichever
owns the pair):

- **Convex** — an OCEAN cell with land poking into it on two perpendicular
  sides (a peninsula tip narrowing the water). Indexed by the land partner's
  ordinal alone (one ocean side is a given).
- **Concave** — a LAND cell with ocean poking into it on two perpendicular
  sides (a bay/inlet tip narrowing the land). Indexed by the land biome's own
  ordinal alone, same reasoning mirrored.
- **Land/land** — two DIFFERENT land biomes meeting only at a shared corner,
  no ocean involved at all (a grassland cell notched by forest on two
  perpendicular sides, or a real three-biome corner where neither flanking
  neighbor is this cell's own biome). `corner_direction_for` is only ever
  reached by the LOWER-priority side of a pair (`dominant_blend_for` already
  claims the higher-priority side via ordinary cardinal dithering first — see
  `paint()`'s own doc comment), so only ONE direction of any two land biomes
  is ever real. Indexed by the UNORDERED pair among every land biome
  (`TerrainRenderer.LAND_BIOMES_BY_PRIORITY`, `_land_corner_pair_ordinal`) —
  C(n,2) pairs, not n×(n-1) ordered ones, since the direction is never
  ambiguous once priority decides it.

A cell can qualify on more than one corner simultaneously (a lone one-tile
pond qualifies on all four; a single-tile-wide spit on two) — every
qualifying corner is collected and carved together, not just the first one
found.

### When a cell qualifies for both

A cell can have a real corner on one diagonal while an entirely unrelated
cardinal edge also qualifies for ordinary dithering toward a third,
lower-priority biome. `paint()` computes both and reconciles them
(`TerrainRenderer._corner_directions_not_covered_by_blend`) rather than
letting one silently win outright:

- A corner direction whose flanking cardinal edge is **already being
  dithered by blend** defers to blend entirely — this is the SAME
  underlying fact, not two different ones (e.g. a cell notched by the same
  lower-priority biome on two perpendicular sides is exactly what
  `dominant_blend_for`'s own multi-edge dithering already covers; carving a
  corner on top would fight it).
- A corner direction whose flanking edges are **not** already dithered
  survives and gets carved, even when blend found something real elsewhere
  on that same tile — blend, by construction, only ever selects
  strictly-lower-priority neighbors, so it could never have expressed this
  corner in the first place.

## Earth-modification blend: `earth_dominant_blend_for`

A built or worn "earth" cell (`TerrainRenderer.EARTH_TILE_ID` — player-built
floor via the Terraria-style build/destroy system, or `PathScarring`'s
worn-ground dirt path, see `src/world/path_scarring.gd`) is not a biome at
all: `Chunk.modifications` shadows the cell's real biome tile with this one
instead, on the same opaque base layer pillar 3 already establishes.
Reported live (screenshot): a grass-to-dirt-path boundary read as a hard
edge, with the corner where they met a hard square — the same two
complaints the corner-blend rounds above kept fixing for real biome pairs,
but this time for a system those rounds never touched at all
(`TerrainRenderer.paint`'s modifications branch short-circuited straight to
one dead-flat `EARTH_COLOR` square before ever consulting neighbor biomes).

`earth_dominant_blend_for` gives earth the same treatment, with one
structural difference from `dominant_blend_for`: earth has no real biome
identity of its own to compare priority against, so there is no "same
biome, stay pure" skip and no priority gate — it unconditionally concedes
to whatever real, unmodified biome cardinally borders it (ocean excluded,
same "land never blends toward ocean" rule pillar 2 already establishes).
Because every differing direction qualifies unconditionally, a shared
corner between two active directions is already handled by the same
directional-blend mask — `generate_multi_directional_blend_image_from`
dithers a shared corner between active directions on its own (see that
function's own doc comment) — so, unlike the land/ocean and land/land
cases above, no separate corner-carve family exists or is reachable for
earth; one blend family (`_earth_blend_base_linear`/`_earth_blend_linear`)
covers both the edge and the corner shape.

Two adjacent earth cells (a multi-tile worn path, or a built floor) must
not dither a seam against each other's pre-modification biome —
`_neighbor_biomes`'s `exclude_modified_neighbors` param omits an in-chunk
neighbor that itself carries a modification, rather than reporting its
shadowed original biome.

## Deliberately out of scope

- **Water/land diagonal-only corners** (e.g. the four corner-diagonal land
  cells around an isolated one-tile pond) have the same underlying gap as
  the land/land diagonal-only case above, but are not carved. The
  water-corner logic already went through four separate bug-fix rounds
  (see `docs/progress.md`); extending it further wasn't asked for and
  isn't free.
- **Symmetric diagonal-only carving.** The diagonal-only case only ever
  carves from the lower-priority side, matching pillar 2. The
  higher-priority side's own corner, looking back at the same point, never
  also carves — its real texture is already what shows through the lower
  side's carved wedge, so there is no second "hole" needing its own
  treatment.
- **Earth-modification neighbors across a chunk seam.** An earth cell's
  cardinal neighbor in an already-loaded adjacent chunk is resolved through
  `global_biome_lookup`, which has no visibility into that neighboring
  chunk's own `Chunk.modifications` — so a modified neighbor just across a
  chunk seam is (incorrectly) read as its original biome instead of being
  excluded. The same pre-existing blind spot the ordinary biome-to-biome
  blend/corner system already has at chunk seams; not attempted here, in
  scope only for the common in-chunk case `PathScarring`/building actually
  produce.

## Status

**Consolidated 2026-09-05.** A near-duplicate doc, `terrain_biome_borders.md`,
had independently accumulated the earth-modification-blend mechanism and a
more careful accounting of open gaps (both merged in above and below) that
this doc's own Status section was missing — while this doc alone had the
most recent staircase-corner fix (last bullet below), which the other doc
never received. Neither doc's own text ever mentioned the other. This one
stays canonical: `src/rendering/terrain_renderer.gd` and
`tests/unit/test_terrain_renderer.gd` already cite it by name in three
places, and it predates the other by roughly two weeks. Found and merged
during a cross-alignment pass over README/progress/roadmap vs. the real
implementation state; see `docs/progress.md`'s new Terrain Borders section
for the mechanism-by-mechanism status this doc's own history duplicated.
`terrain_biome_borders.md` now redirects here.

- ✅ Directional cardinal dithered blend, priority-ranked, water excluded —
  `dominant_blend_for`/`atlas_coords_for_directional_blend`.
- ✅ Convex + concave ocean corners, both shapes, mixed-flanking-biome
  ties broken by `BLEND_PRIORITY` — `corner_direction_for`/
  `atlas_coords_for_corner`.
- ✅ Land/land diagonal corners (reported: "diagonal blend border tiles [are
  broken] at the border of two biomes e.g. grass/forest") — a third corner
  family (`LAND_BIOMES_BY_PRIORITY`, `_land_corner_pair_ordinal`,
  `_land_land_corner_base_linear`), and `corner_direction_for`'s
  mixed-flanking-neighbor tie-break (previously gated to `biome_name ==
  "ocean"` only) generalized to every biome, closing the corner case a real
  three-biome meeting point produces. Before this, a land/land corner
  (a) fell through `_corner_linear`'s existing land-owning family, which
  ignores which non-ocean biome is actually poking in and always returns the
  SAME index as that biome's land-vs-OCEAN corner — a visibly wrong tile (an
  ocean-shaped rounded cutout on dry land) rather than merely an unblended
  hard corner, whenever `horizontal == vertical` already happened to match;
  or (b) fell through to a plain hard corner when the two flanking neighbors
  genuinely differed from each other, since that case was gated to ocean
  only.
- ✅ Corner-vs-blend reconciliation (reported again, as a follow-up, once the
  land/land family above landed: "still sharp corners at diagonal borders")
  — `paint()` used to check blend FIRST and only ever reach
  `corner_direction_for` when blend was entirely empty for the whole cell,
  so an unrelated cardinal edge toward some third, lower-priority biome
  silently stole the whole tile's treatment before a real corner on a
  completely different diagonal was ever even asked about. Measured against
  real generated chunks near Berlin: 553 of 1065 real land/land
  corner-eligible cells (52%) were starved this way before the fix, plus 20
  of 2448 real ocean corners (the same bug, present since the ocean-corner
  system shipped, just far rarer). See "When a cell qualifies for both"
  above for the reconciliation rule.
- ✅ **A staircase corner is found even when the cell also blends.** The
  diagonal-only corner check needs the cell's DIAGONAL neighbours, and
  `paint()` was gathering those only inside its no-blend fallback — passing
  the primary `corner_direction_for` call the cardinal neighbours alone. A
  staircase step almost always has a differing cardinal neighbour too, so
  it took the primary path, where the branch it needed could not fire
  because the diagonals were never handed over. The diagonal-only case
  therefore only ever worked on cells with no blend at all, which is the
  one situation a staircase does not produce — so grass/forest boundaries
  kept visible hard corners through two rounds of corner work (reported a
  third time: "the biome borders still contain hard corners"). The
  diagonals are now gathered once, before the corner call, and used by
  both paths. Verified by reverting just that one argument and watching
  the regression test go red (it paints plain grassland — a hard corner),
  then green again; and by compositing a real two-chunk region near Berlin
  through the actual `paint()` path, where forest/grass boundaries read as
  feathered and irregular rather than stepped.

  Worth recording, since it is the reason this took three passes: the
  underlying biome map was never the problem. Measured directly, 13.7% of
  horizontally adjacent tiles around Berlin change biome, and the raw map
  is visibly blobby and ragged. Every "hard corner" report has been a
  RENDERING gap at an already-organic boundary, not a blocky world.
- ✅ **Earth-modification (built floor / worn path) shared-edge AND
  shared-corner blend toward its real land-biome neighbor, one family** —
  `earth_dominant_blend_for`/`_earth_blend_linear` (reported live,
  screenshot: a grass-to-dirt-path boundary read as a hard edge, with a
  hard square corner where two worn paths met — see "Earth-modification
  blend" above).
- 🚧 Diagonal-only shared-corner carve, water/land — not addressed (see
  "Deliberately out of scope" above).
- 🚧 Earth-modification neighbor detection across a chunk seam — not
  addressed (see "Deliberately out of scope" above).
- ⬜ A visible in-game screenshot re-confirming the land/land corner and
  the earth-modification blend both read correctly at actual camera zoom
  (this environment cannot launch the game to check; verified so far only
  via baked-atlas-pixel tests, see `tests/unit/test_terrain_renderer.gd`).
