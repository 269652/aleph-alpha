extends GutTest

const FarmPlot = preload("res://src/gameplay/farm_plot.gd")

var plot: FarmPlot


func before_each():
	plot = FarmPlot.new()


## Waters and advances in small steps (never exceeding the grace window) until
## the plot reaches "ready", overshooting slightly to absorb float rounding.
func _grow_to_ready(a_plot: FarmPlot) -> void:
	var step: float = a_plot.growth_time / 10.0
	for i in 12:
		a_plot.water()
		a_plot.advance(step)


func test_starts_empty():
	assert_eq(plot.state, "empty")
	assert_false(plot.is_ready())
	assert_false(plot.is_withered())


func test_plant_sets_state_to_growing_and_stores_crop_id():
	plot.plant("wheat", 42)
	assert_eq(plot.state, "growing")
	assert_eq(plot.crop_id, "wheat")


func test_growth_time_is_within_expected_range():
	plot.plant("wheat", 42)
	assert_between(plot.growth_time, FarmPlot.MIN_GROWTH_TIME, FarmPlot.MAX_GROWTH_TIME)


func test_growth_time_is_deterministic_for_the_same_seed_value():
	var a := FarmPlot.new()
	var b := FarmPlot.new()
	a.plant("wheat", 123)
	b.plant("wheat", 123)
	assert_eq(a.growth_time, b.growth_time)


func test_advancing_time_while_regularly_watered_reaches_ready():
	plot.plant("wheat", 42)
	_grow_to_ready(plot)
	assert_true(plot.is_ready())
	assert_eq(plot.state, "ready")


func test_advancing_time_without_watering_past_grace_threshold_withers():
	plot.plant("wheat", 42)
	plot.advance(plot.growth_time * FarmPlot.WATER_GRACE_FRACTION + 0.01)
	assert_true(plot.is_withered())
	assert_false(plot.is_ready())
	assert_eq(plot.state, "withered")


func test_watering_resets_the_neglect_clock():
	plot.plant("wheat", 42)
	var near_threshold: float = plot.growth_time * FarmPlot.WATER_GRACE_FRACTION - 0.1
	plot.advance(near_threshold)
	plot.water()
	plot.advance(near_threshold)
	assert_false(plot.is_withered())
	assert_eq(plot.state, "growing")


func test_harvest_on_ready_plot_returns_positive_count_and_resets_to_empty():
	plot.plant("wheat", 42)
	_grow_to_ready(plot)
	var result: Dictionary = plot.harvest()
	assert_eq(result["crop_id"], "wheat")
	assert_gt(result["count"], 0)
	assert_eq(plot.state, "empty")
	assert_eq(plot.crop_id, "")


func test_harvest_on_growing_plot_is_a_noop():
	plot.plant("wheat", 42)
	var result: Dictionary = plot.harvest()
	assert_eq(result["crop_id"], "")
	assert_eq(result["count"], 0)
	assert_eq(plot.state, "growing")


func test_harvest_on_withered_plot_is_a_noop():
	plot.plant("wheat", 42)
	plot.advance(plot.growth_time * FarmPlot.WATER_GRACE_FRACTION + 0.01)
	var result: Dictionary = plot.harvest()
	assert_eq(result["crop_id"], "")
	assert_eq(result["count"], 0)
	assert_eq(plot.state, "withered")


func test_harvest_on_empty_plot_is_a_noop():
	var result: Dictionary = plot.harvest()
	assert_eq(result["crop_id"], "")
	assert_eq(result["count"], 0)
	assert_eq(plot.state, "empty")


func test_yield_count_is_deterministic_for_the_same_seed_value():
	var a := FarmPlot.new()
	var b := FarmPlot.new()
	a.plant("wheat", 99)
	b.plant("wheat", 99)
	_grow_to_ready(a)
	_grow_to_ready(b)
	var result_a: Dictionary = a.harvest()
	var result_b: Dictionary = b.harvest()
	assert_eq(result_a["count"], result_b["count"])


func test_planting_again_after_harvest_resets_to_growing():
	plot.plant("wheat", 42)
	_grow_to_ready(plot)
	plot.harvest()
	plot.plant("carrot", 7)
	assert_eq(plot.state, "growing")
	assert_eq(plot.crop_id, "carrot")
