extends GutTest

const ProceduralGrassSprite = preload("res://src/rendering/procedural_grass_sprite.gd")

var sprite := ProceduralGrassSprite.new()


func test_image_is_16_by_16():
	var image := sprite.generate_image(1)
	assert_eq(image.get_width(), 16)
	assert_eq(image.get_height(), 16)


func test_background_corners_are_transparent():
	var image := sprite.generate_image(1)
	assert_eq(image.get_pixel(0, 0).a, 0.0)
	assert_eq(image.get_pixel(15, 0).a, 0.0)


func test_contains_green_dominant_blade_pixels():
	var image := sprite.generate_image(1)
	var green_pixels := 0
	for y in 16:
		for x in 16:
			var c := image.get_pixel(x, y)
			if c.a > 0.0 and c.g > c.r and c.g > c.b:
				green_pixels += 1
	assert_gt(green_pixels, 5)


func test_is_deterministic_for_the_same_seed():
	var a := sprite.generate_image(42)
	var b := sprite.generate_image(42)
	assert_eq(a.get_data(), b.get_data())


func test_different_seeds_produce_different_tufts():
	var a := sprite.generate_image(1)
	var b := sprite.generate_image(2)
	assert_ne(a.get_data(), b.get_data())


func test_generate_texture_returns_an_image_texture():
	var texture := sprite.generate_texture(1)
	assert_true(texture is ImageTexture)
