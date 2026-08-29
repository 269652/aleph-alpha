extends GutTest

## SquirrelNutCaching (see docs/concept/flora.md's disperser-vs-predator
## tension and docs/concept/long_grass.md's "Reproduction" section, which
## SeedCaching's mouse scatter-hoarding shape is mirrored from).
##
## A real scatter-hoarding squirrel finds a fallen tree NUT, carries it a
## short ground distance in its mouth while it goes on foraging (exactly
## like a mouse's grass-seed cheek pouch, see SeedCaching), and then either
## eats it outright on the spot -- the majority outcome, a real
## scatter-hoarder's actual meal -- or caches it, in which case it survives
## to sprout a new tree elsewhere. Distinct from BOTH existing carriers:
##   - SeedCaching (mouse grass-seed scatter-hoarding): same on-foot
##     carry-a-short-distance SHAPE, but that module always caches (grass
##     seed has no "the mouse just eats it instead" branch) and it operates
##     on TallGrass's own ground-seed system, not fallen tree nuts.
##   - SeedEndozoochory (bird fruit/ground-seed swallowing): a real
##     mutualism for fruit (the seed always survives digestion) with a
##     GRANIVORY_CONSUMED_CHANCE predation roll only for bare ground seed --
##     never for the fruit/nut a bird swallows whole. A squirrel's nut is the
##     opposite case from tree fruit: the animal is CRACKING it open for the
##     kernel, so the predation roll applies here specifically to a
##     hard-shelled NUT, closing docs/concept/flora.md's last open
##     "no seed predator for fruit/nut seed" gap.

const SquirrelNutCaching = preload("res://src/gameplay/squirrel_nut_caching.gd")
const SeedCaching = preload("res://src/gameplay/seed_caching.gd")
const SeedEndozoochory = preload("res://src/gameplay/seed_endozoochory.gd")


# -- carrying it a short ground distance -------------------------------------

func test_carry_distance_stays_within_its_declared_bounds():
	for seed_value in 40:
		var distance := SquirrelNutCaching.carry_distance_tiles(seed_value)
		assert_between(distance, SquirrelNutCaching.CARRY_MIN_TILES, SquirrelNutCaching.CARRY_MAX_TILES)


func test_different_squirrels_carry_a_nut_different_distances():
	var distances := {}
	for seed_value in 30:
		distances[snappedf(SquirrelNutCaching.carry_distance_tiles(seed_value), 0.01)] = true
	assert_gt(distances.size(), 5, "carry distance should vary between individual squirrels")


func test_carry_distance_is_deterministic():
	assert_eq(
		SquirrelNutCaching.carry_distance_tiles(11), SquirrelNutCaching.carry_distance_tiles(11)
	)


## A nut has to actually travel -- a zero-distance cache would just drop it
## back where it was found and disperse nothing.
func test_cached_nut_always_travels_at_least_a_fraction_of_a_tile():
	assert_gt(SquirrelNutCaching.CARRY_MIN_TILES, 0.0)


## Real squirrels have a bigger home range and are far more mobile than a
## mouse, so their carry range sits ABOVE a mouse's own short on-foot range --
## but a squirrel still walks/hops on the ground rather than flying, so it
## stays well below a bird's gut-passage flight range too. Three real,
## distinctly-grounded tiers, not just three arbitrary numbers.
func test_squirrel_carries_a_nut_farther_than_a_mouse_carries_grass_seed():
	assert_gt(SquirrelNutCaching.CARRY_MAX_TILES, SeedCaching.CARRY_MAX_TILES)


func test_squirrel_carry_range_is_shorter_than_bird_endozoochory():
	assert_lt(SquirrelNutCaching.CARRY_MAX_TILES, SeedEndozoochory.CARRY_MIN_TILES)


