extends RefCounted

## Real AI-illustrated wild-crop art (carrot, potato -- see
## docs/art/ai_sprite_prompts.md section 2, docs/concept/wild_crops.md):
## slices each crop's leaves sheet (3 growth-stage frames) and root/tuber
## sheet (several color variants, the actual harvested object) into
## ready-to-use textures. Cut out on solid magenta with near-white divider
## lines between cells -- the exact same recipe IllustratedAnimalSprite's
## sheep entry already established (chroma-key first, then the ordinary
## SpriteSheetSlicer divider-line detection).

const SpriteSheetSlicer = preload("res://src/rendering/sprite_sheet_slicer.gd")
const ProceduralItemSprite = preload("res://src/rendering/procedural_item_sprite.gd")

const _SHEETS := {
	"carrot": {
		"leaves_path": "res://assets/sprites/plants/carrot_leaves.png",
		"root_path": "res://assets/sprites/plants/carrot.png",
	},
	"potato": {
		"leaves_path": "res://assets/sprites/plants/potato_leaves.png",
		"root_path": "res://assets/sprites/plants/potato.png",
	},
}

## Measured background: flat magenta (#FF00FF), per the shared style
## preamble every sheet in ai_sprite_prompts.md follows.
const CHROMA_KEY := Color(1.0, 0.0, 1.0)
const CHROMA_KEY_TOLERANCE := 0.25

## Small canvases -- a wild crop patch reads at grass-tuft/flower scale, not
## creature scale, so there's no need for IllustratedAnimalSprite's much
## larger walk-cycle canvas. One scale is shared across a whole band (see
## SpriteSheetSlicer.normalize_frames), so the 3 leaf stages keep their
## real relative growth sizes instead of all filling the canvas equally.
const LEAF_CANVAS_SIZE := Vector2i(64, 96)
const LEAF_BASELINE_Y := 90
const ROOT_CANVAS_SIZE := Vector2i(40, 56)
const ROOT_BASELINE_Y := 52

## How big a pulled root/mature leaf cluster should read ON THE GROUND, in
## world pixels -- comparable to the existing dropped-fruit family
## (ProceduralItemSprite.WORLD_WIDTH_BY_ID), never tile-sized. That exact
## "gigantic" bug already happened once for tree fruit (see that file's own
## doc comment); a first WIDTH-only pass at this constant repeated it,
## TWICE, reported live as "huge potato crops above soil" even after a
## re-tune -- LEAF_CANVAS_SIZE/ROOT_CANVAS_SIZE are portrait (taller than
## wide, to fit the source art's own elongated proportions), so sizing off
## canvas WIDTH alone left the real on-screen HEIGHT of a portrait-shaped
## plant nowhere close to constrained. Fixed by measuring the ACTUAL drawn
## content extent (see max_content_extent/leaf_world_scale/root_world_scale
## below) and scaling THAT to this target, in whichever dimension (width or
## height) is larger -- the same "measure the real pixels, don't assume the
## canvas" precedent IllustratedAnimalSprite.marker_scale already
## established for creature art. Sized at APPLE_WORLD_WIDTH -- the biggest
## thing in the existing dropped-fruit family -- since a harvested root or
## a small plant is a similar order of magnitude to a piece of fruit, not
## categorically bigger.
const LEAF_WORLD_SIZE := ProceduralItemSprite.WALNUT_WORLD_WIDTH * 2.0  # == APPLE_WORLD_WIDTH
const ROOT_WORLD_SIZE := LEAF_WORLD_SIZE

var _slicer := SpriteSheetSlicer.new()

## Shared across every instance (see IllustratedAnimalSprite._frame_cache's
## own doc comment: the underlying art never changes, so re-slicing per
## caller would be pure waste). "crop_id" -> Array[ImageTexture].
static var _leaf_frame_cache: Dictionary = {}
static var _root_frame_cache: Dictionary = {}
## "crop_id" -> float, memoized the same reason IllustratedAnimalSprite.
## marker_scale caches: computing it scans every frame's own pixels.
static var _leaf_world_scale_cache: Dictionary = {}
static var _root_world_scale_cache: Dictionary = {}


func has_crop(crop_id: String) -> bool:
	return _SHEETS.has(crop_id)


## The leaf texture for `crop_id` at growth-stage `stage_index` (0 seedling,
## 1 vegetative, 2 mature -- see growth_stage_index). Null for an
## unregistered crop; an out-of-range stage clamps to the nearest real one
## rather than erroring.
func leaf_texture(crop_id: String, stage_index: int) -> Texture2D:
	var frames := _leaf_frames(crop_id)
	if frames.is_empty():
		return null
	return frames[clampi(stage_index, 0, frames.size() - 1)]


## One of `crop_id`'s root/tuber color variants, picked deterministically
## from `seed_value` -- the same "seed picks a variant" idiom
## IllustratedStoneSprite's pebble/boulder frame_for already uses. Null for
## an unregistered crop.
func root_texture(crop_id: String, seed_value: int) -> Texture2D:
	var frames := _root_frames(crop_id)
	if frames.is_empty():
		return null
	return frames[posmod(seed_value, frames.size())]


