extends GutTest

## Per-chunk ant-colony population -- myrmecochory (seed harvesting), see
## docs/concept/soil_fauna.md's "Ants" section.
##
## Same per-chunk patch-sim contract as EarthwormPatch/FlowerPatch/TallGrass/
## DesertScrub/TundraLichen -- deterministic PixelNoise-seeded placement, a
## hard cap, advance(delta), and (here) a pure per-mound foraging-chance
## query rather than a consumption method, since a mound doesn't get "eaten"
## the way a burrow or a patch does.

const AntColony = preload("res://src/world/ant_colony.gd")
const EarthwormPatch = preload("res://src/world/earthworm_patch.gd")
const SeedCaching = preload("res://src/gameplay/seed_caching.gd")
const SquirrelNutCaching = preload("res://src/gameplay/squirrel_nut_caching.gd")
const SeedEndozoochory = preload("res://src/gameplay/seed_endozoochory.gd")
const AntPopulationModel = preload("res://src/world/ant_population_model.gd")
const PheromoneField = preload("res://src/world/pheromone_field.gd")
const EarthChunkManager = preload("res://src/world/earth_chunk_manager.gd")

const SIZE := 32


func _biome(name: String, size: int = SIZE) -> PackedStringArray:
	var out := PackedStringArray()
	for i in size * size:
		out.append(name)
	return out


func _colony(biome_name: String = "grassland", seed_value: int = 1234) -> AntColony:
	return AntColony.new(seed_value, SIZE, SIZE, _biome(biome_name))


# -- placement ----------------------------------------------------------------

func test_seeds_mounds_in_soil_bearing_biomes():
	for biome_name in ["grassland", "forest", "rainforest"]:
		var colony := _colony(biome_name)
		assert_gt(colony.mound_cells().size(), 0, "%s has soil, so it has ant mounds" % biome_name)


func test_seeds_no_mounds_in_soilless_biomes():
	for biome_name in ["ocean", "desert", "tundra", "mountain"]:
		var colony := _colony(biome_name)
		assert_eq(colony.mound_cells().size(), 0, "%s should have no ant mounds" % biome_name)


func test_is_deterministic_for_the_same_seed():
	var a := _colony("grassland", 99)
	var b := _colony("grassland", 99)
	assert_eq(a.mound_cells(), b.mound_cells())


func test_different_seeds_give_different_layouts():
	var a := _colony("grassland", 1)
	var b := _colony("grassland", 2)
	assert_ne(a.mound_cells(), b.mound_cells())


func test_never_exceeds_the_per_chunk_cap():
	for seed_value in range(12):
		var colony := _colony("grassland", seed_value * 7717)
		assert_lte(colony.mound_cells().size(), AntColony.MAX_MOUNDS)


## Real ant nest density per unit area is typically higher than earthworm
## burrow density in the same soil -- pinned as an ordering, not eyeballed.
func test_mounds_are_denser_than_earthworm_burrows():
	assert_gt(AntColony.MOUND_CHANCE, EarthwormPatch.SEED_CHANCE)


func test_has_mound_only_where_one_was_seeded():
	var colony := _colony()
	for cell in colony.mound_cells():
		assert_true(colony.has_mound(cell))
	assert_false(colony.has_mound(Vector2i(-1, -1)))


# -- foraging chance: a small deterministic-per-step roll, PixelNoise-seeded
# off the mound position and the colony's own step count, never hash() -----

func test_forage_roll_spreads_across_true_and_false():
	var colony := _colony()
	var yes := 0
	var no := 0
	for cell in colony.mound_cells():
		if colony.should_forage(cell):
			yes += 1
		else:
			no += 1
	# Advance many steps so different step counts get sampled too, not just
	# step 0 -- the clustering bug this project has hit before would show up
	# as every mound landing on the same side forever.
	for i in 200:
		colony.advance(1.0)
		for cell in colony.mound_cells():
			if colony.should_forage(cell):
				yes += 1
			else:
				no += 1
	assert_gt(yes, 0, "some steps should roll a forage attempt")
	assert_gt(no, 0, "most steps should not -- it is a small chance, not a switch")


