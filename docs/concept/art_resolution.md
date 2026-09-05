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
`ART_TILE_SIZE`^2 pixels each) is far too slow to pay on every launch --
**~138.7s** measured on the current checkout, where the atlas has grown to
2048x5120 px / 10,240 cells. (This section previously said ~13.5s; that
figure predates several atlas expansions and was stale.)
`TerrainAtlasCache` (`src/rendering/terrain_atlas_cache.gd`) saves the
finished atlas image to `user://` and reloads it on later boots, keyed to
`TerrainRenderer.ATLAS_VERSION` so a cache built under older generation
logic is never silently reused. Bump `ATLAS_VERSION` whenever generation
logic changes.

The `TileSet`/`TileSetAtlasSource` metadata rebuilt on top of that cached
image was described here as "cheap". **It is not**: wrapping the image in an
`ImageTexture` and calling `create_tile()` for all 10,240 atlas cells
measured **8.8s per call** -- and `EarthChunkManager._init` calls it once per
instance, which in the headless test suite means once per `before_each`
(~358 times in `test_earth_chunk_manager.gd` alone). So the built `TileSet`
is now memoized **per process** too (`TerrainRenderer._tile_set_cache`), the
same `static var _..._cache` shape the illustrated-art classes already use.

The general rule this is an instance of: **deterministic generated art is
cached at process level, keyed by everything it actually depends on.** Here
that key is `ATLAS_VERSION`, both configurable cache paths, the version
string actually on disk, and the **md5 of the cached atlas bytes** -- so
rewriting the cache file mid-run correctly forces a rebuild (the file's
modified time is not enough: it has one-second resolution and the cache
tests rewrite the same path several times inside one second). Sharing one
`TileSet` between `TileMapLayer`s is safe because nothing in this codebase
ever mutates a built one. The memo does **not** help a cold cache, which
still pays the full ~138.7s once; it costs ~42 MB of RGBA8 per distinct key
for the process lifetime.

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
- ⬜ Phase 3 (vegetation / resource nodes) -- still not a real resolution
  pass (trees still composite onto the same shared canvas,
  `ProceduralTreeSprite.SIZE`, at the same `ArtResolution.DETAIL_MULTIPLIER`
  every other entity uses -- raising that multiplier for trees alone would
  break the same "reads as chunky pixel art, not smooth" floor `Camera2D`
  zoom is already pinned against, see Phase 7 below and
  test_one_art_pixel_covers_several_screen_pixels). What DID land
  (2026-09-05, same blur report as Phase 7): `ProceduralTreeSprite.
  scale_piece` squeezing a large illustrated sheet piece down into that
  small canvas now area-averages instead of nearest-sampling one arbitrary
  source pixel per destination pixel -- real detail the source art already
  has, better represented at the SAME final resolution, not more of it.
  Alpha stays binary (never blends an opaque colour with the transparency
  around it) so this cannot reintroduce the winter-branch smearing bug
  nearest-only was originally chosen to fix. A genuine resolution increase
  -- more final pixels, not just better-chosen ones -- is still the open
  part of this phase.

  **Follow-up (2026-09-05), same day: "trees always looked crispy how are
  they now blurry ... make trees bigger".** Live-verified the two fixes
  above WERE genuinely helping (relaunched, still reported blurry), so
  investigated raising resolution properly this time -- and proved,
  precisely rather than assumed, that it is mathematically impossible
  without a real regression: `screen_pixels_per_art_pixel = SPRITE_SCALE *
  CAMERA_ZOOM.x = (1/N) * 4.0`, which needs `N <= 2` to clear the
  `test_one_art_pixel_covers_several_screen_pixels` floor (>= 2.0) AT ALL
  at the design resolution (720p) -- a TREE-SPECIFIC multiplier is exactly
  as constrained as the shared one, since both share the one `Camera2D`.
  There is no N > 2 for ANY entity, tree-specific or otherwise, that keeps
  the game's own chunky-pixel-art floor at 720p, let alone whole-number
  alignment across every target resolution too.

  So this pass instead made the tree bigger ON SCREEN at the SAME native
  resolution: `ProceduralTreeSprite.WORLD_SIZE` 20x26 -> 25x33 (25%
  bigger, `SIZE`/`SPECKLE_COUNT` follow proportionally), carrying NONE of
  the resolution trade-off above -- every resolution stays exactly as
  pixel-perfect as it already was; the existing detail just gets more
  screen area to read clearly. Deliberately more modest than the
  previously-tried-and-reverted 2x (40x56, "forests crowded and read
  worse") -- reverified directly this time (`tools/probe_forest_density
  .gd`) that a small forest cluster at the new size still shows
  individually distinguishable canopies, not an undifferentiated green
  mass. Also checked and ruled out as the dominant cause here (though not
  fully excluded for a whole scattered forest): sub-pixel sprite-position
  misalignment (`tools/probe_pixel_snap.gd`) -- trees are placed with a
  continuous per-tile jitter (`TreeRenderer._stand_position`), not on a
  clean pixel grid, but a direct snap-2d-transforms-to-pixel A/B render
  showed no visible difference for one tree at normal viewing scale.

  **A genuine native-resolution increase for trees remains impossible
  within this game's current shared camera zoom**, not merely undone --
  any future attempt needs to change the zoom/design-resolution
  relationship itself (Phase 7), not retry a tree-specific carve-out.
- ⬜ Phase 4 (creatures).
- ⬜ Phase 5 (structures).
- ⬜ Phase 6 (items / icons).
- ⬜ Phase 7 (camera/viewport/HUD re-tune) -- not this phase, but `Camera2D.
  zoom` HAS since moved anyway, three times, for reasons unrelated to this
  phase's own stated goal ("bring it back down"): 4x on the original
  resolution bump (see "4x camera zoom" in docs/progress.md), then briefly
  5.2x (2026-09-05, `Player.TARGET_TILE_SCREEN_PX` 64.0 -> 83.2) for a
  direct gameplay-framing ask ("zoom in 30% so trees become relatively
  bigger"), then back to 4.0x the same day once that move was reported
  live as visible blur -- a non-whole-multiple zoom breaks nearest-
  neighbour alignment for every SPRITE_SCALE-path entity (see docs/
  progress.md's own entry). That round trip is itself direct, lived
  evidence for Phase 3 below: the SAME blur report also traced to trees
  compositing onto a canvas far smaller than the character's own per-part
  one, a cause the zoom revert alone did nothing for -- addressed
  separately (same day) by improving how that existing small canvas gets
  filled, not by growing it (see Phase 3's own updated status). Whether
  zoom should actually come back down further given the source art detail
  now available is still genuinely unanswered.
- ✅ Illustrated ground tiles (separate track from the phases above, same
  "hand/AI-illustrated sheet replaces procedural generation where art
  exists" transition `IllustratedStoneSprite` already made for loose
  stone). `IllustratedTerrainSprite` (`src/rendering/
  illustrated_terrain_sprite.gd`) is wired into
  `TerrainRenderer._biome_frame_image` with a `has_variants()`-gated
  fallback to `ProceduralTerrainSprite`, and every LAND biome now has a
  real, registered sheet: `assets/sprites/terrain/
  {grass,forest,desert,mountain,tundra,jungle}.png`. Originally targeted as
  5x5/25-variant sheets (`docs/art/ai_sprite_prompts.md` section 3), but
  real generation only reliably held a square-cell grid at 3x3 — a 5x5
  attempt came back as uneven tall strips, not a grid at all.
  `TerrainRenderer.VARIANTS_PER_BIOME` settled at 9 to match (was briefly
  raised to 25 in anticipation of 5x5), so every baked atlas slot maps to a
  genuinely distinct illustrated tile rather than wasting slots on
  duplicates. The sheets' divider lines carry a soft glow that a strict
  near-pure-magenta chroma-key missed — `IllustratedTerrainSprite` uses a
  looser red/blue-average-above-green threshold than
  `IllustratedStoneSprite`'s, tuned specifically for these sheets. Two
  deliberate scope limits, not gaps: ocean stays procedural (illustrated
  tiles have no animation seam yet, and ocean's whole identity is the
  animated scroll), and the directional-blend/corner-carve border tiles'
  *shape* stays procedurally generated regardless of what's registered
  (illustrating that combinatorial space by hand isn't practical — see
  `IllustratedTerrainSprite`'s own doc comment) — but the *pixels* that
  shape selects between are real illustrated art on both sides, composited
  by `TerrainRenderer._blend_image`/`_corner_image`, and the boundary
  itself now curves organically and differs per baked variant instead of
  running as one straight line (`ProceduralTerrainSprite.
  blend_edge_wobble`) — see `docs/progress.md`'s illustrated-ground-tiles
  entry for the full history of both.


## Presentation: how an art pixel reaches a screen pixel

Authoring art at DETAIL_MULTIPLIER times the world size is only half the
problem. The other half is what happens between the framebuffer and the
monitor, and it is where the coarse, grainy look actually came from.

The game used `window/stretch/mode="viewport"`: everything rendered into a
1280x720 framebuffer which was then blitted to the display. At 1080p that is a
1.5x upscale, so one art pixel covered two screen pixels in some places and one
in others. Uneven pixel sizes are what "grainy" is; nearest filtering was
already on and cannot help, because the unevenness is in the blit, not the
sampling.

The mode is now **`canvas_items`**: the world and the HUD are rasterised at the
window's real resolution. Text is drawn at its true size instead of being
upscaled, which is the single most visible improvement, and sprite edges stay
hard.

### The art size is not a free parameter

Screen pixels per art pixel is `(tile_screen_px / art_tile_px) * canvas_scale`,
and it has to be a whole number at every resolution the game runs at. That
constrains how detailed the art may be, because the canvas scales between
common resolutions are not integer multiples of each other — 1080p to 1440p is
4/3. Surviving that step requires the magnification at 1080p to be divisible by
3, which at this game's framing means **32 art pixels per tile**
(`DETAIL_MULTIPLIER` 2):

| art px / tile | 720p | 1080p | 1440p | 4K |
|---|---|---|---|---|
| 32 (multiplier 2) | 2x | 3x | 4x | 6x |
| 48 (multiplier 3) | 1.33x | 2x | 2.67x | 4x |

Raising the multiplier to 3 buys finer art and gives back the uneven pixels at
720p and 1440p — the exact fault this pass removed. `DisplayScaling.is_pixel_-
perfect_for_art_size` exists so that trade is something a test states rather
than something a later change discovers in a screenshot.

Getting finer art *without* losing pixel-perfection means zooming in (fewer
tiles on screen), not adding pixels at the same framing.

### Ground texture is marks, not static

The terrain fill was independent per-pixel noise at 35% density. Measured, the
tile changed appearance at 65% of neighbouring pixel pairs — worse than a coin
flip, which is to say it was mostly high-frequency noise, and the uneven
upscale made it shimmer on top.

Ground is now built from **marks**: the roll comes from a cell a couple of
pixels across, with a smaller per-pixel contribution that frays each mark's
edge so nothing reads as painted in blocks, at a lower density so clean ground
shows between them. The per-biome features that were previously drowned in
static — dune ripples, moss, cracks — now read as the deliberate details they
were always meant to be.

Three tests hold that shape: transition rate (not static), clean-ground
fraction (not a flat slab), and odd-pixel mark edges (not upscaled blocks). A
fourth checks the texture has no *direction* to it — the first attempt drew its
cell roll from Godot's string `hash()`, which correlates across near-identical
inputs, and produced ground visibly combed along one diagonal. That is what
`PixelNoise` exists for, and it is the third time this project has been bitten
by the same hash.

## Scaling tree art keeps the pixels

Pieces of tree art are resampled NEAREST-NEIGHBOUR, so scaling can only ever
copy pixels: the result's palette is a subset of the source's, and every pixel
is opaque or absent. They were resampled with Lanczos, which blends neighbours
and therefore invents in-between colours and part-transparent edges. On a dense
summer canopy that hides; on bare winter branches — thin high-contrast strokes
on transparency — it reads as smeared, haloed twigs.

The rest of the game is nearest-neighbour pixel art and the project sets
`default_texture_filter` to nearest, so smooth resampling of the source art was
contradicting the house style everywhere else honours. Pinned as a property of
the scaler rather than by eye: any smooth filter fails "invents no new colours".
