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


## Placeable structures (see item_catalog.gd's "placeable" kind) previously
## reused the generic "oval"/"armor" blob shapes -- which only ever shade ONE
## base hue (highlight/shadow of the same color), so a campfire was just an
## orange blob (indistinguishable in SILHOUETTE from fruit/hide/any other oval
## item) and a furnace was just a grey chestplate. They now get dedicated,
## genuinely multi-toned shapes: a campfire needs a brown log color AND a
## separate warm flame color; a furnace needs a grey stone color AND a
## separate glowing firebox color -- something no single-hue blob/plate shade
## can ever produce, so this can't accidentally pass against the old shapes.
func _has_hue_family_pixel(image: Image, predicate: Callable) -> bool:
	for y in ProceduralItemSprite.SIZE:
		for x in ProceduralItemSprite.SIZE:
			var p := image.get_pixel(x, y)
			if p.a > 0.0 and predicate.call(p):
				return true
	return false


func test_campfire_has_both_a_log_brown_pixel_and_a_separate_flame_colored_pixel():
	var image := generator.generate_image("campfire")
	var is_log_brown := func(p: Color) -> bool: return p.r > 0.25 and p.r < 0.6 and p.g < p.r and p.b < p.g + 0.05
	var is_flame := func(p: Color) -> bool: return p.r > 0.7 and p.g > 0.25 and p.b < 0.3
	assert_true(_has_hue_family_pixel(image, is_log_brown), "campfire should have a distinct log/wood-brown pixel")
	assert_true(_has_hue_family_pixel(image, is_flame), "campfire should have a distinct warm flame pixel")


func test_furnace_has_both_a_grey_stone_pixel_and_a_separate_glowing_firebox_pixel():
	var image := generator.generate_image("furnace")
	var is_grey_stone := func(p: Color) -> bool: return absf(p.r - p.g) < 0.08 and absf(p.g - p.b) < 0.08
	var is_glow := func(p: Color) -> bool: return p.r > 0.6 and p.g > 0.2 and p.b < 0.35
	assert_true(_has_hue_family_pixel(image, is_grey_stone), "furnace should have a distinct grey stone pixel")
	assert_true(_has_hue_family_pixel(image, is_glow), "furnace should have a distinct glowing firebox pixel")


# -- named fruit tree items (see TreeSpecies) --------------------------------
#
# Cherry/apple/walnut each need their own distinct look -- fallen fruit is a
# rendered, visible ground entity per docs/concept/flora.md, and the whole
## point of a named species is that it reads as a DIFFERENT thing lying on
## the ground, not just another red "fruit" blob.

func test_named_tree_fruit_items_have_distinct_non_fallback_art():
	var fallback: PackedByteArray = generator.generate_image("definitely_unknown_tree_fruit").get_data()
	for item_id in ["cherry", "apple", "walnut"]:
		assert_ne(generator.generate_image(item_id).get_data(), fallback, "%s needs its own art" % item_id)


func test_named_tree_fruit_items_look_different_from_each_other():
	var cherry := generator.generate_image("cherry")
	var apple := generator.generate_image("apple")
	var walnut := generator.generate_image("walnut")
	assert_ne(cherry.get_data(), apple.get_data())
	assert_ne(apple.get_data(), walnut.get_data())
	assert_ne(cherry.get_data(), walnut.get_data())


func test_campfire_and_furnace_look_different_from_each_other_and_from_generic_shapes():
	var campfire := generator.generate_image("campfire")
	var furnace := generator.generate_image("furnace")
	var fruit := generator.generate_image("fruit")
	var armor := generator.generate_image("leather_chest")

	var any_differs := func(a: Image, b: Image) -> bool:
		for y in ProceduralItemSprite.SIZE:
			for x in ProceduralItemSprite.SIZE:
				if a.get_pixel(x, y) != b.get_pixel(x, y):
					return true
		return false

	assert_true(any_differs.call(campfire, furnace), "campfire and furnace should look different from each other")
	assert_true(any_differs.call(campfire, fruit), "campfire should no longer reuse the generic oval/fruit look")
	assert_true(any_differs.call(furnace, armor), "furnace should no longer reuse the generic armor-plate look")


# -- ground size: fruit against a reference the player can see --------------
#
# Every dropped item rendered at a full 16px tile, so a fallen cherry was as
# wide as the ground square under it (reported: "they are gigantic").

## A butterfly-wide walnut still read as too chunky next to a creature in the
## world, so the whole fruit family halved again -- a walnut is now half a
## butterfly across, and the ratios below carry cherry, apple and nut with it.
func test_a_walnut_is_half_the_width_of_a_butterfly():
	var walnut := ProceduralItemSprite.world_scale_for("walnut") * ProceduralItemSprite.SIZE
	assert_almost_eq(walnut, ProceduralItemSprite.BUTTERFLY_WORLD_WIDTH * 0.5, 0.01)