func test_forage_chance_is_small():
	# A per-call probability, not a near-certainty: step_ants is expected to
	# be called many times a second under normal play (see step_worms'
	# comment on cadence), so anything close to 1.0 would empty every seed
	# within the first second of a chunk loading.
	assert_gt(AntColony.FORAGE_CHANCE, 0.0)
	assert_lt(AntColony.FORAGE_CHANCE, 0.2)


func test_advancing_does_not_change_mound_placement():
	var colony := _colony()
	var before := colony.mound_cells()
	colony.advance(5.0)
	assert_eq(colony.mound_cells(), before, "advance only moves the foraging step, never the mounds")


# -- carry distance and direction: myrmecochory moves a seed the shortest
# range of the game's whole carrier family (coat-carry > gut-passage flight >
# rodent cache > this) -----------------------------------------------------

func test_carry_distance_stays_in_its_own_range():
	for seed_value in [1, 42, 999, 123456]:
		var tiles := AntColony.carry_distance_tiles(seed_value)
		assert_between(tiles, AntColony.CARRY_MIN_TILES, AntColony.CARRY_MAX_TILES)


func test_carry_distance_is_deterministic():
	assert_eq(AntColony.carry_distance_tiles(555), AntColony.carry_distance_tiles(555))


func test_carry_distances_vary_across_seeds():
	var values := {}
	for seed_value in range(20):
		values[AntColony.carry_distance_tiles(seed_value * 3701)] = true
	assert_gt(values.size(), 1, "different carriers should not all cache at the identical range")


## Pinned relationship, mirroring test_rodent_carry_range_is_shorter_than_* in
## test_seed_caching.gd: myrmecochory is shorter-range than even the mouse's
## own scatter-hoard carry, since real ants move a seed centimetres to a
## couple of metres -- the shortest-range disperser of the whole family.
func test_ant_carry_range_is_shorter_than_rodent_carry_range():
	assert_lt(AntColony.CARRY_MAX_TILES, SeedCaching.CARRY_MIN_TILES)


## And the ant's own foraging reach from its mound is shorter still than a
## mouse's home-range pickup radius (SeedCaching.PICKUP_RADIUS_TILES, 3.0
## tiles) -- an ant's foraging range from its mound is far smaller than a
## mouse's home range.
func test_ant_forage_radius_is_shorter_than_rodent_pickup_radius():
	assert_lt(AntColony.FORAGE_RADIUS_TILES, SeedCaching.PICKUP_RADIUS_TILES)


func test_carry_direction_is_a_unit_vector():
	for seed_value in [1, 42, 999]:
		var direction: Vector2 = AntColony.carry_direction(seed_value)
		assert_almost_eq(direction.length(), 1.0, 0.001)


func test_carry_direction_is_deterministic():
	assert_eq(AntColony.carry_direction(77), AntColony.carry_direction(77))


func test_carry_direction_varies_across_seeds():
	var directions := {}
	for seed_value in range(20):
		directions[AntColony.carry_direction(seed_value * 4111)] = true
	assert_gt(directions.size(), 1, "carries should not all head the same way")


## The carrier seed a caller uses to actually place a harvested seed --
## deterministic per (mound cell, colony step), so a reloaded chunk at the
## same moment caches the same way, and different mounds/steps don't collide
## on the same offset.
func test_carrier_seed_is_deterministic_per_cell_and_step():
	var colony := _colony()
	var cell: Vector2i = colony.mound_cells()[0]
	assert_eq(colony.carrier_seed_for(cell), colony.carrier_seed_for(cell))


func test_carrier_seed_changes_as_the_colony_advances():
	var colony := _colony()
	var cell: Vector2i = colony.mound_cells()[0]
	var before := colony.carrier_seed_for(cell)
	for i in 50:
		colony.advance(1.0)
	assert_ne(colony.carrier_seed_for(cell), before, "the carrier seed should move on as the colony steps")


