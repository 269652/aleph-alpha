extends RefCounted

## Illustrated mushroom cap art, sliced from one AI-illustrated 5x5
## reference sheet PER SPECIES -- 25 independent individual specimens, NOT
## an animation (see MushroomMarker, docs/concept/mushrooms.md,
## docs/art/ai_sprite_prompts.md section 12). Same "hand/AI-illustrated
## sheet -> SpriteSheetSlicer -> cached frames, picked per-instance by a
## seeded index" shape as IllustratedAntMoundSprite's single mound pool --
## just one pool per species instead of one pool total, since every
## species now has its own real sheet.
##
## Two real background conventions among the six delivered sheets,
## confirmed by pixel-sampling each one directly rather than assumed from a
## preview:
## - fly_agaric.png: a genuinely transparent background already (an
##   earlier visual read of it as "solid black" was a wide low-alpha
##   antialiasing fringe composited against a dark preview canvas, not
##   real content -- confirmed by sampling interior background pixels and
##   by running the real slicer over it). No chroma_key entry:
##   SpriteSheetSlicer's own alpha_threshold handles it directly.
## - every other species: a solid magenta background (~Color(0.98, 0.01,
##   0.98), sampled at interior background points -- corners/edges read
##   misleadingly pale due to antialiasing feathering). Uses
##   IllustratedAnimalSprite's simpler single-pass _apply_chroma_key
##   technique (a per-channel-tolerance key-out to full transparency,
##   applied once before slicing) rather than IllustratedStoneSprite/
##   IllustratedAntMoundSprite's cast-removal despill quartet -- proven
##   identically effective on sheep/wolf/the world-boss sheets, and
##   simpler since these are fresh single-pass renders with no
##   resize-induced magenta-cast bleed to clean up afterward.

const SpriteSheetSlicer = preload("res://src/rendering/sprite_sheet_slicer.gd")
const SpriteSheetLoader = preload("res://src/rendering/sprite_sheet_loader.gd")
const PixelNoise = preload("res://src/rendering/pixel_noise.gd")
const ProceduralMushroomSprite = preload("res://src/rendering/procedural_mushroom_sprite.gd")

const _MAGENTA := Color(0.98, 0.01, 0.98)
const _MAGENTA_TOLERANCE := 0.25

## species_id -> {"path": String, "chroma_key": Color, "chroma_key_tolerance": float}.
## chroma_key/chroma_key_tolerance absent for fly_agaric (see class doc
## comment above); present for every other species.
const _SHEETS := {
	"fly_agaric": {"path": "res://assets/sprites/mushrooms/fly_agaric.png"},
	"psylo": {
		"path": "res://assets/sprites/mushrooms/psylo.png",
		"chroma_key": _MAGENTA,
		"chroma_key_tolerance": _MAGENTA_TOLERANCE,
	},
	"black_trumpet": {
		"path": "res://assets/sprites/mushrooms/black_trumpet.png",
		"chroma_key": _MAGENTA,
		"chroma_key_tolerance": _MAGENTA_TOLERANCE,
	},
	"champignon": {
		"path": "res://assets/sprites/mushrooms/champignon.png",
		"chroma_key": _MAGENTA,
		"chroma_key_tolerance": _MAGENTA_TOLERANCE,
	},
	# Species id is the correctly-spelled "chanterelle" (see
	# MushroomSpecies.SPECIES) -- the delivered sheet's own filename is
	# misspelled "chantarelle.png". Pointed at as-delivered rather than
	# renamed on disk; see docs/art/ai_sprite_prompts.md section 12.
	"chanterelle": {
		"path": "res://assets/sprites/mushrooms/chantarelle.png",
		"chroma_key": _MAGENTA,
		"chroma_key_tolerance": _MAGENTA_TOLERANCE,
	},
	"parasol": {
		"path": "res://assets/sprites/mushrooms/parasol.png",
		"chroma_key": _MAGENTA,
		"chroma_key_tolerance": _MAGENTA_TOLERANCE,
	},
}

