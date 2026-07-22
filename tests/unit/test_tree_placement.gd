extends GutTest

const TreePlacement = preload("res://src/world/tree_placement.gd")

var placement: TreePlacement


func before_each():
	placement = TreePlacement.new()


func test_non_forest_biomes_never_have_trees():
	for biome_name in ["ocean", "mountain", "tundra", "grassland", "desert"]:
		for i in 20:
			assert_false(placement.has_tree_at(i * 7, i * 13, biome_name))


func test_forest_tiles_are_a_mix_of_tree_and_no_tree():
	var tree_count := 0
	var sample_size := 2000
	for i in sample_size:
		if placement.has_tree_at(i * 31, i * 17, "forest"):
			tree_count += 1
	assert_gt(tree_count, 0)
	assert_lt(tree_count, sample_size)


func test_placement_is_deterministic_for_the_same_tile():
	var first := placement.has_tree_at(12345, 6789, "forest")
	var second := placement.has_tree_at(12345, 6789, "forest")
	assert_eq(first, second)


func test_rainforest_also_gets_trees():
	var tree_count := 0
	var sample_size := 2000
	for i in sample_size:
		if placement.has_tree_at(i * 23, i * 19, "rainforest"):
			tree_count += 1
	assert_gt(tree_count, 0)
