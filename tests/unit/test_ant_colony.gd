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
const SeasonCycle = preload("res://src/world/season_cycle.gd")

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


## How close a scouting forager (see docs/concept/soil_fauna.md's
## "Scouting: real search, not omniscient dispatch") has to physically be
## to notice real food at all -- derived from FORAGE_RADIUS_TILES itself
## (half of it) rather than an independently-eyeballed number, so this
## stays proportionally meaningfully SMALLER than the whole home range a
## scout wanders (real wandering is required to cover it) if that range
## is ever retuned again. Pinned directly, not re-derived in the test,
## since the derivation itself is what this guards against silently
## drifting.
func test_sense_radius_is_half_the_forage_radius():
	assert_eq(AntColony.SENSE_RADIUS_TILES, AntColony.FORAGE_RADIUS_TILES * 0.5)


func test_cluster_threshold_is_pinned():
	assert_eq(AntColony.CLUSTER_THRESHOLD, 3)


func test_scout_wave_size_is_pinned():
	assert_eq(AntColony.SCOUT_WAVE_SIZE, 3)


func test_resolver_wave_size_is_pinned():
	assert_eq(AntColony.RESOLVER_WAVE_SIZE, 2)


func test_resolver_wave_is_smaller_than_scout_wave():
	assert_lt(AntColony.RESOLVER_WAVE_SIZE, AntColony.SCOUT_WAVE_SIZE)


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

## Asked directly, a specific number rather than a range: "start at 15
## ants at the beginning." Supersedes the previous pass's own seeded-RANGE
## fix (below) -- that was itself a correction for colonies that could
## functionally never be seen thriving in ordinary play (see "Thriving
## colonies" in docs/concept/soil_fauna.md); given a specific number here,
## every mound now founds at exactly it rather than variance around it.
## Mounds are still not freshly founded at some bare minimum the instant a
## chunk loads -- 15 IS the established-colony reading, not a floor a real
## colony grows up from over the player's own session.
func test_population_starts_at_fifteen():
	var colony := _colony()
	var cell: Vector2i = colony.mound_cells()[0]
	assert_almost_eq(colony.population_at(cell), AntPopulationModel.STARTING_POPULATION, 0.001)
	assert_almost_eq(AntPopulationModel.STARTING_POPULATION, 15.0, 0.001)


## Superseded (2026-09-06): asked directly for a flat starting population
## (see test_population_starts_at_fifteen above) rather than the previous
## pass's own seeded range -- every mound now starts at the identical,
## specific population by design, so "different mounds start with
## different populations" is no longer a real invariant to hold. This is
## not a regression the way a coincidental flatness would be: it is
## exactly what was asked for. (Mounds still read as real, distinct
## colonies via their own independent forage-success/moisture/food
## histories once advance() actually runs -- see the food-economy tests
## below -- just not from their STARTING population any more.)


## A reloaded chunk must reproduce the exact same mound at the exact same
## established population every time -- the identical determinism
## guarantee every other PixelNoise-seeded roll in this file already
## gives, so the same world looks the same on every visit.
func test_starting_population_is_deterministic_for_the_same_seed():
	var a := _colony("grassland", 55)
	var b := _colony("grassland", 55)
	var cell: Vector2i = a.mound_cells()[0]
	assert_eq(a.population_at(cell), b.population_at(cell))


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


# -- a real food economy: storage, upkeep, and a real growth constraint
# (see docs/concept/soil_fauna.md's "A real food economy" section) --------
#
# Reported live: "ants should bring food (seeds, leaves, nuts) to the
# mound which should get a food supply stat... food then becomes driver
# and constraint of population growth."

## A freshly-seeded mound is never born already starving -- the same
## "map-generated content starts already established" reasoning the
## population itself already follows. Seeded at exactly a full
## FOOD_BUFFER_DAYS reserve for its OWN starting population, so
## food_availability_fraction (below) reads exactly 1.0 for a brand-new
## colony -- derived from the same constants that reserve is measured
## against, not a second, independently-chosen number that could drift
## from what "a full buffer" actually means.
func test_food_stored_starts_at_a_full_buffer_for_the_seeded_population():
	var colony := _colony()
	var cell: Vector2i = colony.mound_cells()[0]
	var expected := (
		AntPopulationModel.STARTING_POPULATION
		* AntPopulationModel.FOOD_PER_ANT_PER_DAY
		* AntPopulationModel.FOOD_BUFFER_DAYS
	)
	assert_almost_eq(colony.food_stored_at(cell), expected, 0.001)


func test_deposit_food_increases_the_stored_amount():
	var colony := _colony()
	var cell: Vector2i = colony.mound_cells()[0]
	var before := colony.food_stored_at(cell)
	colony.deposit_food(cell, 5.0)
	assert_almost_eq(colony.food_stored_at(cell), before + 5.0, 0.001)


## The one place AntForagerMarker already reports a completed trip (see
## docs/concept/soil_fauna.md) now also feeds the real stockpile, for
## every forage kind alike (seed/windfall/leaf) -- a successful trip
## bringing food home is the whole point of the mechanism this stat
## exists for.
func test_recording_forage_success_also_deposits_food():
	var colony := _colony()
	var cell: Vector2i = colony.mound_cells()[0]
	var before := colony.food_stored_at(cell)
	colony.record_forage_result(cell, true)
	assert_almost_eq(colony.food_stored_at(cell), before + AntColony.FOOD_PER_SUCCESSFUL_FORAGE, 0.001)


func test_recording_forage_failure_does_not_deposit_food():
	var colony := _colony()
	var cell: Vector2i = colony.mound_cells()[0]
	var before := colony.food_stored_at(cell)
	colony.record_forage_result(cell, false)
	assert_almost_eq(colony.food_stored_at(cell), before, 0.001)


## The real upkeep a population represents: more ants, more draw on the
## same reserve, every simulated day advance() represents.
func test_advancing_depletes_food_by_population_upkeep():
	var colony := _colony()
	var cell: Vector2i = colony.mound_cells()[0]
	var before := colony.food_stored_at(cell)
	colony.advance(AntColony.SECONDS_PER_SIMULATED_DAY)
	var expected_drop := (
		colony.population_at(cell) * AntPopulationModel.FOOD_PER_ANT_PER_DAY
	)
	assert_almost_eq(colony.food_stored_at(cell), before - expected_drop, 0.01)


func test_food_stored_never_drops_below_zero():
	var colony := _colony()
	var cell: Vector2i = colony.mound_cells()[0]
	for i in 1000:
		colony.advance(AntColony.SECONDS_PER_SIMULATED_DAY)
	assert_gte(colony.food_stored_at(cell), 0.0)


