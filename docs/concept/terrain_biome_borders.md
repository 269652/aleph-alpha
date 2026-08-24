# Terrain Biome Borders

This doc specifies how the border between two neighboring biome tiles reads
as an organic transition rather than a hard-edged grid seam: which side of a
border carries the transition, what shape that transition takes (a dithered
fringe along a shared edge, a rounded carve at a shared corner), and how that
maps onto `TerrainRenderer`'s baked tile atlas. It documents mechanics that
were already implemented and iterated on before this doc existed (see
`docs/progress.md`'s narrative history for the blow-by-blow); this is the
settled spec, not a retrospective.

## Design pillars

1. **Real biomes composite together, not a synthesized swatch.** A border
   tile dithers or carves the two real neighboring textures against each
   other (illustrated art where registered, procedural otherwise) — never a
   flat placeholder color standing in for a biome.
2. **Exactly one side of any border carries the transition.** A denser or
   more dominant biome fringes/carves over its plainer neighbor, which stays
   a pure, unmodified tile. Both sides rendering a transition at once doubles
   the fringe into a mushy two-tile band instead of one crisp handoff.
3. **A tile-grid corner is a real geometric case, not an edge case.** Two
   biomes can meet along a shared edge (a straight run of border) or at a
   single shared corner point (no shared edge at all) — both are common,
   naturally-occurring shapes on any biome boundary that isn't perfectly
   axis-aligned, and both need their own treatment; neither degrades
   gracefully into the other.
4. **Atlas cost is paid once, not every boot.** The baked tile atlas is
   pure pixel data, fully deterministic from these rules — expensive to
   generate, trivial to cache. Growing the rule set (a new corner shape, a
   new biome) grows the one-time bake, never the steady-state boot/frame
   cost, so correctness is never traded against it.

## Biome ownership: `BLEND_PRIORITY`

Every biome has a fixed priority (`TerrainRenderer.BLEND_PRIORITY`), roughly
ordered by ground density/complexity: ocean lowest, then desert, tundra,
grassland, rainforest, forest, mountain highest. Wherever two biomes meet, the
HIGHER-priority side owns the transition and the lower-priority side stays
plain — the single rule pillar 2 above reduces to. Water is a further special
case: land never blends toward or from ocean on this dithered/carved base
layer at all (the shoreline transition belongs entirely to the separate GPU
WaterFx overlay, which reads shore distance as continuous per-pixel data
instead of swapping discrete tiles — see `water_shader.gd`).

## Shared-edge transitions: `dominant_blend_for`

When a cell's cardinal (N/S/E/W) neighbors include a lower-priority biome,
the cell dithers toward it on every edge that neighbor occupies at once (an
ordered-Bayer-dither gradient blending the two real textures, not a hard
cut) — `dominant_blend_for` picks the dominant differing neighbor (most
edges wins, ties broken by biome declaration order), and the atlas reserves
one tile per ordered biome pair × every non-empty subset of the 4 cardinal
edges (`TerrainRenderer._blend_linear`).

## Shared-corner transitions: `corner_direction_for`

A tile-grid corner is carved with a small rounded wedge (radius
`ProceduralTerrainSprite.CORNER_RADIUS_PIXELS`) showing the other biome's
real texture, replacing that wedge of the cell's own tile pixel-for-pixel —
a real change to the tile's baked silhouette, not a translucent overlay.
Three distinct shapes, each detected independently per corner:

- **Convex** — an ocean cell with land on two perpendicular cardinal sides
  (a peninsula tip narrowing the water).
- **Concave** — a land cell with ocean on two perpendicular cardinal sides
  (a bay/inlet tip narrowing the land).
- **Diagonal-only** — two LAND biomes touching only at a shared tile
  corner, with no shared cardinal edge at all (the outer corner of a
  staircase-shaped biome boundary). Detected by reading the actual DIAGONAL
  neighbor cell (`TerrainRenderer._diagonal_neighbor_biomes`) rather than
  the two cardinal neighbors flanking that corner — the convex/concave
  cases above never need this, since a real right-angle corner is fully
  described by its two cardinal flanks. One-sided like the edge case above:
  only the lower-`BLEND_PRIORITY` side carves, gated on the diagonal
  neighbor's priority being strictly higher.

A cell can qualify on more than one of its four corners simultaneously (a
single-tile spit, a lone one-tile pond) — every qualifying direction is
collected and carved together in one tile, grouped by dominant partner
biome when directions disagree.

### Atlas layout: three corner families

The corner atlas reserves three separate blocks (`TerrainRenderer._corner_linear`
routes between them):

- **Ocean-owning** (convex) — indexed by the land partner's ordinal.
- **Land-owning-toward-ocean** (concave) — indexed by the land cell's own
  ordinal (partner is always ocean, so no pair indexing is needed).
- **Land/land** — covers both the diagonal-only case above and a real
  right-angle corner between two land biomes (reachable whenever a
  cell's two cardinal flanks are the SAME higher-priority land biome, but
  that biome's own edge-blend already claimed the tile from its side).
  Genuinely pair-indexed (`_land_land_corner_linear`, mirroring
  `_blend_linear`'s own near/far pair-ordinal formula) over the full
  ordered space of land-biome pairs, not just the land cell's own ordinal —
  a corner toward forest and a corner toward desert from the same owning
  biome must land on different tiles, or one silently overwrites the other
  in the atlas.

## Earth-modification blend: `earth_dominant_blend_for`

A built or worn "earth" cell (`TerrainRenderer.EARTH_TILE_ID` -- player-built
floor via the Terraria-style build/destroy system, or `PathScarring`'s
worn-ground dirt path, see `src/world/path_scarring.gd`) is not a biome at
all: `Chunk.modifications` shadows the cell's real biome tile with this one
instead, on the same opaque base layer everything above paints onto.
Reported live (screenshot): a grass-to-dirt-path boundary read as a hard
edge, with the corner where they met a hard square -- the same two
complaints the corner-blend rounds above kept fixing for real biome pairs,
but this time for a system those rounds never touched at all
(`TerrainRenderer.paint`'s modifications branch short-circuited straight to
one dead-flat `EARTH_COLOR` square before ever consulting neighbor biomes).

`earth_dominant_blend_for` gives earth the same treatment, with one
structural difference from `dominant_blend_for`: earth has no real biome
identity of its own to compare priority against, so there is no "same
biome, stay pure" skip and no priority gate -- it unconditionally concedes
to whatever real, unmodified biome cardinally borders it (ocean excluded,
same "land never blends toward ocean" rule pillar 2 already establishes).
Because every differing direction qualifies unconditionally, a shared
corner between two active directions is already handled by the same
directional-blend mask -- `generate_multi_directional_blend_image_from`
dithers a shared corner between active directions on its own (see that
function's own doc comment) -- so, unlike the land/ocean and land/land
cases, no separate corner-carve family exists or is reachable for earth;
one blend family (`_earth_blend_base_linear`/`_earth_blend_linear`) covers
both the edge and the corner shape.

Two adjacent earth cells (a multi-tile worn path, or a built floor) must
not dither a seam against each other's pre-modification biome --
`_neighbor_biomes`'s `exclude_modified_neighbors` param omits an in-chunk
neighbor that itself carries a modification, rather than reporting its
shadowed original biome.

## Deliberately out of scope

- **Water/land diagonal-only corners** (e.g. the four corner-diagonal land
  cells around an isolated one-tile pond) have the same underlying gap as
  the land/land diagonal-only case, but are not carved. The water-corner
  logic already went through four separate bug-fix rounds (see
  `docs/progress.md`); extending it further wasn't asked for and isn't
  free.
- **Symmetric diagonal-only carving.** The diagonal-only case only ever
  carves from the lower-priority side, matching pillar 2. The higher-
  priority side's own corner, looking back at the same point, never also
  carves -- its real texture is already what shows through the lower side's
  carved wedge, so there is no second "hole" needing its own treatment.
- **Earth-modification neighbors across a chunk seam.** An earth cell's
  cardinal neighbor in an already-loaded adjacent chunk is resolved through
  `global_biome_lookup`, which has no visibility into that neighboring
  chunk's own `Chunk.modifications` -- so a modified neighbor just across a
  chunk seam is (incorrectly) read as its original biome instead of being
  excluded. The same pre-existing blind spot the ordinary biome-to-biome
  blend/corner system already has at chunk seams; not attempted here, in
  scope only for the common in-chunk case PathScarring/building actually
  produce.

## Status

- ✅ Shared-edge dithered blend, any two land biomes.
- ✅ Convex/concave shared-corner carve, land/ocean.
- ✅ Right-angle and diagonal-only shared-corner carve, land/land.
- ✅ Earth-modification (built floor / worn path) shared-edge AND
  shared-corner blend toward its real land-biome neighbor, one family.
- 🚧 Diagonal-only shared-corner carve, water/land -- not addressed.
- 🚧 Earth-modification neighbor detection across a chunk seam -- not
  addressed (see "Deliberately out of scope" above).
- ⬜ A visible in-game screenshot re-confirming the land/land corner reads
  correctly at actual camera zoom (this environment cannot launch the game
  to check; verified so far only via baked-atlas-pixel tests, see
  `tests/unit/test_terrain_renderer.gd`).
