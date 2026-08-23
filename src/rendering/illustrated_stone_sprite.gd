extends RefCounted

## Illustrated loose-stone art, sliced from AI-generated reference sheets --
## one sheet of PEBBLE variants, one of BOULDER variants, one of COBBLE
## variants, each with several differently-sized/shaped stones drawn side by
## side rather than one shape generated procedurally. Same "hand-drawn sheet
## -> SpriteSheetSlicer -> cached frames, picked per-instance by a seeded
## index" shape as IllustratedFlowerHead/IllustratedAnimalSprite;
## StoneRenderer keeps ProceduralStoneSprite as the fallback for any class
## with no sheet yet (see has_variants' own doc comment) -- exactly the
## has_X()-gated fallback convention every other optional illustrated-art
## seam in this codebase uses.
##
## pebbles.png, boulders.png, and cobbles.png are all real, registered art
## today -- 20 variants each, sliced from a 4x5 grid sheet (see _SHEETS' own
## doc comment). This class was originally dropped in as plumbing ahead of
## the art (the same "art can run ahead of code, code can run ahead of art"
## pattern this project already used for flowers); that fallback path still
## applies to any FUTURE class with no sheet yet -- has_variants reports
## false and the stone falls all the way through to the procedural
## generator, gated so nothing errors or draws blank while art is still
## being produced for it.
##
## Cobbles were ORIGINALLY excluded by design (a fist-sized cobble isn't just
## a bigger pebble, so reusing the pebble pool would read wrong) -- that
## concern is answered here by giving cobbles their own distinct sheet
## instead of leaving them undrawn, once the user asked for one. Every real
## stone class now has real illustrated art.

const SpriteSheetSlicer = preload("res://src/rendering/sprite_sheet_slicer.gd")
const PixelNoise = preload("res://src/rendering/pixel_noise.gd")
const StoneSize = preload("res://src/world/stone_size.gd")

## Stone class -> sheet metadata. Only classes with real art land here; a
## class with no entry cleanly reports "nothing to draw" via has_variants
## rather than erroring.
##
## Both pebbles.png and boulders.png are a genuine 4-row x 5-column grid: 20
## distinct hand/AI-illustrated variants per sheet, rows increasing in
## size/complexity top-to-bottom. `row_bands` are the four rows' own Y-ranges
## -- the same "several independently hand-measured bands, each independently
## column-sliced" shape IllustratedAnimalSprite uses for a multi-row sheet
## (see its _SHEETS' own walk_bands/eat_bands), except every band here comes
## from the SAME file rather than a per-action file. Each band is then
## column-sliced automatically by the shared SpriteSheetSlicer (five near-
## white-divided columns per row) -- no per-column hand-measurement needed,
## since the vertical dividers are exactly what detect_frames already looks
## for.
##
## Y-ranges measured directly from the real PNGs (a divider row reads as
## near-uniform pale/white across the width; everything between two divider
## bands is one row's own content): pebbles.png's four content bands run
## 2-290, 294-589, 593-893, 897-1251 out of a 1254x1254 sheet; boulders.png's
## run 2-289, 292-588, 592-892, 896-1251; cobbles.png (1402x1122, a different
## sheet resolution -- the exact pixel dimensions don't matter, only its own
## measured bands do) runs 5-282, 285-560, 563-838, 841-1118, found from the
## sheet's own exact full-width white divider rows (0-5, 282-285, 560-563,
## 838-841, 1118-1122) rather than eyeballed. Every sheet's grid is drawn at
## its own slightly different pixel offsets, which is why bands are listed
## separately per class rather than shared. Frames are concatenated row-major
## (row 0 left-to-right, then row 1, ...) -- variant PICKING is uniform
## across the whole pool (see frame_for), so row order only matters for
## readability, not for any weighting.
const _SHEETS := {
	StoneSize.CLASS_PEBBLE: {
		"path": "res://assets/sprites/pebbles.png",
		"row_bands": [
			Vector2i(2, 290), Vector2i(294, 589), Vector2i(593, 893), Vector2i(897, 1251)
		],
	},
	StoneSize.CLASS_BOULDER: {
		"path": "res://assets/sprites/boulders.png",
		"row_bands": [
			Vector2i(2, 289), Vector2i(292, 588), Vector2i(592, 892), Vector2i(896, 1251)
		],
	},
	StoneSize.CLASS_COBBLE: {
		"path": "res://assets/sprites/cobbles.png",
		"row_bands": [
			Vector2i(5, 282), Vector2i(285, 560), Vector2i(563, 838), Vector2i(841, 1118)
		],
	},
}

