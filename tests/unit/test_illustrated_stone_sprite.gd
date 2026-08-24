extends GutTest

## Pins IllustratedStoneSprite: the plumbing for illustrated pebble/boulder
## variant sheets (see docs/concept/stone.md), same "hand-drawn sheet ->
## SpriteSheetSlicer -> cached frames, picked per-instance by a seeded index"
## shape as IllustratedFlowerHead/IllustratedAnimalSprite.
##
## assets/sprites/pebbles.png, assets/sprites/boulders.png, and assets/
## sprites/cobbles.png are all real, registered art: each is a genuine 4-row
## x 5-column grid (20 distinct variants), rows increasing in size/complexity
## top-to-bottom, sliced as FOUR independently hand-measured row bands
## (mirrors IllustratedAnimalSprite's own walk_bands/eat_bands shape), five
## columns auto-detected per band by the shared SpriteSheetSlicer -- see
## IllustratedStoneSprite._SHEETS's own doc comment for the exact measured
## Y-ranges. Every stone class now has real illustrated art; the earlier
## "cobbles are excluded by design" decision (a fist-sized cobble isn't just
## a bigger pebble) was superseded once the user asked for a cobble sheet
## too -- the shape concern is answered by giving cobbles their OWN distinct
## art instead, not by leaving them undrawn.

const IllustratedStoneSprite = preload("res://src/rendering/illustrated_stone_sprite.gd")
const StoneSize = preload("res://src/world/stone_size.gd")

## All three real sheets are a 4x5 grid: 20 distinct variants per class.
const EXPECTED_FRAME_COUNT := 20

var generator: IllustratedStoneSprite


func before_each():
	generator = IllustratedStoneSprite.new()


func test_has_variants_is_true_for_the_registered_pebble_sheet():
	assert_true(generator.has_variants(StoneSize.CLASS_PEBBLE))


## Boulders and cobbles now both have real registered sheets too (assets/
## sprites/boulders.png, assets/sprites/cobbles.png) -- every stone class has
## real illustrated art as of this pass.
func test_has_variants_is_true_for_the_registered_boulder_sheet():
	assert_true(generator.has_variants(StoneSize.CLASS_BOULDER))


func test_has_variants_is_true_for_the_registered_cobble_sheet():
	assert_true(generator.has_variants(StoneSize.CLASS_COBBLE))


func test_has_variants_is_false_for_an_unknown_class():
	assert_false(generator.has_variants("not_a_real_class"))


func test_frame_for_returns_null_when_nothing_is_registered():
	assert_null(generator.frame_for("not_a_real_class", 42))


# -- shared checks, run against both real sheets -----------------------------
#
# assets/sprites/pebbles.png and assets/sprites/boulders.png are both supplied
# on a solid OPAQUE MAGENTA ground (r>=0.85, b>=0.85, g<=0.15 -- measured
# directly from the real files), not real alpha: "transparent background" was
# ignored by the AI image generator, so this project settled on chroma-keyed
# magenta instead (see docs/art/ai_sprite_prompts.md). SpriteSheetSlicer only
## understands alpha and near-white/grey as background -- it has no concept of
# magenta -- so IllustratedStoneSprite must convert near-magenta pixels to
# real alpha=0 BEFORE handing the image to the slicer, or the whole sheet
# reads as one continuous content blob.

func test_frame_for_pebble_returns_a_real_non_blank_frame():
	var frame := generator.frame_for(StoneSize.CLASS_PEBBLE, 7)
	assert_not_null(frame)
	var image: Image = frame.get_image()
	assert_gt(_painted_pixel_count(image), 0, "frame should have real painted content, not be blank")


func test_frame_for_boulder_returns_a_real_non_blank_frame():
	var frame := generator.frame_for(StoneSize.CLASS_BOULDER, 7)
	assert_not_null(frame)
	var image: Image = frame.get_image()
	assert_gt(_painted_pixel_count(image), 0, "frame should have real painted content, not be blank")


func test_frame_for_cobble_returns_a_real_non_blank_frame():
	var frame := generator.frame_for(StoneSize.CLASS_COBBLE, 7)
	assert_not_null(frame)
	var image: Image = frame.get_image()
	assert_gt(_painted_pixel_count(image), 0, "frame should have real painted content, not be blank")


## The direct regression check for the chroma-key fix: without it, slicing
## would either fail to separate frames at all, or (if it somehow did) the
## magenta background would still show through as opaque magenta pixels
## inside the frame. Every pixel in a sliced frame must be either genuinely
## transparent or genuinely stone-coloured -- never opaque magenta.
func test_frame_for_pebble_has_no_leftover_magenta():
	_assert_no_leftover_magenta(StoneSize.CLASS_PEBBLE)


func test_frame_for_boulder_has_no_leftover_magenta():
	_assert_no_leftover_magenta(StoneSize.CLASS_BOULDER)


func test_frame_for_cobble_has_no_leftover_magenta():
	_assert_no_leftover_magenta(StoneSize.CLASS_COBBLE)


func _assert_no_leftover_magenta(stone_class: String) -> void:
	for seed_value in [1, 2, 3, 4, 5, 6, 7, 8]:
		var frame := generator.frame_for(stone_class, seed_value)
		var image: Image = frame.get_image()
		for y in image.get_height():
			for x in image.get_width():
				var pixel := image.get_pixel(x, y)
				if pixel.a < 0.05:
					continue  # transparent: fine, not content
				var is_magenta := pixel.r >= 0.85 and pixel.b >= 0.85 and pixel.g <= 0.15
				assert_false(
					is_magenta,
					"opaque magenta leaked into a sliced %s frame at (%d,%d)" % [stone_class, x, y]
				)


