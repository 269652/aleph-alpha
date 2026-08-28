extends GutTest

## Regional/aggregate kingfisher population: same shape as
## PredatorPopulationModel, but tracking the EXISTING aquatic fish population
## instead of a new food-density signal -- a kingfisher's prey IS the fish
## EcosystemSimulation already tracks (see docs/concept/ecosystem_dynamics.md's
## Open questions: "a real 'more fish support more birds' feedback ... is a
## natural, grounded follow-up").

const KingfisherPopulationModel = preload("res://src/world/kingfisher_population_model.gd")
const AquaticPopulationModel = preload("res://src/world/aquatic_population_model.gd")

var model: KingfisherPopulationModel


func before_each():
	model = KingfisherPopulationModel.new()


func test_carrying_capacity_is_zero_without_fish():
	assert_eq(model.carrying_capacity(0.0), 0.0)


func test_carrying_capacity_increases_with_fish_population():
	var low := model.carrying_capacity(10.0)
	var high := model.carrying_capacity(100.0)
	assert_gt(high, low)


func test_carrying_capacity_is_a_small_fraction_of_fish_population():
	# Trophic pyramid: a real stretch of river sustains far fewer kingfishers
	# than fish -- a breeding pair's territory can span a long run of bank.
	var fish_population := 100.0
	var capacity := model.carrying_capacity(fish_population)
	assert_lt(capacity, fish_population)


func test_growth_rate_is_slower_than_fish_baseline():
	# Predators reproduce slower than their prey -- kingfishers raise one
	# brood of a handful of chicks a year, nowhere near a fish stock's high
	# fecundity (AquaticPopulationModel.GROWTH_RATE_PER_DAY).
	assert_lt(KingfisherPopulationModel.GROWTH_RATE_PER_DAY, AquaticPopulationModel.GROWTH_RATE_PER_DAY)


func test_step_grows_population_toward_capacity():
	var next := model.step(1.0, 5.0, 1.0)
	assert_gt(next, 1.0)
	assert_lte(next, 5.0)


func test_migrate_moves_population_toward_spare_capacity_neighbor():
	var populations := {Vector2i(0, 0): 5.0, Vector2i(1, 0): 0.0}
	var capacities := {Vector2i(0, 0): 0.5, Vector2i(1, 0): 5.0}

	var next: Dictionary = model.migrate(populations, capacities, 1.0)

	assert_gt(next[Vector2i(1, 0)], 0.0)