# -- windfall fruit/nut foraging (forest/rainforest mounds): closes the
# "structurally present but has nothing to harvest" gap this file's own
# doc comment used to name for a forest/rainforest mound, since TallGrass's
# ground seed is grassland-only. A single forager ant cannot carry off an
# intact nut/dried-fruit propagule the way a squirrel or bird can, so this is
# a far more consumption-dominant case than the grass-seed myrmecochory
# above -- see WINDFALL_CONSUMED_CHANCE's own doc comment. Pinned the same
# way test_squirrel_nut_caching.gd pins SquirrelNutCaching.NUT_CONSUMED_CHANCE
# / nut_is_consumed.

func test_windfall_consumed_chance_is_a_majority_but_not_a_certainty():
	assert_gt(AntColony.WINDFALL_CONSUMED_CHANCE, 0.5)
	assert_lt(AntColony.WINDFALL_CONSUMED_CHANCE, 1.0)


## Ants are the LEAST effective disperser of a large propagule of any
## forager in this game -- a squirrel physically carries a whole nut away in
## its mouth, and a bird swallows a whole seed in flight, but a forager ant
## interacting with fallen fruit/nut debris is documented almost entirely as
## a scavenger/decomposer of soft pulp and residue, not a disperser of the
## hard propagule itself. So this sits ABOVE both existing consumed-chance
## constants, not just above 0.5.
func test_windfall_consumed_chance_is_higher_than_squirrel_and_sparrow():
	assert_gt(AntColony.WINDFALL_CONSUMED_CHANCE, SquirrelNutCaching.NUT_CONSUMED_CHANCE)
	assert_gt(AntColony.WINDFALL_CONSUMED_CHANCE, SeedEndozoochory.GRANIVORY_CONSUMED_CHANCE)


func test_windfall_is_consumed_mostly_true_but_leaves_a_real_minority_cached():
	var consumed := 0
	var cached := 0
	for seed_value in 200:
		if AntColony.windfall_is_consumed(seed_value):
			consumed += 1
		else:
			cached += 1
	assert_gt(consumed, cached, "a colony mostly consumes windfall debris rather than dispersing it")
	assert_gt(cached, 0, "but never say never -- a real minority should still survive to be cached")


func test_windfall_is_consumed_is_deterministic():
	assert_eq(AntColony.windfall_is_consumed(11), AntColony.windfall_is_consumed(11))


## The windfall carrier seed -- deterministic per (mound cell, colony step),
## exactly like carrier_seed_for above, but off its OWN salt
## (_WINDFALL_SALT) so it does not correlate with should_forage's or
## carrier_seed_for's own rolls for the same (cell, step).
func test_windfall_carrier_seed_is_deterministic_per_cell_and_step():
	var colony := _colony()
	var cell: Vector2i = colony.mound_cells()[0]
	assert_eq(colony.windfall_carrier_seed_for(cell), colony.windfall_carrier_seed_for(cell))


func test_windfall_carrier_seed_changes_as_the_colony_advances():
	var colony := _colony()
	var cell: Vector2i = colony.mound_cells()[0]
	var before := colony.windfall_carrier_seed_for(cell)
	for i in 50:
		colony.advance(1.0)
	assert_ne(
		colony.windfall_carrier_seed_for(cell), before,
		"the windfall carrier seed should move on as the colony steps"
	)


## The windfall roll must vary independently of the grass-seed carrier roll
## for the same (cell, step) -- the whole point of giving it its own salt.
func test_windfall_carrier_seed_differs_from_the_grass_carrier_seed():
	var colony := _colony()
	var differed := false
	for cell in colony.mound_cells():
		if colony.windfall_carrier_seed_for(cell) != colony.carrier_seed_for(cell):
			differed = true
			break
	assert_true(differed, "an independent salt should not collide with the grass-seed carrier roll")


# -- a queen, and where a colony's size comes from (see docs/concept/
# soil_fauna.md#a-queen-and-where-a-colonys-size-comes-from) ---------------

func test_population_starts_at_the_founding_size():
	var colony := _colony()
	var cell: Vector2i = colony.mound_cells()[0]
	assert_eq(colony.population_at(cell), AntPopulationModel.STARTING_POPULATION)


func test_capacity_starts_at_the_unfed_baseline():
	var colony := _colony()
	var cell: Vector2i = colony.mound_cells()[0]
	assert_almost_eq(colony.capacity_at(cell), AntPopulationModel.BASE_CAPACITY, 0.001)


