# Art Resolution (4x pixel-detail pass)

This doc specifies the base pixel resolution every procedural art generator
draws at, and the technique used to make a resolution bump actually mean
*more visual detail* rather than the same blocky look stretched larger.

## Why this exists

`Camera2D.zoom` was initially bumped 3x → 4x to make pixel art read clearly
in a full window. That was backwards: with nearest-neighbour filtering, more
zoom means each *source* pixel covers more *screen* pixels -- bigger flat
blocks, not finer detail. Zooming in can never fix pixelation; it can only
make it worse. The only real fix is source art that has more actual pixels
of information in it.

## Design pillars

1. **Real detail, not a bigger canvas.** Multiplying a sprite's canvas size
   by 4 without changing what's painted into it is indistinguishable from
   the old art at 4x zoom -- same blocky shapes, just restated at a bigger
   size. Every generator touched by this pass must paint genuinely new
   information at the higher resolution: smoother curves (a 64px-diameter
   circle has ~4x the edge resolution of a 16px one), independent per-pixel
   texture noise (not the same noise value repeated across a 4x4 block),
   and where it's visually warranted, an added finer detail layer that
   wouldn't have been legible at the old resolution at all.
2. **World footprint and art resolution are separate axes.** This is the
   pillar the pass's first attempt got wrong, and the correction that makes
   the rest work:
   - `TerrainRenderer.TILE_SIZE` (16) is how many **world units** a tile
     occupies. Every gameplay system is built on it -- player movement and
     collision, spawn placement, chunk streaming, creature/fish positioning,
     structure proximity -- and the player's own 12-unit body is
     proportioned against it. **It must not change when art detail
     changes.** Bumping it to 64 made every tile cover 4x the world area,
     reported as "water squares are gigantic compared to the player".
   - `TerrainRenderer.ART_TILE_SIZE` (64) is how many **pixels of art** are
     painted per tile. Every generator's own `SIZE` constant matches this,
     and all atlas image/blit/region math is in these art pixels.
   - `TerrainRenderer.LAYER_SCALE` (`TILE_SIZE / ART_TILE_SIZE` = 0.25) is
     what the `TileMapLayer` nodes are scaled by, so `ART_TILE_SIZE` pixels
     of art span exactly `TILE_SIZE` world units. That single factor is the
     whole mechanism keeping the two axes independent: raise
     `ART_TILE_SIZE` for more detail, `LAYER_SCALE` compensates, the world
     is unchanged.

   Camera zoom is likewise derived, not hardcoded: `Player.CAMERA_ZOOM` =
   `TARGET_TILE_SCREEN_PX / TerrainRenderer.TILE_SIZE`, so the framing is
   stated as an intent ("a tile should read this big on screen") that
   can't silently go stale.
3. **Existing tests are (mostly) already resolution-agnostic.** The
   generator test suite already asserts against `SIZE`/`TILE_SIZE`
   symbolically and checks statistical/relational properties (average
   color, distinctness, monotonic gradients, size-vs-neighbor color
   relationships) rather than pinning literal pixel coordinates -- a
   deliberate existing strength this pass leans on rather than fights. The
   exceptions (a hand-authored generator with absolute pixel-position
   constants, e.g. a campfire's log endpoints or a furnace's brick-row
   height) get every one of those constants scaled by the same 4x factor,
   keeping their composition identical at higher fidelity.
4. **Detail additions are pinned tests, not eyeballed comments** (CLAUDE.md).
   Where a generator gains a genuinely new detail layer, that layer's
   existence is asserted by a test (e.g.
   `test_speckled_texture_has_genuine_per_pixel_detail_not_upscaled_blocks`
   in `test_procedural_terrain_sprite.gd`, which fails if a texture were
   ever reduced back to 4x4 repeated blocks), not just described in a
   comment.

## Boot performance

Painting the full atlas at 4x resolution (thousands of tiles at
`ART_TILE_SIZE`^2 pixels each) measured **~13.5s** -- far too slow to pay on
every launch. `TerrainAtlasCache` (`src/rendering/terrain_atlas_cache.gd`)
saves the finished atlas image to `user://` and reloads it on later boots,
keyed to `TerrainRenderer.ATLAS_VERSION` so a cache built under older
generation logic is never silently reused. Only the pixel painting is
cached; the `TileSet`/`TileSetAtlasSource` metadata (cheap) is rebuilt every
call. Bump `ATLAS_VERSION` whenever generation logic changes.

