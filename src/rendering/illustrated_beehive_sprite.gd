extends RefCounted

## Real illustrated beehive art, sliced from the one user-supplied
## reference sheet (assets/sprites/beehive.png, 2048x768 -- 8 columns x
## 3 rows of 256x256 cells, a perfectly regular grid: 2048/8=256,
## 768/3=256 exactly). Sliced with the KNOWN FIXED GRID directly --
## mirrors tools/probe_worm_sheet.gd's own established precedent for an
## equally regular sheet, NOT SpriteSheetSlicer.detect_frames' own
## column-gap heuristic: tools/probe_beehive_sheet.gd confirms
## detect_frames misreads row 0 (honeycomb) and row 2 (debris) as 10/11
## "frames" instead of the real 8, tripped up by internal content gaps
## in the artwork, the exact same failure mode already documented for
## worm.png's own coiled poses.
##
## Rows 0-1 (16 frames total) are a genuine SIZE/GROWTH progression -- a
## young, exposed comb building up through a fully wax-sealed mature
## hive -- not cosmetic variants the way IllustratedAntMoundSprite's 3x3
## grid is. This follows IllustratedCropSprite.growth_stage_index's own
## "map a continuous fraction onto a discrete frame index" convention
## instead of IllustratedAntMoundSprite's continuous-rescale-one-fixed-
## frame one: the art itself, not an arbitrary technique choice, decides
## which precedent applies (see docs/concept/bees.md).
##
## Row 2 (8 frames) is the harvest/destruction sequence (see bees.md's
## "Harvesting honey"), selected by real harvest-hit count, never by
## growth fraction -- an entirely separate pool from the growth frames,
## not two more growth stages.

const SpriteSheetSlicer = preload("res://src/rendering/sprite_sheet_slicer.gd")
const SpriteSheetLoader = preload("res://src/rendering/sprite_sheet_loader.gd")
const ProceduralBeehiveSprite = preload("res://src/rendering/procedural_beehive_sprite.gd")

const _SHEET_PATH := "res://assets/sprites/beehive.png"

const _COLUMNS := 8
const _CELL_SIZE := Vector2i(256, 256)
const _GROWTH_ROWS := [0, 1]
const _HARVEST_ROW := 2

## Chroma-keyed magenta, fully OPAQUE (alpha channel present but always
## 1.0) -- measured directly (tools/probe_beehive_sheet.gd) at roughly
## (0.955, 0.03, 0.96); same convention and same despill technique as
## IllustratedAntMoundSprite/IllustratedDecomposerSprite/
## IllustratedStoneSprite, reused rather than reinvented.
const _MAGENTA_RED_MIN := 0.85
const _MAGENTA_BLUE_MIN := 0.85
const _MAGENTA_GREEN_MAX := 0.15
const _MAGENTA_CAST_MARGIN := 0.03
const _ALPHA_THRESHOLD := 0.3

## Every cell's real content already touches all four of its own 256x256
## edges (the branch element runs edge-to-edge per row -- see
## tools/probe_beehive_sheet.gd's own FINDINGS), so normalize_frames'
## tight-bbox crop is a structural no-op on the current art; a straight
## 1:1 canvas keeps maximum fidelity from the source rather than an
## arbitrary downscale.
const CANVAS_SIZE := Vector2i(256, 256)
## A hanging hive has no feet/baseline the way a walk cycle does, and
## (unlike IllustratedAntMoundSprite's ground mound) no meaningful
## "stands on this line" concept either -- it hangs from a branch at the
## TOP. Canvas bottom is used anyway, mirroring the mound's own "no real
## baseline, pick one and stay consistent" choice: since content already
## fills every frame edge-to-edge, the specific choice has no visible
## effect today.
const BASELINE_Y := 256

var _slicer := SpriteSheetSlicer.new()

static var _growth_frames: Array[ImageTexture] = []
static var _harvest_frames: Array[ImageTexture] = []
static var _loaded := false
static var _reference_width_cache := -1.0


func has_variants() -> bool:
	return true


func growth_frame_count() -> int:
	return _all_growth_frames().size()


func harvest_frame_count() -> int:
	return _all_harvest_frames().size()


## `stage_index` clamps to the real range rather than erroring -- the
## same "clamp, don't trust" contract IllustratedCropSprite.leaf_texture
## already has for its own stage_index.
func growth_texture(stage_index: int) -> ImageTexture:
	var frames := _all_growth_frames()
	if frames.is_empty():
		return null
	return frames[clampi(stage_index, 0, frames.size() - 1)]


