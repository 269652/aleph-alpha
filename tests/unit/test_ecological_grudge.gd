extends GutTest

## docs/concept/monsters.md, entry 5: the Curupira, "the only creature in the
## game that reads your footprint rather than your position".
##
## Its one behaviour, quoted from the roster: *"it is provoked by YOUR
## ecology. It ignores a player who hunts sustainably and hunts a player who
## has driven the local `herbivore_population` down -- the ecosystem sim is
## the aggro table."*
##
## That is the whole reason this monster is worth building rather than
## reskinning a wolf, and it needs no new state: `EarthChunkManager.
## herbivore_population_at_chunk` and `herbivore_capacity_at_chunk` are both
## live and public already.
##
## The threshold is DERIVED, not picked. `PopulationModel.step` is logistic
## -- `growth * P * (1 - P/K)` -- whose growth rate is maximal at exactly
## half of carrying capacity. That is the textbook maximum sustainable
## yield, and harvesting a population below it is precisely the point at
## which the harvest stops being sustainable. So the game's own growth model
## decides when a hunter has gone too far.

const EcologicalGrudge = preload("res://src/gameplay/ecological_grudge.gd")
const PopulationModel = preload("res://src/world/population_model.gd")


# -- the threshold is the growth model's own ------------------------------

## The derivation, asserted against the real model rather than stated in a
## comment: logistic growth peaks at the fraction this module provokes
## below.
func test_the_threshold_is_where_the_real_growth_model_peaks():
	var model := PopulationModel.new(0.2)
	var capacity := 100.0
	var best_population := 0.0
	var best_growth := -INF
	for step in range(1, 100):
		var population := capacity * float(step) / 100.0
		var growth: float = model.step(population, capacity, 1.0) - population
		if growth > best_growth:
			best_growth = growth
			best_population = population
	assert_almost_eq(
		best_population / capacity, EcologicalGrudge.SUSTAINABLE_FRACTION, 0.02,
		"the provocation threshold must be maximum sustainable yield, not a number somebody liked"
	)


func test_the_fraction_really_is_a_half():
	assert_almost_eq(EcologicalGrudge.SUSTAINABLE_FRACTION, 0.5, 0.0001)


# -- a sustainable hunter is ignored --------------------------------------

func test_a_full_region_provokes_nothing():
	assert_false(EcologicalGrudge.is_provoked(100.0, 100.0))


func test_a_lightly_hunted_region_provokes_nothing():
	assert_false(
		EcologicalGrudge.is_provoked(80.0, 100.0),
		"taking a fifth of the herd is what hunting IS"
	)


## Right at the line, the herd is still growing as fast as it can. The
## grudge starts below it.
func test_exactly_at_maximum_sustainable_yield_is_not_yet_provoked():
	assert_false(EcologicalGrudge.is_provoked(50.0, 100.0))


# -- an over-hunter is not ------------------------------------------------

func test_hunting_past_the_sustainable_line_provokes_it():
	assert_true(EcologicalGrudge.is_provoked(49.0, 100.0))


func test_a_stripped_region_provokes_it():
	assert_true(EcologicalGrudge.is_provoked(1.0, 100.0))


func test_an_emptied_region_provokes_it():
	assert_true(EcologicalGrudge.is_provoked(0.0, 100.0))


# -- and ground that never had a herd is not a grudge ---------------------

## A desert is not a crime scene. Ground whose capacity is zero supports no
## herd at all, so nobody can have over-hunted it.
func test_ground_that_can_support_nothing_is_never_provoked():
	for population in [0.0, 5.0]:
		assert_false(
			EcologicalGrudge.is_provoked(population, 0.0),
			"an empty desert is not evidence of anything"
		)


func test_nonsense_capacity_is_never_provoked():
	assert_false(EcologicalGrudge.is_provoked(0.0, -10.0))


# -- the reading itself ---------------------------------------------------

func test_the_depletion_reading_is_the_fraction_taken():
	assert_almost_eq(EcologicalGrudge.depletion_of(75.0, 100.0), 0.25, 0.0001)
	assert_almost_eq(EcologicalGrudge.depletion_of(100.0, 100.0), 0.0, 0.0001)
	assert_almost_eq(EcologicalGrudge.depletion_of(0.0, 100.0), 1.0, 0.0001)


## A region above its own capacity is not negatively depleted -- it is
## simply not depleted.
func test_a_region_over_capacity_reads_as_untouched():
	assert_almost_eq(EcologicalGrudge.depletion_of(150.0, 100.0), 0.0, 0.0001)


func test_the_reading_is_always_a_fraction():
	for population in [-5.0, 0.0, 33.0, 100.0, 1000.0]:
		var depletion := EcologicalGrudge.depletion_of(population, 100.0)
		assert_true(depletion >= 0.0 and depletion <= 1.0, "%f is not a fraction" % depletion)


## The two readings must agree: provoked exactly when more than the
## sustainable share has been taken.
func test_provocation_and_depletion_never_disagree():
	for step in range(0, 101):
		var population := float(step)
		assert_eq(
			EcologicalGrudge.is_provoked(population, 100.0),
			EcologicalGrudge.depletion_of(population, 100.0) > 1.0 - EcologicalGrudge.SUSTAINABLE_FRACTION,
			"the two readings disagree at a population of %f" % population
		)


# -- it reads a footprint, never a position -------------------------------

## The roster's own claim about this creature. A grudge that could see where
## you are standing would be an ordinary predator with extra steps.
func test_nothing_here_can_see_where_the_player_is():
	var forbidden: Array = [
		"position", "distance", "nearest", "in_range", "can_see", "line_of_sight",
	]
	var declared: Array = []
	for method in EcologicalGrudge.new().get_script().get_script_method_list():
		declared.append(method["name"])
	assert_true(declared.has("is_provoked"), "reflection returned nothing -- the guard would be vacuous")
	for name in declared:
		for forbidden_name in forbidden:
			assert_false(
				String(name).contains(forbidden_name),
				"%s reads a position; this creature reads a footprint" % name
			)
