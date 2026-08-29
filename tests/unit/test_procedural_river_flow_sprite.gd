extends GutTest

## Per-pixel (flow-DIRECTION, flow-SPEED) data, not art -- see
## procedural_river_flow_sprite.gd and docs/concept/rivers.md. Speed added
## 2026-08-29 ("more natural water flow" -- flow speed used to be uniform
## everywhere).

const ProceduralRiverFlowSprite = preload("res://src/rendering/procedural_river_flow_sprite.gd")

var sprite: ProceduralRiverFlowSprite


func before_each():
	sprite = ProceduralRiverFlowSprite.new()


# -- direction binning --------------------------------------------------------

func test_direction_bin_for_wraps_at_360():
	assert_eq(ProceduralRiverFlowSprite.direction_bin_for(0.0), ProceduralRiverFlowSprite.direction_bin_for(360.0))


func test_direction_bin_for_covers_the_full_range():
	var bins := {}
	for i in 360:
		bins[ProceduralRiverFlowSprite.direction_bin_for(float(i))] = true
	assert_eq(bins.size(), ProceduralRiverFlowSprite.DIRECTION_BINS)


func test_angle_for_bin_round_trips_through_direction_bin_for():
	for bin in ProceduralRiverFlowSprite.DIRECTION_BINS:
		var angle := ProceduralRiverFlowSprite.angle_for_bin(bin)
		assert_eq(ProceduralRiverFlowSprite.direction_bin_for(angle), bin)


# -- speed binning --------------------------------------------------------

func test_speed_bin_for_slowest_fraction_is_the_first_bin():
	assert_eq(ProceduralRiverFlowSprite.speed_bin_for(0.0), 0)


func test_speed_bin_for_fastest_fraction_is_the_last_bin():
	assert_eq(ProceduralRiverFlowSprite.speed_bin_for(1.0), ProceduralRiverFlowSprite.SPEED_BINS - 1)


func test_speed_bin_for_increases_monotonically():
	var previous := -1
	for step in 10:
		var fraction := float(step) / 9.0
		var bin := ProceduralRiverFlowSprite.speed_bin_for(fraction)
		assert_gte(bin, previous)
		previous = bin


func test_speed_bin_for_clamps_beyond_the_unit_range():
	assert_eq(ProceduralRiverFlowSprite.speed_bin_for(5.0), ProceduralRiverFlowSprite.SPEED_BINS - 1)
	assert_eq(ProceduralRiverFlowSprite.speed_bin_for(-5.0), 0)


func test_speed_for_bin_round_trips_back_into_the_same_bin():
	for bin in ProceduralRiverFlowSprite.SPEED_BINS:
		var fraction := ProceduralRiverFlowSprite.speed_for_bin(bin)
		assert_eq(ProceduralRiverFlowSprite.speed_bin_for(fraction), bin)


# -- baked image data -----------------------------------------------------

func test_generate_image_bakes_the_normalized_angle_into_red():
	var image := sprite.generate_image(90.0, 0.5)
	var pixel := image.get_pixel(0, 0)
	# 8-bit FORMAT_RGBA8 quantizes to 1/255 steps (~0.0039) -- the same
	# byte-precision gotcha earth_elevation_source.gd's own doc comment
	# documents, not a bug in the bake itself.
	assert_almost_eq(pixel.r, 90.0 / 360.0, 0.005)
	assert_almost_eq(pixel.g, 0.5, 0.005)
	assert_eq(pixel.b, 0.0)


func test_generate_image_bakes_the_speed_fraction_into_green():
	var slow := sprite.generate_image(0.0, 0.0)
	var fast := sprite.generate_image(0.0, 1.0)
	assert_lt(slow.get_pixel(0, 0).g, fast.get_pixel(0, 0).g)


func test_generate_image_is_uniform_across_the_whole_tile():
	var image := sprite.generate_image(200.0, 0.7)
	var corner := image.get_pixel(0, 0)
	var center := image.get_pixel(ProceduralRiverFlowSprite.SIZE / 2, ProceduralRiverFlowSprite.SIZE / 2)
	assert_eq(corner, center)


func test_generate_texture_returns_a_real_texture_of_the_right_size():
	var texture := sprite.generate_texture(45.0, 0.3)
	assert_eq(texture.get_width(), ProceduralRiverFlowSprite.SIZE)
	assert_eq(texture.get_height(), ProceduralRiverFlowSprite.SIZE)
