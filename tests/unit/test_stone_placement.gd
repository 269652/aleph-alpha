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


# -- pebble flocks (see docs/concept/stone.md) --------------------------------
#
# Small stone is everywhere, and not every pebble should be a lone rock: a
# pebble-class cell sometimes turns out to be a FLOCK of several pebbles
# instead of one. Cobbles and boulders never flock -- see StoneSize.

const StoneSize = preload("res://src/world/stone_size.gd")


## Only a PEBBLE-class cell can ever flock. Scans real coordinates rather than
## constructing a fake seed, so this is pinned against the real placement.
func test_only_pebble_class_stones_can_flock():
	for i in 4000:
		var x := i * 7
		var y := i * 11
		var seed_value := placement.seed_at(x, y)
		var stone_class := StoneSize.class_for(StoneSize.diameter_for(seed_value))
		if stone_class != StoneSize.CLASS_PEBBLE:
			assert_eq(
				placement.flock_size_at(x, y), 1,
				"a %s should never flock" % stone_class
			)


func test_flock_size_is_deterministic_for_the_same_tile():
	assert_eq(placement.flock_size_at(500, 900), placement.flock_size_at(500, 900))


## Every returned size is either "solitary" (1) or a real flock within the
## declared bounds -- never something in between or above the ceiling.
func test_flock_sizes_stay_within_bounds():
	for i in 4000:
		var size: int = placement.flock_size_at(i * 13, i * 17)
		if size != 1:
			assert_between(size, StonePlacement.FLOCK_MIN_MEMBERS, StonePlacement.FLOCK_MAX_MEMBERS)


## "different counts each" (the actual ask): a flock is not always the same
## size once it happens.
func test_flock_sizes_vary_not_just_one_value():
	var seen := {}
	for i in 4000:
		var size: int = placement.flock_size_at(i * 13, i * 17)
		if size != 1:
			seen[size] = true
	assert_gt(seen.size(), 1, "flocks should come in more than one size")


## Pins PEBBLE_FLOCK_CHANCE from both sides: a lone pebble must still be a
## common sight (not every pebble flocks), but a flock must be a genuinely
## regular occurrence too (not a rare easter egg) -- see the constant's own
## doc comment for why this value was picked.
func test_flocks_are_common_but_not_universal():
	var pebble_cells := 0
	var flocked := 0
	for i in 4000:
		var x := i * 13
		var y := i * 17
		var seed_value := placement.seed_at(x, y)
		if StoneSize.class_for(StoneSize.diameter_for(seed_value)) != StoneSize.CLASS_PEBBLE:
			continue
		pebble_cells += 1
		if placement.flock_size_at(x, y) > 1:
			flocked += 1
	var share := float(flocked) / float(pebble_cells)
	assert_almost_eq(share, StonePlacement.PEBBLE_FLOCK_CHANCE, 0.1)


func test_flock_member_seed_is_deterministic():
	var base := placement.seed_at(1, 1)
	assert_eq(placement.flock_member_seed(base, 2), placement.flock_member_seed(base, 2))


## Members must vary independently, the same reasoning as
## ProceduralFlowerSprite.BUSH_STEM_SEED_STRIDE -- without this every member
## would be the same pebble drawn several times.
func test_flock_member_seed_varies_by_index():
	var base := placement.seed_at(1, 1)
	var seeds := {}
	for index in StonePlacement.FLOCK_MAX_MEMBERS:
		seeds[placement.flock_member_seed(base, index)] = true
	assert_eq(seeds.size(), StonePlacement.FLOCK_MAX_MEMBERS)
