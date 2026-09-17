extends GutTest

## The visible, player-facing counterpart to FarmPlot (docs/concept/
## farming.md's "farming loop") -- wraps one FarmPlot instance and draws its
## current state (tilled soil + growth-staged crop leaves, the SAME
## IllustratedCropSprite art wild carrot/potato patches already use). Mirrors
## test_wild_crop_marker.gd's real-scene-tree/real-art setup.

const FarmPlotMarker = preload("res://src/rendering/farm_plot_marker.gd")
const FarmPlot = preload("res://src/gameplay/farm_plot.gd")
const IllustratedGrassPatch = preload("res://src/rendering/illustrated_grass_patch.gd")
const IllustratedWheatPatch = preload("res://src/rendering/illustrated_wheat_patch.gd")

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


# -- wheat renders as bending blades, not IllustratedCropSprite's flat -----
# -- leaves -- see docs/concept/long_grass.md's "A second atlas family: ----
# -- farmed wheat" and docs/concept/npc_farm_production.md (the autonomous --
# -- Farm/Farmer already plants and harvests real "wheat", but had no real --
# -- crop art at all until this) -----------------------------------------


func test_current_wheat_season_defaults_sensibly_before_any_advance():
	add_child_autofree(marker)
	assert_eq(marker.current_wheat_season(), IllustratedWheatPatch.DEFAULT_SEASON)


func test_advance_records_the_season_it_was_given():
	add_child_autofree(marker)
	marker.advance(0.0, "autumn")
	assert_eq(marker.current_wheat_season(), "autumn")


func test_advance_still_accepts_no_season_and_ticks_growth_exactly_as_before():
	add_child_autofree(marker)
	marker.till_and_plant("carrot", 42)
	marker.advance(1.0)
	assert_eq(marker.plot.time_growing, 1.0)


func test_a_carrot_plot_does_not_render_as_bending_wheat():
	add_child_autofree(marker)
	marker.till_and_plant("carrot", 42)
	assert_false(marker.is_rendering_bending_wheat())


func test_an_empty_plot_does_not_render_as_bending_wheat():
	add_child_autofree(marker)
	assert_false(marker.is_rendering_bending_wheat())


func test_a_growing_wheat_plot_renders_as_bending_blades():
	add_child_autofree(marker)
	marker.till_and_plant("wheat", 42)
	assert_true(marker.is_rendering_bending_wheat())
	assert_eq(marker.wheat_blade_count(), IllustratedGrassPatch.CARD_COUNT)


func test_a_ready_wheat_plot_still_renders_as_bending_blades():
	add_child_autofree(marker)
	marker.till_and_plant("wheat", 42)
	_grow_to_ready(marker)
	assert_eq(marker.plot.state, "ready")
	assert_true(marker.is_rendering_bending_wheat())


func test_harvesting_wheat_clears_the_bending_blades():
	add_child_autofree(marker)
	marker.till_and_plant("wheat", 42)
	_grow_to_ready(marker)
	marker.harvest()
	assert_eq(marker.plot.state, "empty")
	assert_false(marker.is_rendering_bending_wheat())
	assert_eq(marker.wheat_blade_count(), 0)


## Replanting the SAME plot with a different crop must fully switch render
## paths, not leave stale wheat blades sitting behind the new crop's leaves
## (a real class of bug this codebase has hit before -- stale visuals left
## over from a previous state).
func test_replanting_wheat_over_with_carrot_switches_away_from_bending_blades():
	add_child_autofree(marker)
	marker.till_and_plant("wheat", 42)
	_grow_to_ready(marker)
	marker.harvest()
	marker.till_and_plant("carrot", 7)
	assert_false(marker.is_rendering_bending_wheat())
	assert_eq(marker.wheat_blade_count(), 0)


func test_a_withered_wheat_plot_still_renders_blades_tinted_the_same_withered_color():
	add_child_autofree(marker)
	marker.till_and_plant("wheat", 42)
	marker.advance(marker.plot.growth_time * FarmPlot.WATER_GRACE_FRACTION + 0.01)
	assert_eq(marker.plot.state, "withered")
	assert_true(marker.is_rendering_bending_wheat())


# -- a wheat bed is wheat, not a mound -------------------------------------
#
# Reported with the beds circled: "what's the round procedural dark blob?
# Can you remove it and keep just the wheat please". ProceduralSoilSprite's
# mound sits under every plot. Under a ROOT crop it is the crop's own
# ground -- the root is in the mound, and a pulled root leaves a crater in
# it -- but under a field of bending wheat it is just a dark circle, six of
# them in a 3x2 bed.


func test_a_wheat_plot_shows_no_soil_mound_at_all():
	add_child_autofree(marker)
	marker.till_and_plant("wheat", 42)
	assert_false(marker.is_showing_soil(), "a wheat bed reads as wheat, not as a blob")


## Including once it has been cut: a harvested bed keeps its crop_id, and a
## bare mound appearing the moment the wheat comes off would be the same
## blob back again.
func test_a_harvested_wheat_bed_still_shows_no_mound():
	add_child_autofree(marker)
	marker.till_and_plant("wheat", 42)
	_grow_to_ready(marker)
	marker.harvest()
	assert_eq(marker.plot.state, "empty")
	assert_false(marker.is_showing_soil())


## And the crops the mound was actually drawn for keep it.
func test_a_root_crop_keeps_the_mound_its_root_grows_in():
	add_child_autofree(marker)
	marker.till_and_plant("carrot", 7)
	assert_true(marker.is_showing_soil(), "a carrot's root is IN the mound")


func test_replanting_wheat_over_a_root_crop_takes_the_mound_away_again():
	add_child_autofree(marker)
	marker.till_and_plant("carrot", 7)
	assert_true(marker.is_showing_soil())
	_grow_to_ready(marker)
	marker.harvest()
	marker.till_and_plant("wheat", 42)
	assert_false(marker.is_showing_soil(), "stale soil left behind the new crop")