## Visual check (reported after inspecting a rendered gallery: a visible
## pink halo survived around every pebble's soft outline/shadow) that pins
## the actual bug: the fringe pixels are NOT pure magenta -- they're a whole
## GRADIENT of magenta-tinted dark tones, a blend of the stone's own soft
## outline with the magenta ground baked directly into RGB (no real alpha in
## the source to separate the two). A strict "is this pure magenta" test
## (test_frame_for_pebble_has_no_leftover_magenta above) cannot catch a
## gradient, only its purest end -- this checks for any REMAINING colour
## CAST (red and blue both meaningfully above green) on visible pixels,
## which a despill (not just a binary key) is needed to remove.
func test_frame_for_pebble_has_no_residual_magenta_color_cast():
	_assert_no_residual_magenta_color_cast(StoneSize.CLASS_PEBBLE)


func test_frame_for_boulder_has_no_residual_magenta_color_cast():
	_assert_no_residual_magenta_color_cast(StoneSize.CLASS_BOULDER)


func test_frame_for_cobble_has_no_residual_magenta_color_cast():
	_assert_no_residual_magenta_color_cast(StoneSize.CLASS_COBBLE)


func _assert_no_residual_magenta_color_cast(stone_class: String) -> void:
	var worst_cast := 0.0
	for seed_value in [1, 2, 3, 4, 5, 6, 7, 8]:
		var frame := generator.frame_for(stone_class, seed_value)
		var image: Image = frame.get_image()
		for y in image.get_height():
			for x in image.get_width():
				var pixel := image.get_pixel(x, y)
				if pixel.a < 0.2:
					continue  # near-fully-transparent: not a visible fringe
				var cast: float = minf(pixel.r - pixel.g, pixel.b - pixel.g)
				worst_cast = maxf(worst_cast, cast)
	assert_lt(worst_cast, 0.08, "a visible pink/magenta cast survived on a sliced %s frame" % stone_class)


## Each real sheet is a 4-row x 5-column grid: slicing must find all 20
## distinct variants, not just a handful of giant blobs (one per column,
## spanning every row stacked together) the way a single-band slice over the
## whole sheet height would.
func test_pebble_sheet_slices_into_20_frames():
	var frames := generator._frames_for(StoneSize.CLASS_PEBBLE)
	assert_eq(frames.size(), EXPECTED_FRAME_COUNT)


func test_boulder_sheet_slices_into_20_frames():
	var frames := generator._frames_for(StoneSize.CLASS_BOULDER)
	assert_eq(frames.size(), EXPECTED_FRAME_COUNT)


func test_cobble_sheet_slices_into_20_frames():
	var frames := generator._frames_for(StoneSize.CLASS_COBBLE)
	assert_eq(frames.size(), EXPECTED_FRAME_COUNT)


func test_frame_for_pebble_is_deterministic_per_seed():
	assert_eq(generator.frame_for(StoneSize.CLASS_PEBBLE, 99), generator.frame_for(StoneSize.CLASS_PEBBLE, 99))


func test_frame_for_boulder_is_deterministic_per_seed():
	assert_eq(generator.frame_for(StoneSize.CLASS_BOULDER, 99), generator.frame_for(StoneSize.CLASS_BOULDER, 99))


func test_frame_for_cobble_is_deterministic_per_seed():
	assert_eq(generator.frame_for(StoneSize.CLASS_COBBLE, 99), generator.frame_for(StoneSize.CLASS_COBBLE, 99))


## Different seeds should actually spread across the FULL 20-variant sheet,
## not just a handful of buckets -- a strong bar (over half the pool) rather
## than just "more than one", since PixelNoise.range_index is specifically
## built to avoid the single-bucket failure this pins.
func test_frame_for_pebble_spreads_across_variants():
	assert_gt(_distinct_variant_count(StoneSize.CLASS_PEBBLE), EXPECTED_FRAME_COUNT / 2)


func test_frame_for_boulder_spreads_across_variants():
	assert_gt(_distinct_variant_count(StoneSize.CLASS_BOULDER), EXPECTED_FRAME_COUNT / 2)


func test_frame_for_cobble_spreads_across_variants():
	assert_gt(_distinct_variant_count(StoneSize.CLASS_COBBLE), EXPECTED_FRAME_COUNT / 2)


func _distinct_variant_count(stone_class: String) -> int:
	var seen := {}
	for seed_value in 200:
		seen[generator.frame_for(stone_class, seed_value)] = true
	return seen.size()


func _painted_pixel_count(image: Image) -> int:
	var count := 0
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a > 0.05:
				count += 1
	return count


## A raw Image.load_from_file logs an engine WARNING ("Loaded resource as
## image file, this will not work on export") that GUT's error tracker
## counts as an unhandled error -- see SpriteSheetLoader's own doc comment.
## _frame_cache is cleared first (static, shared across every test in this
## file) so this genuinely re-reads pebbles.png off disk rather than hitting
## a cache an earlier test already warmed.
func test_loading_a_sheet_does_not_log_an_engine_warning():
	IllustratedStoneSprite._frame_cache.clear()
	generator.frame_for(StoneSize.CLASS_PEBBLE, 7)
	assert_engine_error_count(0, "loading a stone sheet should not warn")
