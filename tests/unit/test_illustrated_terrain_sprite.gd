extends GutTest

## Pins IllustratedTerrainSprite: real illustrated ground-tile sheets are now
## registered for every LAND biome (see docs/concept/art_resolution.md and
## docs/art/ai_sprite_prompts.md's terrain section), same "hand-drawn sheet
## -> SpriteSheetSlicer -> cached frames, picked per-instance by a seeded
## index" shape as IllustratedStoneSprite/IllustratedFlowerHead/
## IllustratedAnimalSprite.
##
## assets/sprites/terrain/{grass,forest,desert,mountain,tundra,rainforest}.png
## are each a genuine 3-row x 3-column grid (9 distinct variants), measured
## directly from the real PNGs the same way IllustratedStoneSprite's
## row_bands were -- see IllustratedTerrainSprite._SHEETS's own doc comment
## for the exact Y-ranges. Ocean deliberately has no sheet (see
## IllustratedTerrainSprite's own class doc comment: an illustrated tile
## can't carry the animated water scroll yet) and stays on the
## has_variants()-gated procedural fallback.

const IllustratedTerrainSprite = preload("res://src/rendering/illustrated_terrain_sprite.gd")
const BiomeClassifier = preload("res://src/world/biome_classifier.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")

## Every real sheet is a 3x3 grid: 9 distinct variants per biome.
const EXPECTED_FRAME_COUNT := 9

const LAND_BIOMES: Array[String] = [
	"grassland", "forest", "desert", "mountain", "tundra", "rainforest"
]

var generator: IllustratedTerrainSprite


func before_each():
	generator = IllustratedTerrainSprite.new()


func test_has_variants_is_true_for_every_registered_land_biome():
	for biome_name in LAND_BIOMES:
		assert_true(generator.has_variants(biome_name), "%s should have a real sheet" % biome_name)


## Ocean is deliberately excluded -- see the class doc comment on why an
## illustrated tile can't carry the animated water scroll.
func test_has_variants_is_false_for_ocean():
	assert_false(generator.has_variants("ocean"))


func test_has_variants_is_false_for_an_unknown_biome():
	assert_false(generator.has_variants("not_a_real_biome"))


func test_frame_for_returns_null_for_ocean():
	assert_null(generator.frame_for("ocean", 42))


# -- shared checks, run against every real sheet -----------------------------
#
# Every terrain sheet is supplied on a solid OPAQUE MAGENTA ground (same
# convention as pebbles.png/boulders.png -- see docs/art/ai_sprite_prompts.md)
# -- IllustratedTerrainSprite must chroma-key + despill it before handing the
# image to SpriteSheetSlicer, or the whole sheet reads as one continuous
# content blob.

## Normalizing onto an OVERSIZED intermediate canvas and letting
## TerrainRenderer._blit_tile nearest-neighbour-downscale it a second time
## aliases fine illustrated detail (grass blades, leaf litter) into visible
## "static" -- reported in-game as grass looking like TV noise. Every frame
## must already BE the final baked tile size, so SpriteSheetSlicer's own
## Lanczos resize is the only (and only ever needs to be one) downscale
## pass, and _blit_tile's rescale-if-mismatched branch never triggers for
## illustrated tiles at all.
func test_frame_size_matches_the_final_baked_tile_size_not_an_oversized_intermediate():
	for biome_name in LAND_BIOMES:
		var frame := generator.frame_for(biome_name, 1)
		assert_eq(frame.get_width(), TerrainRenderer.ART_TILE_SIZE, biome_name)
		assert_eq(frame.get_height(), TerrainRenderer.ART_TILE_SIZE, biome_name)


func test_frame_for_returns_a_real_non_blank_frame_for_every_land_biome():
	for biome_name in LAND_BIOMES:
		var frame := generator.frame_for(biome_name, 7)
		assert_not_null(frame, "%s should have produced a frame" % biome_name)
		assert_gt(_painted_pixel_count(frame), 0, "%s frame should have real painted content" % biome_name)


## Ground tiles are full-bleed (see IllustratedTerrainSprite's own doc
## comment): unlike an isolated pebble/flower, there is no transparent
## padding around the drawing -- nearly every pixel should be opaque
## content, or the tile will show a visible transparent gap/hole once
## blitted into the atlas.
func test_frame_is_full_bleed_with_almost_no_transparent_pixels():
	for biome_name in LAND_BIOMES:
		var frame := generator.frame_for(biome_name, 3)
		var total := frame.get_width() * frame.get_height()
		var painted := _painted_pixel_count(frame)
		assert_gt(
			float(painted) / float(total), 0.95,
			"%s frame should be full-bleed, not padded like an isolated object" % biome_name
		)