## ## Chroma-keyed magenta, not real alpha
##
## Sheets are supplied on a solid OPAQUE magenta ground, not real
## transparency: "transparent background" was ignored by the AI image
## generator, so this project settled on magenta instead (see
## docs/art/ai_sprite_prompts.md) -- pebbles.png measures format RGB8, no
## alpha channel at all, corners at roughly (0.9, 0.08, 0.9). Expect every
## future sheet (boulders, and whatever else) to arrive the same way.
## SpriteSheetSlicer only understands alpha and near-white/grey as
## background -- it has no concept of magenta -- so the loaded image needs
## this converted to real alpha=0 BEFORE it ever reaches the slicer, or the
## whole sheet reads as one continuous content blob spanning the full width.
##
## A RANGE rather than exact equality: compression/resampling shifts the
## colour slightly off pure magenta (#FF00FF) at edges and in antialiasing,
## which is exactly why a plain "no alpha channel" source needs a real
## chroma-key pass rather than a single hard-coded colour comparison.
const MAGENTA_RED_MIN := 0.85
const MAGENTA_BLUE_MIN := 0.85
const MAGENTA_GREEN_MAX := 0.15

## ## Despill, not just a binary key
##
## A pure-magenta key alone leaves a visible pink halo (reported after
## rendering a real gallery of sliced frames: a pink tint survives around
## every pebble's soft outline/shadow). The source has NO real alpha, so a
## hand/AI-drawn ANTIALIASED edge -- the pebble's own dark outline blended
## against the magenta ground -- bakes that blend directly into RGB. That
## produces a whole GRADIENT of magenta-tinted dark tones along every edge,
## not just pixels close to pure magenta, and no binary threshold can catch
## a gradient, only its purest end.
##
## The fix is a DESPILL: red and blue are clamped down toward green (the
## direction magenta leans away from) rather than the pixel being zeroed
## outright, so a genuine soft shadow/outline stays a shadow instead of
## being punched into a hard-edged hole.
##
## How much red/blue may exceed green before it counts as cast worth
## removing -- a small allowance so a pixel that is legitimately a warm
## grey/brown stone tone (a real, if slight, r/b-over-g difference) isn't
## chased down to a flat, desaturated greenish grey.
const MAGENTA_CAST_MARGIN := 0.03


## `color` with any magenta-direction cast removed (see MAGENTA_CAST_MARGIN's
## own doc comment). A pixel with no cast (a genuine grey/dark stone tone)
## passes through completely unchanged.
static func _despilled(color: Color) -> Color:
	var cast: float = minf(color.r - color.g, color.b - color.g)
	if cast <= MAGENTA_CAST_MARGIN:
		return color
	var removed := cast - MAGENTA_CAST_MARGIN
	return Color(
		clampf(color.r - removed, 0.0, 1.0),
		color.g,
		clampf(color.b - removed, 0.0, 1.0),
		color.a
	)

## The canvas every sliced frame is normalized onto, matching
## ProceduralStoneSprite.SIZE so an illustrated stone drops into exactly the
## scale math (StoneRenderer._sprite_scale_for) the procedural one already
## uses -- no separate scale seam needed for illustrated art.
const CANVAS_SIZE := Vector2i(32, 32)
const BASELINE_Y := 32

var _slicer := SpriteSheetSlicer.new()

## Keyed by sheet PATH, shared across instances -- every stone drawing from
## the same sheet reuses the identical sliced frames (mirrors
## IllustratedFlowerHead._frame_cache/IllustratedAnimalSprite._frame_cache).
static var _frame_cache: Dictionary = {}


## Whether there is real illustrated art for this stone CLASS
## (StoneSize.CLASS_PEBBLE/CLASS_COBBLE/CLASS_BOULDER). Callers must check
## this before calling frame_for and fall back to the procedural generator
## themselves.
func has_variants(stone_class: String) -> bool:
	return _SHEETS.has(stone_class)


## One deterministically-picked variant frame for `seed_value`, from
## whichever pool `stone_class` maps to, or null if that class has no sheet
## (check has_variants first). Every stone with the same seed always picks
## the same variant, and different seeds spread across the sheet's full
## variant count via PixelNoise.range_index's bucket-avoidance -- the same
## determinism/spread guarantee every other seeded index pick in this
## codebase relies on.
func frame_for(stone_class: String, seed_value: int) -> ImageTexture:
	var frames := _frames_for(stone_class)
	if frames.is_empty():
		return null
	var index := PixelNoise.range_index(seed_value, 0, 0, frames.size())
	return frames[index]