func test_food_availability_fraction_starts_at_one():
	var colony := _colony()
	var cell: Vector2i = colony.mound_cells()[0]
	assert_almost_eq(colony.food_availability_fraction(cell), 1.0, 0.001)


func test_food_availability_fraction_drops_as_food_depletes():
	var colony := _colony()
	var cell: Vector2i = colony.mound_cells()[0]
	for i in 30:
		colony.advance(AntColony.SECONDS_PER_SIMULATED_DAY)
	assert_lt(colony.food_availability_fraction(cell), 1.0)


func test_food_availability_fraction_is_never_negative_or_above_one():
	var colony := _colony()
	var cell: Vector2i = colony.mound_cells()[0]
	for i in 1000:
		colony.advance(AntColony.SECONDS_PER_SIMULATED_DAY)
	assert_gte(colony.food_availability_fraction(cell), 0.0)
	assert_lte(colony.food_availability_fraction(cell), 1.0)


## The real "driver" half: even a colony with a perfect forage-success
## record and ideal moisture cannot exceed the unfed baseline once its
## real reserve actually runs dry -- food is what capacity() answers to
## now, not recent luck alone.
func test_capacity_drops_below_baseline_once_food_runs_out():
	var colony := _colony("grassland", 42)
	var cell: Vector2i = colony.mound_cells()[0]
	for i in 20:
		colony.record_forage_result(cell, true)
		colony.record_moisture(cell, 1.0)
	for i in 200:
		colony.advance(AntColony.SECONDS_PER_SIMULATED_DAY)
	assert_lt(colony.capacity_at(cell), AntPopulationModel.BASE_CAPACITY)


## A real bug caught by test_food_availability_fraction_drops_as_food_
## depletes going red for the wrong reason during development: with zero
## income, population crashes all the way to a literal 0.0 within a
## handful of simulated days (PopulationModel.step's own existing
## "carrying_capacity <= 0.0 -> population 0.0" rule, once food_stored
## itself hits zero) -- and a naive "population 0 means food isn't the
## constraint" reading of food_availability_fraction reported that DEAD
## colony as a perfectly healthy 1.0 forever after, since a population
## stuck at exactly 0.0 can never grow itself back out of that reading.
## Pinned directly so this exact false-healthy-reading regression can't
## come back unnoticed.
##
## *(2026-09-09: ordinary starvation alone can no longer reach a literal
## 0.0 population now that QUEEN_PROTECTED_POPULATION_FLOOR exists -- see
## AntPopulationModel.step's own doc comment -- so this constructs a
## genuine 0.0 directly instead of via 10 days of ordinary decline,
## mirroring a real crushing/predation wipeout, which still can. This test
## is about food_availability_fraction's own read AT population 0, not
## about whether ordinary starvation reaches it.)*
func test_a_fully_starved_colony_reads_zero_food_availability_not_full():
	var colony := _colony("grassland", 42)
	var cell: Vector2i = colony.mound_cells()[0]
	colony._population[cell] = 0.0
	assert_almost_eq(colony.food_availability_fraction(cell), 0.0, 0.001)


## The real "constraint" half, end to end: a colony fed once at the start
## and never again, over enough simulated time, genuinely shrinks back
## down -- the same real famine/overcrowding decline PopulationModel.step
## already gives every species once population outruns its own capacity,
## now reachable through a real depleting food store rather than a new
## bespoke starvation branch.
func test_a_colony_that_never_restocks_food_eventually_shrinks():
	var colony := _colony("grassland", 42)
	var cell: Vector2i = colony.mound_cells()[0]
	var starting_population := colony.population_at(cell)
	for i in 20:
		colony.record_forage_result(cell, true)
		colony.record_moisture(cell, 1.0)
	for i in 400:
		colony.advance(AntColony.SECONDS_PER_SIMULATED_DAY)
	assert_lt(colony.population_at(cell), starting_population)


# -- cold soil: real dormancy, not a guaranteed permanent death sentence
# (reported live: "now i don't see any ant mounds at all anymore (fresh
# start, winter)") -- confirmed root cause: FOOD_BUFFER_DAYS(3) *
# SECONDS_PER_SIMULATED_DAY(60) = 180 real seconds is far shorter than a
# real winter's near-total lack of forage success (bare trees drop no
# windfall, fallen leaf litter ages into its own terminal decay stage with
# nothing replacing it -- see docs/concept/leaf_litter.md), so every mound
# starves to a literal population 0.0 well within one season, and (see the
# next section) can never recover from that on its own. -----------------

## Mirrors EarthwormPatch's own record_moisture-shaped API exactly.
func test_record_warmth_accepts_a_reading_without_error():
	var colony := _colony()
	var cell: Vector2i = colony.mound_cells()[0]
	colony.record_warmth(cell, 0.3)
	pass_test("record_warmth accepted a reading without error")


## Never recorded at all (a mound that has not yet had its first periodic
## refresh -- see EarthChunkManager._refresh_ant_moisture's own cadence)
## must read as full, undiminished activity, the OPPOSITE default
## moisture/forage_success use. Deliberately so: those two feed a BONUS
## (a missing one just reads as "none earned yet", still a perfectly
## healthy baseline -- see capacity()'s own "1.0 +" floor), but warmth
## drives a PENALTY here -- defaulting it to "coldest possible" would
## throttle every freshly-loaded mound before its own first real reading
## ever arrives, directly contradicting "a freshly-seeded mound is never
## born already starving" (_founding_food_reserve's own doc comment).
func test_a_mound_with_no_warmth_recorded_yet_depletes_at_the_undiminished_rate():
	var colony := _colony()
	var cell: Vector2i = colony.mound_cells()[0]
	var before := colony.food_stored_at(cell)
	colony.advance(AntColony.SECONDS_PER_SIMULATED_DAY)
	var expected_drop := colony.population_at(cell) * AntPopulationModel.FOOD_PER_ANT_PER_DAY
	assert_almost_eq(colony.food_stored_at(cell), before - expected_drop, 0.01)


