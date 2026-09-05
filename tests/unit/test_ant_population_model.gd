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


func test_capacity_is_positive_with_no_forage_success_at_all():
	assert_gt(model.capacity(0.0), 0.0)


func test_capacity_increases_with_recent_forage_success():
	var starved := model.capacity(0.0)
	var well_fed := model.capacity(1.0)
	assert_gt(well_fed, starved, "a colony that keeps finding food should support more than one that keeps coming home empty")


func test_capacity_is_clamped_for_an_out_of_range_success_fraction():
	assert_almost_eq(model.capacity(1.0), model.capacity(2.0), 0.001)
	assert_almost_eq(model.capacity(0.0), model.capacity(-1.0), 0.001)


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
	assert_lt(AntPopulationModel.STARTING_POPULATION, AntPopulationModel.new().capacity(0.0))
