extends GutTest

const PopulationModel = preload("res://src/world/population_model.gd")

var model: PopulationModel


func before_each():
	model = PopulationModel.new(0.4)  # 0.4 == growth_rate_per_day


# -- step (logistic reproduction/death toward capacity) -----------------------

func test_step_grows_population_toward_capacity():
	var next := model.step(2.0, 10.0, 1.0)
	assert_gt(next, 2.0)
	assert_lt(next, 10.0)


func test_step_never_exceeds_capacity_even_with_a_huge_delta():
	var next := model.step(2.0, 10.0, 1000.0)
	assert_almost_eq(next, 10.0, 0.01)


func test_step_declines_population_that_is_above_capacity():
	# e.g. vegetation collapsed (drought) out from under an existing herd.
	var next := model.step(10.0, 2.0, 1.0)
	assert_lt(next, 10.0)


func test_step_stays_at_zero_when_capacity_is_zero():
	var next := model.step(0.0, 0.0, 5.0)
	assert_eq(next, 0.0)


func test_step_never_goes_negative():
	var next := model.step(0.01, 0.0, 1000.0)
	assert_gte(next, 0.0)


# -- migrate (redistribution between neighboring regions) ---------------------

func test_migrate_moves_population_from_overcrowded_to_spare_capacity_neighbor():
	var populations := {Vector2i(0, 0): 10.0, Vector2i(1, 0): 0.0}
	var capacities := {Vector2i(0, 0): 2.0, Vector2i(1, 0): 10.0}

	var next: Dictionary = model.migrate(populations, capacities, 0.1, 1.0)

	assert_lt(next[Vector2i(0, 0)], 10.0, "overcrowded region should lose population")
	assert_gt(next[Vector2i(1, 0)], 0.0, "spare-capacity neighbor should gain population")


func test_migrate_conserves_total_population():
	var populations := {Vector2i(0, 0): 10.0, Vector2i(1, 0): 0.0, Vector2i(2, 0): 3.0}
	var capacities := {Vector2i(0, 0): 2.0, Vector2i(1, 0): 10.0, Vector2i(2, 0): 3.0}

	var next: Dictionary = model.migrate(populations, capacities, 0.1, 1.0)

	var total_before := 0.0
	for v in populations.values():
		total_before += v
	var total_after := 0.0
	for v in next.values():
		total_after += v
	assert_almost_eq(total_after, total_before, 0.01)


func test_migrate_leaves_an_isolated_region_unchanged():
	var populations := {Vector2i(0, 0): 5.0, Vector2i(50, 50): 5.0}
	var capacities := {Vector2i(0, 0): 5.0, Vector2i(50, 50): 1.0}

	var next: Dictionary = model.migrate(populations, capacities, 0.5, 1.0)

	assert_almost_eq(next[Vector2i(0, 0)], 5.0, 0.0001)
	assert_almost_eq(next[Vector2i(50, 50)], 5.0, 0.0001)


func test_migrate_never_produces_negative_population():
	var populations := {Vector2i(0, 0): 0.5, Vector2i(1, 0): 0.0}
	var capacities := {Vector2i(0, 0): 0.5, Vector2i(1, 0): 100.0}

	var next: Dictionary = model.migrate(populations, capacities, 5.0, 1000.0)

	assert_gte(next[Vector2i(0, 0)], 0.0)
	assert_gte(next[Vector2i(1, 0)], 0.0)
