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


## This tile's own onset offset, in [-ONSET_VARIANCE, ONSET_VARIANCE] --
## seeded from its GLOBAL tile coordinates (not chunk-local, so the pattern
## doesn't repeat or seam at chunk boundaries) via PixelNoise rather than
## Godot's own `hash()`, which correlates neighbouring inputs (see
## PixelNoise's doc comment).
func onset_offset_for(global_x: int, global_y: int) -> float:
	return PixelNoise.range_value(_ONSET_SALT, global_x, global_y, -ONSET_VARIANCE, ONSET_VARIANCE)


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
