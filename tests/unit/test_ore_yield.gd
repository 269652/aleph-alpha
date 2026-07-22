extends GutTest

const OreYield = preload("res://src/gameplay/ore_yield.gd")

var oy: OreYield


func before_each():
	oy = OreYield.new()


func _total_of(drops: Array, item_id: String) -> int:
	var total := 0
	for d in drops:
		if d.item_id == item_id:
			total += d.count
	return total


func test_bare_hands_yield_only_stone_no_ore():
	var drops := oy.yields("iron", 0.0, 123)
	assert_gt(_total_of(drops, "stone"), 0, "should still get some stone")
	assert_eq(_total_of(drops, "iron_ore"), 0, "bare hands yield no ore")


func test_pickaxe_yields_ore_item_for_type():
	var drops := oy.yields("iron", 2.0, 123)
	assert_gt(_total_of(drops, "iron_ore"), 0)


func test_copper_yields_copper_ore():
	var drops := oy.yields("copper", 2.0, 55)
	assert_gt(_total_of(drops, "copper_ore"), 0)
	assert_eq(_total_of(drops, "iron_ore"), 0)


func test_coal_yields_coal_item():
	var drops := oy.yields("coal", 2.0, 55)
	assert_gt(_total_of(drops, "coal"), 0)


func test_always_yields_some_stone():
	var drops := oy.yields("iron", 3.0, 7)
	assert_gt(_total_of(drops, "stone"), 0)


func test_deterministic_per_seed():
	var a := oy.yields("iron", 2.0, 999)
	var b := oy.yields("iron", 2.0, 999)
	assert_eq(a, b)


func test_higher_power_yields_more_ore_on_average():
	var low := 0
	var high := 0
	for s in range(0, 60):
		low += _total_of(oy.yields("iron", 1.0, s), "iron_ore")
		high += _total_of(oy.yields("iron", 4.0, s), "iron_ore")
	assert_gt(high, low, "stronger pickaxe should net more ore overall")


func test_ore_count_respects_max_scaling_constant():
	# Ore count is bounded by BASE_ORE + power scaling. Pin the ceiling.
	for s in range(0, 200):
		var drops := oy.yields("iron", 3.0, s)
		var n := _total_of(drops, "iron_ore")
		assert_between(
			n,
			1,
			OreYield.BASE_ORE + int(ceil(3.0 * OreYield.ORE_PER_POWER)),
			"ore count out of pinned range at seed %d" % s
		)


func test_stone_count_is_pinned_constant():
	var drops := oy.yields("iron", 2.0, 1)
	assert_eq(_total_of(drops, "stone"), OreYield.STONE_PER_MINE)
