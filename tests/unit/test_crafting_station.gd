extends GutTest

const CraftingStation = preload("res://src/gameplay/crafting_station.gd")

var crafting_station: CraftingStation


func before_each():
	crafting_station = CraftingStation.new()


func test_tier_of_returns_correct_tier_for_campfire():
	assert_eq(crafting_station.tier_of("campfire"), 1)


func test_tier_of_returns_correct_tier_for_forge():
	assert_eq(crafting_station.tier_of("forge"), 2)


func test_tier_of_returns_correct_tier_for_arcane_altar():
	assert_eq(crafting_station.tier_of("arcane_altar"), 3)


func test_tier_of_returns_zero_for_unknown_station():
	assert_eq(crafting_station.tier_of("nonexistent_station"), 0)


func test_can_craft_at_true_when_tier_meets_requirement():
	assert_true(crafting_station.can_craft_at("forge", 2))


func test_can_craft_at_true_when_tier_exceeds_requirement():
	assert_true(crafting_station.can_craft_at("arcane_altar", 1))


func test_can_craft_at_false_when_tier_below_requirement():
	assert_false(crafting_station.can_craft_at("campfire", 2))


func test_can_craft_at_false_for_unknown_station_against_positive_requirement():
	assert_false(crafting_station.can_craft_at("nonexistent_station", 1))


func test_station_ids_returns_every_defined_station():
	var ids: Array = crafting_station.station_ids()
	assert_true(ids.has("campfire"))
	assert_true(ids.has("forge"))
	assert_true(ids.has("arcane_altar"))
	assert_eq(ids.size(), 3)


func test_stations_at_or_above_returns_only_qualifying_stations():
	var result: Array = crafting_station.stations_at_or_above(2)
	assert_eq(result, ["arcane_altar", "forge"])


func test_stations_at_or_above_returns_empty_array_above_highest_tier():
	var result: Array = crafting_station.stations_at_or_above(99)
	assert_eq(result, [])


func test_stations_at_or_above_is_sorted_alphabetically():
	var result: Array = crafting_station.stations_at_or_above(1)
	var sorted_copy: Array = result.duplicate()
	sorted_copy.sort()
	assert_eq(result, sorted_copy)
