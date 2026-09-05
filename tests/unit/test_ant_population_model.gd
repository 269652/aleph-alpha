extends GutTest

## See docs/concept/soil_fauna.md#a-queen-and-where-a-colonys-size-comes-from.
## Thin domain wrapper around PopulationModel, the ant sibling of
## AquaticPopulationModel/HerbivorePopulationModel/etc -- mirrors
## test_aquatic_population_model.gd's own shape.

const AntPopulationModel = preload("res://src/world/ant_population_model.gd")
const PredatorPopulationModel = preload("res://src/world/predator_population_model.gd")

var model: AntPopulationModel


func before_each():
	model = AntPopulationModel.new()


func test_capacity_is_positive_with_no_forage_success_or_moisture_at_all():
	assert_gt(model.capacity(0.0, 0.0), 0.0)


func test_capacity_increases_with_recent_forage_success():
	var starved := model.capacity(0.0, 0.0)
	var well_fed := model.capacity(1.0, 0.0)
	assert_gt(well_fed, starved, "a colony that keeps finding food should support more than one that keeps coming home empty")


func test_capacity_is_clamped_for_an_out_of_range_success_fraction():
	assert_almost_eq(model.capacity(1.0, 0.0), model.capacity(2.0, 0.0), 0.001)
	assert_almost_eq(model.capacity(0.0, 0.0), model.capacity(-1.0, 0.0), 0.001)


## Real-world grounding: larval development needs humidity, and colonies
## measurably struggle through drought even with forage still available
## -- water is a second, independent input to capacity, not folded into
## the food signal.
func test_capacity_increases_with_recent_moisture():
	var dry := model.capacity(0.0, 0.0)
	var damp := model.capacity(0.0, 1.0)
	assert_gt(damp, dry, "a colony sitting on consistently damp ground should support more than one on parched ground")


func test_capacity_is_clamped_for_an_out_of_range_moisture_fraction():
	assert_almost_eq(model.capacity(0.0, 1.0), model.capacity(0.0, 2.0), 0.001)
	assert_almost_eq(model.capacity(0.0, 0.0), model.capacity(0.0, -1.0), 0.001)


## Food and water are pinned to the identical bonus magnitude -- both are
## real, independently-acting inputs to the same real mechanism, and
## nothing in the grounding argues either should structurally dominate.
func test_water_bonus_is_pinned_equal_to_food_bonus():
	assert_almost_eq(AntPopulationModel.WATER_CAPACITY_BONUS, AntPopulationModel.FOOD_CAPACITY_BONUS, 0.001)


func test_capacity_is_highest_with_both_food_and_water_abundant():
	var best := model.capacity(1.0, 1.0)
	assert_gt(best, model.capacity(1.0, 0.0))
	assert_gt(best, model.capacity(0.0, 1.0))


## MAX_REFERENCE_POPULATION is what AntColony.growth_fraction_at (and so
## mound visual size) normalizes against -- it must actually equal the
## real ceiling capacity() can produce, not an independently-chosen
## number that could silently drift from it.
func test_max_reference_population_matches_capacity_at_full_food_and_water():
	assert_almost_eq(
		AntPopulationModel.MAX_REFERENCE_POPULATION, model.capacity(1.0, 1.0), 0.001
	)


## Real ant colonies mature over years -- the slowest-growing population
## this game tracks, against land mammals'/fish's/birds' comparatively
## fast seasonal reproduction. Pinned below PredatorPopulationModel's own
## 0.15 (the previous slowest), not just asserted.
func test_growth_rate_is_the_slowest_population_this_game_tracks():
	assert_lt(AntPopulationModel.GROWTH_RATE_PER_DAY, PredatorPopulationModel.GROWTH_RATE_PER_DAY)


func test_step_grows_population_toward_capacity():
	var next := model.step(AntPopulationModel.STARTING_POPULATION, 10.0, 30.0)
	assert_gt(next, AntPopulationModel.STARTING_POPULATION)
	assert_lte(next, 10.0)


func test_step_does_not_grow_past_capacity():
	var next := model.step(10.0, 10.0, 30.0)
	assert_almost_eq(next, 10.0, 0.01)


func test_starting_population_is_a_small_founding_colony():
	assert_gt(AntPopulationModel.STARTING_POPULATION, 0.0)
	assert_lt(AntPopulationModel.STARTING_POPULATION, AntPopulationModel.new().capacity(0.0, 0.0))