func test_frame_for_has_no_leftover_magenta_for_every_land_biome():
	for biome_name in LAND_BIOMES:
		_assert_no_leftover_magenta(biome_name)


func _assert_no_leftover_magenta(biome_name: String) -> void:
	for seed_value in [1, 2, 3, 4, 5, 6, 7, 8]:
		var frame := generator.frame_for(biome_name, seed_value)
		for y in frame.get_height():
			for x in frame.get_width():
				var pixel := frame.get_pixel(x, y)
				if pixel.a < 0.05:
					continue
				var is_magenta := pixel.r >= 0.85 and pixel.b >= 0.85 and pixel.g <= 0.15
				assert_false(
					is_magenta,
					"opaque magenta leaked into a sliced %s frame at (%d,%d)" % [biome_name, x, y]
				)


func test_frame_for_is_deterministic_per_seed():
	for biome_name in LAND_BIOMES:
		assert_eq(
			generator.frame_for(biome_name, 99), generator.frame_for(biome_name, 99), biome_name
		)


## Each real sheet is a 3-row x 3-column grid: slicing must find all 9
## distinct variants, not just 3 giant blobs (one per column, spanning every
## row stacked together) the way a single-band slice over the whole sheet
## height would.
func test_sheet_slices_into_9_frames_for_every_land_biome():
	for biome_name in LAND_BIOMES:
		var frames := generator._frames_for(biome_name)
		assert_eq(frames.size(), EXPECTED_FRAME_COUNT, biome_name)


## Different seeds should spread across the full 9-variant pool, not just a
## handful of buckets -- mirrors IllustratedStoneSprite's own >50% bar.
func test_frame_for_spreads_across_variants():
	for biome_name in LAND_BIOMES:
		assert_gt(_distinct_variant_count(biome_name), EXPECTED_FRAME_COUNT / 2, biome_name)


func _distinct_variant_count(biome_name: String) -> int:
	var seen := {}
	for seed_value in 100:
		seen[generator.frame_for(biome_name, seed_value)] = true
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
## file) so this genuinely re-reads grass.png off disk rather than hitting a
## cache an earlier test already warmed.
func test_loading_a_sheet_does_not_log_an_engine_warning():
	IllustratedTerrainSprite._frame_cache.clear()
	generator.frame_for("grassland", 7)
	assert_engine_error_count(0, "loading a terrain sheet should not warn")


# -- _prepared_for_slicing / _scrub_magenta_fringe performance -------------
#
# This class's own despill loops were a SEPARATE, never-fixed duplicate of
# the exact naive per-pixel Image.get_pixel/set_pixel technique already fixed
# in SpriteSheetSlicer/IllustratedMushroomSprite/IllustratedAnimalSprite/
# IllustratedStoneSprite (see docs/progress.md's "Still at 1fps" per-pixel
# art-loading investigation, 2026-09-10) -- none of those fixes touched this
# file's own local reimplementation.
#
# Measured directly (docs/concept/character_creator_preview_scene.md's "Load
# cost" section): loading the grassland sheet costs ~987ms, of which the
# PNG decode itself is only ~36ms and _prepared_for_slicing alone is ~458ms.
# That lands squarely in the character creator's own first open -- its
# diorama stands on real grassland ground -- as well as in the first chunk
# of any real world.


## A naive per-pixel get_pixel/set_pixel despill -- the exact shape this
## class carried until it was rewritten, kept here only as a yardstick.
##
## The pin below is COMPARATIVE, not an absolute millisecond ceiling, and
## that is deliberate. An absolute ceiling measures the machine as much as
## the code: pinned at 200ms from a real 180ms measurement, this went red at
## 221ms the first time it ran on a loaded box with the implementation
## untouched, and a test that fails on a busy runner teaches people to
## ignore it. Racing the real implementation against this reference in the
## SAME process, on the SAME image, cancels the machine out -- both sides
## slow down together -- and the gap being guarded here is large enough to
## survive that honestly: 458ms against 180ms on the real grassland sheet,
## a 2.5x win, not a margin inside the noise.
static func _naively_prepared(image: Image) -> Image:
	var prepared := image.duplicate() as Image
	if prepared.get_format() != Image.FORMAT_RGBA8:
		prepared.convert(Image.FORMAT_RGBA8)
	for y in prepared.get_height():
		for x in prepared.get_width():
			var pixel := prepared.get_pixel(x, y)
			if IllustratedTerrainSprite._is_magenta(pixel):
				prepared.set_pixel(x, y, Color(pixel.r, pixel.g, pixel.b, 0.0))
			else:
				prepared.set_pixel(x, y, IllustratedTerrainSprite._despilled(pixel))
	return prepared


