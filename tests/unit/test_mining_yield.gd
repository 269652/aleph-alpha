extends GutTest

const MiningYield = preload("res://src/gameplay/mining_yield.gd")

var vein: MiningYield


func before_each():
	vein = MiningYield.new()
	vein.max_yield = 100.0
	vein.remaining_yield = 100.0


func test_starts_full_and_not_depleted():
	assert_almost_eq(vein.remaining_yield, 100.0, 0.001)
	assert_false(vein.is_depleted())


func test_mining_reduces_remaining_yield_by_requested_amount_when_enough_left():
	var extracted := vein.mine(30.0)
	assert_almost_eq(extracted, 30.0, 0.001)
	assert_almost_eq(vein.remaining_yield, 70.0, 0.001)


func test_mining_near_empty_returns_only_what_is_left():
	vein.remaining_yield = 10.0
	var extracted := vein.mine(30.0)
	assert_almost_eq(extracted, 10.0, 0.001)


func test_mining_near_empty_leaves_remaining_yield_at_exactly_zero():
	vein.remaining_yield = 10.0
	vein.mine(30.0)
	assert_almost_eq(vein.remaining_yield, 0.0, 0.001)


func test_is_depleted_becomes_true_at_exactly_zero_remaining():
	vein.remaining_yield = 5.0
	vein.mine(5.0)
	assert_true(vein.is_depleted())


func test_regenerate_increases_remaining_yield_over_time():
	vein.remaining_yield = 50.0
	vein.regenerate(1.0, 10.0)
	assert_almost_eq(vein.remaining_yield, 60.0, 0.001)


func test_regenerate_clamps_at_max_yield_and_does_not_overshoot():
	vein.remaining_yield = 95.0
	vein.regenerate(1.0, 10.0)
	assert_almost_eq(vein.remaining_yield, 100.0, 0.001)


func test_mining_a_fully_depleted_vein_returns_zero():
	vein.remaining_yield = 0.0
	var extracted := vein.mine(20.0)
	assert_almost_eq(extracted, 0.0, 0.001)
