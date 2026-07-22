extends GutTest

const ProceduralStoneSprite = preload("res://src/rendering/procedural_stone_sprite.gd")
const PixelPalette = preload("res://src/rendering/pixel_palette.gd")

var generator: ProceduralStoneSprite


func _has_pixel(image: Image, target: Color) -> bool:
	for y in image.get_height():
		for x in image.get_width():
			var p := image.get_pixel(x, y)
			if p.a > 0.0 and Vector3(p.r, p.g, p.b).distance_to(Vector3(target.r, target.g, target.b)) < 0.01:
				return true
	return false


## Art-direction pass: the boulder silhouette is ringed with the shared
## near-black cool outline so it pops against the ground.
func test_boulder_uses_the_shared_dark_outline():
	var image := generator.generate_image(42)
	assert_true(_has_pixel(image, PixelPalette.OUTLINE), "boulder should use the shared outline color")


func before_each():
	generator = ProceduralStoneSprite.new()


func test_image_is_16_by_16():
	var image := generator.generate_image(42)
	assert_eq(image.get_width(), 16)
	assert_eq(image.get_height(), 16)


func test_image_has_transparent_background_and_opaque_boulder():
	var image := generator.generate_image(42)
	var opaque := 0
	var transparent := 0
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a > 0.5:
				opaque += 1
			else:
				transparent += 1
	assert_gt(opaque, 20)
	assert_gt(transparent, 20)


func test_boulder_pixels_are_grey():
	var image := generator.generate_image(7)
	for y in image.get_height():
		for x in image.get_width():
			var color := image.get_pixel(x, y)
			if color.a > 0.5:
				assert_almost_eq(color.r, color.g, 0.05)
				assert_almost_eq(color.g, color.b, 0.05)


func test_same_seed_produces_identical_image():
	var a := generator.generate_image(123)
	var b := generator.generate_image(123)
	assert_eq(a.get_data(), b.get_data())


func test_different_seeds_produce_different_images():
	var a := generator.generate_image(1)
	var b := generator.generate_image(2)
	assert_ne(a.get_data(), b.get_data())


func test_boulder_is_shaded_with_multiple_grey_tones():
	var image := generator.generate_image(42)
	var tones := {}
	for y in image.get_height():
		for x in image.get_width():
			var color := image.get_pixel(x, y)
			if color.a > 0.5:
				tones[color.to_html()] = true
	assert_gt(tones.size(), 2)


func test_generate_texture_wraps_image():
	var texture := generator.generate_texture(42)
	assert_not_null(texture)
	assert_eq(texture.get_width(), 16)
	assert_eq(texture.get_height(), 16)