# -- which way it heads off while carrying -----------------------------------
#
# CreatureWander (ordinary ground-creature wander, shared by squirrels) is the
# SAME home-tethered containment shape AmbientFlyerMovement uses for birds --
# measured at a hard ~2.6-tile ceiling regardless of wander_seed (see
# docs/progress.md), which most of this module's own 2-9 tile range already
# exceeds. A squirrel needs an actual heading to lean into while carrying,
# not just a distance it hasn't covered yet -- mirrors
# SeedEndozoochory.carry_direction exactly. Sampled at PixelNoise coordinate
# (0, 2), distinct from BOTH carry_distance_tiles's (0, 0) and
# nut_is_consumed's (0, 1), so all three rolls vary independently.

func test_carry_direction_is_a_unit_vector():
	for seed_value in 20:
		var heading := SquirrelNutCaching.carry_direction(seed_value)
		assert_almost_eq(heading.length(), 1.0, 0.001)


func test_carry_direction_is_deterministic():
	assert_eq(
		SquirrelNutCaching.carry_direction(11), SquirrelNutCaching.carry_direction(11)
	)


func test_different_squirrels_head_off_in_different_directions():
	var headings := {}
	for seed_value in 30:
		headings[snappedf(SquirrelNutCaching.carry_direction(seed_value).angle(), 0.01)] = true
	assert_gt(headings.size(), 5, "carry direction should vary between individual squirrels")


## Sampled at a coordinate distinct from BOTH carry_distance_tiles's and
## nut_is_consumed's, so a far-caching squirrel is equally likely in any
## direction regardless of whether it ends up eating or caching the nut.
func test_carry_direction_varies_independently_of_carry_distance_and_consumption():
	var direction_values := {}
	var distance_values := {}
	var consumed_values := {}
	for seed_value in 30:
		direction_values[snappedf(SquirrelNutCaching.carry_direction(seed_value).angle(), 0.01)] = true
		distance_values[snappedf(SquirrelNutCaching.carry_distance_tiles(seed_value), 0.01)] = true
		consumed_values[SquirrelNutCaching.nut_is_consumed(seed_value)] = true
	assert_gt(direction_values.size(), 5)
	assert_gt(distance_values.size(), 5)
	assert_eq(consumed_values.size(), 2)


# -- noticing a fallen nut while foraging ------------------------------------

func test_pickup_radius_is_a_close_range():
	assert_gt(SquirrelNutCaching.PICKUP_RADIUS_TILES, 0.0)
	assert_lte(SquirrelNutCaching.PICKUP_RADIUS_TILES, 4.0)


# -- eaten outright vs. cached: the disperser-vs-predator tension -----------
#
# Real scatter-hoarding rodents cache only a MINORITY of what they gather --
# most handled nuts are eaten immediately, and caching becomes the exception
# rather than the rule (field studies on grey squirrels/chipmunks commonly
## find well under half of harvested nuts actually get cached, the rest eaten
# on the spot). NUT_CONSUMED_CHANCE is deliberately its own constant, not a
# reuse of SeedEndozoochory.GRANIVORY_CONSUMED_CHANCE (0.8): granivory is
# passive/incidental gut-passage survival on a tiny bare seed, while scatter-
# hoarding is a deliberate food-storing behaviour on a much larger, more
# valuable food item -- a real squirrel invests real effort in caching a
# nut, so a meaningfully higher share of what it handles survives to be
# planted than a sparrow's incidentally-surviving grain (see
# test_squirrels_cache_a_bigger_share_than_a_sparrows_incidental_survival).

func test_nut_consumed_chance_is_a_majority_but_not_a_certainty():
	assert_gt(SquirrelNutCaching.NUT_CONSUMED_CHANCE, 0.5)
	assert_lt(SquirrelNutCaching.NUT_CONSUMED_CHANCE, 1.0)


func test_a_squirrel_mostly_eats_the_nut_but_sometimes_caches_it():
	var consumed := 0
	var cached := 0
	for seed_value in 200:
		if SquirrelNutCaching.nut_is_consumed(seed_value):
			consumed += 1
		else:
			cached += 1
	assert_gt(consumed, cached, "a scatter-hoarder eats most of what it handles")
	assert_gt(cached, 0, "but not literally every nut -- some get cached instead")