## Five content rows, identical across every sheet -- all six are the same
## 1254x1254 canvas divided into 5 equal bands (measured directly, not
## assumed).
const _ROW_BANDS := [
	Vector2i(0, 251), Vector2i(251, 502), Vector2i(502, 752), Vector2i(752, 1003), Vector2i(1003, 1254)
]

## A mushroom has no walk cycle to bob -- like IllustratedAntMoundSprite's
## mound, BASELINE_Y is simply the canvas bottom, standing every specimen's
## own base on the same line with no wasted ground margin.
const CANVAS_SIZE := Vector2i(64, 64)
const BASELINE_Y := 64

var _slicer := SpriteSheetSlicer.new()

static var _frames_cache: Dictionary = {}
static var _marker_scale_cache: Dictionary = {}


## Whether there is a real illustrated sheet registered for `species_id`.
## True for every roster species today -- kept as an explicit gate anyway,
## the same has_X()-before-frame_for() convention every other optional
## illustrated-art seam in this codebase uses.
func has_variants(species_id: String) -> bool:
	return _SHEETS.has(species_id)


func frame_count(species_id: String) -> int:
	return _all_frames(species_id).size()


## One deterministically-picked variant for `seed_value`, or null if
## `species_id` has no registered sheet. Every marker with the same seed
## always picks the same variant, and different seeds spread across the
## sheet's full variant count via PixelNoise.range_index's bucket-avoidance
## (mirrors IllustratedAntMoundSprite.frame_for exactly).
func frame_for(species_id: String, seed_value: int) -> ImageTexture:
	var frames := _all_frames(species_id)
	if frames.is_empty():
		return null
	var index: int = PixelNoise.range_index(seed_value, 0, 0, frames.size())
	return frames[index]


func _all_frames(species_id: String) -> Array:
	if not _SHEETS.has(species_id):
		return []
	if not _frames_cache.has(species_id):
		_frames_cache[species_id] = _load_frames(species_id)
	return _frames_cache[species_id]


func _load_frames(species_id: String) -> Array[ImageTexture]:
	var sheet: Dictionary = _SHEETS[species_id]
	var image := SpriteSheetLoader.load_image(sheet["path"])
	# Turning the chroma-keyed background transparent up front lets the
	# exact same downstream detect_frames/normalize_frames (via
	# SpriteSheetSlicer.is_empty's alpha check) handle it with no separate
	# "or matches this color" branch -- same reasoning as
	# IllustratedAnimalSprite._slice_bands.
	if sheet.has("chroma_key"):
		image = _apply_chroma_key(image, sheet["chroma_key"], sheet["chroma_key_tolerance"])
	var textures: Array[ImageTexture] = []
	for band in _ROW_BANDS:
		var rect: Vector2i = band
		var frames := _slicer.detect_frames(image, rect.x, rect.y, 60, 1)
		for frame_image in _slicer.normalize_frames(image, frames, CANVAS_SIZE, BASELINE_Y):
			textures.append(ImageTexture.create_from_image(frame_image))
	return textures


## A copy of `image` with every pixel within `tolerance` of `key` (each of
## R/G/B independently, ignoring alpha) turned fully transparent --
## IllustratedAnimalSprite's own technique (see its doc comment there), not
## IllustratedAntMoundSprite's cast-removal despill quartet: these are
## fresh single-pass renders with no resize-induced magenta-cast bleed to
## clean up afterward, so one pass before slicing is enough.
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


## How much to scale a CANVAS_SIZE-normalized frame so it reads at
## ProceduralMushroomSprite.MUSHROOM_WORLD_WIDTH on screen -- the same
## real-world width the procedural fallback already uses, measured from
## the real art's own opaque width per species rather than assumed to
## match the canvas proportions (mirrors IllustratedAntMoundSprite/
## IllustratedAnimalSprite marker_scale). Cached per species: art doesn't
## change once loaded.
func marker_scale(species_id: String) -> float:
	if not _SHEETS.has(species_id):
		return 1.0
	if _marker_scale_cache.has(species_id):
		return _marker_scale_cache[species_id]
	var frames := _all_frames(species_id)
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
	var scale_value: float = ProceduralMushroomSprite.MUSHROOM_WORLD_WIDTH / reference_width
	_marker_scale_cache[species_id] = scale_value
	return scale_value
