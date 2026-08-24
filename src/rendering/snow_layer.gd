extends RefCounted

## Snow as a per-tile overlay, so footprints can be carved out of it.
##
## Snow started as a tint on the whole ground layer, which cannot express
## "this tile is trodden and that one is not" -- a tint is one number for the
## entire world. Making it a layer of TILES is what lets a trail through a
## field exist at all.
##
## The layer sits above the terrain and below everything that stands on it, so
## grass and stones keep their shape under the cover: the ground is covered,
## not replaced.

const ArtResolution = preload("res://src/rendering/art_resolution.gd")
const PixelNoise = preload("res://src/rendering/pixel_noise.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")

## How many depths of cover there are, from a dusting to full.
##
## Ground goes bare, dusted, covered, deep -- rather than snapping between two
## states, which is what makes a snowfall something you watch arrive.
const DEPTH_BANDS := 4

## How white each band is, and how much of the tile it covers.
##
## The shallowest band is patchy on purpose: a dusting is snow lying in the
## dips with grass showing through, not a thin even wash.
const BAND_WHITENESS := [0.80, 0.88, 0.94, 0.99]
const BAND_COVERAGE := [0.45, 0.72, 0.92, 1.0]

## How much a fully trodden tile drops in depth.
##
## Walking PACKS snow rather than clearing it: a trail should read as tracks
## through a field, not as a trench dug to the soil. Only where the cover was
## thin to begin with does a boot reach the ground.
const TREAD_BANDS := 2.0

## ## Per-tile spread (see docs/concept/weather.md's "It fills in tile by
## tile, not the whole field at once")
##
## One lying-snow DEPTH still drives an entire snowfall (see Snowfall) -- one
## clock, one number -- but every tile reshapes that same depth by its own
## WARP exponent before banding it: `pow(depth, warp)`. Real snow does not
## accumulate evenly (a sheltered hollow or the shade under a tree line holds
## it differently than open, exposed ground), so different tiles cross into a
## deeper band at different points along the same snowfall -- reported: "snow
## still covers a percentage of a whole chunk instantly instead of gradually
## filling individual tiles".
##
## `pow` is what keeps both ends of a snowfall agreeing regardless of warp:
## `0^k == 0` and `1^k == 1` for any positive k, so bare ground (depth 0) and
## a complete snowfall (depth 1) land on the exact same band for every tile
## no matter its warp -- only the MIDDLE of a snowfall differs tile to tile.
## A warp below 1 reaches a given band at a shallower depth (an early
## starter); above 1, a deeper depth is needed first (a late one).
const WARP_MIN := 0.6
const WARP_MAX := 1.6

## How many tiles one warp "patch" spans. Real snow drifts in coherent
## patches (a hollow, a lee side), not tile-to-tile static -- see
## `tile_warp`'s own doc comment. Smaller means smaller, more scattered
## patches; this is the PERIOD in tiles (roughly 1/WARP_NOISE_SCALE), not the
## noise frequency itself, since a frequency is harder to reason about
## directly than "how many tiles wide is a patch".
const WARP_PATCH_SIZE_TILES := 7.0
const WARP_NOISE_SCALE := 1.0 / WARP_PATCH_SIZE_TILES

## Arbitrary fixed salt for the warp noise -- any constant works, it only
## needs to differ from other PixelNoise callers sharing the same coordinate
## space so their patterns don't correlate.
const WARP_NOISE_SEED := 7331


## The warp exponent this tile reshapes the field's lying-snow depth by
## before banding it -- deterministic (same tile always answers the same),
## and spatially COHERENT rather than scattered: `PixelNoise.smooth` varies
## gradually between neighbouring tiles (see `WARP_PATCH_SIZE_TILES`) so warp
## forms drifting patches rather than a tile-to-tile static pattern, which
## would read as noise rather than as snow.
static func tile_warp(tile: Vector2i) -> float:
	var noise := PixelNoise.smooth(
		WARP_NOISE_SEED, float(tile.x) * WARP_NOISE_SCALE, float(tile.y) * WARP_NOISE_SCALE
	)
	return WARP_MIN + noise * (WARP_MAX - WARP_MIN)


## The tile set: one tile per depth band.
func build_tile_set() -> TileSet:
	var art := TerrainRenderer.ART_TILE_SIZE
	var sheet := Image.create(DEPTH_BANDS * art, art, false, Image.FORMAT_RGBA8)
	for band in DEPTH_BANDS:
		sheet.blit_rect(
			build_band_image(band), Rect2i(0, 0, art, art), Vector2i(band * art, 0)
		)
	var source := TileSetAtlasSource.new()
	source.texture = ImageTexture.create_from_image(sheet)
	source.texture_region_size = Vector2i(art, art)
	for band in DEPTH_BANDS:
		source.create_tile(Vector2i(band, 0))
	var tile_set := TileSet.new()
	tile_set.tile_size = Vector2i(art, art)
	tile_set.add_source(source, 0)
	return tile_set


## One band's tile.
##
## Grainy rather than flat: a field of flat white reads as a hole in the world
## rather than as snow. The grain is the same trick the terrain sprites use --
## each pixel rolled a little lighter or darker on its own.
func build_band_image(band: int) -> Image:
	var art := TerrainRenderer.ART_TILE_SIZE
	var image := Image.create(art, art, false, Image.FORMAT_RGBA8)
	var clamped := clampi(band, 0, DEPTH_BANDS - 1)
	var whiteness: float = BAND_WHITENESS[clamped]
	var coverage: float = BAND_COVERAGE[clamped]
	for y in art:
		for x in art:
			# Patchy at the shallow end: a dusting lies in the dips with grass
			# showing through, rather than as a thin even wash.
			var lies := float(PixelNoise.range_index(x * 131 + y, 233 + clamped, 0, 1000)) / 1000.0
			if lies > coverage:
				continue
			var grain := float(PixelNoise.range_index(x * 917 + y, 239, 0, 100)) / 100.0
			var shade := clampf(whiteness - 0.06 + grain * 0.08, 0.0, 1.0)
			# Faintly blue, because snow in daylight is, and a flat grey wash
			# reads as fog rather than as ground.
			image.set_pixel(x, y, Color(shade, shade, minf(shade + 0.03, 1.0), 1.0))
	return image


## Which band a tile shows, or -1 for bare ground.
##
## `depth` is how much snow is lying (see Snowfall) and `tread` how much has
## been displaced by walking (see SnowTrail). `warp` is this tile's own
## reshaping of `depth` before banding (see `tile_warp`'s own doc comment) --
## defaults to 1.0, an identity power that reproduces the plain global
## banding exactly, so every existing two-argument call site (and the field's
## own bare/fully-covered extremes, at any warp) is unaffected.
func band_for(depth: float, tread: float, warp: float = 1.0) -> int:
	var lying := clampf(depth, 0.0, 1.0)
	if lying <= 0.0:
		return -1
	var warped: float = pow(lying, warp)
	# Depth maps onto the bands, then treading knocks it down.
	var band := int(ceil(warped * float(DEPTH_BANDS))) - 1
	band -= int(round(clampf(tread, 0.0, 1.0) * TREAD_BANDS))
	return clampi(band, -1, DEPTH_BANDS - 1)
