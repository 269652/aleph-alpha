extends GutTest

const OrePlacement = preload("res://src/world/ore_placement.gd")
const StonePlacement = preload("res://src/world/stone_placement.gd")

var placement: OrePlacement
var stone: StonePlacement


func before_each():
	placement = OrePlacement.new()
	stone = StonePlacement.new()


func _find_stone_cell() -> Vector2i:
	# Deterministic scan for a grassland cell that carries a plain stone.
	for y in range(0, 400):
		for x in range(0, 400):
			if stone.has_stone_at(x, y, "grassland"):
				return Vector2i(x, y)
	return Vector2i(-1, -1)


func test_ore_only_where_stone_exists():
	# Every ore cell must be a stone cell too (ore replaces a boulder).
	for y in range(0, 200):
		for x in range(0, 200):
			if placement.is_ore_at(x, y, "grassland"):
				assert_true(
					stone.has_stone_at(x, y, "grassland"),
					"ore at (%d,%d) but no stone there" % [x, y]
				)


func test_ore_is_rarer_than_plain_stone():
	var stone_count := 0
	var ore_count := 0
	for y in range(0, 300):
		for x in range(0, 300):
			if stone.has_stone_at(x, y, "grassland"):
				stone_count += 1
				if placement.is_ore_at(x, y, "grassland"):
					ore_count += 1
	assert_gt(stone_count, 0, "need some stones to sample")
	assert_gt(ore_count, 0, "expected some ore among the stones")
	assert_lt(ore_count, stone_count, "ore must be rarer than plain stone")


func test_ore_fraction_roughly_matches_constant():
	var stone_count := 0
	var ore_count := 0
	for y in range(0, 400):
		for x in range(0, 400):
			if stone.has_stone_at(x, y, "grassland"):
				stone_count += 1
				if placement.is_ore_at(x, y, "grassland"):
					ore_count += 1
	var fraction := float(ore_count) / float(stone_count)
	assert_almost_eq(fraction, OrePlacement.ORE_FRACTION, 0.12)


func test_no_ore_in_non_stone_biome():
	assert_false(placement.is_ore_at(5, 5, "ocean"))


func test_is_ore_deterministic():
	var cell := _find_stone_cell()
	assert_ne(cell.x, -1, "should have found a stone cell")
	var a := placement.is_ore_at(cell.x, cell.y, "grassland")
	var b := placement.is_ore_at(cell.x, cell.y, "grassland")
	assert_eq(a, b)


func test_ore_type_is_one_of_the_known_types():
	for y in range(0, 200):
		for x in range(0, 200):
			if placement.is_ore_at(x, y, "grassland"):
				var t := placement.ore_type_at(x, y)
				assert_true(OrePlacement.ORE_TYPES.has(t), "unknown ore type %s" % t)


func test_ore_type_deterministic():
	var a := placement.ore_type_at(17, 42)
	var b := placement.ore_type_at(17, 42)
	assert_eq(a, b)


func test_ore_type_varies_across_cells():
	var types := {}
	for y in range(0, 400):
		for x in range(0, 400):
			if placement.is_ore_at(x, y, "grassland"):
				types[placement.ore_type_at(x, y)] = true
	assert_gt(types.size(), 1, "expected more than one ore type across the map")


func test_seed_at_deterministic():
	assert_eq(placement.seed_at(3, 9), placement.seed_at(3, 9))


func test_seed_at_varies_by_cell():
	assert_ne(placement.seed_at(3, 9), placement.seed_at(4, 9))