## The actual fix: cold soil throttles upkeep the same way EarthwormPatch's
## own soil_warmth already throttles worm surfacing (same soil, same real
## mechanism) -- real ants, like real earthworms, drastically cut activity
## in cold soil rather than continuing to draw full upkeep while genuinely
## unable to forage for it. 20 repeated readings (same EMA warm-up
## convention test_recording_moisture_raises_capacity already uses) so the
## EMA has actually settled near the recorded value rather than still
## sitting close to its own "no reading yet" default -- a REALISTIC
## soil_warmth-scale reading (0.05), not an abstract "0.0 on an independent
## coldness slider": EarthwormPatch's own COLD_CUTOFF/MILD_WARMTH are
## calibrated against soil_warmth's real climate*seasonal output range,
## which a temperate biome's own real winter genuinely reaches down into
## (see soil_warmth's own doc comment on why a raw 1.0 essentially never
## occurs there either).
func test_cold_soil_depletes_food_slower_than_warm_soil():
	var cold := _colony("grassland", 42)
	var warm := _colony("grassland", 42)
	var cell: Vector2i = cold.mound_cells()[0]
	for i in 20:
		cold.record_warmth(cell, 0.05)
		warm.record_warmth(cell, 1.0)
	cold.advance(AntColony.SECONDS_PER_SIMULATED_DAY)
	warm.advance(AntColony.SECONDS_PER_SIMULATED_DAY)
	assert_gt(
		cold.food_stored_at(cell), warm.food_stored_at(cell),
		"cold, dormant soil should draw the food reserve down slower than warm soil"
	)


## The other real half of dormancy (see docs/concept/seasonal_behavior.md,
## "Ant/honeybee forager cold-gate"): a torpid colony's own workers stay
## home, not just draw down the reserve slower. Before this fix,
## should_forage() read no warmth signal at all, so a mound at
## DORMANCY_FLOOR still sent foragers out at the ordinary FORAGE_CHANCE --
## the literal opposite of "cluster deep in the mound and barely feed at
## all" from this section's own header comment. Same seed on both
## colonies so should_forage's PixelNoise roll is IDENTICAL at every step
## for both -- only the dormancy multiplier applied to the effective
## threshold differs, so cold's attempt count can never exceed warm's,
## making this an exact comparison rather than merely a likely one.
func test_cold_soil_reduces_forage_attempts_not_just_depletion():
	var cold := _colony("grassland", 42)
	var warm := _colony("grassland", 42)
	var cell: Vector2i = cold.mound_cells()[0]
	for i in 20:
		cold.record_warmth(cell, 0.05)
		warm.record_warmth(cell, 1.0)
	var cold_attempts := 0
	var warm_attempts := 0
	for i in 500:
		cold.advance(1.0)
		warm.advance(1.0)
		if cold.should_forage(cell):
			cold_attempts += 1
		if warm.should_forage(cell):
			warm_attempts += 1
	assert_lt(
		cold_attempts, warm_attempts,
		"a dormant, cold-clustered mound should send foragers out far less often than an active one"
	)


## Never all the way to zero -- a genuinely dormant colony still needs
## SOME food to survive winter on stored fat. A hard 0.0 floor here would
## just move the identical permanent-death bug to "a sufficiently long or
## severe cold spell" instead of actually fixing it.
func test_cold_soil_still_depletes_some_food_not_zero():
	var colony := _colony("grassland", 42)
	var cell: Vector2i = colony.mound_cells()[0]
	for i in 20:
		colony.record_warmth(cell, 0.05)
	var before := colony.food_stored_at(cell)
	colony.advance(AntColony.SECONDS_PER_SIMULATED_DAY)
	assert_lt(colony.food_stored_at(cell), before)


## The actual reported symptom, closed: a colony sitting through a real,
## sustained cold spell with ZERO forage success (exactly what a real
## winter's lack of leaf litter/seed/windfall gives it) must not starve to
## extinction purely from the cold itself, over the same stretch that
## test_a_fully_starved_colony_reads_zero_food_availability_not_full's own
## WARM-soil equivalent already fully starves. Warmth is pre-settled
## (same 20-reading warm-up as the tests above) before the advance loop
## begins, matching how a mound already deep in winter -- not one just now
## starting to cool -- is the realistic case this fix targets.
func test_a_colony_kept_cold_and_foodless_survives_far_longer_than_a_warm_one():
	var colony := _colony("grassland", 42)
	var cell: Vector2i = colony.mound_cells()[0]
	for i in 20:
		colony.record_warmth(cell, 0.05)
	for i in 10:
		colony.advance(AntColony.SECONDS_PER_SIMULATED_DAY)
	assert_gt(
		colony.population_at(cell), 0.0,
		"a cold, dormant colony should not yet have starved over the same stretch that fully starves a warm one"
	)


# -- re-founding: a mound that hit a literal population 0.0 is not gone
# forever -- see PopulationModel.step's own hard "carrying_capacity <= 0.0
# -> population immediately 0.0" rule, confirmed directly below to be
# permanent and unrecoverable through ordinary growth alone (growth is
# proportional to CURRENT population, and zero population growing at any
# rate is still zero) --------------------------------------------------

## Pinned directly: feeding a starved colony a GUARANTEED forage success
## on every single advance() call never lifts population off a literal
## 0.0 -- food_availability_fraction's own guard (population <= 0.0 ->
## 0.0, unconditionally) means capacity_at stays locked at exactly 0.0
## regardless of how good recent forage success/moisture read, so
## PopulationModel.step's "carrying_capacity <= 0.0" rule keeps re-firing
## forever. Deliberately only 2 successes (not enough to cross
## REFOUNDING_FOOD_THRESHOLD and trigger REAL recovery -- see the
## refounding tests below, which are what actually lifts this) -- this
## test is isolated to prove growth math ALONE never does it.
##
## *(2026-09-09: forced directly to a real 0.0 rather than reached via 10
## days of ordinary decline -- QUEEN_PROTECTED_POPULATION_FLOOR means
## ordinary starvation alone no longer reaches a literal zero; this test
## is about growth math's own behaviour once genuinely AT zero, which a
## real crushing/predation wipeout can still produce, not about how a
## colony gets there.)*
func test_a_starved_colony_does_not_recover_through_ordinary_growth_alone():
	var colony := _colony("grassland", 42)
	var cell: Vector2i = colony.mound_cells()[0]
	colony._population[cell] = 0.0
	colony._food_stored[cell] = 0.0
	for i in 2:
		colony.record_forage_result(cell, true)
		colony.advance(AntColony.SECONDS_PER_SIMULATED_DAY)
	assert_almost_eq(
		colony.population_at(cell), 0.0, 0.001,
		"ordinary growth alone should never lift population off a literal 0.0"
	)


