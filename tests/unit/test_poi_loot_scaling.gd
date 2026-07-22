extends GutTest

const PoiLootScaling = preload("res://src/gameplay/poi_loot_scaling.gd")

var scaling: PoiLootScaling


func before_each():
	scaling = PoiLootScaling.new()


func test_min_guaranteed_rarity_for_low_is_common():
	assert_eq(scaling.min_guaranteed_rarity("low"), 0)


func test_min_guaranteed_rarity_for_unknown_level_is_common():
	assert_eq(scaling.min_guaranteed_rarity("not_a_real_danger_level"), 0)


func test_min_guaranteed_rarity_is_non_decreasing_from_low_to_extreme():
	var low: int = scaling.min_guaranteed_rarity("low")
	var medium: int = scaling.min_guaranteed_rarity("medium")
	var high: int = scaling.min_guaranteed_rarity("high")
	var extreme: int = scaling.min_guaranteed_rarity("extreme")
	assert_lte(low, medium)
	assert_lte(medium, high)
	assert_lte(high, extreme)


func test_min_guaranteed_rarity_extreme_is_strictly_higher_than_low():
	assert_gt(scaling.min_guaranteed_rarity("extreme"), scaling.min_guaranteed_rarity("low"))


func test_loot_count_for_unknown_level_adds_no_bonus():
	assert_eq(scaling.loot_count_for("not_a_real_danger_level", 5), 5)


func test_loot_count_for_low_adds_its_bonus_to_base_count():
	var expected: int = 3 + scaling.POI_DANGER_LEVELS["low"]["loot_count_bonus"]
	assert_eq(scaling.loot_count_for("low", 3), expected)


func test_loot_count_for_medium_adds_its_bonus_to_base_count():
	var expected: int = 3 + scaling.POI_DANGER_LEVELS["medium"]["loot_count_bonus"]
	assert_eq(scaling.loot_count_for("medium", 3), expected)


func test_loot_count_for_high_adds_its_bonus_to_base_count():
	var expected: int = 3 + scaling.POI_DANGER_LEVELS["high"]["loot_count_bonus"]
	assert_eq(scaling.loot_count_for("high", 3), expected)


func test_loot_count_for_extreme_adds_its_bonus_to_base_count():
	var expected: int = 3 + scaling.POI_DANGER_LEVELS["extreme"]["loot_count_bonus"]
	assert_eq(scaling.loot_count_for("extreme", 3), expected)


func test_loot_count_for_is_non_decreasing_from_low_to_extreme():
	var low: int = scaling.loot_count_for("low", 2)
	var medium: int = scaling.loot_count_for("medium", 2)
	var high: int = scaling.loot_count_for("high", 2)
	var extreme: int = scaling.loot_count_for("extreme", 2)
	assert_lte(low, medium)
	assert_lte(medium, high)
	assert_lte(high, extreme)


func test_loot_count_for_extreme_is_strictly_higher_than_low():
	assert_gt(scaling.loot_count_for("extreme", 0), scaling.loot_count_for("low", 0))


func test_min_guaranteed_rarity_never_negative_for_any_defined_level():
	for level in scaling.POI_DANGER_LEVELS.keys():
		assert_gte(scaling.min_guaranteed_rarity(level), 0)
