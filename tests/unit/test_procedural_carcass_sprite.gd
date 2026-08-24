extends GutTest

const ProceduralCarcassSprite = preload("res://src/rendering/procedural_carcass_sprite.gd")

var generator := ProceduralCarcassSprite.new()


func test_image_has_the_expected_size():
	var image := generator.generate_image(false)
	assert_eq(image.get_width(), ProceduralCarcassSprite.SIZE)
	assert_eq(image.get_height(), ProceduralCarcassSprite.SIZE)


func test_has_transparent_corners_and_an_opaque_center():
	var image := generator.generate_image(false)
	assert_eq(image.get_pixel(0, 0).a, 0.0)
	var mid := ProceduralCarcassSprite.SIZE / 2
	assert_gt(image.get_pixel(mid, mid).a, 0.0)


func test_is_deterministic():
	var a := generator.generate_image(false)
	var b := generator.generate_image(false)
	assert_eq(a.get_data(), b.get_data())


## The stripped (post-butchering) look must actually read differently from
## the intact one -- a player watching the last cut land should see it.
func test_stripped_looks_different_from_intact():
	var intact := generator.generate_image(false)
	var stripped := generator.generate_image(true)
	assert_ne(intact.get_data(), stripped.get_data())


func test_generate_texture_returns_an_image_texture():
	var texture := generator.generate_texture(false)
	assert_eq(texture.get_width(), ProceduralCarcassSprite.SIZE)
