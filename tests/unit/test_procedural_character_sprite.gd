extends GutTest

const ProceduralCharacterSprite = preload("res://src/rendering/procedural_character_sprite.gd")
const PixelPalette = preload("res://src/rendering/pixel_palette.gd")

var generator: ProceduralCharacterSprite


func _has_pixel(image: Image, target: Color) -> bool:
	for y in image.get_height():
		for x in image.get_width():
			var p := image.get_pixel(x, y)
			if p.a > 0.0 and Vector3(p.r, p.g, p.b).distance_to(Vector3(target.r, target.g, target.b)) < 0.01:
				return true
	return false


## Art-direction pass: body parts are outlined with the shared near-black cool
## outline so the character pops against the ground (Hammerwatch readability).
func test_body_part_uses_the_shared_dark_outline():
	var image := generator.generate_body_part_image(Vector2i(10, 14), Color(0.2, 0.4, 0.8))
	assert_true(_has_pixel(image, PixelPalette.OUTLINE), "body part should use the shared outline color")


func before_each():
	generator = ProceduralCharacterSprite.new()


func test_body_part_image_has_the_requested_size():
	var image := generator.generate_body_part_image(Vector2i(10, 14), Color(0.2, 0.4, 0.8))
	assert_eq(image.get_width(), 10)
	assert_eq(image.get_height(), 14)


func test_body_part_image_is_not_a_single_flat_color():
	var image := generator.generate_body_part_image(Vector2i(10, 14), Color(0.2, 0.4, 0.8))
	var distinct := {}
	for y in image.get_height():
		for x in image.get_width():
			distinct[image.get_pixel(x, y)] = true
	assert_gt(distinct.size(), 1, "expected shading/outline to introduce color variety")


func test_body_part_image_is_deterministic():
	var a := generator.generate_body_part_image(Vector2i(10, 14), Color(0.2, 0.4, 0.8))
	var b := generator.generate_body_part_image(Vector2i(10, 14), Color(0.2, 0.4, 0.8))
	for y in a.get_height():
		for x in a.get_width():
			assert_eq(a.get_pixel(x, y), b.get_pixel(x, y))


func test_head_image_has_the_requested_size():
	var image := generator.generate_head_image(Vector2i(8, 8), Color(0.9, 0.75, 0.6), Color(0.1, 0.1, 0.1))
	assert_eq(image.get_width(), 8)
	assert_eq(image.get_height(), 8)


func test_head_image_is_shaded_not_flat():
	var image := generator.generate_head_image(Vector2i(8, 8), Color(0.9, 0.75, 0.6), Color(0.1, 0.1, 0.1))
	var distinct := {}
	for y in image.get_height():
		for x in image.get_width():
			var p := image.get_pixel(x, y)
			if p.a > 0.0:
				distinct[p] = true
	assert_gt(distinct.size(), 2, "expected shading + eyes to introduce color variety")


func test_head_image_has_transparent_corners_and_an_opaque_center():
	var image := generator.generate_head_image(Vector2i(8, 8), Color(0.9, 0.75, 0.6), Color(0.1, 0.1, 0.1))
	assert_eq(image.get_pixel(0, 0).a, 0.0)
	assert_gt(image.get_pixel(4, 4).a, 0.0)


func test_generate_body_part_texture_returns_an_image_texture():
	var texture := generator.generate_body_part_texture(Vector2i(10, 14), Color(0.2, 0.4, 0.8))
	assert_eq(texture.get_width(), 10)


func test_generate_head_texture_returns_an_image_texture():
	var texture := generator.generate_head_texture(Vector2i(8, 8), Color(0.9, 0.75, 0.6), Color(0.1, 0.1, 0.1))
	assert_eq(texture.get_width(), 8)