func _frames_for(stone_class: String) -> Array:
	if not has_variants(stone_class):
		return []
	var path: String = _SHEETS[stone_class]["path"]
	if not _frame_cache.has(path):
		_frame_cache[path] = _load_frames_from(stone_class)
	return _frame_cache[path]


## Slices+normalizes every row_band for `stone_class`'s sheet, concatenating
## them in list order (row-major: see _SHEETS' own doc comment) -- the same
## "one image, several independently-measured bands" shape
## IllustratedAnimalSprite._slice_bands uses, except every band here comes
## from one shared file rather than a per-action one.
func _load_frames_from(stone_class: String) -> Array:
	var sheet: Dictionary = _SHEETS[stone_class]
	var image := _prepared_for_slicing(Image.load_from_file(sheet["path"]))
	var textures: Array[ImageTexture] = []
	for band in sheet["row_bands"]:
		var rect: Vector2i = band
		var frames := _slicer.detect_frames(image, rect.x, rect.y)
		var normalized := _slicer.normalize_frames(image, frames, CANVAS_SIZE, BASELINE_Y)
		for frame_image in normalized:
			_scrub_magenta_fringe(frame_image)
			textures.append(ImageTexture.create_from_image(frame_image))
	return textures


## A second, final cleanup pass over each already-cropped-and-resized SMALL
## frame -- SpriteSheetSlicer's own crop+Lanczos resize can still ring a few
## output pixels back toward a magenta cast even once the SOURCE sheet has
## been despilled (_prepared_for_slicing), since resizing blends a
## transparent (0,0,0,0) background pixel with an adjacent opaque one and
## can overshoot. Cheap at this scale (one 32x32 pass per frame, once per
## sheet, cached thereafter). Two passes, in order: pixels close enough to
## PURE magenta are treated as background outright (a one-pixel transparent
## gap at pixel-art scale is invisible, where an opaque magenta pixel is
## not); anything left with a softer cast is despilled rather than deleted,
## so a genuine soft shadow/outline survives as a shadow instead of being
## punched into a hard-edged hole (see MAGENTA_CAST_MARGIN's own doc
## comment).
func _scrub_magenta_fringe(image: Image) -> void:
	for y in image.get_height():
		for x in image.get_width():
			var pixel := image.get_pixel(x, y)
			if _is_magenta(pixel):
				image.set_pixel(x, y, Color(0, 0, 0, 0))
			else:
				image.set_pixel(x, y, _despilled(pixel))


## Makes a sheet's background genuinely transparent before it reaches
## SpriteSheetSlicer. Robust to BOTH supply conventions: a sheet that
## already carries a real alpha channel (its native format has one, whatever
## the actual per-pixel values are) passes through unchanged -- a sheet with
## real alpha and a magenta-TINTED rock is plausible, and chroma-keying it
## unconditionally would erase real content along with the background. A
## sheet loaded with NO alpha channel at all (FORMAT_RGB8 and similar) is,
## by construction, the opaque-magenta convention (see MAGENTA_RED_MIN's own
## doc comment) -- every near-magenta pixel in it gets punched to alpha=0.
func _prepared_for_slicing(image: Image) -> Image:
	var had_alpha_channel := image.get_format() in [
		Image.FORMAT_RGBA8, Image.FORMAT_RGBAF, Image.FORMAT_RGBAH, Image.FORMAT_LA8
	]
	# duplicate() returns the base Resource type in GDScript's static
	# analysis (Image doesn't narrow it), so the cast is needed -- without it
	# every call below fails to type-check.
	var prepared := image.duplicate() as Image
	if prepared.get_format() != Image.FORMAT_RGBA8:
		prepared.convert(Image.FORMAT_RGBA8)
	if had_alpha_channel:
		return prepared
	for y in prepared.get_height():
		for x in prepared.get_width():
			var pixel := prepared.get_pixel(x, y)
			if _is_magenta(pixel):
				prepared.set_pixel(x, y, Color(pixel.r, pixel.g, pixel.b, 0.0))
			else:
				# Despill BEFORE the slicer crops/resizes: cleaning the
				# source first means far less magenta-tinted colour is left
				# for the later crop+Lanczos resize to blend/ring at edges
				# in the first place (see MAGENTA_CAST_MARGIN's own doc
				# comment).
				prepared.set_pixel(x, y, _despilled(pixel))
	return prepared


static func _is_magenta(color: Color) -> bool:
	return color.r >= MAGENTA_RED_MIN and color.b >= MAGENTA_BLUE_MIN and color.g <= MAGENTA_GREEN_MAX