## The actual fix: once real food has genuinely piled back up to a full
## founding reserve at an empty mound (the same standard _seed_initial_
## mounds itself starts every brand-new colony at -- see _founding_food_
## reserve) -- still reachable even for an "extinct" mound, since
## EarthChunkManager._dispatch_forager's own active_forager_cap_at floors
## at 1 forager regardless of population -- a fresh colony re-founds
## there, the same real recolonization a wiped-out nest site actually gets
## once conditions genuinely improve.
##
## *(2026-09-09: forced directly to a real 0.0/0.0 -- see
## test_a_starved_colony_does_not_recover_through_ordinary_growth_alone's
## own doc comment on why ordinary starvation alone no longer reaches this
## state since QUEEN_PROTECTED_POPULATION_FLOOR exists.)*
func test_a_starved_mound_refounds_once_a_full_reserve_genuinely_accumulates():
	var colony := _colony("grassland", 42)
	var cell: Vector2i = colony.mound_cells()[0]
	colony._population[cell] = 0.0
	colony._food_stored[cell] = 0.0
	colony.deposit_food(cell, 10000.0)  # a real, large surplus -- not a special-cased amount
	colony.advance(0.01)
	assert_gt(colony.population_at(cell), 0.0, "a genuinely refounded mound should have real population again")


## Reported live: "when an ant mound collapses and hits 0 population then
## it stays at 0 population even if new ants enter or bring food. the
## food stock correctly increments, but the population stays zero" --
## confirmed directly (a throwaway diagnostic probe, deleted once its job
## was done): gating refounding on a FULL _founding_food_reserve() (the
## same 45.0-unit, multi-day standard a brand-new mound starts with) took
## over 22 REAL MINUTES even under a perfectly successful lone forager
## trip every 30 real seconds -- not a bug in the mechanism itself, but a
## threshold nobody would ever realistically observe recover.
## REFOUNDING_FOOD_THRESHOLD must be far smaller -- real, repeated
## evidence a handful of trips home is possible again, not a whole mature
## colony's own reserve.
func test_refounding_food_threshold_is_far_smaller_than_a_full_founding_reserve():
	var colony := _colony()
	assert_lt(AntColony.REFOUNDING_FOOD_THRESHOLD, colony._founding_food_reserve() * 0.5)


## The actual fix: far less than a full founding reserve is now enough --
## a handful of successful trips' worth, not 45 of them.
##
## *(2026-09-09: forced directly to a real 0.0/0.0 -- see
## test_a_starved_colony_does_not_recover_through_ordinary_growth_alone's
## own doc comment on why ordinary starvation alone no longer reaches this
## state since QUEEN_PROTECTED_POPULATION_FLOOR exists.)*
func test_a_starved_mound_refounds_with_far_less_than_a_full_founding_reserve():
	var colony := _colony("grassland", 42)
	var cell: Vector2i = colony.mound_cells()[0]
	colony._population[cell] = 0.0
	colony._food_stored[cell] = 0.0
	colony.deposit_food(cell, AntColony.REFOUNDING_FOOD_THRESHOLD)
	colony.advance(0.01)
	assert_gt(
		colony.population_at(cell), 0.0,
		"exactly the new, smaller threshold should already be enough to refound"
	)


## *(2026-09-09: forced directly to a real 0.0 -- see
## test_a_starved_colony_does_not_recover_through_ordinary_growth_alone's
## own doc comment on why ordinary starvation alone no longer reaches this
## state since QUEEN_PROTECTED_POPULATION_FLOOR exists.)*
func test_refounding_lands_at_the_same_starting_population_a_brand_new_mound_gets():
	var colony := _colony("grassland", 42)
	var cell: Vector2i = colony.mound_cells()[0]
	colony._population[cell] = 0.0
	colony._food_stored[cell] = 0.0
	colony.deposit_food(cell, 10000.0)
	colony.advance(0.01)
	assert_almost_eq(colony.population_at(cell), AntPopulationModel.STARTING_POPULATION, 0.001)


## Scoped to a genuinely EXTINCT mound only -- refounding must never
## trigger for (and so never silently reset) a colony that still has any
## real population left, no matter how abundant its food is.
func test_refounding_never_triggers_for_a_colony_that_still_has_any_real_population():
	var colony := _colony("grassland", 42)
	var cell: Vector2i = colony.mound_cells()[0]
	colony.deposit_food(cell, 10000.0)
	colony.advance(AntColony.SECONDS_PER_SIMULATED_DAY)
	assert_almost_eq(
		colony.population_at(cell), AntPopulationModel.STARTING_POPULATION, 0.5,
		"a colony that never actually went extinct should follow ordinary growth, not silently reset"
	)


# -- the real live-reported bug: "Both ant mounds near the spawn show
# queenless when changing from winter to spring... they then refound; but
# it collapses again because there's still no queen" -- root-caused and
# reproduced directly (see docs/concept/soil_fauna.md's "Winter->spring
# repeat-collapse: root cause and fix"): _maybe_refound reset population
# straight to the FULL STARTING_POPULATION the instant food crossed the
# tiny REFOUNDING_FOOD_THRESHOLD, but never gave the colony a matching
# food reserve the way a genuinely brand-new mound gets (_founding_food_
# reserve) -- so a just-refounded colony was instantly ~93% food-insecure
# (3.0 stored against the 45.0 a 15-strong colony needs), which crushed
# capacity_at, which crashed population right back toward zero within
# days. Confirmed live via a throwaway diagnostic probe (deleted once its
# job was done, per this file's own established convention): starve to a
# real 0.0, trickle home exactly REFOUNDING_FOOD_THRESHOLD worth of food
# (matching a lone still-active forager finally finding food as spring
# odds improve, NOT a giant windfall), and population that "refounded" at
# 15.0 was back to a literal 0.0 within 10 simulated days, every time,
# repeatably. Two real, separate fixes close this: (1) refounding/adoption
# now also tops up the food reserve, not just population, and (2) the
# QUEEN_PROTECTED_POPULATION_FLOOR above means even an under-resourced
# colony can no longer be driven all the way back to a literal 0.0 by
# ordinary starvation alone while she's alive. ------------------------

## The precise mismatch: right after refounding, food_stored_at must be at
## least a real _founding_food_reserve() -- the same standard a genuinely
## brand-new mound starts at -- not just whatever bare minimum happened to
## cross REFOUNDING_FOOD_THRESHOLD.
func test_refounding_gives_the_colony_a_real_food_reserve_not_just_a_population_number():
	var colony := _colony("grassland", 42)
	var cell: Vector2i = colony.mound_cells()[0]
	colony._population[cell] = 0.0
	colony._food_stored[cell] = 0.0
	colony.deposit_food(cell, AntColony.REFOUNDING_FOOD_THRESHOLD)
	colony.advance(0.01)
	assert_gt(colony.population_at(cell), 0.0, "precondition: should have refounded")
	assert_gte(
		colony.food_stored_at(cell), colony._founding_food_reserve(),
		"a refounded colony must start as food-secure as a genuinely brand-new mound, not instantly starving"
	)


