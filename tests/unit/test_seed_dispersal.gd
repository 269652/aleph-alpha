extends GutTest

## SeedDispersal (see docs/concept/flora.md#spread-by-animal-seed-dispersal).
##
## Flowers spread because animals carry seed, not by teleporting into
## neighbouring cells. That ties flower spread to the ecosystem's actual
## movement corridors: a region that loses its grazers slowly stops spreading
## flowers, the same "ecology has consequences" thread as tree spread.

const SeedDispersal = preload("res://src/world/seed_dispersal.gd")

const TILE := 16.0


func _flower(position: Vector2, species: String = "rose") -> Dictionary:
	return {"position": position, "species": species}


# -- picking seed up ---------------------------------------------------------

func test_an_animal_standing_in_a_bloom_picks_up_that_species():
	var picked := SeedDispersal.pickup_species(
		Vector2.ZERO, [_flower(Vector2.ZERO)], "summer", TILE, 7
	)
	assert_eq(picked, "rose")


func test_an_animal_far_from_any_flower_picks_up_nothing():
	var far := Vector2((SeedDispersal.PICKUP_RADIUS_TILES + 2.0) * TILE, 0.0)
	assert_eq(SeedDispersal.pickup_species(far, [_flower(Vector2.ZERO)], "summer", TILE, 7), "")


## Seed comes from a BLOOM. A rose in winter is just a plant.
func test_nothing_is_picked_up_from_a_species_out_of_season():
	assert_eq(
		SeedDispersal.pickup_species(Vector2.ZERO, [_flower(Vector2.ZERO)], "winter", TILE, 7), ""
	)


func test_pickup_is_deterministic():
	var flowers := [_flower(Vector2(4, 4)), _flower(Vector2(-30, 9), "clover")]
	assert_eq(
		SeedDispersal.pickup_species(Vector2.ZERO, flowers, "summer", TILE, 3),
		SeedDispersal.pickup_species(Vector2.ZERO, flowers, "summer", TILE, 3)
	)


func test_pickup_from_an_empty_meadow_is_harmless():
	assert_eq(SeedDispersal.pickup_species(Vector2.ZERO, [], "summer", TILE, 1), "")


# -- carrying it somewhere ---------------------------------------------------

## The carry distance is what actually moves a species across the map, and it
## must vary per animal -- a fixed distance would stamp flowers at a constant
## radius, which reads as a pattern rather than as spread.
func test_carry_distance_stays_within_its_declared_bounds():
	for seed_value in 40:
		var distance := SeedDispersal.carry_distance_tiles(seed_value)
		assert_between(
			distance, SeedDispersal.CARRY_MIN_TILES, SeedDispersal.CARRY_MAX_TILES
		)


func test_different_animals_carry_seed_different_distances():
	var distances := {}
	for seed_value in 30:
		distances[snappedf(SeedDispersal.carry_distance_tiles(seed_value), 0.01)] = true
	assert_gt(distances.size(), 5, "carry distance should vary between animals")


func test_carry_distance_is_deterministic():
	assert_eq(
		SeedDispersal.carry_distance_tiles(11), SeedDispersal.carry_distance_tiles(11)
	)


## Seed has to actually travel -- a zero-distance drop would just re-plant the
## flower on top of its parent and spread nothing.
func test_seed_always_travels_at_least_a_tile():
	assert_gte(SeedDispersal.CARRY_MIN_TILES, 1.0)


# -- which way it heads off while carrying -----------------------------------
#
# CreatureWander (ordinary ground-creature wander) is the SAME home-tethered
# containment shape AmbientFlyerMovement uses for birds -- measured at a hard
# ~2.6-tile ceiling regardless of wander_seed (see docs/progress.md), well
# short of this module's own 3-14 tile range. A carrier needs an actual
# heading to lean into while carrying, not just a distance to be told it
# hasn't covered yet -- mirrors SeedEndozoochory.carry_direction exactly.

func test_carry_direction_is_a_unit_vector():
	for seed_value in 20:
		var heading := SeedDispersal.carry_direction(seed_value)
		assert_almost_eq(heading.length(), 1.0, 0.001)


func test_carry_direction_is_deterministic():
	assert_eq(SeedDispersal.carry_direction(11), SeedDispersal.carry_direction(11))


func test_different_animals_head_off_in_different_directions():
	var headings := {}
	for seed_value in 30:
		headings[snappedf(SeedDispersal.carry_direction(seed_value).angle(), 0.01)] = true
	assert_gt(headings.size(), 5, "carry direction should vary between animals")


## Sampled at a different PixelNoise coordinate than carry_distance_tiles's,
## so a fast/far-carrying animal is equally likely in any direction.
func test_carry_direction_varies_independently_of_carry_distance():
	var direction_values := {}
	var distance_values := {}
	for seed_value in 30:
		direction_values[snappedf(SeedDispersal.carry_direction(seed_value).angle(), 0.01)] = true
		distance_values[snappedf(SeedDispersal.carry_distance_tiles(seed_value), 0.01)] = true
	assert_gt(direction_values.size(), 5)
	assert_gt(distance_values.size(), 5)


# -- where it can root -------------------------------------------------------

func test_seed_roots_on_grassland():
	assert_true(SeedDispersal.can_root_in("grassland"))


## Dropping a rose in the sea or on bare rock must not grow one.
func test_seed_does_not_root_on_water_or_rock():
	for biome in ["ocean", "mountain"]:
		assert_false(SeedDispersal.can_root_in(biome), "%s should not sprout flowers" % biome)


func test_an_unknown_biome_does_not_sprout_flowers():
	assert_false(SeedDispersal.can_root_in("moonbase"))
