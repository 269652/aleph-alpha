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

## How white each band is, how much of the tile it covers, and how OPAQUE it
## is.
##
## The shallowest band is patchy on purpose: a dusting is snow lying in the
## dips with grass showing through, not a thin even wash.
##
## ALPHA is what makes that true. The bands used to be fully opaque, so a
## 45%-coverage band was 45% of the tile switched hard to near-white and 55%
## punched out -- a 50/50 dither of near-white at the finest grain the atlas
## can express, reported as "~50% pure-white 1px noise, reads as texture
## corruption". A thin cover is tinted TOWARD THE GROUND, and letting the
## ground composite through is the only way this layer can do that: SnowLayer
## bakes ONE tile set for every biome (grassland, desert, tundra, forest
## floor), so it has no ground colour of its own to blend with -- the
## compositor has.
##
## Measured, not eyeballed: mean alpha per band comes out 0.28 / 0.53 / 0.82
## / 1.00 and mean whiteness*alpha 0.22 / 0.46 / 0.75 / 0.97, still strictly
## increasing (see test_deeper_snow_is_whiter). Pinned by
## DUSTING_MAX_MEAN_ALPHA and FULL_COVER_MIN_MEAN_ALPHA.
const BAND_WHITENESS := [0.80, 0.88, 0.94, 0.99]
const BAND_COVERAGE := [0.62, 0.82, 0.96, 1.0]
const BAND_ALPHA := [0.45, 0.65, 0.85, 1.0]

## A dusting must let its ground through; full cover must not.
const DUSTING_MAX_MEAN_ALPHA := 0.35
const FULL_COVER_MIN_MEAN_ALPHA := 0.99

## Snow grain is rolled in blocks this many ART pixels across.
##
## ART_TILE_SIZE is TILE_SIZE * ArtResolution.DETAIL_MULTIPLIER, so one art
## pixel is half a WORLD pixel. A shade nudge may legitimately be that fine
## (art_resolution.md's 1px mortar lines), but COVERAGE is not a nudge -- it
## is a hard present/absent mask, and a hard mask rolled below the world
## pixel grid is a dither rather than texture. One world pixel is the floor:
## the same "chunky enough to read as pixel art rather than a hairline
## scratch" rule RainOverlay.STREAK_WIDTH already states.
const GRAIN_BLOCK := ArtResolution.DETAIL_MULTIPLIER

## How much a fully trodden tile drops in depth.
##
## Walking PACKS snow rather than clearing it: a trail should read as tracks
## through a field, not as a trench dug to the soil. Only where the cover was
## thin to begin with does a boot reach the ground.
const TREAD_BANDS := 2.0

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
	var alpha: float = BAND_ALPHA[clamped]
	for y in art:
		for x in art:
			# Rolled per BLOCK, not per art pixel, so the smallest snow mark is
			# never finer than one world pixel (see GRAIN_BLOCK) -- a hard mask
			# below that grid is a dither, i.e. static.
			var block_x := x / GRAIN_BLOCK
			var block_y := y / GRAIN_BLOCK
			# Patchy at the shallow end: a dusting lies in the dips with grass
			# showing through, rather than as a thin even wash.
			var lies := (
				float(PixelNoise.range_index(block_x * 131 + block_y, 233 + clamped, 0, 1000))
				/ 1000.0
			)
			if lies > coverage:
				continue
			var grain := (
				float(PixelNoise.range_index(block_x * 917 + block_y, 239, 0, 100)) / 100.0
			)
			var shade := clampf(whiteness - 0.06 + grain * 0.08, 0.0, 1.0)
			# Faintly blue, because snow in daylight is, and a flat grey wash
			# reads as fog rather than as ground. Translucent at the shallow
			# end so the ground TINTS through rather than being punched out
			# (see BAND_ALPHA).
			image.set_pixel(x, y, Color(shade, shade, minf(shade + 0.03, 1.0), alpha))
	return image


