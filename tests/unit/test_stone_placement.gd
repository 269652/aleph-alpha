extends GutTest

const StonePlacement = preload("res://src/world/stone_placement.gd")
const TreePlacement = preload("res://src/world/tree_placement.gd")

var placement: StonePlacement


func before_each():
	placement = StonePlacement.new()


func test_non_stone_biomes_never_have_stones():
	for biome_name in ["ocean", "desert", "tundra", "mountain", "rainforest", "beach"]:
		for i in 20:
			assert_false(placement.has_stone_at(i * 7, i * 13, biome_name))


func test_grassland_gets_sparse_stones():
	var stone_count := 0
	var sample_size := 5000
	for i in sample_size:
		if placement.has_stone_at(i * 31, i * 17, "grassland"):
			stone_count += 1
	assert_gt(stone_count, 0)
	# Sparse: well under the tree density of 0.35
	assert_lt(stone_count, int(sample_size * 0.1))


func test_forest_also_gets_stones():
	var stone_count := 0
	for i in 5000:
		if placement.has_stone_at(i * 23, i * 19, "forest"):
			stone_count += 1
	assert_gt(stone_count, 0)


func test_placement_is_deterministic_for_the_same_tile():
	var first := placement.has_stone_at(12345, 6789, "grassland")
	var second := placement.has_stone_at(12345, 6789, "grassland")
	assert_eq(first, second)


func test_forest_stones_never_overlap_trees():
	var tree_placement := TreePlacement.new()
	for i in 5000:
		var x := i * 3
		var y := i * 5
		if placement.has_stone_at(x, y, "forest"):
			assert_false(tree_placement.has_tree_at(x, y, "forest"))


func test_stones_in_chunk_returns_only_valid_local_positions():
	var width := 32
	var height := 32
	var biome: Array = []
	for i in width * height:
		biome.append("grassland")
	var stones := placement.stones_in_chunk(Vector2i(64, -32), biome, width, height)
	assert_gt(stones.size(), 0)
	# "a few per chunk": sparse, not blanket coverage
	assert_lt(stones.size(), 40)
	for local_pos in stones:
		assert_between(local_pos.x, 0, width - 1)
		assert_between(local_pos.y, 0, height - 1)


func test_stones_in_chunk_matches_has_stone_at():
	var width := 8
	var height := 8
	var biome: Array = []
	for i in width * height:
		biome.append("grassland")
	var origin := Vector2i(160, 320)
	var stones := placement.stones_in_chunk(origin, biome, width, height)
	for y in height:
		for x in width:
			var expected := placement.has_stone_at(origin.x + x, origin.y + y, "grassland")
			assert_eq(stones.has(Vector2i(x, y)), expected)


func test_seed_at_is_deterministic_and_varies_by_tile():
	assert_eq(placement.seed_at(10, 20), placement.seed_at(10, 20))
	assert_ne(placement.seed_at(10, 20), placement.seed_at(11, 20))
