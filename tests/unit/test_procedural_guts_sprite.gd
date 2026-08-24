extends GutTest

const ProceduralGutsSprite = preload("res://src/rendering/procedural_guts_sprite.gd")

var generator := ProceduralGutsSprite.new()


func test_image_has_the_expected_size():
	var image := generator.generate_image()
	assert_eq(image.get_width(), ProceduralGutsSprite.SIZE)
	assert_eq(image.get_height(), ProceduralGutsSprite.SIZE)


func test_has_transparent_corners_and_an_opaque_center():
	var image := generator.generate_image()
	assert_eq(image.get_pixel(0, 0).a, 0.0)
	var mid := ProceduralGutsSprite.SIZE / 2
	assert_gt(image.get_pixel(mid, mid).a, 0.0)


func test_is_deterministic():
	var a := generator.generate_image()
	var b := generator.generate_image()
	assert_eq(a.get_data(), b.get_data())


func test_generate_texture_returns_an_image_texture():
	var texture := generator.generate_texture()
	assert_eq(texture.get_width(), ProceduralGutsSprite.SIZE)
