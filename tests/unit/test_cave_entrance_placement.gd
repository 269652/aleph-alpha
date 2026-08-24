extends GutTest

## CaveEntrancePlacement: sparse, deterministic, mountain-biome-weighted
## cave-mouth placement, mirroring StonePlacement/OrePlacement's own
## coordinate-hash convention (see docs/concept/geology.md "Cave
## entrances").

const CaveEntrancePlacement = preload("res://src/world/cave_entrance_placement.gd")

var placement: CaveEntrancePlacement


func before_each():
	placement = CaveEntrancePlacement.new()


func _count_entrances(biome_name: String, span: int) -> int:
	var count := 0
	for y in range(0, span):
		for x in range(0, span):
			if placement.has_entrance_at(x, y, biome_name):
				count += 1
	return count


func test_no_entrances_in_ocean():
	assert_eq(_count_entrances("ocean", 300), 0)


func test_entrances_are_sparse_in_mountain():
	var count := _count_entrances("mountain", 300)
	assert_gt(count, 0, "expected at least a few entrances across 300x300 mountain tiles")
	assert_lt(count, 300, "entrances must stay sparse, not one every tile")


func test_mountain_has_far_more_entrances_than_grassland():
	var mountain_count := _count_entrances("mountain", 400)
	var grassland_count := _count_entrances("grassland", 400)
	assert_gt(mountain_count, grassland_count)


func test_has_entrance_at_is_deterministic():
	var a := placement.has_entrance_at(11, 22, "mountain")
	var b := placement.has_entrance_at(11, 22, "mountain")
	assert_eq(a, b)


func test_seed_at_deterministic():
	assert_eq(placement.seed_at(4, 4), placement.seed_at(4, 4))


func test_seed_at_varies_by_cell():
	assert_ne(placement.seed_at(4, 4), placement.seed_at(5, 4))
