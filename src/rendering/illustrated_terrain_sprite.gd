extends RefCounted

## Illustrated ground-tile art, sliced from AI-generated reference sheets --
## one 3x3 (9-variant) sheet per LAND biome, each cell a differently-detailed
## patch of that biome's ground rather than one texture generated
## procedurally. Same "hand-drawn sheet -> SpriteSheetSlicer -> cached
## frames, picked per-instance by a seeded index" shape as
## IllustratedStoneSprite/IllustratedFlowerHead/IllustratedAnimalSprite;
## TerrainRenderer keeps ProceduralTerrainSprite as the fallback for any
## biome with no sheet (ocean, deliberately -- see below), the same
## has_X()-gated fallback convention every optional illustrated-art seam in
## this codebase uses.
##
## Originally targeted as 5x5/25-variant sheets (see docs/art/
## ai_sprite_prompts.md's terrain section), but real generation only
## reliably held a square-cell grid at 3x3 -- a 5x5 attempt came back as
## uneven tall strips, unusable for a full-bleed tile. 9 variants per biome
## still gives real position-to-position variety (see
## TerrainRenderer.variant_index_for_position's decorrelated picking) without
## fighting the generator for a count it wouldn't reliably hold.
##
## Base ground fill ONLY. The directional-blend and corner-carve tiles that
## dither one biome into a neighbor at borders (see
## TerrainRenderer.dominant_blend_for/corner_direction_for) stay entirely
## procedural regardless of what's registered here: ProceduralTerrainSprite
## can synthesize a blend/corner image for any of the thousands of (biome
## pair x direction mask x corner mask x variant) combinations on demand,
## and illustrating that same combinatorial space by hand is not in scope. A
## biome with illustrated base art still shows a procedurally-blended fringe
## at its borders with a differing neighbor -- see docs/concept/
## art_resolution.md.
##
## Ocean has no sheet, by design: ProceduralTerrainSprite animates water as a
## 4-frame scrolling loop, and an illustrated tile has no animation of its
## own (see TerrainRenderer._biome_frame_image, which reuses one frame across
## every animation slot) -- registering an ocean sheet would trade the real
## moving water for a flat static tile. Ocean falls through to the
## procedural generator unconditionally until an animated-illustrated
## mechanism exists.

const SpriteSheetSlicer = preload("res://src/rendering/sprite_sheet_slicer.gd")
const SpriteSheetLoader = preload("res://src/rendering/sprite_sheet_loader.gd")
const PixelNoise = preload("res://src/rendering/pixel_noise.gd")

## Biome name -> sheet metadata: a "path" and a list of row_bands (one per
## illustrated sheet row), the same shape IllustratedStoneSprite._SHEETS
## uses. Every LAND biome now has a real sheet -- a genuine 3-row x 3-column
## grid, 9 distinct variants (not the originally-targeted 5x5/25: the model
## reliably held a square-cell 3x3 grid but not a 5x5 one, see docs/art/
## ai_sprite_prompts.md's terrain section for the working prompt this
## actually came from). Ocean has no sheet, by design (see this class's own
## doc comment: an illustrated tile can't carry the animated water scroll).
##
## Y-ranges measured directly from the real PNGs (a divider row reads as a
## pinkish/magenta band across the width; everything between two divider
## bands is one row's own content, with a couple of anti-aliased pixels of
## slop at each edge which normalize_frames' own content-cropping absorbs):
## every sheet below is a 1254x1254 grid with near-identical row bands
## (~5-414, ~421-831, ~838-1247) since all six were generated from the same
## template. Frames are concatenated row-major (row 0 left-to-right, then
## row 1, ...) -- variant PICKING is uniform across the whole pool (see
## frame_for), so row order only matters for readability, not weighting.
const _SHEETS := {
	"grassland": {
		"path": "res://assets/sprites/terrain/grass.png",
		"row_bands": [Vector2i(5, 415), Vector2i(421, 832), Vector2i(838, 1247)],
	},
	"forest": {
		"path": "res://assets/sprites/terrain/forest.png",
		"row_bands": [Vector2i(5, 414), Vector2i(422, 830), Vector2i(838, 1247)],
	},
	"desert": {
		"path": "res://assets/sprites/terrain/desert.png",
		"row_bands": [Vector2i(5, 414), Vector2i(421, 831), Vector2i(838, 1247)],
	},
	"mountain": {
		"path": "res://assets/sprites/terrain/mountain.png",
		"row_bands": [Vector2i(5, 413), Vector2i(421, 830), Vector2i(838, 1247)],
	},
	"tundra": {
		"path": "res://assets/sprites/terrain/tundra.png",
		"row_bands": [Vector2i(5, 414), Vector2i(421, 831), Vector2i(838, 1247)],
	},
	"rainforest": {
		"path": "res://assets/sprites/terrain/rainforest.png",
		"row_bands": [Vector2i(5, 414), Vector2i(421, 831), Vector2i(838, 1247)],
	},
}

