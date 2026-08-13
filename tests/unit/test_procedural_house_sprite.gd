extends GutTest

## ProceduralHouseSprite: village house art (see VillageRenderer). Reworked
## from the original one-size 20x20 cottage (smaller than the villager
## itself, near-identical across a village -- the reported "tiny houselike
## buildings... all the same") to 3 real house sizes, seeded wall/roof
## palettes, windows, and chimneys -- so a village reads as a settlement of
## individual homes.

const ProceduralHouseSprite = preload("res://src/rendering/procedural_house_sprite.gd")
const VillageRenderer = preload("res://src/rendering/village_renderer.gd")

var generator := ProceduralHouseSprite.new()


func test_image_size_matches_size_for_and_comes_from_the_pinned_pool():
	for seed_value in range(12):
		var size := generator.size_for(seed_value)
		assert_has(ProceduralHouseSprite.SIZES, size)
		var image := generator.generate_image(seed_value)
		assert_eq(Vector2i(image.get_width(), image.get_height()), size)


## The report: houses were smaller than the NPC standing next to them. Every
## house size must comfortably exceed a villager (body + head, see
## VillageRenderer.BODY_SIZE/HEAD_SIZE).
func test_every_house_size_is_clearly_bigger_than_a_villager():
	var villager_height := VillageRenderer.BODY_SIZE.y + VillageRenderer.HEAD_SIZE.y
	for size in ProceduralHouseSprite.SIZES:
		assert_gte(size.x, VillageRenderer.BODY_SIZE.x * 2, "house should be at least twice as wide as a villager")
		assert_gte(size.y, villager_height, "house should be at least as tall as a full villager")


func test_is_deterministic_for_the_same_seed():
	var a := generator.generate_image(9)
	var b := generator.generate_image(9)
	assert_eq(a.get_data(), b.get_data())


func test_different_seeds_produce_different_houses():
	var a := generator.generate_image(1)
	var b := generator.generate_image(2)
	assert_ne(a.get_data(), b.get_data())


## "They shouldn't look all the same": across enough seeds, houses must vary
## in size AND wall color AND roof color -- via the pinned seeded functions,
## not an eyeballed sample of pixels.
func test_houses_vary_in_size_wall_and_roof_across_seeds():
	var sizes := {}
	var walls := {}
	var roofs := {}
	for seed_value in range(30):
		sizes[generator.size_for(seed_value)] = true
		walls[generator.wall_color_for(seed_value)] = true
		roofs[generator.roof_color_for(seed_value)] = true
	assert_gt(sizes.size(), 1, "houses should come in more than one size")
	assert_gt(walls.size(), 1, "houses should come in more than one wall color")
	assert_gt(roofs.size(), 1, "houses should come in more than one roof color")


func test_has_transparent_corners_and_an_opaque_body():
	var image := generator.generate_image(0)
	assert_eq(image.get_pixel(0, 0).a, 0.0)
	var mid := Vector2i(image.get_width() / 2, image.get_height() - 3)
	assert_gt(image.get_pixel(mid.x, mid.y).a, 0.0)


## The rendered house actually uses its seed's palette: at least one pixel
## near the seeded wall color and one near the seeded roof color. The wall
## tolerance derives from _WALL_JITTER_RANGE (each house's walls are
## deliberately lightened/darkened up to half that range for individuality);
## the roof is unjittered so only 8-bit quantization applies.
func test_image_carries_its_seeds_wall_and_roof_colors():
	var wall_tolerance: float = ProceduralHouseSprite._WALL_JITTER_RANGE + 0.02
	for seed_value in [0, 7, 13]:
		var image := generator.generate_image(seed_value)
		assert_true(
			_has_color_near(image, generator.wall_color_for(seed_value), wall_tolerance),
			"seed %d image should contain (a jittered shade of) its wall color" % seed_value
		)
		assert_true(
			_has_color_near(image, generator.roof_color_for(seed_value), 0.04),
			"seed %d image should contain its roof color" % seed_value
		)


func test_generate_texture_returns_an_image_texture():
	var texture := generator.generate_texture(3)
	assert_eq(texture.get_width(), generator.size_for(3).x)


func _has_color_near(image: Image, target: Color, tolerance: float = 0.04) -> bool:
	for y in image.get_height():
		for x in image.get_width():
			var p := image.get_pixel(x, y)
			if p.a > 0.0 and Vector3(p.r, p.g, p.b).distance_to(Vector3(target.r, target.g, target.b)) < tolerance:
				return true
	return false