## The scale factor a marker applies to `crop_id`'s leaf sprites so that
## the LARGEST growth stage's own real drawn extent (see max_content_extent)
## -- not the nominal canvas size -- reads at LEAF_WORLD_SIZE on screen.
## Since every stage shares one normalize_frames scale (see LEAF_CANVAS_SIZE's
## own doc comment), a smaller stage's real extent is proportionally
## smaller too, so nothing ever exceeds the target.
func leaf_world_scale(crop_id: String) -> float:
	if not _leaf_world_scale_cache.has(crop_id):
		_leaf_world_scale_cache[crop_id] = _world_scale_for(_leaf_frames(crop_id), LEAF_WORLD_SIZE)
	return _leaf_world_scale_cache[crop_id]


## The scale factor a marker applies to `crop_id`'s root sprites so that
## the LARGEST variant's own real drawn extent reads at ROOT_WORLD_SIZE.
func root_world_scale(crop_id: String) -> float:
	if not _root_world_scale_cache.has(crop_id):
		_root_world_scale_cache[crop_id] = _world_scale_for(_root_frames(crop_id), ROOT_WORLD_SIZE)
	return _root_world_scale_cache[crop_id]


func _world_scale_for(frames: Array, target_size: float) -> float:
	var widest := 0.0
	for texture in frames:
		widest = maxf(widest, max_content_extent(texture))
	return target_size / maxf(widest, 1.0)


## The largest opaque-pixel dimension (width or height) actually drawn in
## `texture` -- the real footprint, not the canvas it was normalized onto,
## which can carry significant padding on one axis when the source art's
## aspect ratio doesn't match the canvas (see LEAF_WORLD_SIZE's own doc
## comment for the live-reported bug this fixes). Public so callers/tests
## can verify a scaled sprite's actual on-screen size, not just its nominal
## canvas size.
static func max_content_extent(texture: Texture2D) -> float:
	if texture == null:
		return 0.0
	var image := texture.get_image()
	var min_x := image.get_width()
	var max_x := -1
	var min_y := image.get_height()
	var max_y := -1
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a > 0.01:
				min_x = mini(min_x, x)
				max_x = maxi(max_x, x)
				min_y = mini(min_y, y)
				max_y = maxi(max_y, y)
	if max_x < 0:
		return 0.0
	return maxf(float(max_x - min_x + 1), float(max_y - min_y + 1))


## Maps WildCropPatch's continuous 0..1 growth onto a discrete stage index
## for leaf_texture -- see docs/concept/wild_crops.md's "Growth stages ->
## art" section for the exact thresholds.
static func growth_stage_index(growth: float) -> int:
	if growth >= 1.0:
		return 2
	if growth >= 1.0 / 3.0:
		return 1
	return 0


func _leaf_frames(crop_id: String) -> Array:
	if not _SHEETS.has(crop_id):
		return []
	if not _leaf_frame_cache.has(crop_id):
		_leaf_frame_cache[crop_id] = _slice(
			_SHEETS[crop_id]["leaves_path"], LEAF_CANVAS_SIZE, LEAF_BASELINE_Y
		)
	return _leaf_frame_cache[crop_id]


func _root_frames(crop_id: String) -> Array:
	if not _SHEETS.has(crop_id):
		return []
	if not _root_frame_cache.has(crop_id):
		_root_frame_cache[crop_id] = _slice(
			_SHEETS[crop_id]["root_path"], ROOT_CANVAS_SIZE, ROOT_BASELINE_Y
		)
	return _root_frame_cache[crop_id]


func _slice(path: String, canvas_size: Vector2i, baseline_y: int) -> Array[ImageTexture]:
	var image := Image.load_from_file(path)
	if image == null:
		return []
	var keyed := _apply_chroma_key(image, CHROMA_KEY, CHROMA_KEY_TOLERANCE)
	# Every sheet in this doc is laid out as a single row -- the full image
	# height is the band, same as detect_frames' ordinary single-band usage.
	var frames := _slicer.detect_frames(keyed, 0, keyed.get_height())
	var textures: Array[ImageTexture] = []
	for normalized in _slicer.normalize_frames(keyed, frames, canvas_size, baseline_y):
		textures.append(ImageTexture.create_from_image(normalized))
	return textures


## Copy of `image` with every pixel within `tolerance` of `key` (each of
## R/G/B independently) turned fully transparent -- identical to
## IllustratedAnimalSprite's own _apply_chroma_key (sheep.png's recipe).
func _apply_chroma_key(image: Image, key: Color, tolerance: float) -> Image:
	var keyed := image.duplicate()
	if keyed.get_format() != Image.FORMAT_RGBA8:
		keyed.convert(Image.FORMAT_RGBA8)
	for y in keyed.get_height():
		for x in keyed.get_width():
			var c: Color = keyed.get_pixel(x, y)
			if (
				absf(c.r - key.r) <= tolerance
				and absf(c.g - key.g) <= tolerance
				and absf(c.b - key.b) <= tolerance
			):
				keyed.set_pixel(x, y, Color(0, 0, 0, 0))
	return keyed