func test_recording_forage_success_raises_capacity():
	var colony := _colony()
	var cell: Vector2i = colony.mound_cells()[0]
	var before := colony.capacity_at(cell)
	for i in 20:
		colony.record_forage_result(cell, true)
	assert_gt(colony.capacity_at(cell), before)


func test_recording_forage_failure_does_not_raise_capacity_above_baseline():
	var colony := _colony()
	var cell: Vector2i = colony.mound_cells()[0]
	for i in 20:
		colony.record_forage_result(cell, false)
	assert_almost_eq(colony.capacity_at(cell), AntPopulationModel.BASE_CAPACITY, 0.001)


## The real feedback loop: a mound that keeps finding food grows a bigger
## colony than an equally-old one that keeps coming home empty.
func test_a_well_fed_mound_grows_larger_than_a_starved_one():
	var fed := _colony("grassland", 42)
	var starved := _colony("grassland", 42)
	var cell: Vector2i = fed.mound_cells()[0]
	for i in 100:
		fed.record_forage_result(cell, true)
		starved.record_forage_result(cell, false)
		fed.advance(1.0)
		starved.advance(1.0)
	assert_gt(fed.population_at(cell), starved.population_at(cell))


# -- water, not just food: a second real growth driver (see docs/concept/
# soil_fauna.md's own section by that name) --------------------------------

func test_recording_moisture_raises_capacity():
	var colony := _colony()
	var cell: Vector2i = colony.mound_cells()[0]
	var before := colony.capacity_at(cell)
	for i in 20:
		colony.record_moisture(cell, 1.0)
	assert_gt(colony.capacity_at(cell), before)


func test_recording_dryness_does_not_raise_capacity_above_baseline():
	var colony := _colony()
	var cell: Vector2i = colony.mound_cells()[0]
	for i in 20:
		colony.record_moisture(cell, 0.0)
	assert_almost_eq(colony.capacity_at(cell), AntPopulationModel.BASE_CAPACITY, 0.001)


## Food and water act independently -- a well-fed colony on damp ground
## supports more than either advantage alone.
func test_food_and_water_together_raise_capacity_more_than_either_alone():
	var colony := _colony()
	var cell: Vector2i = colony.mound_cells()[0]
	for i in 20:
		colony.record_forage_result(cell, true)
		colony.record_moisture(cell, 1.0)
	var both := colony.capacity_at(cell)

	var food_only := _colony()
	var food_cell: Vector2i = food_only.mound_cells()[0]
	for i in 20:
		food_only.record_forage_result(food_cell, true)
	assert_gt(both, food_only.capacity_at(food_cell))


## The real feedback loop, water half: a mound on consistently damp
## ground grows a bigger colony than an equally-old one on parched
## ground, even with identical (absent) forage success.
func test_a_well_watered_mound_grows_larger_than_a_dry_one():
	var damp := _colony("grassland", 42)
	var dry := _colony("grassland", 42)
	var cell: Vector2i = damp.mound_cells()[0]
	for i in 100:
		damp.record_moisture(cell, 1.0)
		dry.record_moisture(cell, 0.0)
		damp.advance(1.0)
		dry.advance(1.0)
	assert_gt(damp.population_at(cell), dry.population_at(cell))


# -- growth_fraction_at: what a mound's own visual size reads (see
# ProceduralAntMoundSprite.world_width_for) -------------------------------

func test_growth_fraction_starts_near_zero_for_a_founding_colony():
	var colony := _colony()
	var cell: Vector2i = colony.mound_cells()[0]
	assert_lt(colony.growth_fraction_at(cell), 0.1)


