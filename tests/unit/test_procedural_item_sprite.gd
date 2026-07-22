extends GutTest

const ProceduralItemSprite = preload("res://src/rendering/procedural_item_sprite.gd")
const PixelPalette = preload("res://src/rendering/pixel_palette.gd")

var generator: ProceduralItemSprite


func _has_pixel(image: Image, target: Color) -> bool:
	# Images are RGBA8, so compare against the 8-bit-quantized target.
	for y in ProceduralItemSprite.SIZE:
		for x in ProceduralItemSprite.SIZE:
			var p := image.get_pixel(x, y)
			if p.a > 0.0 and Vector3(p.r, p.g, p.b).distance_to(Vector3(target.r, target.g, target.b)) < 0.01:
				return true
	return false


func before_each():
	generator = ProceduralItemSprite.new()


func test_image_has_the_expected_size():
	var image := generator.generate_image("hide")
	assert_eq(image.get_width(), ProceduralItemSprite.SIZE)
	assert_eq(image.get_height(), ProceduralItemSprite.SIZE)


func test_has_transparent_corners_and_an_opaque_center():
	var image := generator.generate_image("meat")
	assert_eq(image.get_pixel(0, 0).a, 0.0)
	var mid := ProceduralItemSprite.SIZE / 2
	assert_gt(image.get_pixel(mid, mid).a, 0.0)


func test_is_not_a_single_flat_color():
	var image := generator.generate_image("fang")
	var distinct := {}
	for y in ProceduralItemSprite.SIZE:
		for x in ProceduralItemSprite.SIZE:
			var p := image.get_pixel(x, y)
			if p.a > 0.0:
				distinct[p] = true
	assert_gt(distinct.size(), 1, "expected shading to introduce color variety")


func test_is_deterministic_for_the_same_item():
	var a := generator.generate_image("wooden_club")
	var b := generator.generate_image("wooden_club")
	for y in ProceduralItemSprite.SIZE:
		for x in ProceduralItemSprite.SIZE:
			assert_eq(a.get_pixel(x, y), b.get_pixel(x, y))


func test_different_items_look_different():
	var fruit := generator.generate_image("fruit")
	var sword := generator.generate_image("wooden_club")
	var any_differs := false
	for y in ProceduralItemSprite.SIZE:
		for x in ProceduralItemSprite.SIZE:
			if fruit.get_pixel(x, y) != sword.get_pixel(x, y):
				any_differs = true
	assert_true(any_differs, "distinct item ids should render distinctly")


func test_unknown_item_id_still_produces_a_valid_sprite():
	var image := generator.generate_image("some_new_item")
	assert_eq(image.get_width(), ProceduralItemSprite.SIZE)
	var mid := ProceduralItemSprite.SIZE / 2
	assert_gt(image.get_pixel(mid, mid).a, 0.0)


## Art-direction pass: rounded items are ringed by the shared near-black cool
## outline so they pop against the ground (Hammerwatch readability).
func test_rounded_item_uses_the_shared_dark_outline():
	var image := generator.generate_image("fruit")
	assert_true(_has_pixel(image, PixelPalette.OUTLINE), "fruit should be ringed by the shared outline color")


func test_generate_texture_returns_an_image_texture():
	var texture := generator.generate_texture("hide")
	assert_eq(texture.get_width(), ProceduralItemSprite.SIZE)


func test_axe_renders_a_valid_distinct_sprite():
	var axe := generator.generate_image("iron_axe")
	assert_eq(axe.get_width(), ProceduralItemSprite.SIZE)
	var mid := ProceduralItemSprite.SIZE / 2
	assert_gt(axe.get_pixel(mid, mid).a, 0.0)


func test_axe_has_its_own_look_rather_than_falling_back_to_the_generic_pebble():
	var axe := generator.generate_image("iron_axe")
	var fallback := generator.generate_image("some_totally_unknown_item")
	var any_differs := false
	for y in ProceduralItemSprite.SIZE:
		for x in ProceduralItemSprite.SIZE:
			if axe.get_pixel(x, y) != fallback.get_pixel(x, y):
				any_differs = true
	assert_true(any_differs, "iron_axe should have a dedicated look, not the unknown-item fallback")


func test_axe_looks_different_from_a_sword():
	var axe := generator.generate_image("iron_axe")
	var sword := generator.generate_image("iron_sword")
	var any_differs := false
	for y in ProceduralItemSprite.SIZE:
		for x in ProceduralItemSprite.SIZE:
			if axe.get_pixel(x, y) != sword.get_pixel(x, y):
				any_differs = true
	assert_true(any_differs, "an axe should not render identically to a sword")


func test_crafted_items_have_their_own_look_rather_than_the_generic_fallback():
	var fallback := generator.generate_image("some_totally_unknown_item")
	for item_id in ["torch", "campfire", "cooked_meat"]:
		var image := generator.generate_image(item_id)
		var any_differs := false
		for y in ProceduralItemSprite.SIZE:
			for x in ProceduralItemSprite.SIZE:
				if image.get_pixel(x, y) != fallback.get_pixel(x, y):
					any_differs = true
		assert_true(any_differs, "%s should have a dedicated look, not the unknown-item fallback" % item_id)


func test_cooked_meat_looks_different_from_raw_meat():
	var raw := generator.generate_image("meat")
	var cooked := generator.generate_image("cooked_meat")
	var any_differs := false
	for y in ProceduralItemSprite.SIZE:
		for x in ProceduralItemSprite.SIZE:
			if raw.get_pixel(x, y) != cooked.get_pixel(x, y):
				any_differs = true
	assert_true(any_differs, "cooked meat should look different from raw meat")


func test_knapping_chain_items_have_distinct_non_fallback_art():
	var fallback_data: PackedByteArray = generator.generate_image("definitely_unknown_item").get_data()
	for item_id in ["rock", "stick", "sharp_shard", "plant_fibre", "crude_blade"]:
		var image := generator.generate_image(item_id)
		assert_ne(image.get_data(), fallback_data, "%s should have its own look, not the fallback" % item_id)


func test_leather_armor_pieces_have_distinct_non_fallback_art():
	var fallback: PackedByteArray = generator.generate_image("definitely_unknown_armor").get_data()
	for item_id in ["leather_helm", "leather_chest", "leather_legs", "leather_boots"]:
		assert_ne(generator.generate_image(item_id).get_data(), fallback, "%s needs its own art" % item_id)


func test_smelting_items_have_distinct_non_fallback_art():
	var fallback: PackedByteArray = generator.generate_image("definitely_unknown_ingot").get_data()
	for item_id in ["iron_ingot", "copper_ingot", "furnace",
			"iron_helm", "iron_chest", "iron_legs", "iron_boots"]:
		assert_ne(generator.generate_image(item_id).get_data(), fallback, "%s needs its own art" % item_id)


func test_fishing_rod_has_non_fallback_art():
	var fallback: PackedByteArray = generator.generate_image("definitely_unknown_rod").get_data()
	assert_ne(generator.generate_image("fishing_rod").get_data(), fallback)
