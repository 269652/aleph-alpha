extends GutTest

const FastTravel = preload("res://src/gameplay/fast_travel.gd")

var fast_travel: FastTravel


func before_each():
	fast_travel = FastTravel.new()


func test_cost_at_zero_distance_is_documented_minimum():
	assert_eq(fast_travel.cost_for_distance(0.0), FastTravel.BASE_COST)


func test_cost_is_non_decreasing_as_distance_increases():
	var previous_cost: int = fast_travel.cost_for_distance(0.0)
	for distance in [10.0, 50.0, 200.0, 1000.0]:
		var current_cost: int = fast_travel.cost_for_distance(distance)
		assert_gte(current_cost, previous_cost)
		previous_cost = current_cost


func test_cost_actually_grows_for_a_large_distance_increase():
	var near_cost: int = fast_travel.cost_for_distance(10.0)
	var far_cost: int = fast_travel.cost_for_distance(2000.0)
	assert_gt(far_cost, near_cost)


func test_cooldown_at_zero_distance_is_documented_minimum():
	assert_almost_eq(fast_travel.cooldown_seconds_for_distance(0.0), FastTravel.BASE_COOLDOWN_SECONDS, 0.001)


func test_cooldown_is_non_decreasing_as_distance_increases():
	var previous_cooldown: float = fast_travel.cooldown_seconds_for_distance(0.0)
	for distance in [10.0, 50.0, 200.0, 1000.0]:
		var current_cooldown: float = fast_travel.cooldown_seconds_for_distance(distance)
		assert_gte(current_cooldown, previous_cooldown)
		previous_cooldown = current_cooldown


func test_cooldown_actually_grows_for_a_large_distance_increase():
	var near_cooldown: float = fast_travel.cooldown_seconds_for_distance(10.0)
	var far_cooldown: float = fast_travel.cooldown_seconds_for_distance(2000.0)
	assert_gt(far_cooldown, near_cooldown)


func test_can_fast_travel_true_when_affordable_and_off_cooldown():
	assert_true(fast_travel.can_fast_travel(100, 50, 0.0))


func test_can_fast_travel_false_when_unaffordable_even_with_cooldown_ready():
	assert_false(fast_travel.can_fast_travel(10, 50, 0.0))


func test_can_fast_travel_false_when_on_cooldown_even_if_affordable():
	assert_false(fast_travel.can_fast_travel(100, 50, 5.0))


func test_can_fast_travel_true_at_exact_affordability_boundary():
	assert_true(fast_travel.can_fast_travel(50, 50, 0.0))


func test_can_fast_travel_false_at_cooldown_remaining_small_positive_epsilon():
	assert_false(fast_travel.can_fast_travel(100, 50, 0.0001))


func test_can_fast_travel_true_at_cooldown_remaining_exactly_zero():
	assert_true(fast_travel.can_fast_travel(100, 50, 0.0))


func test_can_fast_travel_with_cargo_true_for_empty_cargo():
	assert_true(fast_travel.can_fast_travel_with_cargo([]))


func test_can_fast_travel_with_cargo_true_for_inanimate_items_only():
	var cargo := [
		{"id": "wood", "is_living": false},
		{"id": "ore", "is_living": false},
	]
	assert_true(fast_travel.can_fast_travel_with_cargo(cargo))


func test_can_fast_travel_with_cargo_true_when_is_living_key_is_absent():
	var cargo := [{"id": "wood"}]
	assert_true(fast_travel.can_fast_travel_with_cargo(cargo))


func test_can_fast_travel_with_cargo_false_when_any_item_is_a_living_creature():
	var cargo := [
		{"id": "wood", "is_living": false},
		{"id": "tamed_horse", "is_living": true},
	]
	assert_false(fast_travel.can_fast_travel_with_cargo(cargo))


func test_can_fast_travel_with_cargo_false_when_only_item_is_a_living_creature():
	var cargo := [{"id": "tamed_horse", "is_living": true}]
	assert_false(fast_travel.can_fast_travel_with_cargo(cargo))
