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


# -- carry direction: which way the bird flies off with it ------------------
#
# Distance alone turned out not to be enough to actually disperse a seed --
# see AmbientFlyerMarker._step_seed_carrying's own doc comment: ordinary
# wander is anchored to a home point within a fairly tight radius (measured
# at a hard ~2.5-tile ceiling for a sparrow, regardless of wander_seed or the
# 10-40 tile range intended above), so a carrying bird needs an actual
# heading to fly off in, not just a duration that assumes it is covering
# ground in a straight line.

func test_carry_direction_is_a_unit_vector():
	for seed_value in 20:
		var heading := SeedEndozoochory.carry_direction(seed_value)
		assert_almost_eq(heading.length(), 1.0, 0.001)


func test_carry_direction_is_deterministic():
	assert_eq(
		SeedEndozoochory.carry_direction(11), SeedEndozoochory.carry_direction(11)
	)


func test_different_birds_head_off_in_different_directions():
	var headings := {}
	for seed_value in 30:
		headings[snappedf(SeedEndozoochory.carry_direction(seed_value).angle(), 0.01)] = true
	assert_gt(headings.size(), 5, "carry direction should vary between birds")


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


# -- granivory: most swallowed GROUND seed is destroyed, not dispersed ------
#
# Distinct from the fruit-tree case above: a fleshy fruit exists specifically
# so the seed riding inside is swallowed unharmed and passes on -- a real
# mutualism. A bare seed picked straight off the ground (flower/grass seed,
# see AmbientFlyerMarker._step_seed_carrying) IS the meal for a true
# granivore like a sparrow, and a real seed-eating songbird's gizzard grinds
# up the large majority of what it eats; only a minority survives gut
# passage to actually establish a new plant. This is what closes
# docs/concept/flora.md's "No seed PREDATORS exist yet" open question for
# this one carrier.

func test_granivory_consumed_chance_is_a_large_majority():
	# Large majority, not near-certain either way: pinned in range so this
	# reads as "a real predator, but the disperser mechanic still fires
	# sometimes" -- see test_seed_mostly_consumed_but_sometimes_survives for
	# the actual distribution this constant produces.
	assert_gt(SeedEndozoochory.GRANIVORY_CONSUMED_CHANCE, 0.5)
	assert_lt(SeedEndozoochory.GRANIVORY_CONSUMED_CHANCE, 1.0)


func test_seed_mostly_consumed_but_sometimes_survives():
	var consumed := 0
	var survived := 0
	for seed_value in 200:
		if SeedEndozoochory.seed_is_consumed(seed_value):
			consumed += 1
		else:
			survived += 1
	assert_gt(consumed, survived, "a real granivore destroys most of what it eats")
	assert_gt(survived, 0, "but not literally every seed -- some still survive to be planted")


func test_consumption_roll_is_deterministic():
	assert_eq(
		SeedEndozoochory.seed_is_consumed(11), SeedEndozoochory.seed_is_consumed(11)
	)


# -- individual fitness modestly nudges the consumption chance --------------
#
# AnimalFitness's first real caller here: a fitter forager (per
# AnimalFitness.fitness_score, from the bird's own identity seed --
# AmbientFlyerMarker.wander_seed) is a slightly more efficient predator, so
# its consumption chance sits a little above GRANIVORY_CONSUMED_CHANCE
# rather than every bird using the exact same flat number regardless of the
# individual. Kept modest: real individual variation in foraging efficiency
# is a few percentage points, not a dramatic swing, and it must never push
# the chance for ANY individual outside the "large majority, not certainty"
# band the existing property tests above already pin.

func test_consumption_chance_increases_with_forager_fitness():
	var AnimalFitness = preload("res://src/world/animal_fitness.gd")
	var fitness := AnimalFitness.new()
	# Seeds chosen (by direct fitness_score computation) to give a clearly
	# low- and clearly high-fitness forager.
	var low_seed := 0
	var high_seed := 0
	var low_score := 2.0
	var high_score := -1.0
	for candidate in 50:
		var score: float = fitness.fitness_score(fitness.phenotype_for(candidate))
		if score < low_score:
			low_score = score
			low_seed = candidate
		if score > high_score:
			high_score = score
			high_seed = candidate
	assert_gt(
		SeedEndozoochory.consumption_chance_for(high_seed),
		SeedEndozoochory.consumption_chance_for(low_seed),
		"a fitter forager should have a measurably higher consumption chance"
	)


func test_consumption_chance_stays_a_modest_nudge_around_the_base_chance():
	var AnimalFitness = preload("res://src/world/animal_fitness.gd")
	var fitness := AnimalFitness.new()
	for seed_value in 50:
		var score: float = fitness.fitness_score(fitness.phenotype_for(seed_value))
		var chance := SeedEndozoochory.consumption_chance_for(seed_value)
		assert_almost_eq(chance, SeedEndozoochory.GRANIVORY_CONSUMED_CHANCE, 0.1)
		assert_gt(chance, 0.5, "still a large majority for every individual")
		assert_lt(chance, 1.0, "never certainty for any individual")


## The actual point of wiring this in: seed_is_consumed accepts the eating
## bird's own identity seed separately from the per-pick roll seed, and uses
## it to nudge the chance -- both still inside the large-majority band the
## existing property tests already pin for every individual, not just on
## average.
func test_seed_is_consumed_still_a_large_majority_for_every_individual_bird():
	var AnimalFitness = preload("res://src/world/animal_fitness.gd")
	var fitness := AnimalFitness.new()
	for forager_seed in 20:
		var consumed := 0
		var survived := 0
		for pick in 200:
			if SeedEndozoochory.seed_is_consumed(forager_seed * 1000 + pick, forager_seed):
				consumed += 1
			else:
				survived += 1
		assert_gt(
			consumed, survived,
			"forager %d should still destroy most of what it eats" % forager_seed
		)


## seed_is_consumed's forager_seed argument defaults to carrier_seed, so
## every existing single-argument call site (and the property tests above)
## is unaffected.
func test_seed_is_consumed_defaults_forager_seed_to_carrier_seed():
	assert_eq(
		SeedEndozoochory.seed_is_consumed(11),
		SeedEndozoochory.seed_is_consumed(11, 11)
	)
