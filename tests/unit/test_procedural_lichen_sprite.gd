extends GutTest

const ProceduralLichenSprite = preload("res://src/rendering/procedural_lichen_sprite.gd")

var sprite := ProceduralLichenSprite.new()


func test_image_is_16_by_16():
	var image := sprite.generate_image(1)
	assert_eq(image.get_width(), 16)
	assert_eq(image.get_height(), 16)


func test_background_corners_are_transparent():
	var image := sprite.generate_image(1)
	assert_eq(image.get_pixel(0, 0).a, 0.0)
	assert_eq(image.get_pixel(15, 0).a, 0.0)


## Lichen should read as pale grey-green/mossy, not vibrant -- opaque pixels
## should have red/green/blue components all fairly close together (low
## saturation) rather than one channel clearly dominating.
func test_contains_muted_grey_green_dominant_blade_pixels():
	var image := sprite.generate_image(1)
	var muted_pixels := 0
	for y in 16:
		for x in 16:
			var c := image.get_pixel(x, y)
			if c.a > 0.0 and c.g >= c.r and c.g >= c.b and (c.g - c.b) < 0.2:
				muted_pixels += 1
	assert_gt(muted_pixels, 5)


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