## Never DECREASES an existing reserve either -- test_a_starved_mound_
## refounds_once_a_full_reserve_genuinely_accumulates already deposits a
## real 10000.0 surplus before refounding; topping up must take the max,
## never clobber a reserve that was already ample.
func test_refounding_never_reduces_an_already_ample_food_reserve():
	var colony := _colony("grassland", 42)
	var cell: Vector2i = colony.mound_cells()[0]
	colony._population[cell] = 0.0
	colony._food_stored[cell] = 0.0
	colony.deposit_food(cell, 10000.0)
	colony.advance(0.01)
	assert_almost_eq(colony.food_stored_at(cell), 10000.0, 1.0)


## The actual regression test for the live-reported cycle: a colony forced
## to a real 0.0, refounded off a realistic small trickle (not a windfall),
## must not collapse back to queenless again over a realistic stretch of
## subsequent time -- and, even in a worst-case follow-up famine (no more
## food at all), must settle at the protected floor rather than zero.
func test_a_refounded_colony_does_not_collapse_back_to_queenless_again():
	var colony := _colony("grassland", 42)
	var cell: Vector2i = colony.mound_cells()[0]
	colony._population[cell] = 0.0
	colony._food_stored[cell] = 0.0

	for i in 3:
		colony.record_forage_result(cell, true)
	colony.advance(0.01)
	assert_gt(colony.population_at(cell), 0.0, "precondition: should have refounded")

	# No further deposits at all -- the realistic worst case a spring
	# transition can still look like (early-season forage odds still
	# recovering). Advance a full month of simulated days and check EVERY
	# step along the way, not just the end -- the reported bug was a
	# collapse ALONG THE WAY, not necessarily at a single final instant.
	for day in 30:
		colony.advance(AntColony.SECONDS_PER_SIMULATED_DAY)
		assert_true(
			colony.has_queen_at(cell),
			"day %d: a refounded colony should never fall back to queenless from ordinary starvation alone" % day
		)


## Same scenario, run twice in a row (the user's own literal report: it
## refounds, THEN collapses, and -- implicitly -- would keep doing so) --
## proves this is not merely fixed for one cycle by coincidence.
func test_a_refounded_colony_stays_alive_across_two_consecutive_lean_stretches():
	var colony := _colony("grassland", 42)
	var cell: Vector2i = colony.mound_cells()[0]
	colony._population[cell] = 0.0
	colony._food_stored[cell] = 0.0

	for cycle in 2:
		for i in 3:
			colony.record_forage_result(cell, true)
		colony.advance(0.01)
		assert_true(colony.has_queen_at(cell), "cycle %d: should have (re)gained a queen" % cycle)
		for day in 20:
			colony.advance(AntColony.SECONDS_PER_SIMULATED_DAY)
			assert_true(
				colony.has_queen_at(cell),
				"cycle %d, day %d: should not have collapsed back to queenless" % [cycle, day]
			)


# -- a new queen, over real time: real ant queen succession by adoption --
# an already-mated, dealate queen from a nuptial flight wandering onto a
# queenless nest and being accepted into it ("secondary polygyny... by
# adoption", real, documented ant biology -- pleometrosis/colony adoption,
# distinct from _maybe_refound's own food-gated "a wholly fresh colony
# happens to colonize the empty site" story). Requested live: "If they
# have no queen; they should make a new one... It should take time thoug
# for a new queen to hatch" -- and, on being asked directly to research the
# real biology rather than invent a game-y mechanic: real nuptial flights
# are seasonal (once, or a handful of times, per year for a given species/
# region), so "the next real opportunity for a wandering queen to find
# this exact site" is honestly a SEASON-scale wait, not a food-stockpile-
# scale one -- a second, independent, deliberately much SLOWER path to a
# new queen than the food-gated one, gated purely on real elapsed queenless
# time regardless of food (a founding queen's own histolysed flight muscles
# are her first real food reserve, not the site's own stockpile -- see
# docs/concept/soil_fauna.md's "A new queen, over real time: adoption").
# ---------------------------------------------------------------------

func test_a_queenless_mound_does_not_adopt_a_new_queen_before_the_real_wait_elapses():
	var colony := _colony("grassland", 42)
	var cell: Vector2i = colony.mound_cells()[0]
	colony._population[cell] = 0.0
	colony._food_stored[cell] = 0.0
	colony.advance(AntColony.NEW_QUEEN_ADOPTION_SECONDS * 0.5)
	assert_almost_eq(
		colony.population_at(cell), 0.0, 0.001,
		"half the real wait should not be enough for a new queen to have found this site yet"
	)


func test_a_queenless_mound_adopts_a_new_queen_once_the_real_wait_elapses():
	var colony := _colony("grassland", 42)
	var cell: Vector2i = colony.mound_cells()[0]
	colony._population[cell] = 0.0
	colony._food_stored[cell] = 0.0
	colony.advance(AntColony.NEW_QUEEN_ADOPTION_SECONDS + 1.0)
	assert_gt(colony.population_at(cell), 0.0, "a new queen should have adopted this genuinely queenless site by now")


## The explicit ask, proven directly: this must NOT resolve quickly or
## immediately -- nowhere near as fast as the food-gated path (which can
## fire within moments of a lucky trickle of successful trips).
func test_new_queen_adoption_does_not_resolve_quickly_or_immediately():
	var colony := _colony("grassland", 42)
	var cell: Vector2i = colony.mound_cells()[0]
	colony._population[cell] = 0.0
	colony._food_stored[cell] = 0.0
	# A generous few real minutes -- comfortably longer than any realistic
	# food-gated refound -- with NO food at all deposited.
	colony.advance(600.0)
	assert_almost_eq(
		colony.population_at(cell), 0.0, 0.001,
		"a few real minutes must not be anywhere near enough for adoption to fire"
	)


func test_new_queen_adoption_seconds_is_meaningfully_slower_than_the_food_gated_path():
	# The food-gated path's own worst documented case before it was fixed
	# down (REFOUNDING_FOOD_THRESHOLD's own doc comment) was 22 real
	# minutes; its TYPICAL case today is a handful of successful trips,
	# on the order of real minutes. Adoption must comfortably exceed even
	# that old worst case, not just the fast common case.
	assert_gt(AntColony.NEW_QUEEN_ADOPTION_SECONDS, 22.0 * 60.0)