## The three fruit keep real proportions relative to each other -- asserted
## as RATIOS so re-sizing the walnut carries the other two with it.
func test_fruit_keep_their_proportions_to_each_other():
	var walnut := ProceduralItemSprite.world_scale_for("walnut")
	var cherry := ProceduralItemSprite.world_scale_for("cherry")
	var apple := ProceduralItemSprite.world_scale_for("apple")
	assert_almost_eq(cherry / walnut, 0.8, 0.01, "a cherry is smaller than a walnut")
	assert_almost_eq(apple / walnut, 2.0, 0.01, "an apple is a good deal bigger")


## The generic "nut" an ambient (unnamed) tree drops is the smallest of the
## family -- a hazelnut-ish thing rather than a walnut.
func test_a_generic_nut_is_smaller_than_a_cherry():
	var cherry := ProceduralItemSprite.world_scale_for("cherry")
	var nut := ProceduralItemSprite.world_scale_for("nut")
	assert_almost_eq(nut / cherry, 0.8, 0.01, "a nut is 0.8 of a cherry")


## The ambient (far-from-player) forage tier drops the generic "fruit"/"nut"
## pair; sizing only the nut would leave a tile-wide fruit lying next to a
## speck of a nut, which is the same bug that started this.
func test_the_generic_fruit_matches_the_named_fruit_it_stands_in_for():
	assert_almost_eq(
		ProceduralItemSprite.world_scale_for("fruit"),
		ProceduralItemSprite.world_scale_for("cherry"),
		0.001
	)


func test_every_fruit_is_well_under_a_tile_wide():
	for fruit in ["walnut", "cherry", "apple", "nut", "fruit"]:
		var width := ProceduralItemSprite.world_scale_for(fruit) * ProceduralItemSprite.SIZE
		assert_lt(width, ProceduralItemSprite.TILE_SIZE, "%s must not fill its own tile" % fruit)


## Only fruit was wrong; tools and resources keep the size they always had.
func test_a_non_fruit_item_keeps_its_previous_size():
	assert_almost_eq(ProceduralItemSprite.world_scale_for("stone"), 0.5, 0.001)


# -- texture reuse ------------------------------------------------------------
#
# Item art is a pure function of the item id, but every DroppedItem that
# entered the scene rebuilt its own 32x32 image pixel by pixel and wrapped it
# in a fresh ImageTexture. That was invisible while a handful of items lay
# around and expensive once the world was dropping windfall continuously (see
# FruitingModel.BEARING_CYCLE_SECONDS).

## The cache is shared across generator INSTANCES, since two DroppedItems
## each holding their own generator is exactly the case that was rebuilding
## the same apple over and over.
func test_the_same_item_hands_back_the_same_texture():
	var first = ProceduralItemSprite.new().texture_for("apple")
	var second = ProceduralItemSprite.new().texture_for("apple")
	assert_same(first, second, "one apple texture, however many apples are on the ground")


func test_different_items_still_get_their_own_texture():
	var g = ProceduralItemSprite.new()
	assert_not_same(g.texture_for("apple"), g.texture_for("walnut"))


func test_a_cached_texture_still_matches_the_generated_art():
	var g = ProceduralItemSprite.new()
	assert_eq(g.texture_for("cherry").get_image().get_data(), g.generate_image("cherry").get_data())


# -- taming gear art (see docs/concept/taming.md) -----------------------------
#
# An item with no entry falls back to a generic grey pebble, which is fine as
# a crash-guard for an unknown id and wrong for an item the player crafts on
# purpose and carries in hand.

func test_the_lasso_and_carrot_do_not_render_as_the_fallback_pebble():
	var generator = ProceduralItemSprite.new()
	var pebble := generator.generate_image("a_totally_unknown_item").get_data()
	for item_id in ["lasso", "carrot"]:
		assert_ne(generator.generate_image(item_id).get_data(), pebble, "%s needs its own look" % item_id)


func test_a_carrot_reads_orange():
	var carrot: Color = ProceduralItemSprite.color_for("carrot")
	assert_gt(carrot.r, carrot.g, "warmer than it is green")
	assert_gt(carrot.g, carrot.b, "and orange rather than red")


## Rope, not vegetation: the lasso must not read as a bundle of plant fibre
## sitting next to plant fibre in the inventory.
func test_the_lasso_does_not_read_as_the_fibre_it_is_braided_from():
	assert_ne(ProceduralItemSprite.color_for("lasso"), ProceduralItemSprite.color_for("plant_fibre"))
