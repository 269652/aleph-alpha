extends GutTest

## The visible, player-facing counterpart to FarmPlot (docs/concept/
## farming.md's "farming loop") -- wraps one FarmPlot instance and draws its
## current state (tilled soil + growth-staged crop leaves, the SAME
## IllustratedCropSprite art wild carrot/potato patches already use). Mirrors
## test_wild_crop_marker.gd's real-scene-tree/real-art setup.

const FarmPlotMarker = preload("res://src/rendering/farm_plot_marker.gd")
const FarmPlot = preload("res://src/gameplay/farm_plot.gd")

var marker: FarmPlotMarker


func before_each():
	marker = FarmPlotMarker.new()


func after_each():
	if is_instance_valid(marker):
		marker.free()


func test_joins_the_farm_plot_group():
	add_child_autofree(marker)
	assert_true(marker.is_in_group(FarmPlotMarker.GROUP_NAME))


func test_starts_with_an_empty_plot():
	add_child_autofree(marker)
	assert_eq(marker.plot.state, "empty")


func test_till_and_plant_starts_growth():
	add_child_autofree(marker)
	var planted := marker.till_and_plant("carrot", 42)
	assert_true(planted)
	assert_eq(marker.plot.state, "growing")
	assert_eq(marker.plot.crop_id, "carrot")


func test_till_and_plant_refuses_to_disturb_a_growing_plot():
	add_child_autofree(marker)
	marker.till_and_plant("carrot", 42)
	var replanted := marker.till_and_plant("potato", 7)
	assert_false(replanted, "a live crop must never be silently overwritten")
	assert_eq(marker.plot.crop_id, "carrot")


func test_till_and_plant_refuses_to_disturb_a_ready_plot():
	add_child_autofree(marker)
	marker.till_and_plant("carrot", 42)
	_grow_to_ready(marker)
	var replanted := marker.till_and_plant("potato", 7)
	assert_false(replanted, "an unharvested ready crop must never be silently overwritten")
	assert_eq(marker.plot.state, "ready")


func test_till_and_plant_succeeds_again_over_a_withered_plot():
	add_child_autofree(marker)
	marker.till_and_plant("carrot", 42)
	marker.plot.advance(marker.plot.growth_time * FarmPlot.WATER_GRACE_FRACTION + 0.01)
	assert_eq(marker.plot.state, "withered")
	var replanted := marker.till_and_plant("potato", 7)
	assert_true(replanted)
	assert_eq(marker.plot.state, "growing")
	assert_eq(marker.plot.crop_id, "potato")


func test_advance_ticks_the_underlying_plot():
	add_child_autofree(marker)
	marker.till_and_plant("carrot", 42)
	marker.advance(1.0)
	assert_eq(marker.plot.time_growing, 1.0)


func test_water_resets_the_neglect_clock_while_growing():
	add_child_autofree(marker)
	marker.till_and_plant("carrot", 42)
	marker.advance(marker.plot.growth_time * FarmPlot.WATER_GRACE_FRACTION - 0.1)
	var watered := marker.water()
	assert_true(watered)
	assert_eq(marker.plot.time_since_watered, 0.0)


func test_water_is_a_noop_with_nothing_planted():
	add_child_autofree(marker)
	var watered := marker.water()
	assert_false(watered)


func test_harvest_on_a_ready_plot_returns_a_positive_count_and_clears_the_leaves():
	add_child_autofree(marker)
	marker.till_and_plant("carrot", 42)
	_grow_to_ready(marker)
	var result: Dictionary = marker.harvest()
	assert_eq(result["crop_id"], "carrot")
	assert_gt(result["count"], 0)
	assert_eq(marker.plot.state, "empty")


func test_harvest_on_a_growing_plot_is_a_noop():
	add_child_autofree(marker)
	marker.till_and_plant("carrot", 42)
	var result: Dictionary = marker.harvest()
	assert_eq(result["crop_id"], "")
	assert_eq(result["count"], 0)
	assert_eq(marker.plot.state, "growing")


## Waters and advances in small steps (never exceeding the grace window)
## until the plot reaches "ready" -- same idiom test_farm_plot.gd's own
## _grow_to_ready uses, driven through the MARKER's own advance()/water()
## rather than poking the plot directly, so this exercises the exact same
## call shape a real tick + tend loop would.
func _grow_to_ready(a_marker: FarmPlotMarker) -> void:
	var step: float = a_marker.plot.growth_time / 10.0
	for i in 12:
		a_marker.water()
		a_marker.advance(step)
