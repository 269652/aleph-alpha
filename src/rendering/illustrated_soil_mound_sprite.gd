extends RefCounted

## Illustrated art for a farm bed's tilled soil mound, sliced from one
## AI-illustrated reference sheet -- a 3x3 grid of independent undisturbed-
## mound variants (see FarmPlotMarker, ProceduralSoilSprite's own
## "swappable for real art later" doc comment, docs/concept/wild_crops.md's
## "Soil mound" entry). Same "hand-drawn sheet -> SpriteSheetSlicer ->
## cached frames, picked per-instance by a seeded index" shape as
## IllustratedAntMoundSprite, mirrored closely since both are single-sheet,
## non-animated, round mound drawings.
##
## assets/sprites/terrain/soil_mound.png's gutters are near-BLACK and fully
## OPAQUE (alpha always 1.0), rather than chroma-keyed magenta -- the exact
## same structural quirk IllustratedTerrainSprite's "soil" entry already
## hit on the same 1254x1254 template. Measured directly off the real PNG
## with tools/_probe_soil_mound_grid.gd rather than assumed to divide
## evenly (a naive width/3 split lands mid-gutter on this sheet).

const SpriteSheetSlicer = preload("res://src/rendering/sprite_sheet_slicer.gd")
const SpriteSheetLoader = preload("res://src/rendering/sprite_sheet_loader.gd")
const PixelNoise = preload("res://src/rendering/pixel_noise.gd")
const ProceduralSoilSprite = preload("res://src/rendering/procedural_soil_sprite.gd")

const _SHEET_PATH := "res://assets/sprites/terrain/soil_mound.png"

## Row content bands measured directly off the real PNG (see this file's
## own doc comment) -- gutters sit at y~[0,39), [388,430), [775,820) and
## [1169,1254).
const _ROW_BANDS := [Vector2i(39, 388), Vector2i(430, 775), Vector2i(820, 1169)]

## How dark a pixel must be to read as gutter rather than mound content --
## measured against the sheet's own near-black divider (max channel ~0.004
## at a gutter pixel, far below any lit earth tone).
const _DARK_MAX := 0.06

## The canvas every sliced variant is normalized onto -- a mound has no
## "feet"/baseline to stand animation frames on the way a walk cycle does
## (it never moves or changes pose), so BASELINE_Y is simply the canvas
## bottom, centring each variant the same way IllustratedAntMoundSprite's
## own CANVAS_SIZE/BASELINE_Y already do.
const CANVAS_SIZE := Vector2i(96, 96)
const BASELINE_Y := 96

var _slicer := SpriteSheetSlicer.new()

static var _frames: Array[ImageTexture] = []
static var _loaded := false


## Whether there is real illustrated art for the mound. Always true today
## (the sheet is real, committed art) -- kept as an explicit gate anyway,
## the same has_X()-before-frame_for() convention every other optional
## illustrated-art seam in this codebase uses.
func has_variants() -> bool:
	return true


## One deterministically-picked variant for `seed_value` -- every mound
## with the same seed always picks the same variant, and different seeds
## spread across the sheet's full variant count via PixelNoise.range_index's
## bucket-avoidance (mirrors IllustratedAntMoundSprite.frame_for exactly).
func frame_for(seed_value: int) -> ImageTexture:
	var frames := _all_frames()
	if frames.is_empty():
		return null
	var index := PixelNoise.range_index(seed_value, 0, 0, frames.size())
	return frames[index]


func frame_count() -> int:
	return _all_frames().size()


## The scale a marker applies to a CANVAS_SIZE-authored frame so it reads at
## ProceduralSoilSprite.SOIL_WORLD_WIDTH on screen -- the same real-world
## footprint the procedural mound this replaces already uses, so swapping in
## real art never changes a bed's footprint.
func world_scale() -> float:
	return ProceduralSoilSprite.SOIL_WORLD_WIDTH / float(CANVAS_SIZE.x)


func _all_frames() -> Array[ImageTexture]:
	if not _loaded:
		_frames = _load_frames()
		_loaded = true
	return _frames


func _load_frames() -> Array[ImageTexture]:
	var image := _prepared_for_slicing(SpriteSheetLoader.load_image(_SHEET_PATH))
	var textures: Array[ImageTexture] = []
	for band in _ROW_BANDS:
		var rect: Vector2i = band
		var frames := _slicer.detect_frames(image, rect.x, rect.y)
		for frame_image in _slicer.normalize_frames(image, frames, CANVAS_SIZE, BASELINE_Y):
			textures.append(ImageTexture.create_from_image(frame_image))
	return textures


## Keys the sheet's near-black gutter out to real transparency so the
## generic alpha-based SpriteSheetSlicer (built for chroma-keyed sheets)
## can find the frames without a bespoke gutter-detection path of its own.
func _prepared_for_slicing(image: Image) -> Image:
	var prepared := image.duplicate() as Image
	if prepared.get_format() != Image.FORMAT_RGBA8:
		prepared.convert(Image.FORMAT_RGBA8)
	for y in prepared.get_height():
		for x in prepared.get_width():
			var pixel := prepared.get_pixel(x, y)
			if maxf(pixel.r, maxf(pixel.g, pixel.b)) <= _DARK_MAX:
				prepared.set_pixel(x, y, Color(0, 0, 0, 0))
	return prepared
