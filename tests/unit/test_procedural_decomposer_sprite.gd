extends GutTest

const ProceduralDecomposerSprite = preload("res://src/rendering/procedural_decomposer_sprite.gd")

var generator := ProceduralDecomposerSprite.new()


func test_image_has_the_expected_size():
	var image := generator.generate_image("ant")
	assert_eq(image.get_width(), ProceduralDecomposerSprite.SIZE)
	assert_eq(image.get_height(), ProceduralDecomposerSprite.SIZE)


func test_has_transparent_corners_and_an_opaque_center():
	var image := generator.generate_image("ant")
	assert_eq(image.get_pixel(0, 0).a, 0.0)
	var mid := ProceduralDecomposerSprite.SIZE / 2
	assert_gt(image.get_pixel(mid, mid).a, 0.0)


func test_is_deterministic():
	var a := generator.generate_image("ant")
	var b := generator.generate_image("ant")
	assert_eq(a.get_data(), b.get_data())


func test_ant_and_bug_look_different():
	var ant := generator.generate_image("ant")
	var bug := generator.generate_image("bug")
	assert_ne(ant.get_data(), bug.get_data())


func test_generate_texture_returns_an_image_texture():
	var texture := generator.generate_texture("bug")
	assert_eq(texture.get_width(), ProceduralDecomposerSprite.SIZE)


func test_unknown_species_falls_back_to_a_valid_texture():
	var texture := generator.generate_texture("mystery_bug")
	assert_not_null(texture)