## Real grounding, checked directly rather than left an eyeballed comment
## (CLAUDE.md's own rule): pinned against a real SeasonCycle season, since
## real nuptial flights are seasonal events.
func test_new_queen_adoption_seconds_matches_a_real_season():
	assert_almost_eq(AntColony.NEW_QUEEN_ADOPTION_SECONDS, SeasonCycle.SECONDS_PER_YEAR / 4.0, 0.001)


## An adopted queen must be exactly as food-secure as a food-refounded one
## -- the same real fix as test_refounding_gives_the_colony_a_real_food_
## reserve_not_just_a_population_number, for the same reason: an adopted
## colony must never be born back into the exact bug this whole pass fixes.
func test_adoption_also_gives_the_colony_a_real_food_reserve():
	var colony := _colony("grassland", 42)
	var cell: Vector2i = colony.mound_cells()[0]
	colony._population[cell] = 0.0
	colony._food_stored[cell] = 0.0
	colony.advance(AntColony.NEW_QUEEN_ADOPTION_SECONDS + 1.0)
	assert_gte(colony.food_stored_at(cell), colony._founding_food_reserve())


## The queenless clock must reset once a queen returns (whichever path got
## her there) -- a LATER extinction starts counting from zero again, not
## from a stale accumulated duration that would let a second adoption fire
## suspiciously fast.
func test_queenless_timer_resets_once_a_queen_returns_via_the_food_gated_path():
	var colony := _colony("grassland", 42)
	var cell: Vector2i = colony.mound_cells()[0]
	colony._population[cell] = 0.0
	colony._food_stored[cell] = 0.0
	colony.advance(AntColony.NEW_QUEEN_ADOPTION_SECONDS * 0.9)  # most of the way through the real wait
	for i in 3:
		colony.record_forage_result(cell, true)
	colony.advance(0.01)
	assert_gt(colony.population_at(cell), 0.0, "precondition: should have refounded via the food-gated path")

	# Wipe her out again directly (mirrors forager_crushed/forager_eaten's
	# own real effect) and confirm adoption does NOT fire suspiciously
	# fast off the old, stale accumulated duration.
	colony._population[cell] = 0.0
	colony._food_stored[cell] = 0.0
	colony.advance(AntColony.NEW_QUEEN_ADOPTION_SECONDS * 0.5)
	assert_almost_eq(
		colony.population_at(cell), 0.0, 0.001,
		"the queenless timer should have reset -- half the real wait should not be enough on its own again"
	)


## Mirrors BeeColony.requeening_progress_at's own hover-facing contract --
## now genuinely TWO real paths to report progress on, so this reads
## whichever is actually further along.
func test_refounding_progress_reflects_whichever_path_is_further_along():
	var colony := _colony("grassland", 42)
	var cell: Vector2i = colony.mound_cells()[0]
	colony._population[cell] = 0.0
	colony._food_stored[cell] = 0.0

	# No time elapsed yet, but food is already most of the way to the
	# threshold -- the food path should dominate.
	colony.deposit_food(cell, AntColony.REFOUNDING_FOOD_THRESHOLD * 0.5)
	var food_led := colony.refounding_progress_at(cell)
	assert_almost_eq(food_led, 0.5, 0.01)

	# Now let real time pass well past the food path's own progress,
	# with no further food -- the time path should take over.
	colony.advance(AntColony.NEW_QUEEN_ADOPTION_SECONDS * 0.9)
	var time_led := colony.refounding_progress_at(cell)
	assert_almost_eq(time_led, 0.9, 0.01)
	assert_gt(time_led, food_led)


func test_refounding_progress_is_zero_while_a_queen_is_genuinely_present():
	var colony := _colony("grassland", 42)
	var cell: Vector2i = colony.mound_cells()[0]
	assert_almost_eq(colony.refounding_progress_at(cell), 0.0, 0.001)


# -- colony budding: a mound at its own maximum capacity founds a new one
# (reported live: "ant mounds should have a maximum capacity and upon
# overpopulation half of the colony will found a new mound hatch a new
# queen and grow the new colony again... they should found based on
# minimum distance to original mound and food availability within scout
# radius") -- real ant colonies bud/split this way once a nest genuinely
# outgrows its site, a new queen and a share of the workforce founding a
# fresh, independent colony nearby rather than the parent growing without
# limit forever. AntColony.MAX_REFERENCE_POPULATION is already named "the
# ceiling capacity() can ever produce" (see that constant's own doc
# comment) -- population chasing a capacity that itself never exceeds it
# means this IS already the real, natural maximum a mound can sustain, not
# a second, redundant "capacity" concept invented on top. -------------------

func test_is_overpopulated_at_is_false_for_a_founding_mound():
	var colony := _colony()
	var cell: Vector2i = colony.mound_cells()[0]
	assert_false(colony.is_overpopulated_at(cell))


func test_is_overpopulated_at_is_true_once_population_reaches_the_reference_maximum():
	var colony := _colony()
	var cell: Vector2i = colony.mound_cells()[0]
	colony._population[cell] = AntPopulationModel.MAX_REFERENCE_POPULATION
	assert_true(colony.is_overpopulated_at(cell))


func test_is_overpopulated_at_is_false_just_short_of_the_reference_maximum():
	var colony := _colony()
	var cell: Vector2i = colony.mound_cells()[0]
	colony._population[cell] = AntPopulationModel.MAX_REFERENCE_POPULATION - 0.01
	assert_false(colony.is_overpopulated_at(cell))


## is_valid_mound_site: the same two real-world facts _seed_initial_mounds
## itself already gates a brand-new mound on (see that function) -- real
## soil (SOIL_BIOMES), and not already somebody else's entrance.
func test_is_valid_mound_site_is_true_for_a_real_soil_cell_with_no_mound():
	var colony := _colony("grassland")
	var occupied: Vector2i = colony.mound_cells()[0]
	var empty := Vector2i((occupied.x + 1) % SIZE, occupied.y)
	while colony.mound_cells().has(empty):
		empty.x = (empty.x + 1) % SIZE
	assert_true(colony.is_valid_mound_site(empty))


func test_is_valid_mound_site_is_false_for_a_cell_that_is_already_a_mound():
	var colony := _colony("grassland")
	var occupied: Vector2i = colony.mound_cells()[0]
	assert_false(colony.is_valid_mound_site(occupied))


func test_is_valid_mound_site_is_false_outside_soil_biomes():
	var colony := AntColony.new(1234, SIZE, SIZE, _biome("ocean"))
	assert_false(colony.is_valid_mound_site(Vector2i(4, 4)))


