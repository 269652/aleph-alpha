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


## 4.0 -> 15.0 (2026-09-06, "start at 15 ants"): raised to match the new
## flat starting population exactly (see test_starting_population_
## matches_the_unfed_baseline_capacity above) -- FOOD_CAPACITY_BONUS/
## WATER_CAPACITY_BONUS stay at their existing 1.0-of-BASE_CAPACITY ratio,
## unchanged, so MAX_REFERENCE_POPULATION rises proportionally (45.0) with
## no separate decision needed.
func test_base_capacity_matches_the_new_starting_population():
	assert_almost_eq(AntPopulationModel.BASE_CAPACITY, 15.0, 0.001)


func test_max_reference_population_is_forty_five():
	assert_almost_eq(AntPopulationModel.MAX_REFERENCE_POPULATION, 45.0, 0.001)


## How much a single ant draws from its own mound's stored food reserve
## per simulated day -- see AntColony.advance/food_stored_at. Defined as
## exactly 1.0 so "one food unit" IS "one ant's daily ration": the
## simplest possible unit choice, needing no separate justification for
## what the number itself means.
func test_food_per_ant_per_day_is_one_ration_unit():
	assert_almost_eq(AntPopulationModel.FOOD_PER_ANT_PER_DAY, 1.0, 0.001)


## How many days of reserve, at the CURRENT population's own upkeep rate,
## counts as "secure" (food_availability_fraction reads 1.0) -- see
## AntColony.food_availability_fraction. A modest few-day buffer: real
## enough to survive an ordinary short dry spell, not a hoard so large the
## constraint this whole mechanism exists for could never actually bite.
func test_food_buffer_days_is_three():
	assert_almost_eq(AntPopulationModel.FOOD_BUFFER_DAYS, 3.0, 0.001)


## Real ant colonies mature over years -- the slowest-growing population
## this game tracks, against land mammals'/fish's/birds' comparatively
## fast seasonal reproduction. Pinned below PredatorPopulationModel's own
## 0.15 (the previous slowest), not just asserted.
func test_growth_rate_is_the_slowest_population_this_game_tracks():
	assert_lt(AntPopulationModel.GROWTH_RATE_PER_DAY, PredatorPopulationModel.GROWTH_RATE_PER_DAY)


## Capacity (30.0) picked comfortably ABOVE STARTING_POPULATION (15.0,
## since 2026-09-06's flat-15 starting population -- see
## test_starting_population_matches_the_unfed_baseline_capacity below for
## why 10.0 no longer works here) so this keeps testing real growth,
## not a population already above the capacity it's meant to grow toward.
func test_step_grows_population_toward_capacity():
	var next := model.step(AntPopulationModel.STARTING_POPULATION, 30.0, 30.0)
	assert_gt(next, AntPopulationModel.STARTING_POPULATION)
	assert_lte(next, 30.0)


func test_step_does_not_grow_past_capacity():
	var next := model.step(10.0, 10.0, 30.0)
	assert_almost_eq(next, 10.0, 0.01)


## Deliberately EQUAL, not merely less-than (2026-09-06, food economy):
## AntColony._seed_initial_mounds never seeds a mound above its own
## unfed-baseline capacity ceiling (BASE_CAPACITY), on pain of
## PopulationModel.step reading it as already overcrowded and shrinking
## it back down before a player ever sees it settle -- a real, tested
## safety this file's own git history shows was already load-bearing at
## the old 1.0/4.0 scale, preserved exactly, just at the new one.
func test_starting_population_matches_the_unfed_baseline_capacity():
	assert_almost_eq(
		AntPopulationModel.STARTING_POPULATION, AntPopulationModel.new().capacity(0.0, 0.0), 0.001
	)