## AntColony.advance is a single Euler step (PopulationModel.step), not a
## closed-form solution -- it badly under-integrates for large single
## deltas, so this saturates both EMAs first (20 calls each, matching
## FORAGE_SUCCESS_EMA_RATE/MOISTURE_EMA_RATE's own 0.3 convergence rate),
## THEN advances by many real SECONDS_PER_SIMULATED_DAY-sized steps --
## GROWTH_RATE_PER_DAY (0.05) genuinely means the slowest-growing
## population this game tracks, so reaching near-capacity takes real
## simulated YEARS' worth of daily steps, not a handful of arbitrary
## advance() calls.
func test_growth_fraction_approaches_one_for_a_thriving_colony():
	var colony := _colony("grassland", 42)
	var cell: Vector2i = colony.mound_cells()[0]
	for i in 20:
		colony.record_forage_result(cell, true)
		colony.record_moisture(cell, 1.0)
	for i in 400:
		colony.advance(AntColony.SECONDS_PER_SIMULATED_DAY)
	assert_gt(colony.growth_fraction_at(cell), 0.9)


func test_growth_fraction_is_never_negative_or_above_one():
	var colony := _colony()
	var cell: Vector2i = colony.mound_cells()[0]
	assert_gte(colony.growth_fraction_at(cell), 0.0)
	assert_lte(colony.growth_fraction_at(cell), 1.0)


func test_active_forager_cap_is_at_least_one_for_a_brand_new_mound():
	var colony := _colony()
	var cell: Vector2i = colony.mound_cells()[0]
	assert_gte(colony.active_forager_cap_at(cell), 1)


func test_active_forager_cap_never_exceeds_its_own_maximum():
	var colony := _colony("grassland", 42)
	var cell: Vector2i = colony.mound_cells()[0]
	for i in 100:
		colony.record_forage_result(cell, true)
		colony.advance(1.0)
	assert_lte(colony.active_forager_cap_at(cell), AntColony.MAX_CONCURRENT_FORAGERS)


func test_active_forager_cap_grows_with_a_thriving_colony():
	var colony := _colony("grassland", 42)
	var cell: Vector2i = colony.mound_cells()[0]
	var before := colony.active_forager_cap_at(cell)
	for i in 100:
		colony.record_forage_result(cell, true)
		colony.advance(1.0)
	assert_gte(colony.active_forager_cap_at(cell), before)


# -- pheromone trails: recruitment to a known-good source -------------------

func test_pheromones_at_returns_null_before_any_deposit():
	var colony := _colony()
	var cell: Vector2i = colony.mound_cells()[0]
	assert_null(colony.pheromones_at(cell))


func test_deposit_pheromone_creates_the_field_lazily_and_records_the_deposit():
	var colony := _colony()
	var cell: Vector2i = colony.mound_cells()[0]
	var tile := Vector2i(9, 9)
	colony.deposit_pheromone(cell, tile)
	var field = colony.pheromones_at(cell)
	assert_not_null(field)
	assert_false(field.is_empty())


func test_advance_decays_a_mounds_pheromone_field_over_real_elapsed_time():
	var colony := _colony()
	var cell: Vector2i = colony.mound_cells()[0]
	var tile := Vector2i(4, 4)
	colony.deposit_pheromone(cell, tile)
	var tile_center := (Vector2(tile) + Vector2(0.5, 0.5)) * 16.0
	var before: float = colony.pheromones_at(cell).concentration_at(tile_center, 16.0)
	colony.advance(PheromoneField.HALF_LIFE_SECONDS)
	var after: float = colony.pheromones_at(cell).concentration_at(tile_center, 16.0)
	assert_almost_eq(after, before * 0.5, 0.01)


## Different mounds are different colonies -- one's trail must not bleed
## into another's.
func test_each_mound_owns_its_own_independent_pheromone_field():
	var colony := _colony()
	var cells: Array = colony.mound_cells()
	assert_gt(cells.size(), 1, "need at least two mounds to prove independence")
	colony.deposit_pheromone(cells[0], Vector2i(1, 1))
	assert_null(colony.pheromones_at(cells[1]), "a deposit at one mound must not appear at another")


# -- SECONDS_PER_SIMULATED_DAY must stay in sync with EarthChunkManager's
# own constant of the same name (see AntColony's doc comment on why it is
# restated here rather than imported -- EarthChunkManager already preloads
# AntColony, so the reverse import would be circular). ----------------------

func test_seconds_per_simulated_day_matches_earth_chunk_managers_own_constant():
	assert_eq(AntColony.SECONDS_PER_SIMULATED_DAY, EarthChunkManager.SECONDS_PER_SIMULATED_DAY)
