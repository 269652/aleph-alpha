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
