extends GutTest

## SeedCaching (see docs/concept/long_grass.md's "Reproduction" section).
##
## Rodent scatter-hoarding: a mouse finds a fallen grass seed, carries a
## whole one in its cheek pouch on foot for a short ground distance, and
## caches it nearby but not adjacent. Deliberately NOT SeedEndozoochory's
## swallow-and-digest-over-flight-time model -- a mouse does not fly and
## does not digest a seed in transit, so its carry range is a fraction of a
## bird's or even a grazer's own epizoochory range.

const SeedCaching = preload("res://src/gameplay/seed_caching.gd")
const SeedDispersal = preload("res://src/world/seed_dispersal.gd")
const SeedEndozoochory = preload("res://src/gameplay/seed_endozoochory.gd")


# -- carrying it a short ground distance -------------------------------------

func test_carry_distance_stays_within_its_declared_bounds():
	for seed_value in 40:
		var distance := SeedCaching.carry_distance_tiles(seed_value)
		assert_between(distance, SeedCaching.CARRY_MIN_TILES, SeedCaching.CARRY_MAX_TILES)


func test_different_mice_carry_seed_different_distances():
	var distances := {}
	for seed_value in 30:
		distances[snappedf(SeedCaching.carry_distance_tiles(seed_value), 0.01)] = true
	assert_gt(distances.size(), 5, "carry distance should vary between individual mice")


func test_carry_distance_is_deterministic():
	assert_eq(SeedCaching.carry_distance_tiles(11), SeedCaching.carry_distance_tiles(11))


## Seed has to actually travel -- a zero-distance cache would just drop the
## seed back where it was found and disperse nothing.
func test_cached_seed_always_travels_at_least_a_fraction_of_a_tile():
	assert_gt(SeedCaching.CARRY_MIN_TILES, 0.0)


## The whole grounded reasoning for a separate module: a mouse is a short-
## range, on-foot carrier, not an airborne digester -- its range must sit
## well below both existing carriers, not merely below the bird's.
func test_rodent_carry_range_is_shorter_than_bird_endozoochory():
	assert_lt(SeedCaching.CARRY_MAX_TILES, SeedEndozoochory.CARRY_MIN_TILES)


func test_rodent_carry_range_is_shorter_than_grazer_epizoochory():
	assert_lt(SeedCaching.CARRY_MAX_TILES, SeedDispersal.CARRY_MAX_TILES)


# -- which way it heads off while carrying -----------------------------------
#
# CreatureWander (ordinary ground-creature wander, shared by mice) is the SAME
# home-tethered containment shape AmbientFlyerMovement uses for birds --
# measured at a hard ~2.6-tile ceiling regardless of wander_seed (see
# docs/progress.md), which the TOP of this module's own 1-6 tile range
# already exceeds. A mouse needs an actual heading to lean into while
# carrying, not just a distance it hasn't covered yet -- mirrors
# SeedEndozoochory.carry_direction exactly.

func test_carry_direction_is_a_unit_vector():
	for seed_value in 20:
		var heading := SeedCaching.carry_direction(seed_value)
		assert_almost_eq(heading.length(), 1.0, 0.001)


func test_carry_direction_is_deterministic():
	assert_eq(SeedCaching.carry_direction(11), SeedCaching.carry_direction(11))


func test_different_mice_head_off_in_different_directions():
	var headings := {}
	for seed_value in 30:
		headings[snappedf(SeedCaching.carry_direction(seed_value).angle(), 0.01)] = true
	assert_gt(headings.size(), 5, "carry direction should vary between individual mice")


## Sampled at a different PixelNoise coordinate than carry_distance_tiles's,
## so a far-caching mouse is equally likely in any direction.
func test_carry_direction_varies_independently_of_carry_distance():
	var direction_values := {}
	var distance_values := {}
	for seed_value in 30:
		direction_values[snappedf(SeedCaching.carry_direction(seed_value).angle(), 0.01)] = true
		distance_values[snappedf(SeedCaching.carry_distance_tiles(seed_value), 0.01)] = true
	assert_gt(direction_values.size(), 5)
	assert_gt(distance_values.size(), 5)


# -- noticing a fallen seed while foraging -----------------------------------

## Tight, like SeedDispersal's own brushing radius -- a mouse grabs a seed it
## is essentially standing next to, not one anywhere across a meadow.
func test_pickup_radius_is_a_close_range():
	assert_gt(SeedCaching.PICKUP_RADIUS_TILES, 0.0)
	assert_lte(SeedCaching.PICKUP_RADIUS_TILES, 4.0)