## Chroma-keyed magenta, not real alpha -- identical convention/thresholds to
## IllustratedStoneSprite (see its own doc comment for the full rationale:
## "transparent background" is ignored by the AI image generator, so this
## project settled on solid magenta instead). Kept as this class's own copy
## rather than shared, matching how IllustratedStoneSprite already keeps its
## own copy independent of the other illustrated-art classes.
## Looser than IllustratedStoneSprite's 0.85/0.85/0.15 (r/b-min, g-max): these
## terrain sheets' divider lines carry a visible soft glow/anti-aliasing that
## never reaches pure magenta across most of their own width. Measured
## directly against the real PNGs -- the strict pebble/boulder thresholds
## missed most of a divider's width, so several columns within a row band
## never separated into distinct frames at all (a whole row read as one
## wide merged frame). Real terrain colors in these sheets (desaturated
## green/grey/tan) never have red AND blue both this far above green at
## once, so this stays safely non-triggering on actual ground content --
## see _is_magenta's own average-skew check.
const MAGENTA_RED_MIN := 0.55
const MAGENTA_BLUE_MIN := 0.55

## How far the red/blue average must sit above green to read as a magenta-
## leaning pixel -- looser than a per-channel g-max because a divider's
## anti-aliased edge can have ONE channel (say red) drop while the other
## stays high; averaging catches that where a strict per-channel test on
## green alone would not.
##
## Lowered from 0.25: desert.png/mountain.png's divider gaps carry a few
## stray, even paler anti-aliased pixels (measured skew ~0.20, e.g.
## r=0.98 g=0.78 b=0.97) that 0.25 missed -- SpriteSheetSlicer's real
## column-emptiness check needs EVERY pixel down a divider column clean,
## so even a handful of unmatched pixels merged whole cells together
## (measured directly: desert sliced into only 6 of 9 frames, mountain 8).
## Real ground colors stay safely below this even at 0.15: desert's own
## sandy tan (b well under MAGENTA_BLUE_MIN) and mountain's grey-green (r
## well under MAGENTA_RED_MIN) are excluded by the per-channel gates
## before skew is even checked, not by this margin.
const MAGENTA_SKEW_MIN := 0.15

## Despill margin -- see IllustratedStoneSprite.MAGENTA_CAST_MARGIN's own doc
## comment for why a binary chroma-key alone leaves a visible pink cast along
## soft/antialiased edges baked directly into RGB.
const MAGENTA_CAST_MARGIN := 0.03

## The canvas every sliced frame is normalized onto -- the ACTUAL final
## baked tile size (TerrainRenderer.ART_TILE_SIZE, 32 at the current
## DETAIL_MULTIPLIER), not an oversized intermediate. Hardcoded rather than
## referenced live (mirrors ProceduralTerrainSprite's own SIZE constant --
## keep in sync with ART_TILE_SIZE by hand if DETAIL_MULTIPLIER ever
## changes) to avoid a circular preload with TerrainRenderer, which already
## preloads this class.
##
## This USED to normalize onto a 64x64 canvas ("matches ProceduralTerrain-
## Sprite.SIZE"), leaving TerrainRenderer._blit_tile to nearest-neighbour-
## downscale it a second time down to the real 32x32 tile. That second,
## lossy resize is what aliased the illustrated art's own fine per-pixel
## detail (individual grass blades, leaf-litter speckle) into visible
## "static" once shrunk -- reported in-game as grass looking like TV noise,
## strikingly different from (and much worse than) the same frame viewed at
## its own native resolution. Nearest-neighbour is the RIGHT choice for
## UPSCALING (keeps pixel art crisp, see _blit_tile's own doc comment) but
## the WRONG one for DOWNSCALING (it discards whole rows/columns of source
## pixels with no averaging, i.e. aliasing, regardless of source content) --
## ProceduralTerrainSprite only gets away with the old two-stage path
## because its own texture is deliberately painted in coarse 2x2-pixel
## marks (see its SPECKLE_CLUSTER) built to survive exactly that decimation
## cleanly; illustrated art was never authored with that constraint. Fixing
## this INSIDE this class -- normalizing directly to the real final size, so
## SpriteSheetSlicer's own Lanczos resize is the only downscale that ever
## happens -- keeps every other tile family (procedural biomes, structures,
## blend/corner tiles) completely untouched, rather than changing
## _blit_tile's shared rescale behaviour for everything that flows through
## it. See test_frame_size_matches_the_final_baked_tile_size_not_an_
## oversized_intermediate.
const CANVAS_SIZE := Vector2i(32, 32)
const BASELINE_Y := 32

var _slicer := SpriteSheetSlicer.new()

## Keyed by sheet PATH, shared across instances -- every tile drawing from
## the same sheet reuses the identical sliced frames (mirrors
## IllustratedStoneSprite._frame_cache).
static var _frame_cache: Dictionary = {}


## Whether there is real illustrated art for this BIOME name (see
## BiomeClassifier.KNOWN_BIOMES). Callers must check this before calling
## frame_for and fall back to the procedural generator themselves.
func has_variants(biome_name: String) -> bool:
	return _SHEETS.has(biome_name)


