extends GutTest

## Real illustrated beehive art, sliced from the user-supplied
## assets/sprites/beehive.png (see tools/probe_beehive_sheet.gd,
## docs/concept/bees.md). Rows 0-1 (16 frames) are a genuine size/growth
## progression, selected by growth_stage_index -- mirrors
## IllustratedCropSprite.growth_stage_index's own "map a continuous
## fraction onto a discrete frame index" convention, NOT
## IllustratedAntMoundSprite's continuous-rescale-one-fixed-frame one.
## Row 2 (8 frames) is the harvest/destruction sequence, selected by real
## harvest-hit count via harvest_frame_index.

const IllustratedBeehiveSprite = preload("res://src/rendering/illustrated_beehive_sprite.gd")
const ProceduralBeehiveSprite = preload("res://src/rendering/procedural_beehive_sprite.gd")

const EXPECTED_GROWTH_FRAME_COUNT := 16
const EXPECTED_HARVEST_FRAME_COUNT := 8

var sprite: IllustratedBeehiveSprite


func before_each():
	sprite = IllustratedBeehiveSprite.new()


func _has_opaque_pixel(image: Image) -> bool:
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a > 0.5:
				return true
	return false


func _has_no_leftover_magenta(image: Image) -> bool:
	for y in image.get_height():
		for x in image.get_width():
			var c := image.get_pixel(x, y)
			if c.a <= 0.5:
				continue
			if c.r > 0.85 and c.b > 0.85 and c.g < 0.3:
				return false
	return true


func test_has_variants_is_true():
	assert_true(sprite.has_variants())


# -- growth sequence (rows 0-1) ----------------------------------------------

func test_sheet_slices_into_sixteen_growth_frames():
	assert_eq(sprite.growth_frame_count(), EXPECTED_GROWTH_FRAME_COUNT)


func test_growth_texture_returns_a_real_non_blank_frame():
	var texture := sprite.growth_texture(0)
	assert_not_null(texture)
	assert_true(_has_opaque_pixel(texture.get_image()))


func test_growth_texture_has_no_leftover_magenta():
	for stage in [0, 8, 15]:
		assert_true(
			_has_no_leftover_magenta(sprite.growth_texture(stage).get_image()),
			"stage %d should have no leftover magenta" % stage
		)


func test_growth_texture_clamps_an_out_of_range_stage():
	assert_eq(sprite.growth_texture(-5), sprite.growth_texture(0))
	assert_eq(sprite.growth_texture(999), sprite.growth_texture(EXPECTED_GROWTH_FRAME_COUNT - 1))


## Maps growth_fraction ([0,1], see BeeColony.growth_fraction_at) onto a
## discrete growth-sequence frame index -- mirrors IllustratedCropSprite.
## growth_stage_index's own shape exactly, just proportional across 16
## real steps rather than 3 named ones.
func test_growth_stage_index_is_zero_at_zero_growth():
	assert_eq(IllustratedBeehiveSprite.growth_stage_index(0.0), 0)


func test_growth_stage_index_is_the_last_frame_at_full_growth():
	assert_eq(IllustratedBeehiveSprite.growth_stage_index(1.0), EXPECTED_GROWTH_FRAME_COUNT - 1)


func test_growth_stage_index_is_monotonic():
	var previous := -1
	var steps := 40
	for i in steps + 1:
		var index := IllustratedBeehiveSprite.growth_stage_index(float(i) / float(steps))
		assert_gte(index, previous)
		previous = index


func test_growth_stage_index_clamps_out_of_range_growth():
	assert_eq(IllustratedBeehiveSprite.growth_stage_index(2.0), EXPECTED_GROWTH_FRAME_COUNT - 1)
	assert_eq(IllustratedBeehiveSprite.growth_stage_index(-1.0), 0)


# -- harvest/destruction sequence (row 2) ------------------------------------

func test_sheet_slices_into_eight_harvest_frames():
	assert_eq(sprite.harvest_frame_count(), EXPECTED_HARVEST_FRAME_COUNT)


func test_harvest_texture_returns_a_real_non_blank_frame():
	var texture := sprite.harvest_texture(0)
	assert_not_null(texture)
	assert_true(_has_opaque_pixel(texture.get_image()))


func test_harvest_texture_has_no_leftover_magenta():
	for stage in [0, 4, 7]:
		assert_true(
			_has_no_leftover_magenta(sprite.harvest_texture(stage).get_image()),
			"harvest frame %d should have no leftover magenta" % stage
		)


func test_growth_and_harvest_frames_are_two_genuinely_different_pools():
	assert_ne(sprite.growth_texture(15), sprite.harvest_texture(0))


## The first landed hit shows the first, barely-damaged destruction
## frame; the final hit (matching HARVEST_HITS_TO_DESTROY, see bees.md)
## shows the last, nearly-gone one -- 1-indexed "hits landed so far",
## since 0 hits landed means harvesting hasn't started at all (the
## marker shows a growth frame, not a harvest one, at that point).
func test_harvest_frame_index_is_zero_after_the_first_hit():
	assert_eq(IllustratedBeehiveSprite.harvest_frame_index(1), 0)


func test_harvest_frame_index_is_the_last_frame_at_the_final_hit():
	assert_eq(IllustratedBeehiveSprite.harvest_frame_index(EXPECTED_HARVEST_FRAME_COUNT), EXPECTED_HARVEST_FRAME_COUNT - 1)


func test_harvest_frame_index_clamps_out_of_range_hit_counts():
	assert_eq(IllustratedBeehiveSprite.harvest_frame_index(0), 0)
	assert_eq(IllustratedBeehiveSprite.harvest_frame_index(999), EXPECTED_HARVEST_FRAME_COUNT - 1)


# -- world-scale (shared with the procedural fallback) -----------------------

func test_marker_scale_is_positive():
	assert_gt(sprite.marker_scale(0.0), 0.0)
	assert_gt(sprite.marker_scale(1.0), 0.0)


func test_marker_scale_grows_with_growth_fraction():
	assert_gt(sprite.marker_scale(1.0), sprite.marker_scale(0.0))


## Illustrated art must land at the SAME real-world size the procedural
## hive already uses at any given growth_fraction, so swapping the art in
## doesn't suddenly grow/shrink every hive already placed in the world --
## mirrors test_illustrated_ant_mound_sprite.gd's own identical contract.
func test_marker_scale_produces_the_procedural_hives_own_world_width():
	var image: Image = sprite.growth_texture(0).get_image()
	var min_x := image.get_width()
	var max_x := -1
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a > 0.0:
				min_x = mini(min_x, x)
				max_x = maxi(max_x, x)
	var opaque_width := float(max_x - min_x + 1)
	for growth_fraction in [0.0, 0.5, 1.0]:
		assert_almost_eq(
			opaque_width * sprite.marker_scale(growth_fraction),
			ProceduralBeehiveSprite.world_width_for(growth_fraction), 1.0
		)