## A caller searching for a bud site (EarthChunkManager._find_bud_site)
## may reasonably scan a fixed CHUNK_SIZE window without first checking
## it against THIS colony's own (possibly smaller, in a synthetic test)
## real width/height -- out of bounds must read as "not valid" rather
## than indexing _biome out of its own real range.
func test_is_valid_mound_site_is_false_out_of_bounds():
	var colony := _colony("grassland")
	assert_false(colony.is_valid_mound_site(Vector2i(-1, 0)))
	assert_false(colony.is_valid_mound_site(Vector2i(0, -1)))
	assert_false(colony.is_valid_mound_site(Vector2i(SIZE, 0)))
	assert_false(colony.is_valid_mound_site(Vector2i(0, SIZE)))


## bud_new_mound: "half of the colony" -- both population AND its stored
## food reserve, so the new colony is not born starving (mirrors
## _founding_food_reserve's own "never born already starving" reasoning)
## nor is the parent left with an oddly outsized reserve for its own now-
## halved population.
func test_bud_new_mound_halves_the_parents_population_and_food():
	var colony := _colony("grassland", 42)
	var from_cell: Vector2i = colony.mound_cells()[0]
	colony._population[from_cell] = AntPopulationModel.MAX_REFERENCE_POPULATION
	var population_before := colony.population_at(from_cell)
	var food_before := colony.food_stored_at(from_cell)
	var to_cell := Vector2i((from_cell.x + 3) % SIZE, from_cell.y)
	colony.bud_new_mound(from_cell, to_cell)
	assert_almost_eq(colony.population_at(from_cell), population_before * 0.5, 0.01)
	assert_almost_eq(colony.food_stored_at(from_cell), food_before * 0.5, 0.01)


func test_bud_new_mound_gives_the_new_mound_the_other_half():
	var colony := _colony("grassland", 42)
	var from_cell: Vector2i = colony.mound_cells()[0]
	colony._population[from_cell] = AntPopulationModel.MAX_REFERENCE_POPULATION
	var population_before := colony.population_at(from_cell)
	var food_before := colony.food_stored_at(from_cell)
	var to_cell := Vector2i((from_cell.x + 3) % SIZE, from_cell.y)
	colony.bud_new_mound(from_cell, to_cell)
	assert_true(colony.mound_cells().has(to_cell), "the new mound must be real, not just a population entry")
	assert_almost_eq(colony.population_at(to_cell), population_before * 0.5, 0.01)
	assert_almost_eq(colony.food_stored_at(to_cell), food_before * 0.5, 0.01)


## A no-op, not an error, at an invalid site -- the caller (EarthChunkManager)
## is expected to have already checked is_valid_mound_site, but this stays
## safe on its own regardless, the same defensive contract invalidate_
## pheromone_near/other "just try and let this decide" accessors already
## have.
func test_bud_new_mound_does_nothing_at_a_site_that_is_already_a_mound():
	var colony := _colony("grassland")
	var cells: Array = colony.mound_cells()
	assert_gt(cells.size(), 1, "need at least two mounds for this test's own premise")
	var population_before := colony.population_at(cells[0])
	colony.bud_new_mound(cells[0], cells[1])
	assert_almost_eq(colony.population_at(cells[0]), population_before, 0.01, "an invalid target must not touch the source either")


func test_should_bud_is_false_when_not_overpopulated():
	var colony := _colony()
	var cell: Vector2i = colony.mound_cells()[0]
	assert_false(colony.should_bud(cell))


## Mirrors test_forage_roll_spreads_across_true_and_false's own shape: a
## small per-step chance, not an instant guarantee the moment a mound
## crosses the threshold -- real budding is a rare event even for a
## genuinely overpopulated colony, the same "ongoing background activity,
## not a burst" reasoning FORAGE_CHANCE/MOUND_CHANCE's own doc comments
## already give.
func test_should_bud_spreads_across_true_and_false_once_overpopulated():
	var colony := _colony("grassland", 42)
	var cell: Vector2i = colony.mound_cells()[0]
	colony._population[cell] = AntPopulationModel.MAX_REFERENCE_POPULATION
	var saw_true := false
	var saw_false := false
	for i in 200:
		colony._step_count = i
		if colony.should_bud(cell):
			saw_true = true
		else:
			saw_false = true
	assert_true(saw_true, "should roll true at least once across 200 steps")
	assert_true(saw_false, "should roll false at least once across 200 steps -- not an instant guarantee")


func test_bud_chance_is_small():
	assert_lt(AntColony.BUD_CHANCE, 0.5)
	assert_gt(AntColony.BUD_CHANCE, 0.0)


# -- fewer, bigger colonies from the start (see docs/concept/soil_fauna.md's
# "A real food economy" section) -------------------------------------------

## "1 for every 5" of the previous per-chunk cap, taken literally.
func test_max_mounds_is_one_fifth_of_its_previous_value():
	assert_eq(AntColony.MAX_MOUNDS, 2)


## Matches the new starting population exactly -- a healthy, well-fed
## mound can have as many workers out at once as it actually starts with.
func test_max_concurrent_foragers_matches_the_new_starting_population():
	assert_eq(AntColony.MAX_CONCURRENT_FORAGERS, int(AntPopulationModel.STARTING_POPULATION))


# -- growth_fraction_at: what a mound's own visual size reads (see
# ProceduralAntMoundSprite.world_width_for) -------------------------------

## Superseded (2026-09-06): a founding colony now starts at a specific,
## substantial population (15, see test_population_starts_at_fifteen)
## rather than the bare single-digit minimum this test's own premise
## assumed -- reading as an established colony with real room left to
## grow, not a newborn wisp. Replaced with the bound that actually still
## holds: comfortably inside (0, 1), neither a founding wisp's own old
## near-zero reading nor already maxed out the instant it is seeded.
func test_growth_fraction_starts_comfortably_between_founding_and_maxed_out():
	var colony := _colony()
	var cell: Vector2i = colony.mound_cells()[0]
	var fraction := colony.growth_fraction_at(cell)
	assert_gt(fraction, 0.1)
	assert_lt(fraction, 0.9)