## Deliberate caching effort should survive proportionally MORE often than a
## bird's merely-incidental gut-passage survival of a bare ground seed.
func test_squirrels_cache_a_bigger_share_than_a_sparrows_incidental_survival():
	assert_lt(SquirrelNutCaching.NUT_CONSUMED_CHANCE, SeedEndozoochory.GRANIVORY_CONSUMED_CHANCE)


func test_consumption_roll_is_deterministic():
	assert_eq(
		SquirrelNutCaching.nut_is_consumed(11), SquirrelNutCaching.nut_is_consumed(11)
	)


## The consumed-vs-cached roll must vary independently of the carry-distance
## roll for the same carrier -- sampled at a different PixelNoise coordinate,
## exactly like SeedEndozoochory.seed_is_consumed vs. carry_distance_tiles.
func test_consumption_roll_varies_independently_of_carry_distance():
	var consumed_values := {}
	var carry_values := {}
	for seed_value in 30:
		consumed_values[SquirrelNutCaching.nut_is_consumed(seed_value)] = true
		carry_values[snappedf(SquirrelNutCaching.carry_distance_tiles(seed_value), 0.01)] = true
	assert_eq(consumed_values.size(), 2, "both outcomes should appear across enough individuals")
	assert_gt(carry_values.size(), 5, "carry distance should still vary across the same individuals")


# -- individual fitness modestly nudges the consumption chance --------------
#
# Mirrors SeedEndozoochory's own AnimalFitness wiring exactly (see that
# module's "individual fitness modestly nudges the consumption chance"
# section): a fitter squirrel (per AnimalFitness.fitness_score, from the
# squirrel's own identity seed -- CreatureMarker.wander_seed) is a slightly
# more efficient forager, so its own consumption chance sits a little above
# NUT_CONSUMED_CHANCE rather than every squirrel sharing one flat number.
# Kept modest -- a few percentage points, not a dramatic swing -- and it must
# never push the chance for ANY individual squirrel outside the "clear
# majority eaten, real minority cached" band
# test_nut_consumed_chance_is_a_majority_but_not_a_certainty already pins.

func test_nut_consumption_chance_increases_with_forager_fitness():
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
		SquirrelNutCaching.nut_consumption_chance_for(high_seed),
		SquirrelNutCaching.nut_consumption_chance_for(low_seed),
		"a fitter forager should have a measurably higher consumption chance"
	)


func test_nut_consumption_chance_stays_a_modest_nudge_around_the_base_chance():
	var AnimalFitness = preload("res://src/world/animal_fitness.gd")
	var fitness := AnimalFitness.new()
	for seed_value in 50:
		var score: float = fitness.fitness_score(fitness.phenotype_for(seed_value))
		var chance := SquirrelNutCaching.nut_consumption_chance_for(seed_value)
		assert_almost_eq(chance, SquirrelNutCaching.NUT_CONSUMED_CHANCE, 0.1)
		assert_gt(chance, 0.5, "still a clear majority for every individual")
		assert_lt(chance, 1.0, "never certainty for any individual")


## The actual point of wiring this in: nut_is_consumed accepts the eating
## squirrel's own identity seed separately from the per-pick roll seed, and
## uses it to nudge the chance -- both still inside the majority-but-not-
## certainty band the existing property tests already pin, for every
## individual, not just on average.
func test_nut_is_consumed_still_a_majority_for_every_individual_squirrel():
	for forager_seed in 20:
		var consumed := 0
		var cached := 0
		for pick in 200:
			if SquirrelNutCaching.nut_is_consumed(forager_seed * 1000 + pick, forager_seed):
				consumed += 1
			else:
				cached += 1
		assert_gt(
			consumed, cached,
			"forager %d should still eat most of what it handles" % forager_seed
		)


## nut_is_consumed's forager_seed argument defaults to carrier_seed, so every
## existing single-argument call site (and the property tests above) is
## unaffected.
func test_nut_is_consumed_defaults_forager_seed_to_carrier_seed():
	assert_eq(
		SquirrelNutCaching.nut_is_consumed(11),
		SquirrelNutCaching.nut_is_consumed(11, 11)
	)
