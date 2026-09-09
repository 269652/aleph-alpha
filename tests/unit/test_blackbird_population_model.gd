extends GutTest

## Regional/aggregate blackbird population: reproduction/migration/death as a
## function of local worm density (see EarthwormPatch.worm_cells and
## docs/concept/seasonal_behavior.md, "Blackbird: new species, real
## population, real diet shift"). Mirrors Robin/SparrowPopulationModel's
## test shape exactly.
##
## Real blackbirds (Turdus merula) are thrushes -- the same real ecological
## role as the robin this project already models (both are worm-hunting
## lawn/garden birds), not the seed-bulk-feeding sparrow -- so worm density
## is the real, closest-available capacity signal, not a new one invented
## for this species.

const BlackbirdPopulationModel = preload("res://src/world/blackbird_population_model.gd")
const RobinPopulationModel = preload("res://src/world/robin_population_model.gd")

var model: BlackbirdPopulationModel


func before_each():
	model = BlackbirdPopulationModel.new()


func test_carrying_capacity_is_zero_without_worms():
	assert_eq(model.carrying_capacity(0.0), 0.0)


func test_carrying_capacity_increases_with_worm_density():
	var low := model.carrying_capacity(2.0)
	var high := model.carrying_capacity(20.0)
	assert_gt(high, low)


func test_growth_rate_matches_its_closest_real_ecological_analog():
	# Blackbirds and robins are both thrushes with a genuinely similar real
	# breeding rate -- unlike the sparrow (a different family with a
	# distinctly faster, bulk-brooding strategy already modeled separately),
	# there is no real basis to invent a DIFFERENT rate here.
	assert_eq(BlackbirdPopulationModel.GROWTH_RATE_PER_DAY, RobinPopulationModel.GROWTH_RATE_PER_DAY)


func test_supports_fewer_blackbirds_per_worm_cell_than_robins():
	# A blackbird's real diet leans on fruit more than a robin's does (see
	# FlyerDiet's own real fruit list for each) -- the same worm density
	# should support proportionally FEWER blackbirds than robins, since
	# blackbirds are less exclusively worm-dependent. A real, derived
	# ordering (see the constant's own doc comment for the exact ratio),
	# not an eyeballed number.
	assert_lt(BlackbirdPopulationModel.BLACKBIRDS_PER_WORM_CELL, RobinPopulationModel.ROBINS_PER_WORM_CELL)


func test_step_grows_population_toward_capacity():
	var next := model.step(1.0, 10.0, 1.0)
	assert_gt(next, 1.0)
	assert_lte(next, 10.0)


func test_migrate_moves_population_toward_spare_capacity_neighbor():
	var populations := {Vector2i(0, 0): 10.0, Vector2i(1, 0): 0.0}
	var capacities := {Vector2i(0, 0): 1.0, Vector2i(1, 0): 10.0}

	var next: Dictionary = model.migrate(populations, capacities, 1.0)

	assert_gt(next[Vector2i(1, 0)], 0.0)