## Scale factor

**4x linear** on every generator's base canvas dimensions (`ART_TILE_SIZE`
64 vs the original 16px tiles, `WIDTH/HEIGHT` pairs scaled the same way,
etc.) -- matches the game's own framing of the ask ("4 times the pixels").
Feature-level constants
*within* a generator (blade height, brick row spacing, firebox bounds, log
thickness) scale by the same 4x factor by default so composition stays
identical at higher fidelity; a few are deliberately exempted where a
thin-relative-to-its-surroundings look is itself the realistic detail (e.g.
a furnace's 1px mortar lines staying 1px while brick spacing scales 4x reads
as *finer* masonry, not coarser -- scaling the mortar's width too would have
made it chunkier, the opposite of "more detail").

## Phased rollout

Every procedural generator in `src/rendering/` gets its own red-first pass
(new/updated tests, then the resolution bump + detail work), grouped by
what's visually foundational first:

1. **Ground plane** -- `TerrainRenderer`/`TILE_SIZE`, `ProceduralTerrainSprite`
   (all 7 biomes' speckle/grass/moss/dune/crack/foam detail), `ProceduralShoreDistanceSprite`
   (the water shader's data texture -- already fully `SIZE`-relative, gets a
   free resolution/smoothness bump), `ProceduralStructureSprite` (campfire/
   furnace ground tiles).
2. **Character** -- `character_view.gd`/`.tscn`, `ProceduralCharacterSprite`
   (body/head/portrait), fixing `village_renderer.gd`'s pre-existing stale
   NPC body/head sizes (already out of sync with `character_view.gd` even
   before this pass -- a real bug this pass's file-by-file audit surfaced).
3. **Vegetation / resource nodes** -- trees, grass, scrub, lichen, stone, ore.
4. **Creatures** -- animals, fish, ambient birds/butterflies, the fishing
   bobber.
5. **Structures** -- houses (3 sizes), landmarks (well/stall/gate).
6. **Items / icons** -- `ProceduralItemSprite`.
7. **Re-tune presentation** -- `Camera2D.zoom` (bring back down now that
   source art actually has 4x the pixel density -- the earlier 3x→4x zoom
   bump this doc's "Why this exists" section describes was the wrong fix and
   gets revisited here), viewport/window size, and a sanity check that HUD/UI
   element sizing (built screen-space, independent of world art) still reads
   proportionately once the world renders at higher fidelity.

`minimap_renderer.gd` and `drop_shadow.gd` are pixel-painters but not
`procedural_*` sprite generators in the usual sense (a per-tile biome-color
sample grid and a parametric per-entity-width shadow, respectively) --
`drop_shadow.gd` takes its width as a caller-supplied parameter already, so
it needs no resolution change of its own; `minimap_renderer.gd` is a
zoomed-out abstraction (one image pixel per world *tile*, not per source
sprite pixel) that isn't meant to show sprite-level detail at all, so it's
out of scope for "more detail" and only needs verifying it still reads
correct tile positions once `TILE_SIZE` changes.

## Status / mechanisms

- ✅ Phase 1 (ground plane) -- `ART_TILE_SIZE`/`LAYER_SCALE` split,
  `ProceduralTerrainSprite` at 64px (per-pixel speckle, tapered/curved grass
  blades, branching mountain cracks, larger moss/flower/stone detail),
  `ProceduralShoreDistanceSprite` at 64px, `ProceduralStructureSprite` at
  64px with every hand-placed constant scaled, plus `TerrainAtlasCache` for
  boot performance and a tile-centered player spawn fix (the corner-based
  spawn read as "the player is offset by half a tile" once tile edges got
  sharp).
- ⬜ Phase 2 (character).
- ⬜ Phase 3 (vegetation / resource nodes).
- ⬜ Phase 4 (creatures).
- ⬜ Phase 5 (structures).
- ⬜ Phase 6 (items / icons).
- ⬜ Phase 7 (camera/viewport/HUD re-tune).
