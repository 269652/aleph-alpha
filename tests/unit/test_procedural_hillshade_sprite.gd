extends GutTest

const ProceduralHillshadeSprite = preload("res://src/rendering/procedural_hillshade_sprite.gd")

var generator: ProceduralHillshadeSprite


func before_each():
	generator = ProceduralHillshadeSprite.new()


# -- binning: quantizing continuous real slope/aspect into a small atlas --------

func test_slope_bin_for_flat_ground_is_the_first_bin():
	assert_eq(ProceduralHillshadeSprite.slope_bin_for(0.0), 0)


func test_slope_bin_for_the_steepest_slope_is_the_last_bin():
	assert_eq(
		ProceduralHillshadeSprite.slope_bin_for(ProceduralHillshadeSprite.MAX_SLOPE_DEG),
		ProceduralHillshadeSprite.SLOPE_BINS - 1
	)


func test_slope_bin_for_increases_monotonically_with_slope():
	var previous := -1
	for step in 10:
		var slope := float(step) / 9.0 * ProceduralHillshadeSprite.MAX_SLOPE_DEG
		var bin := ProceduralHillshadeSprite.slope_bin_for(slope)
		assert_gte(bin, previous)
		previous = bin


func test_slope_bin_for_clamps_beyond_the_max_slope():
	assert_eq(
		ProceduralHillshadeSprite.slope_bin_for(200.0), ProceduralHillshadeSprite.SLOPE_BINS - 1
	)


func test_aspect_bin_for_wraps_correctly():
	assert_eq(
		ProceduralHillshadeSprite.aspect_bin_for(0.0), ProceduralHillshadeSprite.aspect_bin_for(360.0)
	)


func test_aspect_bin_for_covers_every_bin_across_the_full_compass():
	var seen := {}
	for step in 360:
		seen[ProceduralHillshadeSprite.aspect_bin_for(float(step))] = true
	assert_eq(seen.size(), ProceduralHillshadeSprite.ASPECT_BINS)


func test_slope_for_bin_round_trips_back_into_the_same_bin():
	for bin in ProceduralHillshadeSprite.SLOPE_BINS:
		var slope := ProceduralHillshadeSprite.slope_for_bin(bin)
		assert_eq(ProceduralHillshadeSprite.slope_bin_for(slope), bin)


func test_aspect_for_bin_round_trips_back_into_the_same_bin():
	for bin in ProceduralHillshadeSprite.ASPECT_BINS:
		var aspect := ProceduralHillshadeSprite.aspect_for_bin(bin)
		assert_eq(ProceduralHillshadeSprite.aspect_bin_for(aspect), bin)


# -- image encoding: slope in red, aspect in green, uniform across the tile -----

func test_image_matches_the_generators_canvas_size():
	var image := generator.generate_image(30.0, 90.0)
	assert_eq(image.get_width(), ProceduralHillshadeSprite.SIZE)
	assert_eq(image.get_height(), ProceduralHillshadeSprite.SIZE)


func test_generate_image_encodes_slope_in_the_red_channel():
	var steep := generator.generate_image(80.0, 0.0)
	var gentle := generator.generate_image(5.0, 0.0)
	assert_gt(steep.get_pixel(0, 0).r, gentle.get_pixel(0, 0).r)


func test_generate_image_encodes_aspect_in_the_green_channel():
	var north := generator.generate_image(45.0, 0.0)
	var south := generator.generate_image(45.0, 180.0)
	assert_ne(north.get_pixel(0, 0).g, south.get_pixel(0, 0).g)


func test_generate_image_is_uniform_across_the_whole_tile():
	var image := generator.generate_image(37.0, 210.0)
	assert_eq(image.get_pixel(0, 0), image.get_pixel(ProceduralHillshadeSprite.SIZE - 1, ProceduralHillshadeSprite.SIZE - 1))


func test_generate_flat_image_has_zero_slope_encoding():
	var image := generator.generate_flat_image()
	assert_eq(image.get_pixel(0, 0).r, 0.0)


func test_generate_image_clamps_slope_beyond_the_max():
	var image := generator.generate_image(500.0, 0.0)
	assert_almost_eq(image.get_pixel(0, 0).r, 1.0, 0.001)
