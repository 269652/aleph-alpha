extends GutTest

const IllustratedGrassPatch = preload("res://src/rendering/illustrated_grass_patch.gd")


func test_each_seed_selects_one_tile_inside_the_delivered_10x10_atlas():
	var rect := IllustratedGrassPatch.atlas_region_for_seed(42)
	assert_between(rect.size.x, 125, 126)
	assert_between(rect.size.y, 125, 126)
	assert_gte(rect.position.x, 0)
	assert_gte(rect.position.y, 0)
	assert_lt(rect.position.x, 1254)
	assert_lt(rect.position.y, 1254)


func test_a_patch_has_multiple_deterministically_placed_blade_cards():
	var first := IllustratedGrassPatch.card_specs_for_seed(42)
	assert_eq(first, IllustratedGrassPatch.card_specs_for_seed(42))
	assert_gte(first.size(), 3)
	assert_gt(first[0].depth, first[first.size() - 1].depth)


func test_shader_keeps_roots_planted_and_bends_for_a_nearby_walker():
	assert_string_contains(IllustratedGrassPatch.SHADER_CODE, "player_world_position")
	assert_string_contains(IllustratedGrassPatch.SHADER_CODE, "UV.y")
	assert_string_contains(IllustratedGrassPatch.SHADER_CODE, "walker_radius")
