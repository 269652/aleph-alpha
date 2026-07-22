extends GutTest

const EcosystemSimulation = preload("res://src/world/ecosystem_simulation.gd")
const Chunk = preload("res://src/world/chunk.gd")

var simulation: EcosystemSimulation


func before_each():
	simulation = EcosystemSimulation.new()


func _make_chunk(biome_name: String, temperature: float, moisture: float, size: int = 4) -> Chunk:
	var chunk := Chunk.new()
	chunk.width = size
	chunk.height = size
	chunk.elevation = PackedFloat32Array()
	chunk.elevation.resize(size * size)
	chunk.biome = PackedStringArray()
	chunk.biome.resize(size * size)
	chunk.biome.fill(biome_name)
	chunk.temperature = PackedFloat32Array()
	chunk.temperature.resize(size * size)
	chunk.temperature.fill(temperature)
	chunk.moisture = PackedFloat32Array()
	chunk.moisture.resize(size * size)
	chunk.moisture.fill(moisture)
	return chunk


func test_add_region_starts_populated_for_a_hospitable_biome():
	# Vegetation/creatures are assumed to already exist in the world at
	# equilibrium when a region is first visited, not grown from nothing --
	# matches the static tree placement the game already uses.
	simulation.add_region(Vector2i(0, 0), _make_chunk("rainforest", 0.9, 0.9))

	assert_gt(simulation.average_vegetation_density(Vector2i(0, 0)), 0.0)
	assert_gt(simulation.herbivore_population(Vector2i(0, 0)), 0.0)
	assert_gt(simulation.predator_population(Vector2i(0, 0)), 0.0)


func test_add_region_stays_empty_for_an_inhospitable_biome():
	simulation.add_region(Vector2i(0, 0), _make_chunk("ocean", 0.9, 0.9))

	assert_eq(simulation.average_vegetation_density(Vector2i(0, 0)), 0.0)
	assert_eq(simulation.herbivore_population(Vector2i(0, 0)), 0.0)
	assert_eq(simulation.predator_population(Vector2i(0, 0)), 0.0)


func test_has_region_reflects_add_and_remove():
	var coord := Vector2i(3, 3)
	assert_false(simulation.has_region(coord))

	simulation.add_region(coord, _make_chunk("grassland", 0.7, 0.7))
	assert_true(simulation.has_region(coord))

	simulation.remove_region(coord)
	assert_false(simulation.has_region(coord))


func test_step_does_not_crash_with_no_regions_loaded():
	simulation.step(1.0)
	pass_test("step() with zero regions should be a no-op, not an error")


func test_step_keeps_populations_within_their_capacities_over_many_days():
	simulation.add_region(Vector2i(0, 0), _make_chunk("forest", 0.7, 0.7))

	for i in 50:
		simulation.step(1.0)

	var vegetation_capacity := 1.0  # forest's own carrying capacity is < 1.0; loose upper bound
	assert_between(simulation.average_vegetation_density(Vector2i(0, 0)), 0.0, vegetation_capacity)
	assert_gte(simulation.herbivore_population(Vector2i(0, 0)), 0.0)
	assert_gte(simulation.predator_population(Vector2i(0, 0)), 0.0)


func test_migration_moves_surplus_population_to_an_adjacent_spare_capacity_region():
	# Two thriving, at-equilibrium regions have zero surplus each -- nothing
	# should migrate between them just because their capacities differ. A
	# region that suddenly becomes overcrowded relative to its OWN new
	# capacity is what should push population toward a spare-capacity
	# neighbor -- exactly what a drought does to an existing population.
	var crowded_coord := Vector2i(0, 0)
	var spare_coord := Vector2i(1, 0)
	simulation.add_region(crowded_coord, _make_chunk("rainforest", 0.9, 0.9))
	simulation.add_region(spare_coord, _make_chunk("rainforest", 0.9, 0.9))

	simulation.update_environment(crowded_coord, _make_chunk("desert", 0.9, 0.0))

	var spare_population_before := simulation.herbivore_population(spare_coord)
	for i in 5:
		simulation.step(1.0)

	assert_gt(simulation.herbivore_population(spare_coord), spare_population_before)


func test_update_environment_changes_future_steps_without_resetting_current_state():
	var coord := Vector2i(0, 0)
	simulation.add_region(coord, _make_chunk("grassland", 0.8, 0.8))
	for i in 10:
		simulation.step(1.0)
	var population_at_swap := simulation.herbivore_population(coord)

	simulation.update_environment(coord, _make_chunk("grassland", 0.8, 0.8))

	assert_almost_eq(simulation.herbivore_population(coord), population_at_swap, 0.01)


func test_seed_populations_overrides_the_equilibrium_from_add_region():
	# add_region seeds a region at carrying-capacity equilibrium; the
	# unloaded-chunk catch-up (EarthChunkManager) needs to override that with
	# the caught-up populations from ChunkEcologyCatchup on revisit.
	var chunk := _make_chunk("grassland", 0.6, 0.6)
	var sim = EcosystemSimulation.new()
	sim.add_region(Vector2i.ZERO, chunk)
	var cap = sim.herbivore_capacity_at(Vector2i.ZERO)
	assert_gt(cap, 0.0, "grassland should have positive herbivore capacity")

	sim.seed_populations(Vector2i.ZERO, 2.0, 1.0)
	assert_almost_eq(sim.herbivore_population(Vector2i.ZERO), 2.0, 0.001)
	assert_almost_eq(sim.predator_population(Vector2i.ZERO), 1.0, 0.001)


func test_herbivore_capacity_at_is_zero_for_an_unknown_region():
	var sim = EcosystemSimulation.new()
	assert_eq(sim.herbivore_capacity_at(Vector2i(9, 9)), 0.0)
