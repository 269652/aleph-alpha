extends GutTest

## Phase 1 roadmap's explicit "Basic time-lapse test": run the simulation for
## N simulated days with no player present and confirm population
## distributions shift sensibly -- both naturally (different biomes end up
## with different populations, with no hand-placed spawners) and in response
## to a scripted disturbance (a drought visibly shifts where creatures are
## found afterward).

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


func test_creatures_naturally_cluster_more_in_lush_biomes_than_barren_ones():
	# Far enough apart that migration between them isn't a factor -- this is
	# about each region settling near its own biome's carrying capacity, not
	# about redistribution.
	var lush_coord := Vector2i(0, 0)
	var barren_coord := Vector2i(1000, 1000)
	simulation.add_region(lush_coord, _make_chunk("rainforest", 0.9, 0.9))
	simulation.add_region(barren_coord, _make_chunk("desert", 0.9, 0.1))

	for day in 30:
		simulation.step(1.0)

	assert_gt(
		simulation.herbivore_population(lush_coord),
		simulation.herbivore_population(barren_coord),
		"rainforest should sustain more herbivores than desert"
	)
	assert_gt(
		simulation.predator_population(lush_coord),
		simulation.predator_population(barren_coord),
		"more prey in the rainforest should sustain more predators there too"
	)


func test_a_scripted_drought_visibly_shifts_where_creatures_are_found():
	var coord := Vector2i(0, 0)
	simulation.add_region(coord, _make_chunk("grassland", 0.8, 0.8))

	# Let the region reach a stable, lived-in equilibrium first.
	for day in 30:
		simulation.step(1.0)
	var herbivores_before_drought := simulation.herbivore_population(coord)
	var predators_before_drought := simulation.predator_population(coord)
	assert_gt(herbivores_before_drought, 0.0, "sanity check: region should be populated before the drought")

	# Drought: rain stops, but it's still the same grassland otherwise.
	simulation.update_environment(coord, _make_chunk("grassland", 0.8, 0.0))
	for day in 30:
		simulation.step(1.0)

	assert_lt(
		simulation.herbivore_population(coord),
		herbivores_before_drought,
		"herbivore population should visibly decline after a drought"
	)
	assert_lt(
		simulation.predator_population(coord),
		predators_before_drought,
		"predator population should follow prey decline downward after a drought"
	)


func test_population_recovers_after_a_drought_ends():
	var coord := Vector2i(0, 0)
	simulation.add_region(coord, _make_chunk("grassland", 0.8, 0.8))
	for day in 30:
		simulation.step(1.0)

	simulation.update_environment(coord, _make_chunk("grassland", 0.8, 0.0))
	for day in 30:
		simulation.step(1.0)
	var herbivores_during_drought := simulation.herbivore_population(coord)

	# The rains return.
	simulation.update_environment(coord, _make_chunk("grassland", 0.8, 0.8))
	for day in 60:
		simulation.step(1.0)

	assert_gt(
		simulation.herbivore_population(coord),
		herbivores_during_drought,
		"population should recover once the drought ends and vegetation regrows"
	)