## AntColony.advance is a single Euler step (PopulationModel.step), not a
## closed-form solution -- it badly under-integrates for large single
## deltas, so this saturates both EMAs first (20 calls each, matching
## FORAGE_SUCCESS_EMA_RATE/MOISTURE_EMA_RATE's own 0.3 convergence rate),
## THEN advances by many real SECONDS_PER_SIMULATED_DAY-sized steps --
## GROWTH_RATE_PER_DAY (0.05) genuinely means the slowest-growing
## population this game tracks, so reaching near-capacity takes real
## simulated YEARS' worth of daily steps, not a handful of arbitrary
## advance() calls.
## Forage success is now recorded THROUGHOUT the 400-day loop, not just
## up front (2026-09-06, food economy): a mound's own population now
## genuinely eats from a real, depleting food store between successful
## trips (see AntColony.food_availability_fraction) -- a colony fed once
## and then left alone for 400 simulated days would run its reserve down
## and starve back down (a REAL, correctly-modelled outcome -- see
## test_a_colony_that_never_restocks_food_eventually_shrinks -- not a bug
## in this test). A colony that keeps finding food EVERY simulated day,
## the way an actually thriving one would, is what this test means to
## show approaches full growth -- so it keeps depositing food the whole
## way through, at a real per-day RATE (50 completed trips/day) rather
## than the arbitrary single call/day a test loop's own iteration count
## would otherwise imply: MAX_CONCURRENT_FORAGERS (15) foragers each
## completing a trip every few real seconds can complete far more than
## one trip per simulated (60-real-second) day in actual play (see
## docs/concept/soil_fauna.md) -- 50/day is a real, comfortably-above-its-
## own-upkeep rate for a colony approaching MAX_REFERENCE_POPULATION (45,
## needing 45 food/day at FOOD_PER_ANT_PER_DAY=1.0), not a contrived one.
func test_growth_fraction_approaches_one_for_a_thriving_colony():
	var colony := _colony("grassland", 42)
	var cell: Vector2i = colony.mound_cells()[0]
	for i in 20:
		colony.record_forage_result(cell, true)
		colony.record_moisture(cell, 1.0)
	for i in 400:
		for trip in 50:
			colony.record_forage_result(cell, true)
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


## Saturates the recent-success EMA (fixing the capacity ceiling) BEFORE
## advancing, the same order test_growth_fraction_approaches_one_for_a_
## thriving_colony uses and for the identical reason: recording success
## and advancing in the SAME short loop raises the ceiling (EMA, fast)
## well ahead of population (GROWTH_RATE_PER_DAY, genuinely the slowest
## in the game) ever catching up to it, so a mound whose own seeded
## population (see AntColony._seed_initial_mounds) already started above
## the OLD baseline ceiling would see its cap transiently DROP as the
## ceiling jumps out from under it, before growth has had any real time
## to close the gap -- exactly backwards from what this test means to
## show. Advancing by many SECONDS_PER_SIMULATED_DAY-sized steps AFTER
## the ceiling is already fixed is what actually gives population time to
## grow toward it.
## Forage success is now recorded THROUGHOUT the 300-day loop, at a real
## per-day RATE, for the identical reason test_growth_fraction_
## approaches_one_for_a_thriving_colony above now does (see that test's
## own doc comment) -- a real, depleting food store (see AntColony.
## food_availability_fraction) means a colony fed only once and left
## alone for 300 simulated days would starve back toward its unfed floor,
## the real "constraint" half of the new mechanism working as designed --
## not what this test, about a colony that keeps thriving, means to
## exercise.
func test_active_forager_cap_grows_with_a_thriving_colony():
	var colony := _colony("grassland", 42)
	var cell: Vector2i = colony.mound_cells()[0]
	var before := colony.active_forager_cap_at(cell)
	for i in 20:
		colony.record_forage_result(cell, true)
	for i in 300:
		for trip in 50:
			colony.record_forage_result(cell, true)
		colony.advance(AntColony.SECONDS_PER_SIMULATED_DAY)
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


# -- crushed underfoot: one real forager lost (see docs/concept/
# soil_fauna.md's own "Generalized to ants too" -- "no effect on the
# mound's own population/food economy beyond the one forager actually
# lost", now closed) ---------------------------------------------------------

func test_forager_crushed_reduces_population_by_one_worker():
	var colony := _colony()
	var cell: Vector2i = colony.mound_cells()[0]
	var population_before := colony.population_at(cell)
	colony.forager_crushed(cell)
	assert_almost_eq(
		colony.population_at(cell), population_before - AntColony.FORAGER_CRUSH_POPULATION_LOSS, 0.001
	)


func test_forager_crushed_never_drives_population_negative():
	var colony := _colony()
	var cell: Vector2i = colony.mound_cells()[0]
	for i in 1000:
		colony.forager_crushed(cell)
	assert_almost_eq(colony.population_at(cell), 0.0, 0.001)


func test_forager_crushed_at_an_unrelated_cell_does_not_touch_a_real_mound():
	var colony := _colony()
	var cell: Vector2i = colony.mound_cells()[0]
	var population_before := colony.population_at(cell)
	colony.forager_crushed(cell + Vector2i(1000, 1000))
	assert_almost_eq(
		colony.population_at(cell), population_before, 0.001,
		"crushing at an unrelated cell must not touch a real mound"
	)


# -- forager_eaten: a live forager taken by a real bird predator ----------
#
# A distinctly-named sibling of forager_crushed, not a reuse of it --
# see that method's own doc comment: the same population-loss effect
# either way (losing a worker is losing a worker), but kept separate so
# EarthChunkManager can wire a player-caused crush to Karma
# (Karma.WORM_OR_CATERPILLAR_CRUSH_PENALTY, applied by the caller) while
# natural bird predation never triggers that same penalty.

func test_forager_eaten_reduces_population_by_one_worker():
	var colony := _colony()
	var cell: Vector2i = colony.mound_cells()[0]
	var population_before := colony.population_at(cell)
	colony.forager_eaten(cell)
	assert_almost_eq(
		colony.population_at(cell), population_before - AntColony.FORAGER_CRUSH_POPULATION_LOSS, 0.001
	)


func test_forager_eaten_never_drives_population_negative():
	var colony := _colony()
	var cell: Vector2i = colony.mound_cells()[0]
	for i in 1000:
		colony.forager_eaten(cell)
	assert_almost_eq(colony.population_at(cell), 0.0, 0.001)


func test_forager_eaten_at_an_unrelated_cell_does_not_touch_a_real_mound():
	var colony := _colony()
	var cell: Vector2i = colony.mound_cells()[0]
	var population_before := colony.population_at(cell)
	colony.forager_eaten(cell + Vector2i(1000, 1000))
	assert_almost_eq(
		colony.population_at(cell), population_before, 0.001,
		"eating a forager at an unrelated cell must not touch a real mound"
	)
