extends GutTest

## The Sägewerk's Lumberjack NPC -- a tiny deterministic silhouette, same
## offline-art convention as ProceduralDecomposerSprite (see
## test_procedural_decomposer_sprite.gd, this file's mirror).

const ProceduralLumberjackSprite = preload("res://src/rendering/procedural_lumberjack_sprite.gd")

var generator := ProceduralLumberjackSprite.new()


func test_image_has_the_expected_size():
	var image := generator.generate_image()
	assert_eq(image.get_width(), ProceduralLumberjackSprite.SIZE)
	assert_eq(image.get_height(), ProceduralLumberjackSprite.SIZE)


func test_has_transparent_corners_and_an_opaque_center():
	var image := generator.generate_image()
	assert_eq(image.get_pixel(0, 0).a, 0.0)
	var mid := ProceduralLumberjackSprite.SIZE / 2
	assert_gt(image.get_pixel(mid, mid).a, 0.0)


func test_is_deterministic():
	var a := generator.generate_image()
	var b := generator.generate_image()
	assert_eq(a.get_data(), b.get_data())


func test_generate_texture_returns_an_image_texture():
	var texture := generator.generate_texture()
	assert_eq(texture.get_width(), ProceduralLumberjackSprite.SIZE)
