extends GutTest

## See docs/concept/bees.md#honeybee-colony-economy. Thin domain wrapper
## around PopulationModel, the bee sibling of AntPopulationModel/
## AquaticPopulationModel/etc -- mirrors test_ant_population_model.gd's
## own shape, trimmed to ONE capacity input (forage success) rather than
## two: see bees.md's own doc comment on why there is deliberately no
## separate water/moisture bonus for bees the way ants have one.

const BeePopulationModel = preload("res://src/world/bee_population_model.gd")
const AntPopulationModel = preload("res://src/world/ant_population_model.gd")

var model: BeePopulationModel


func before_each():
	model = BeePopulationModel.new()


func test_capacity_is_positive_with_no_forage_success_at_all():
	assert_gt(model.capacity(0.0), 0.0)


func test_capacity_increases_with_recent_forage_success():
	var starved := model.capacity(0.0)
	var well_fed := model.capacity(1.0)
	assert_gt(
		well_fed, starved,
		"a hive that keeps finding nectar should support more bees than one that keeps coming home empty"
	)


func test_capacity_is_clamped_for_an_out_of_range_success_fraction():
	assert_almost_eq(model.capacity(1.0), model.capacity(2.0), 0.001)
	assert_almost_eq(model.capacity(0.0), model.capacity(-1.0), 0.001)


## MAX_REFERENCE_POPULATION is what BeeColony.growth_fraction_at (and so a
## hive's own growth-stage art frame) normalizes against -- it must
## actually equal the real ceiling capacity() can produce, not an
## independently-chosen number that could silently drift from it.
func test_max_reference_population_matches_capacity_at_full_forage_success():
	assert_almost_eq(BeePopulationModel.MAX_REFERENCE_POPULATION, model.capacity(1.0), 0.001)


func test_max_reference_population_is_forty():
	assert_almost_eq(BeePopulationModel.MAX_REFERENCE_POPULATION, 40.0, 0.001)


func test_base_capacity_matches_the_starting_population():
	assert_almost_eq(BeePopulationModel.BASE_CAPACITY, 20.0, 0.001)


## How much a single bee draws from its own hive's stored honey reserve
## per simulated day -- see BeeColony.advance/honey_stored_at. Defined as
## exactly 1.0 so "one honey unit" IS "one bee's daily ration," the
## identical unit choice AntPopulationModel.FOOD_PER_ANT_PER_DAY already
## makes for ants.
func test_honey_per_bee_per_day_is_one_ration_unit():
	assert_almost_eq(BeePopulationModel.HONEY_PER_BEE_PER_DAY, 1.0, 0.001)


## Mirrors AntPopulationModel.FOOD_BUFFER_DAYS's own reasoning exactly: a
## modest few-day buffer, real enough to survive an ordinary short dry
## spell, not a hoard so large the constraint could never actually bite.
func test_honey_buffer_days_is_three():
	assert_almost_eq(BeePopulationModel.HONEY_BUFFER_DAYS, 3.0, 0.001)


## Real honeybee colonies build up across a single growing season --
## considerably faster than an ant colony's multi-year maturation, though
## not claimed to be among the very fastest populations this game tracks
## (small birds/fish reproduce many times a season in large broods; even a
## fast-building superorganism colony is not that). Pinned ABOVE
## AntPopulationModel's own rate, not just asserted.
func test_growth_rate_is_faster_than_an_ant_colonys():
	assert_gt(BeePopulationModel.GROWTH_RATE_PER_DAY, AntPopulationModel.GROWTH_RATE_PER_DAY)


func test_growth_rate_is_fifteen_percent_per_day():
	assert_almost_eq(BeePopulationModel.GROWTH_RATE_PER_DAY, 0.15, 0.001)


func test_step_grows_population_toward_capacity():
	var next := model.step(BeePopulationModel.STARTING_POPULATION, 40.0, 30.0)
	assert_gt(next, BeePopulationModel.STARTING_POPULATION)
	assert_lte(next, 40.0)


func test_step_does_not_grow_past_capacity():
	var next := model.step(10.0, 10.0, 30.0)
	assert_almost_eq(next, 10.0, 0.01)


## A freshly-founded hive (or one just re-established by a swarm/
## absconding move) must never read as already ABOVE its own unfed
## baseline capacity ceiling, on pain of PopulationModel.step reading it
## as overcrowded and shrinking it back down before a player ever sees it
## settle -- the identical safety AntPopulationModel's own starting
## population already guarantees.
func test_starting_population_matches_the_unfed_baseline_capacity():
	assert_almost_eq(
		BeePopulationModel.STARTING_POPULATION, BeePopulationModel.new().capacity(0.0), 0.001
	)