func harvest_texture(hit_index: int) -> ImageTexture:
	var frames := _all_harvest_frames()
	if frames.is_empty():
		return null
	return frames[clampi(hit_index, 0, frames.size() - 1)]


## Maps BeeColony.growth_fraction_at's continuous [0, 1] onto a discrete
## growth_texture index -- directly proportional across all 16 real
## steps (unlike IllustratedCropSprite's 3 NAMED stage thresholds, 16
## real drawn steps needs no individually-named breakpoints, just an
## even split). Clamped, the same "out-of-range input, not out-of-range
## behaviour" contract every growth-fraction consumer in this codebase
## already has.
static func growth_stage_index(growth: float) -> int:
	const FRAME_COUNT := 16
	return clampi(int(clampf(growth, 0.0, 1.0) * float(FRAME_COUNT)), 0, FRAME_COUNT - 1)


## Maps a real harvest-hit COUNT (1-indexed: how many hits have actually
## landed so far, since 0 landed means harvesting hasn't started at all)
## onto a discrete harvest_texture index -- pinned 1:1 against row 2's
## own 8 real frames (see bees.md's "Harvesting honey":
## HARVEST_HITS_TO_DESTROY is defined AGAINST this exact frame count, not
## the other way around). The first landed hit shows the first,
## barely-damaged frame; the final hit shows the last, nearly-gone one.
static func harvest_frame_index(hits_landed: int) -> int:
	const FRAME_COUNT := 8
	return clampi(hits_landed - 1, 0, FRAME_COUNT - 1)


func marker_scale(growth_fraction: float) -> float:
	var reference_width := _reference_width()
	if reference_width <= 0.0:
		return 1.0
	return ProceduralBeehiveSprite.world_width_for(growth_fraction) / reference_width


func _all_growth_frames() -> Array[ImageTexture]:
	_ensure_loaded()
	return _growth_frames


func _all_harvest_frames() -> Array[ImageTexture]:
	_ensure_loaded()
	return _harvest_frames


func _ensure_loaded() -> void:
	if _loaded:
		return
	var image := _prepared_for_slicing(SpriteSheetLoader.load_image(_SHEET_PATH))
	_growth_frames = []
	for row in _GROWTH_ROWS:
		_growth_frames.append_array(_slice_row(image, row))
	_harvest_frames = _slice_row(image, _HARVEST_ROW)
	_loaded = true


## Slices one row's 8 KNOWN fixed 256x256 cells directly (see this file's
## own header doc comment for why, not SpriteSheetSlicer.detect_frames)
## -- mirrors tools/probe_worm_sheet.gd's precedent of handing
## normalize_frames the outer rects directly, which still finds each
## frame's own real content bbox regardless of where the outer rect came
## from.
func _slice_row(image: Image, row: int) -> Array[ImageTexture]:
	var cells: Array[Rect2i] = []
	for col in _COLUMNS:
		cells.append(Rect2i(col * _CELL_SIZE.x, row * _CELL_SIZE.y, _CELL_SIZE.x, _CELL_SIZE.y))
	var textures: Array[ImageTexture] = []
	for frame_image in _slicer.normalize_frames(image, cells, CANVAS_SIZE, BASELINE_Y, _ALPHA_THRESHOLD):
		_despill_image(frame_image)
		textures.append(ImageTexture.create_from_image(frame_image))
	return textures


## The reference frame's own real opaque width, in the same technique
## IllustratedAntMoundSprite._reference_width uses -- measured once
## (every hive shares one sheet, so this never changes) from the
## smallest growth frame, the same "measure the real pixels" precedent
## IllustratedCropSprite.max_content_extent also established
## independently for crops.
func _reference_width() -> float:
	if _reference_width_cache > 0.0:
		return _reference_width_cache
	var frames := _all_growth_frames()
	if frames.is_empty():
		return 0.0
	var image: Image = frames[0].get_image()
	var min_x := image.get_width()
	var max_x := -1
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a > 0.0:
				min_x = mini(min_x, x)
				max_x = maxi(max_x, x)
	_reference_width_cache = float(max_x - min_x + 1) if max_x >= min_x else float(CANVAS_SIZE.x)
	return _reference_width_cache


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
