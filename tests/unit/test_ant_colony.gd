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
