extends GutTest

const ProceduralSpriteGenerator = preload("res://src/rendering/procedural_sprite_generator.gd")

var generator: ProceduralSpriteGenerator
var base_color := Color(0.65, 0.5, 0.2)


func before_each():
	generator = ProceduralSpriteGenerator.new()


func test_generated_image_has_the_expected_size():
	var image := generator.generate_creature_image(base_color, 1)
	assert_eq(image.get_width(), ProceduralSpriteGenerator.SIZE)
	assert_eq(image.get_height(), ProceduralSpriteGenerator.SIZE)


func test_generated_image_has_transparent_corners_outside_the_silhouette():
	var image := generator.generate_creature_image(base_color, 1)
	assert_eq(image.get_pixel(0, 0).a, 0.0)


func test_generated_image_has_an_opaque_center():
	var image := generator.generate_creature_image(base_color, 1)
	var center := ProceduralSpriteGenerator.SIZE / 2
	assert_gt(image.get_pixel(center, center).a, 0.0)


func test_generated_image_is_not_a_single_flat_color():
	var image := generator.generate_creature_image(base_color, 1)
	var distinct_colors := {}
	for y in ProceduralSpriteGenerator.SIZE:
		for x in ProceduralSpriteGenerator.SIZE:
			var pixel := image.get_pixel(x, y)
			if pixel.a > 0.0:
				distinct_colors[pixel] = true
	assert_gt(distinct_colors.size(), 1, "expected shading/outline/eyes to introduce color variety")


func test_generated_image_is_deterministic_for_the_same_inputs():
	var first := generator.generate_creature_image(base_color, 42)
	var second := generator.generate_creature_image(base_color, 42)
	for y in ProceduralSpriteGenerator.SIZE:
		for x in ProceduralSpriteGenerator.SIZE:
			assert_eq(first.get_pixel(x, y), second.get_pixel(x, y))


func test_generated_image_differs_for_a_different_seed():
	var first := generator.generate_creature_image(base_color, 1)
	var second := generator.generate_creature_image(base_color, 2)
	var any_pixel_differs := false
	for y in ProceduralSpriteGenerator.SIZE:
		for x in ProceduralSpriteGenerator.SIZE:
			if first.get_pixel(x, y) != second.get_pixel(x, y):
				any_pixel_differs = true
	assert_true(any_pixel_differs, "different seeds should produce a visibly different individual")


func test_generate_creature_texture_returns_an_image_texture():
	var texture := generator.generate_creature_texture(base_color, 1)
	assert_eq(texture.get_width(), ProceduralSpriteGenerator.SIZE)