## Real sheet resolution (1254x1254 -- see _SHEETS' own doc comment), format
## RGB8 with no alpha channel, which is the path every real terrain sheet
## takes today. Uniform non-magenta fill: this loop has no early-out or
## bounding box, so every pixel costs the same fixed handful of comparisons
## regardless of content and a solid fill is a faithful worst case, not an
## artificially easy one.
func test_prepared_for_slicing_beats_the_naive_loop_it_replaced():
	var width := 1254
	var height := 1254
	var image := Image.create(width, height, false, Image.FORMAT_RGB8)
	image.fill(Color(0.5, 0.5, 0.5))

	var reference_start := Time.get_ticks_usec()
	var reference := _naively_prepared(image)
	var reference_usec := Time.get_ticks_usec() - reference_start
	var actual_start := Time.get_ticks_usec()
	var actual: Image = generator._prepared_for_slicing(image)
	var actual_usec := Time.get_ticks_usec() - actual_start

	assert_lt(
		actual_usec,
		reference_usec,
		(
			"_prepared_for_slicing (%dus) is no faster than the naive per-pixel loop it replaced (%dus)"
			% [actual_usec, reference_usec]
		)
	)
	assert_eq(
		actual.get_data(), reference.get_data(), "...and it must produce the identical image"
	)


## CANVAS_SIZE (32x32) -- the per-FRAME cleanup pass, called once per sliced
## frame (9 per sheet, one per variant).
func test_scrub_magenta_fringe_completes_quickly_at_real_frame_resolution():
	var image := Image.create(
		IllustratedTerrainSprite.CANVAS_SIZE.x, IllustratedTerrainSprite.CANVAS_SIZE.y, false, Image.FORMAT_RGBA8
	)
	image.fill(Color(0.5, 0.5, 0.5, 1.0))
	var start_usec := Time.get_ticks_usec()
	generator._scrub_magenta_fringe(image)
	var elapsed_ms := (Time.get_ticks_usec() - start_usec) / 1000.0
	assert_lt(
		elapsed_ms,
		5.0,
		(
			"scrubbing one %dx%d frame took %.2fms -- a naive per-pixel get_pixel/set_pixel loop regressed back in"
			% [IllustratedTerrainSprite.CANVAS_SIZE.x, IllustratedTerrainSprite.CANVAS_SIZE.y, elapsed_ms]
		)
	)


## Speed is worthless if the pixels change. Pins the three cases the loop
## actually distinguishes, against this class's OWN thresholds
## (MAGENTA_RED_MIN/MAGENTA_BLUE_MIN/MAGENTA_SKEW_MIN -- note the skew test,
## which is what makes this genuinely different from IllustratedStoneSprite's
## per-channel green-max version and why its loop cannot just be copied).
func test_prepared_for_slicing_keys_despills_and_leaves_pixels_exactly_as_before():
	var image := Image.create(3, 1, false, Image.FORMAT_RGB8)
	# A true magenta divider pixel: red and blue both over the gate, and the
	# red/blue average well clear of green.
	image.set_pixel(0, 0, Color(1.0, 0.0, 1.0))
	# A soft magenta CAST on a green-ish ground pixel: not magenta by the
	# gates above, but red and blue both sit above green by more than
	# MAGENTA_CAST_MARGIN, so the despill has to pull them down to it.
	image.set_pixel(1, 0, Color(0.5, 0.2, 0.5))
	# Clean ground: green dominant, nothing to remove.
	image.set_pixel(2, 0, Color(0.2, 0.6, 0.25))

	var prepared: Image = generator._prepared_for_slicing(image)

	assert_almost_eq(prepared.get_pixel(0, 0).a, 0.0, 0.01, "a magenta divider pixel must go transparent")
	var despilled := prepared.get_pixel(1, 0)
	assert_almost_eq(despilled.g, 0.2, 0.01, "green is never touched by the despill")
	assert_almost_eq(
		despilled.r, 0.2 + IllustratedTerrainSprite.MAGENTA_CAST_MARGIN, 0.01,
		"red is pulled down to exactly the cast margin above green"
	)
	assert_almost_eq(
		despilled.b, 0.2 + IllustratedTerrainSprite.MAGENTA_CAST_MARGIN, 0.01,
		"and so is blue"
	)
	assert_almost_eq(despilled.a, 1.0, 0.01, "a despilled pixel stays opaque")
	var clean := prepared.get_pixel(2, 0)
	assert_almost_eq(clean.r, 0.2, 0.01, "clean ground is left alone")
	assert_almost_eq(clean.g, 0.6, 0.01)
	assert_almost_eq(clean.b, 0.25, 0.01)
	assert_almost_eq(clean.a, 1.0, 0.01)