## How far a tile's own snow onset can lead or lag the field's overall
## coverage, so a chunk fills in as a visible spread rather than every tile
## crossing the same threshold in the same instant.
##
## Every tile used to read the exact same `depth` (see EarthChunkManager's
## single shared `_snow_depth`), so the moment that one number ticked past a
## band boundary the WHOLE loaded field flipped together -- reported as "snow
## covers a whole chunk instantly instead of spreading progressively". This is
## the same seeded-per-cell-jitter idea TallGrass/FlowerPatch already use so a
## uniform process doesn't read as synchronized (see PixelNoise's own doc
## comment: this project has hit that "same value everywhere" clustering bug
## five times already), just applied to WHEN a tile catches on rather than
## WHERE something is placed.
##
## Bounded well under one full depth band (0.25 at DEPTH_BANDS=4): wide enough
## that a partial snowfall genuinely mixes bare and covered tiles instead of
## everyone crossing together, narrow enough that full cover (depth 1.0) still
## reaches the deepest band even for the most-lagging tile, and bare ground
## (depth 0.0) still shows nothing even for the most-leading one.
const ONSET_VARIANCE := 0.18
const _ONSET_SALT := 5303

## How many TILES one lift of the drift field spans.
##
## This offset used to be rolled per tile with PixelNoise.range_value --
## white noise, so two touching tiles could land 2 * ONSET_VARIANCE apart
## (measured: 0.3582) which is MORE than one whole depth band (1.0 /
## DEPTH_BANDS = 0.25). Snow then rendered as a checkerboard of bare /
## dusted / covered SQUARES with a razor edge on the tile grid, reported as
## texture corruption rather than as snow: the tile is the smallest thing
## band_for can speak about, so the noise driving it has to be much COARSER
## than a tile, not finer.
##
## Snow drifts and shelters in patches many metres across -- a hollow, a lee
## side, the shade of a tree line -- so the field deciding which ground
## catches first is low-frequency by construction: neighbours nearly
## identical, only tens of tiles apart fully different. Same PixelNoise
## everything else draws with, just its `smooth` form rather than its
## per-cell scatter (see PixelNoise's own doc comment).
##
## Measured, not eyeballed: 12 tiles gives a max neighbour step of 0.0436
## while the field still spans the whole +/-ONSET_VARIANCE range. Pinned
## from both sides -- MAX_NEIGHBOUR_ONSET_STEP says it is coarse enough,
## test_the_drift_field_still_covers_the_ground_unevenly says it has not
## been flattened into a constant.
const ONSET_DRIFT_TILES := 12.0

## The most two edge-adjacent tiles' onsets may differ.
##
## A quarter of a depth band, so a band boundary takes at least four tiles to
## cross: the snow LINE meanders through the field instead of snapping from
## square to square, and two neighbours can never be a whole band apart.
const MAX_NEIGHBOUR_ONSET_STEP := 0.25 / float(DEPTH_BANDS)


## This tile's own onset offset, in [-ONSET_VARIANCE, ONSET_VARIANCE] --
## seeded from its GLOBAL tile coordinates (not chunk-local, so the pattern
## doesn't repeat or seam at chunk boundaries) via PixelNoise rather than
## Godot's own `hash()`, which correlates neighbouring inputs (see
## PixelNoise's doc comment).
##
## Sampled from a SMOOTH field at ONSET_DRIFT_TILES tiles per lift rather
## than rolled per tile, so the bare/dusted boundary reads as a meandering
## snow line rather than as grid squares (see ONSET_DRIFT_TILES).
func onset_offset_for(global_x: int, global_y: int) -> float:
	var drift := PixelNoise.smooth(
		_ONSET_SALT,
		float(global_x) / ONSET_DRIFT_TILES,
		float(global_y) / ONSET_DRIFT_TILES
	)
	return lerpf(-ONSET_VARIANCE, ONSET_VARIANCE, drift)


## Which band a tile shows, or -1 for bare ground.
##
## `depth` is how much snow is lying overall (see Snowfall), `tread` how much
## has been displaced by walking (see SnowTrail), and `onset_offset` this
## tile's own lead/lag on the field's coverage (see onset_offset_for) -- it is
## what turns one shared depth into a chunk that fills in tile by tile rather
## than snapping everywhere at once.
func band_for(depth: float, tread: float, onset_offset: float = 0.0) -> int:
	# A genuinely bare field (no snow has fallen ANYWHERE) stays bare even for
	# the most-leading tile -- onset is a lead/lag on real snow, not a way to
	# conjure some out of nothing.
	if depth <= 0.0:
		return -1
	var lying := clampf(depth + onset_offset, 0.0, 1.0)
	if lying <= 0.0:
		return -1
	# Depth maps onto the bands, then treading knocks it down.
	var band := int(ceil(lying * float(DEPTH_BANDS))) - 1
	band -= int(round(clampf(tread, 0.0, 1.0) * TREAD_BANDS))
	return clampi(band, -1, DEPTH_BANDS - 1)
