extends GutTest

## SeedEndozoochory (see docs/concept/flora.md#bird-endozoochory).
##
## Distinct from SeedDispersal (flower EPIzoochory -- seed riding on a
## grazer's coat, picked up by brushing past a bloom): this is a bird
## swallowing a fallen fruit WHOLE, the seed surviving digestion and getting
## deposited elsewhere once the bird has actually flown on. Same
## carry-distance/can-root-in shape as SeedDispersal (the established idiom
## this codebase already uses for animal-carried seed), but its own module --
## a different disperser, a different distance range, and different rootable
## biomes (fruit TREES, not meadow flowers).

const SeedEndozoochory = preload("res://src/gameplay/seed_endozoochory.gd")


# -- carrying it somewhere ---------------------------------------------------

## A bird's gut passage carries seed much further than a grazer brushing
## seed onto its coat (SeedDispersal.CARRY_MAX_TILES is 14) -- real
## endozoochory routinely disperses seed well beyond a ground animal's
## epizoochory range, since the disperser is airborne and takes longer to
## pass the seed than to shed it off its fur.
func test_carry_distance_exceeds_ground_epizoochory_range():
	const SeedDispersal = preload("res://src/world/seed_dispersal.gd")
	assert_gt(SeedEndozoochory.CARRY_MIN_TILES, SeedDispersal.CARRY_MAX_TILES * 0.5)
	assert_gt(SeedEndozoochory.CARRY_MAX_TILES, SeedDispersal.CARRY_MAX_TILES)


func test_carry_distance_stays_within_its_declared_bounds():
	for seed_value in 40:
		var distance := SeedEndozoochory.carry_distance_tiles(seed_value)
		assert_between(
			distance, SeedEndozoochory.CARRY_MIN_TILES, SeedEndozoochory.CARRY_MAX_TILES
		)


func test_different_birds_carry_seed_different_distances():
	var distances := {}
	for seed_value in 30:
		distances[snappedf(SeedEndozoochory.carry_distance_tiles(seed_value), 0.01)] = true
	assert_gt(distances.size(), 5, "carry distance should vary between birds")


func test_carry_distance_is_deterministic():
	assert_eq(
		SeedEndozoochory.carry_distance_tiles(11), SeedEndozoochory.carry_distance_tiles(11)
	)


func test_seed_always_travels_at_least_a_tile():
	assert_gte(SeedEndozoochory.CARRY_MIN_TILES, 1.0)


# -- where a dispersed tree seed can root ------------------------------------
#
# Delegated to TreeRooting, which is the ONE answer to "can a tree stand here".
# This module used to keep its own list -- forest and rainforest only -- while
# ground spread had no check at all, which is how trees ended up standing in a
# lake. Two rules for one question is the drift this project keeps getting bitten
# by.
#
# Grassland is now included, which is a real widening: a bird carrying seed out
# into a meadow is most of what bird dispersal is FOR, and a wood that can never
# leave the wood cannot colonise anything.

func test_tree_seed_roots_where_a_tree_can_stand():
	for biome in ["forest", "rainforest", "grassland"]:
		assert_true(SeedEndozoochory.can_root_in(biome), biome)


func test_tree_seed_does_not_root_on_water_or_rock():
	for biome in ["ocean", "mountain", "desert", "tundra"]:
		assert_false(SeedEndozoochory.can_root_in(biome), "%s should not sprout a tree" % biome)


## The delegation is the point: one rule, not two that can drift.
func test_it_gives_the_same_answer_as_the_shared_rooting_rule():
	var TreeRooting := load("res://src/world/tree_rooting.gd")
	for biome in ["forest", "rainforest", "grassland", "ocean", "mountain", "desert", "tundra", "x"]:
		assert_eq(
			SeedEndozoochory.can_root_in(biome), TreeRooting.can_root_in(biome), biome
		)


func test_an_unknown_biome_does_not_sprout_a_tree():
	assert_false(SeedEndozoochory.can_root_in("moonbase"))
