extends RefCounted

## Illustrated ant-mound art, sliced from one AI-illustrated reference
## sheet -- a 3x3 grid of independent, differently-detailed mound-with-
## entrance drawings, NOT an animation (see AntMoundMarker, docs/concept/
## soil_fauna.md). Same "hand-drawn sheet -> SpriteSheetSlicer -> cached
## frames, picked per-instance by a seeded index" shape as
## IllustratedStoneSprite's pebble/boulder/cobble pools, scoped to this one
## sheet since there is only one mound "class" (unlike stones' several
## distinct size tiers).

const SpriteSheetSlicer = preload("res://src/rendering/sprite_sheet_slicer.gd")
const SpriteSheetLoader = preload("res://src/rendering/sprite_sheet_loader.gd")
const PixelNoise = preload("res://src/rendering/pixel_noise.gd")
const ProceduralAntMoundSprite = preload("res://src/rendering/procedural_ant_mound_sprite.gd")

const _SHEET_PATH := "res://assets/sprites/animals/ant_mound.png"

## Three content rows, three columns each -- measured directly from the
## real PNG the same way as IllustratedDecomposerSprite's bands (a divider
## band reads as near-uniform chroma-key magenta across the full width).
const _ROW_BANDS := [Vector2i(59, 344), Vector2i(445, 745), Vector2i(833, 1147)]

## Chroma-keyed magenta, fully OPAQUE (alpha channel present but always
## 1.0) -- same convention and same despill technique as
## IllustratedDecomposerSprite/IllustratedStoneSprite, reused rather than
## reinvented; see either class's own doc comment for why a binary key
## alone leaves a visible pink halo around an antialiased edge.
const _MAGENTA_RED_MIN := 0.85
const _MAGENTA_BLUE_MIN := 0.85
const _MAGENTA_GREEN_MAX := 0.15
const _MAGENTA_CAST_MARGIN := 0.03
const _ALPHA_THRESHOLD := 0.3

## The canvas every sliced variant is normalized onto -- a mound has no
## "feet"/baseline to stand animation frames on the way a walk cycle does
## (it never moves or changes pose), so BASELINE_Y is simply the canvas
## bottom, centring each variant the same way ProceduralAntMoundSprite's
## own circular silhouette is naturally centred in ITS canvas.
const CANVAS_SIZE := Vector2i(96, 96)
const BASELINE_Y := 96

var _slicer := SpriteSheetSlicer.new()

static var _frames: Array[ImageTexture] = []
static var _loaded := false
static var _marker_scale_cache := -1.0


## Whether there is real illustrated art for the mound. Always true today
## (the sheet is real, committed art) -- kept as an explicit gate anyway,
## the same has_X()-before-frame_for() convention every other optional
## illustrated-art seam in this codebase uses, so a caller that already
## codes defensively against "no art yet" needs no special-casing here.
func has_variants() -> bool:
	return true


## One deterministically-picked variant for `seed_value`, or null if
## has_variants() is false. Every mound with the same seed always picks the
## same variant, and different seeds spread across the sheet's full
## variant count via PixelNoise.range_index's bucket-avoidance -- the same
## determinism/spread guarantee every other seeded index pick in this
## codebase relies on (mirrors IllustratedStoneSprite.frame_for exactly).
func frame_for(seed_value: int) -> ImageTexture:
	var frames := _all_frames()
	if frames.is_empty():
		return null
	var index := PixelNoise.range_index(seed_value, 0, 0, frames.size())
	return frames[index]


func frame_count() -> int:
	return _all_frames().size()


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
		var frames := _slicer.detect_frames(image, rect.x, rect.y, 60, 1, _ALPHA_THRESHOLD)
		for frame_image in _slicer.normalize_frames(
			image, frames, CANVAS_SIZE, BASELINE_Y, _ALPHA_THRESHOLD
		):
			_despill_image(frame_image)
			textures.append(ImageTexture.create_from_image(frame_image))
	return textures


## How much to scale a CANVAS_SIZE-normalized frame so it reads at
## ProceduralAntMoundSprite.MOUND_WORLD_WIDTH on screen -- the same real-
## world width the procedural fallback already uses, measured from the
## real art's own opaque width rather than assumed to match the canvas
## proportions (mirrors IllustratedAnimalSprite/IllustratedDecomposerSprite
## marker_scale). Cached: every mound shares one sheet, so this never
## changes once computed.
func marker_scale() -> float:
	if _marker_scale_cache > 0.0:
		return _marker_scale_cache
	var frames := _all_frames()
	if frames.is_empty():
		return 1.0
	var image: Image = frames[0].get_image()
	var min_x := image.get_width()
	var max_x := -1
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a > 0.0:
				min_x = mini(min_x, x)
				max_x = maxi(max_x, x)
	var reference_width := float(max_x - min_x + 1) if max_x >= min_x else float(CANVAS_SIZE.x)
	_marker_scale_cache = ProceduralAntMoundSprite.MOUND_WORLD_WIDTH / reference_width
	return _marker_scale_cache


func _prepared_for_slicing(image: Image) -> Image:
	var prepared := image.duplicate() as Image
	if prepared.get_format() != Image.FORMAT_RGBA8:
		prepared.convert(Image.FORMAT_RGBA8)
	for y in prepared.get_height():
		for x in prepared.get_width():
			var pixel := prepared.get_pixel(x, y)
			if _is_magenta(pixel):
				prepared.set_pixel(x, y, Color(pixel.r, pixel.g, pixel.b, 0.0))
			else:
				prepared.set_pixel(x, y, _despilled(pixel))
	return prepared


func _despill_image(image: Image) -> void:
	for y in image.get_height():
		for x in image.get_width():
			var pixel := image.get_pixel(x, y)
			if _is_magenta(pixel):
				image.set_pixel(x, y, Color(0, 0, 0, 0))
			else:
				image.set_pixel(x, y, _despilled(pixel))


static func _is_magenta(color: Color) -> bool:
	return color.r >= _MAGENTA_RED_MIN and color.b >= _MAGENTA_BLUE_MIN and color.g <= _MAGENTA_GREEN_MAX


static func _despilled(color: Color) -> Color:
	var cast: float = minf(color.r - color.g, color.b - color.g)
	if cast <= _MAGENTA_CAST_MARGIN:
		return color
	var removed := cast - _MAGENTA_CAST_MARGIN
	return Color(
		clampf(color.r - removed, 0.0, 1.0), color.g,
		clampf(color.b - removed, 0.0, 1.0), color.a
	)
