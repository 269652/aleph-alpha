extends GutTest

const WaterMovementModel = preload("res://src/gameplay/water_movement_model.gd")

var model: WaterMovementModel


func before_each():
	model = WaterMovementModel.new()


func test_dry_land_is_walking_at_full_speed():
	var result := model.resolve(0.0, 10.0, 50.0)
	assert_eq(result.mode, "walking")
	assert_almost_eq(result.speed_multiplier, 1.0, 0.001)


func test_shallow_water_is_wading_with_reduced_speed():
	# 0.5m: well within WADE_DEPTH_METERS (1.5m) -- ankle/shin-deep, realistic wading.
	var result := model.resolve(0.5, 10.0, 50.0)
	assert_eq(result.mode, "wading")
	assert_between(result.speed_multiplier, 0.0, 1.0)


func test_wading_speed_decreases_as_depth_increases():
	var shallow := model.resolve(0.3, 10.0, 50.0)
	var deeper := model.resolve(1.2, 10.0, 50.0)
	assert_lt(deeper.speed_multiplier, shallow.speed_multiplier)


func test_deep_water_with_light_load_is_swimming():
	# 3m: clearly past wading depth, must swim.
	var result := model.resolve(3.0, 10.0, 50.0)
	assert_eq(result.mode, "swimming")
	assert_gt(result.speed_multiplier, 0.0)


func test_deep_water_with_weight_over_the_limit_is_drowning():
	var result := model.resolve(3.0, 60.0, 50.0)
	assert_eq(result.mode, "drowning")
	assert_eq(result.speed_multiplier, 0.0)


func test_swimming_speed_decreases_as_carried_weight_increases():
	var light := model.resolve(3.0, 10.0, 50.0)
	var heavy := model.resolve(3.0, 40.0, 50.0)
	assert_lt(heavy.speed_multiplier, light.speed_multiplier)


func test_swimming_at_exactly_the_weight_limit_is_still_swimming_not_drowning():
	var result := model.resolve(3.0, 50.0, 50.0)
	assert_eq(result.mode, "swimming")