## One deterministically-picked variant frame Image for `seed_value`, from
## whichever pool `biome_name` maps to, or null if that biome has no sheet
## (check has_variants first). Every tile with the same seed always picks the
## same variant, and different seeds spread across the sheet's full variant
## count via PixelNoise.range_index's bucket-avoidance -- the same
## determinism/spread guarantee every other seeded index pick in this
## codebase relies on.
##
## Returns a raw Image, not an ImageTexture (unlike IllustratedStoneSprite.
## frame_for): TerrainRenderer consumes these by blitting into a shared atlas
## Image, not by handing a texture straight to a Sprite2D.
func frame_for(biome_name: String, seed_value: int) -> Image:
	var frames := _frames_for(biome_name)
	if frames.is_empty():
		return null
	var index := PixelNoise.range_index(seed_value, 0, 0, frames.size())
	return frames[index]


func _frames_for(biome_name: String) -> Array:
	if not has_variants(biome_name):
		return []
	var path: String = _SHEETS[biome_name]["path"]
	if not _frame_cache.has(path):
		_frame_cache[path] = _load_frames_from(biome_name)
	return _frame_cache[path]


## Slices+normalizes every row_band for `biome_name`'s sheet, concatenating
## them in list order (row-major) -- the same "one image, several
## independently-measured bands" shape IllustratedStoneSprite._load_frames_from
## uses.
## Higher than any real color channel can reach (channels are 0..1) --
## effectively disables SpriteSheetSlicer's own "near-white/low-saturation
## counts as divider" heuristic. That heuristic exists for sheets whose only
## background signal IS a pale divider line; here the real dividers are
## already punched to genuine alpha=0 by _prepared_for_slicing, so the
## heuristic has nothing left to do except misfire on a biome's own pale
## ground color -- tundra's near-white frost tone measured ~90% full-bleed
## instead of the full tile before this override, the SAME near-white pixels
## meant to be the divider heuristic's target were catching real content.
## Alpha is still the real, correct background signal (DEFAULT_ALPHA_THRESHOLD).
const _DISABLED_DIVIDER_GRAY_MIN := 1.01


func _load_frames_from(biome_name: String) -> Array:
	var sheet: Dictionary = _SHEETS[biome_name]
	var image := _prepared_for_slicing(SpriteSheetLoader.load_image(sheet["path"]))
	var images: Array[Image] = []
	for band in sheet["row_bands"]:
		var rect: Vector2i = band
		var frames := _slicer.detect_frames(
			image, rect.x, rect.y,
			SpriteSheetSlicer.DEFAULT_MIN_FRAME_WIDTH, SpriteSheetSlicer.DEFAULT_MIN_DIVIDER_WIDTH,
			SpriteSheetSlicer.DEFAULT_ALPHA_THRESHOLD, _DISABLED_DIVIDER_GRAY_MIN
		)
		var normalized := _slicer.normalize_frames(
			image, frames, CANVAS_SIZE, BASELINE_Y,
			SpriteSheetSlicer.DEFAULT_ALPHA_THRESHOLD, _DISABLED_DIVIDER_GRAY_MIN
		)
		for frame_image in normalized:
			_scrub_magenta_fringe(frame_image)
			images.append(frame_image)
	return images


## A second, final cleanup pass over each already-cropped-and-resized frame --
## see IllustratedStoneSprite._scrub_magenta_fringe's own doc comment for why
## this two-pass (pure-magenta-as-background, softer-cast-as-despill) shape
## is needed even once the source sheet has already been despilled.
func _scrub_magenta_fringe(image: Image) -> void:
	for y in image.get_height():
		for x in image.get_width():
			var pixel := image.get_pixel(x, y)
			if _is_magenta(pixel):
				image.set_pixel(x, y, Color(0, 0, 0, 0))
			else:
				image.set_pixel(x, y, _despilled(pixel))


## Makes a sheet's background genuinely transparent before it reaches
## SpriteSheetSlicer -- see IllustratedStoneSprite._prepared_for_slicing's
## own doc comment for the full rationale (robust to both a real-alpha and a
## no-alpha-channel-at-all supply convention).
func _prepared_for_slicing(image: Image) -> Image:
	var had_alpha_channel := image.get_format() in [
		Image.FORMAT_RGBA8, Image.FORMAT_RGBAF, Image.FORMAT_RGBAH, Image.FORMAT_LA8
	]
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
				prepared.set_pixel(x, y, _despilled(pixel))
	return prepared


## `color` with any magenta-direction cast removed -- see
## IllustratedStoneSprite._despilled's own doc comment.
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


static func _is_magenta(color: Color) -> bool:
	return (
		color.r >= MAGENTA_RED_MIN
		and color.b >= MAGENTA_BLUE_MIN
		and (color.r + color.b) / 2.0 - color.g >= MAGENTA_SKEW_MIN
	)
