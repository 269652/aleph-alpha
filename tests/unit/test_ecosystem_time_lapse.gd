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


# -- predation is a disturbance too: hunting suppresses, and it recovers ------
#
# docs/concept/ecosystem_dynamics.md's own pillar: "Populations rise and fall
# from births, deaths, PREDATION, and food." The drought tests above already
# prove a disturbance visibly moves a region's population and that it
# recovers once the disturbance lifts; this proves the exact same shape for
# repeated individual kills instead of weather -- the causal link
# EcosystemSimulation.record_death exists for. A real, individually-simulated
# creature dying (health.gd's take_damage/is_dead reaching zero) via player
# combat books its death through CreatureMarker._book_death_against_the_region
# -> EarthChunkManager.record_death_at -> here, keyed by the SAME
# _chunk_coord_for_tile the promotion system
# (EarthChunkManager._reconcile_chunk_creatures) already reads population
# from -- so there is no separate "promotion region" for this to drift
# against; suppressing the population IS suppressing the promotion rate
# (CreatureRenderer.marker_count_for is a monotonic function of it).

func test_repeated_kills_measurably_suppress_a_regions_population_versus_an_unhunted_control():
	# Two identical, far-apart (no migration -- see
	# test_creatures_naturally_cluster_more_in_lush_biomes_than_barren_ones's
	# same idiom above) regions start at the same seeded equilibrium. Only one
	# absorbs kills; the other is the control a real unhunted valley would be.
	var hunted_coord := Vector2i(0, 0)
	var control_coord := Vector2i(1000, 1000)
	simulation.add_region(hunted_coord, _make_chunk("grassland", 0.8, 0.8))
	simulation.add_region(control_coord, _make_chunk("grassland", 0.8, 0.8))
	assert_almost_eq(
		simulation.herbivore_population(hunted_coord),
		simulation.herbivore_population(control_coord),
		0.001
	)

	# A kill a day, well above what a single day of logistic growth could ever
	# replace -- genuine sustained hunting pressure, the same "sustained, not
	# one-off" shape test_sustained_overharvest_depletes_land_health_over_many_
	# steps already uses for vegetation harvest.
	var capacity: float = simulation.herbivore_capacity_at(hunted_coord)
	for day in 6:
		simulation.record_death(hunted_coord, false, capacity * 0.15)
		simulation.step(1.0)

	assert_lt(
		simulation.herbivore_population(hunted_coord),
		simulation.herbivore_population(control_coord),
		"a region absorbing repeated kills should fall measurably behind an identical, unhunted twin"
	)
	assert_gt(
		simulation.herbivore_population(hunted_coord), 0.0,
		"sanity check: this hunting pressure should suppress, not annihilate, the population"
	)


func test_a_hunted_regions_population_recovers_once_the_killing_stops():
	var coord := Vector2i(0, 0)
	simulation.add_region(coord, _make_chunk("grassland", 0.8, 0.8))
	var capacity: float = simulation.herbivore_capacity_at(coord)

	for day in 6:
		simulation.record_death(coord, false, capacity * 0.15)
		simulation.step(1.0)
	var herbivores_after_hunting := simulation.herbivore_population(coord)

	# The killing stops; nothing further removes population, so the model's
	# own existing reproduction term (PopulationModel.step's logistic growth)
	# is the only thing left that can move the number -- exactly like
	# vegetation regrowing once a drought ends above.
	for day in 40:
		simulation.step(1.0)

	assert_gt(
		simulation.herbivore_population(coord),
		herbivores_after_hunting,
		"population should recover via ordinary reproduction once hunting stops"
	)


## The same causal shape, proven for the OTHER population model too --
## predator_population_model.gd, not just herbivore_population_model.gd --
## since record_death books a kill against whichever pool the dead
## creature's own is_predator flag names (see EcosystemSimulation.
## record_death's own doc comment, and CreatureInfo.is_predator, which is
## what CreatureMarker passes through _book_death_against_the_region). Prey
## (herbivores) are left untouched here so predator carrying capacity -- which
## is itself derived from the herbivore population every step -- stays a
## fixed target rather than a second moving variable.
func test_repeated_predator_kills_suppress_and_then_recover_the_predator_population():
	var coord := Vector2i(0, 0)
	simulation.add_region(coord, _make_chunk("grassland", 0.8, 0.8))
	var capacity: float = simulation.predator_population(coord)
	assert_gt(capacity, 0.0, "sanity check: grassland should start with a real predator population")

	for day in 6:
		simulation.record_death(coord, true, capacity * 0.15)
		simulation.step(1.0)
	var predators_after_hunting := simulation.predator_population(coord)

	assert_lt(
		predators_after_hunting, capacity,
		"repeated predator kills should measurably suppress the predator population"
	)
	assert_gt(
		predators_after_hunting, 0.0,
		"sanity check: this hunting pressure should suppress, not annihilate, the population"
	)

	for day in 60:
		simulation.step(1.0)

	assert_gt(
		simulation.predator_population(coord),
		predators_after_hunting,
		"predator population should recover via reproduction once hunting stops"
	)
