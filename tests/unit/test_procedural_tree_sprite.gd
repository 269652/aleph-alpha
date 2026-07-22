extends GutTest

const ProceduralTreeSprite = preload("res://src/rendering/procedural_tree_sprite.gd")
const PixelPalette = preload("res://src/rendering/pixel_palette.gd")

var generator := ProceduralTreeSprite.new()


func _has_pixel(image: Image, target: Color) -> bool:
	for y in image.get_height():
		for x in image.get_width():
			var p := image.get_pixel(x, y)
			if p.a > 0.0 and Vector3(p.r, p.g, p.b).distance_to(Vector3(target.r, target.g, target.b)) < 0.01:
				return true
	return false


## Art-direction pass: the tree silhouette is ringed with the shared near-black
## cool outline so it pops against the ground.
func test_tree_uses_the_shared_dark_outline():
	var image := generator.generate_image(0.5, 1)
	assert_true(_has_pixel(image, PixelPalette.OUTLINE), "tree should use the shared outline color")


func test_generates_an_image_of_the_expected_size():
	var image := generator.generate_image(0.5, 1)
	assert_eq(image.get_width(), ProceduralTreeSprite.SIZE.x)
	assert_eq(image.get_height(), ProceduralTreeSprite.SIZE.y)


func test_canopy_area_is_greenish_and_opaque():
	var image := generator.generate_image(0.5, 1)
	var canopy_pixel := image.get_pixel(ProceduralTreeSprite.SIZE.x / 2, 2)
	assert_gt(canopy_pixel.a, 0.0)
	assert_gt(canopy_pixel.g, canopy_pixel.r)
	assert_gt(canopy_pixel.g, canopy_pixel.b)


func test_trunk_area_is_brownish_and_opaque():
	var image := generator.generate_image(0.5, 1)
	var trunk_pixel := image.get_pixel(ProceduralTreeSprite.SIZE.x / 2, ProceduralTreeSprite.SIZE.y - 2)
	assert_gt(trunk_pixel.a, 0.0)
	assert_gt(trunk_pixel.r, trunk_pixel.b)


func test_is_deterministic_for_the_same_inputs():
	var a := generator.generate_image(0.5, 7)
	var b := generator.generate_image(0.5, 7)
	assert_eq(a.get_data(), b.get_data())


func test_differs_for_a_different_seed():
	var a := generator.generate_image(0.5, 7)
	var b := generator.generate_image(0.5, 8)
	assert_ne(a.get_data(), b.get_data())


func test_a_fruit_leaning_tree_looks_different_from_a_nut_leaning_tree():
	var nut_leaning := generator.generate_image(0.0, 3)
	var fruit_leaning := generator.generate_image(1.0, 3)
	assert_ne(nut_leaning.get_data(), fruit_leaning.get_data())


func test_zero_ripe_fruit_matches_the_plain_canopy():
	var plain := generator.generate_image(1.0, 7)
	var no_fruit := generator.generate_image_with_fruit(1.0, 7, 0)
	assert_eq(no_fruit.get_data(), plain.get_data(), "no ripe fruit should look identical to the plain tree")


func _fruit_dot_pixel_count(image: Image) -> int:
	# Ripe fruit dots are drawn in a distinctly warm (reddish) colour unlike the
	# green canopy / brown trunk -- count pixels where red clearly dominates.
	var count := 0
	for y in image.get_height():
		for x in image.get_width():
			var c := image.get_pixel(x, y)
			if c.a > 0.0 and c.r > 0.55 and c.r > c.g + 0.2 and c.r > c.b + 0.2:
				count += 1
	return count


func test_ripe_fruit_adds_warm_fruit_dots_to_the_canopy():
	var some := generator.generate_image_with_fruit(1.0, 7, 3)
	assert_gt(_fruit_dot_pixel_count(some), 0, "ripe fruit should paint warm dots on the canopy")


func test_more_ripe_fruit_shows_at_least_as_many_dots_up_to_the_cap():
	var few := _fruit_dot_pixel_count(generator.generate_image_with_fruit(1.0, 7, 1))
	var many := _fruit_dot_pixel_count(generator.generate_image_with_fruit(1.0, 7, 6))
	assert_gte(many, few, "more ripe fruit should render at least as many dots")
	assert_gt(many, 0)


func test_fruit_rendering_is_deterministic():
	var a := generator.generate_image_with_fruit(0.8, 42, 4)
	var b := generator.generate_image_with_fruit(0.8, 42, 4)
	assert_eq(a.get_data(), b.get_data())
