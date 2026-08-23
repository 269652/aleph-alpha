extends GutTest

const ProceduralGrassSprite = preload("res://src/rendering/procedural_grass_sprite.gd")

var sprite := ProceduralGrassSprite.new()


func test_image_matches_the_generators_canvas_size():
	var image := sprite.generate_image(1)
	assert_eq(image.get_width(), ProceduralGrassSprite.SIZE.x)
	assert_eq(image.get_height(), ProceduralGrassSprite.SIZE.y)


func test_background_corners_are_transparent():
	var image := sprite.generate_image(1)
	assert_eq(image.get_pixel(0, 0).a, 0.0)
	assert_eq(image.get_pixel(ProceduralGrassSprite.SIZE.x - 1, 0).a, 0.0)


func test_contains_green_dominant_blade_pixels():
	var image := sprite.generate_image(1)
	var green_pixels := 0
	for y in ProceduralGrassSprite.SIZE.y:
		for x in ProceduralGrassSprite.SIZE.x:
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


## world_scale_for_seed must always land within the variants' declared
## 0.75..1.5 tile range, and must agree with variant_for_seed for the same
## seed (single source of truth for which variant a seed rolls).
func test_world_scale_for_seed_stays_within_the_variant_height_range():
	var min_tiles: float = ProceduralGrassSprite.VARIANTS[0].world_tiles
	var max_tiles: float = ProceduralGrassSprite.VARIANTS[ProceduralGrassSprite.VARIANTS.size() - 1].world_tiles
	for seed_value in 40:
		var scale := ProceduralGrassSprite.world_scale_for_seed(seed_value)
		var rendered_height := scale * ProceduralGrassSprite.SIZE.y
		assert_between(
			rendered_height, ProceduralGrassSprite.WORLD_WIDTH * min_tiles, ProceduralGrassSprite.WORLD_WIDTH * max_tiles
		)


func test_world_scale_for_seed_matches_the_rolled_variants_world_tiles():
	for seed_value in 20:
		var variant := ProceduralGrassSprite.variant_for_seed(seed_value)
		var expected_height: float = (
			ProceduralGrassSprite.WORLD_WIDTH * float(ProceduralGrassSprite.VARIANTS[variant].world_tiles)
		)
		var actual_height := ProceduralGrassSprite.world_scale_for_seed(seed_value) * ProceduralGrassSprite.SIZE.y
		assert_almost_eq(actual_height, expected_height, 0.01)


func test_generate_texture_returns_an_image_texture():
	var texture := sprite.generate_texture(1)
	assert_true(texture is ImageTexture)
