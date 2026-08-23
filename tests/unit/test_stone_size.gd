extends GutTest

## How big a loose stone is, and what that means for taking it (see
## docs/concept/stone.md).
##
## The pillar: if you can lift it you take it, if you can't you break it. The
## divide is a physical question about the stone, not a tag on it.

const StoneSize = preload("res://src/world/stone_size.gd")


# -- the classes -------------------------------------------------------------

## Wentworth grain sizes, the standard geological scale, rather than invented
## tiers. The game's lift/smash line and the real classification agree because
## they are answering the same question.
func test_the_classes_follow_the_wentworth_scale():
	assert_eq(StoneSize.class_for(2.0), StoneSize.CLASS_PEBBLE)
	assert_eq(StoneSize.class_for(10.0), StoneSize.CLASS_COBBLE)
	assert_eq(StoneSize.class_for(80.0), StoneSize.CLASS_BOULDER)


func test_the_boundaries_land_where_the_scale_puts_them():
	assert_eq(StoneSize.class_for(StoneSize.PEBBLE_MAX_CM - 0.01), StoneSize.CLASS_PEBBLE)
	assert_eq(StoneSize.class_for(StoneSize.PEBBLE_MAX_CM + 0.01), StoneSize.CLASS_COBBLE)
	assert_eq(StoneSize.class_for(StoneSize.COBBLE_MAX_CM - 0.01), StoneSize.CLASS_COBBLE)
	assert_eq(StoneSize.class_for(StoneSize.COBBLE_MAX_CM + 0.01), StoneSize.CLASS_BOULDER)


# -- lift it or break it -----------------------------------------------------

func test_a_pebble_is_picked_up_not_smashed():
	assert_true(StoneSize.is_liftable(3.0))
	assert_false(StoneSize.must_be_smashed(3.0))


func test_a_cobble_is_still_something_you_can_carry():
	assert_true(StoneSize.is_liftable(20.0))


func test_a_boulder_has_to_be_broken():
	assert_false(StoneSize.is_liftable(100.0))
	assert_true(StoneSize.must_be_smashed(100.0))


## Every stone is exactly one of the two: there is no size that can neither be
## lifted nor smashed, and none that can be both.
func test_every_stone_can_be_taken_one_way_or_the_other():
	var diameter := 0.5
	while diameter < StoneSize.LARGEST_CM:
		assert_ne(
			StoneSize.is_liftable(diameter), StoneSize.must_be_smashed(diameter),
			"a %.1fcm stone is neither liftable nor smashable, or both" % diameter
		)
		diameter += 0.5


## The line sits at the cobble-boulder boundary, which is where a rock stops
## being liftable in life.
func test_the_lift_line_is_the_cobble_boulder_boundary():
	assert_true(StoneSize.is_liftable(StoneSize.COBBLE_MAX_CM - 0.01))
	assert_false(StoneSize.is_liftable(StoneSize.COBBLE_MAX_CM + 0.01))


# -- what the ground is made of ----------------------------------------------

## Small stone vastly outnumbers large, as it does in real scree. A field of
## uniformly-sized boulders reads as props rather than as eroded ground.
func test_small_stone_is_far_commoner_than_large():
	var small := 0
	var large := 0
	for seed_value in 800:
		if StoneSize.is_liftable(StoneSize.diameter_for(seed_value)):
			small += 1
		else:
			large += 1
	assert_gt(small, large, "the ground should be mostly small stone")
	assert_gt(large, 0, "...but a boulder has to turn up sometimes")


## Every size class actually occurs -- a class that never spawns is dead code.
func test_every_class_turns_up():
	var seen := {}
	for seed_value in 800:
		seen[StoneSize.class_for(StoneSize.diameter_for(seed_value))] = true
	for stone_class in [StoneSize.CLASS_PEBBLE, StoneSize.CLASS_COBBLE, StoneSize.CLASS_BOULDER]:
		assert_true(seen.has(stone_class), "%s never spawns" % stone_class)


## Boulders themselves vary: a field of identical boulders is the same failure
## one step up.
func test_boulders_are_not_all_the_same_size():
	var diameters := {}
	for seed_value in 800:
		var diameter := StoneSize.diameter_for(seed_value)
		if StoneSize.must_be_smashed(diameter):
			diameters[snappedf(diameter, 5.0)] = true
	assert_gt(diameters.size(), 2, "boulders should come in more than one size")


func test_a_given_stone_keeps_its_size():
	for seed_value in [0, 5, 91, 3000]:
		assert_eq(StoneSize.diameter_for(seed_value), StoneSize.diameter_for(seed_value))


func test_no_stone_falls_outside_the_scale():
	for seed_value in 800:
		var diameter := StoneSize.diameter_for(seed_value)
		assert_between(diameter, StoneSize.SMALLEST_CM, StoneSize.LARGEST_CM)


# -- size is worth something -------------------------------------------------

## A bigger boulder is more work AND more reward. If size were cosmetic the
## variety would just be noise.
func test_a_bigger_boulder_takes_more_breaking():
	assert_gt(StoneSize.hits_to_smash(150.0), StoneSize.hits_to_smash(30.0))


func test_breaking_never_gets_easier_as_a_stone_gets_bigger():
	var previous := 0
	var diameter := StoneSize.COBBLE_MAX_CM
	while diameter <= StoneSize.LARGEST_CM:
		var hits := StoneSize.hits_to_smash(diameter)
		assert_gte(hits, previous, "a %.0fcm boulder broke easier than a smaller one" % diameter)
		previous = hits
		diameter += 5.0


## Even the largest boulder stays worth starting: a rock that takes thirty
## swings is a chore, not a decision.
func test_even_the_largest_boulder_is_worth_starting():
	assert_lte(StoneSize.hits_to_smash(StoneSize.LARGEST_CM), StoneSize.MAX_HITS)


func test_the_smallest_boulder_still_takes_more_than_one_hit():
	assert_gt(
		StoneSize.hits_to_smash(StoneSize.COBBLE_MAX_CM + 0.01), 1,
		"a boulder you break in one tap is not a boulder"
	)


func test_a_bigger_stone_yields_more_rock():
	assert_gt(StoneSize.rock_yield(150.0), StoneSize.rock_yield(30.0))
	assert_gt(StoneSize.rock_yield(20.0), StoneSize.rock_yield(3.0))


func test_every_stone_yields_at_least_one_rock():
	var diameter := StoneSize.SMALLEST_CM
	while diameter <= StoneSize.LARGEST_CM:
		assert_gte(StoneSize.rock_yield(diameter), 1, "a %.1fcm stone yielded nothing" % diameter)
		diameter += 1.0


## The reward per swing must not collapse with size, or the big boulder is a
## trap: more work for less rock a hit.
func test_a_big_boulder_pays_at_least_as_well_per_swing():
	var small_rate := (
		float(StoneSize.rock_yield(StoneSize.COBBLE_MAX_CM + 1.0))
		/ float(StoneSize.hits_to_smash(StoneSize.COBBLE_MAX_CM + 1.0))
	)
	var large_rate := (
		float(StoneSize.rock_yield(StoneSize.LARGEST_CM))
		/ float(StoneSize.hits_to_smash(StoneSize.LARGEST_CM))
	)
	assert_gte(large_rate, small_rate, "the big boulder must not be a trap")


# -- how big it looks --------------------------------------------------------

## Read against the player, like everything else in this world. A two-metre
## boulder stands a head above a person, because it is two metres and a person
## is not -- the yardstick is applied honestly rather than rounded to "as tall
## as the player".
func test_the_largest_boulder_stands_a_head_above_the_player():
	assert_almost_eq(
		StoneSize.world_height_px(StoneSize.LARGEST_CM) / StoneSize.PLAYER_WORLD_HEIGHT_PX,
		StoneSize.LARGEST_CM / StoneSize.PLAYER_HEIGHT_CM,
		0.02,
		"a two-metre boulder should stand a head above the player"
	)


## ...and nothing on the ground towers over that.
func test_no_loose_stone_is_more_than_a_boulder():
	var diameter := StoneSize.SMALLEST_CM
	while diameter <= StoneSize.LARGEST_CM:
		assert_lte(
			StoneSize.world_height_px(diameter) / StoneSize.PLAYER_WORLD_HEIGHT_PX,
			StoneSize.LARGEST_CM / StoneSize.PLAYER_HEIGHT_CM + 0.01,
			"a %.0fcm stone drew bigger than the largest boulder" % diameter
		)
		diameter += 1.0


func test_a_pebble_is_underfoot_not_knee_high():
	assert_lt(
		StoneSize.world_height_px(3.0) / StoneSize.PLAYER_WORLD_HEIGHT_PX,
		0.2,
		"a pebble should be something you step over"
	)


## Small stone is exaggerated toward legibility -- a true-scale pebble would be
## a fraction of a pixel -- but the exaggeration must never reorder the sizes.
func test_drawing_never_reorders_the_sizes():
	var previous := 0.0
	var diameter := StoneSize.SMALLEST_CM
	while diameter <= StoneSize.LARGEST_CM:
		var height := StoneSize.world_height_px(diameter)
		assert_gte(height, previous, "a %.1fcm stone drew smaller than a smaller one" % diameter)
		previous = height
		diameter += 0.5


func test_even_the_smallest_pebble_is_still_visible():
	assert_gte(
		StoneSize.world_height_px(StoneSize.SMALLEST_CM), StoneSize.MINIMUM_READABLE_HEIGHT_PX
	)


## Pebbles are ADDED to the ground, not carved out of the boulders that were
## already there.
##
## Every stone cell used to be a boulder. Now most roll small, so leaving the
## spawn density alone would silently have made boulders two-thirds rarer --
## a change nobody asked for, arriving as a side effect of adding pebbles.
## The density is raised to compensate, and this pins the two together.
func test_adding_pebbles_did_not_make_boulders_rarer():
	var StonePlacement := load("res://src/world/stone_placement.gd")
	var boulder_share := 0.0
	var samples := 2000
	for seed_value in samples:
		if StoneSize.must_be_smashed(StoneSize.diameter_for(seed_value)):
			boulder_share += 1.0
	boulder_share /= float(samples)
	var boulders_per_tile: float = StonePlacement.STONE_DENSITY * boulder_share
	assert_almost_eq(
		boulders_per_tile,
		StonePlacement.BOULDERS_PER_TILE_BEFORE_PEBBLES,
		StonePlacement.BOULDERS_PER_TILE_BEFORE_PEBBLES * 0.25,
		"boulders should turn up about as often as they always did"
	)


## ...and the ground really is mostly small stone, not an even mix.
func test_the_ground_is_mostly_small_stone():
	var small := 0
	for seed_value in 2000:
		if StoneSize.is_liftable(StoneSize.diameter_for(seed_value)):
			small += 1
	assert_gt(float(small) / 2000.0, 0.6, "a field should be mostly pebbles and cobbles")


# -- a flock member's own diameter --------------------------------------------

## A flock (see docs/concept/stone.md, StonePlacement.flock_size_at) is a
## cluster of PEBBLES. Each member rolls its own diameter independently so
## the flock isn't the same pebble cloned several times, but that roll must
## stay inside the pebble range specifically -- otherwise a "pebble flock"
## could by chance contain a cobble- or boulder-sized member, which would
## break the lift/smash pillar for that member (a flock member is always
## built as a LiftableStone with no boulder fallback).
func test_pebble_diameter_for_never_leaves_the_pebble_range():
	for seed_value in 800:
		var diameter := StoneSize.pebble_diameter_for(seed_value)
		assert_between(diameter, StoneSize.SMALLEST_CM, StoneSize.PEBBLE_MAX_CM)


func test_pebble_diameter_for_is_deterministic():
	for seed_value in [0, 5, 91, 3000]:
		assert_eq(StoneSize.pebble_diameter_for(seed_value), StoneSize.pebble_diameter_for(seed_value))


## Members still need to look different from each other -- a flock of
## identically-sized pebbles is the same "all one size" failure the general
## diameter roll already avoids.
func test_pebble_diameter_for_varies_across_seeds():
	var diameters := {}
	for seed_value in 200:
		diameters[snappedf(StoneSize.pebble_diameter_for(seed_value), 0.1)] = true
	assert_gt(diameters.size(), 5, "flock members should come in more than a handful of sizes")


## Independent of diameter_for's own roll for the same seed -- otherwise a
## flock member's "own" diameter would just be a rescaled copy of a number
## already used elsewhere for that seed.
func test_pebble_diameter_for_is_not_just_diameter_for_rescaled():
	var differs := false
	for seed_value in 50:
		var general := StoneSize.diameter_for(seed_value)
		var pebble_only := StoneSize.pebble_diameter_for(seed_value)
		if not is_equal_approx(general, pebble_only):
			differs = true
			break
	assert_true(differs, "pebble_diameter_for should not track diameter_for exactly")


# -- real mass, for the momentum model (see docs/concept/materials.md, --
# -- impact_resolver.gd/throwable.gd's momentum = mass * velocity)  ----------
#
# A stone is treated as roughly spherical: mass = granite density x sphere
# volume. Pinned against the exact formula (not just plausibility) so the
# constant and the formula can't silently drift apart, PLUS a plausibility
# sanity check at both ends of the real range, per this project's "no
# eyeballed numbers" rule.

## The exact sphere-volume-times-density formula, computed independently of
## StoneSize's own implementation, so this test would catch either the
## formula OR the density constant drifting.
func test_mass_kg_for_matches_the_sphere_volume_formula():
	var diameter_cm := 10.0
	var radius_cm := diameter_cm / 2.0
	var volume_cm3 := (4.0 / 3.0) * PI * radius_cm * radius_cm * radius_cm
	var expected_kg := volume_cm3 * StoneSize.GRANITE_DENSITY_G_PER_CM3 / 1000.0
	assert_almost_eq(StoneSize.mass_kg_for(diameter_cm), expected_kg, 0.001)


## A ~5cm pebble should land at a plausible FRACTION of a kilogram -- not
## grams (too light to matter) and not several kilos (that's cobble territory).
func test_mass_kg_for_a_small_pebble_is_a_plausible_fraction_of_a_kilogram():
	assert_between(StoneSize.mass_kg_for(5.0), 0.05, 0.5)


## A ~150cm boulder should land at plausible TONNES -- a real two-metre-class
## granite boulder is multiple tonnes, not a few kilos.
func test_mass_kg_for_a_large_boulder_is_plausible_tonnes():
	assert_between(StoneSize.mass_kg_for(150.0), 1000.0, 10000.0)


## Mass must never shrink as a stone gets bigger -- the same "never reorders"
## guarantee world_height_px already pins for the drawn size.
func test_mass_kg_for_never_shrinks_as_diameter_grows():
	var previous := 0.0
	var diameter := StoneSize.SMALLEST_CM
	while diameter <= StoneSize.LARGEST_CM:
		var mass := StoneSize.mass_kg_for(diameter)
		assert_gte(mass, previous, "a %.1fcm stone massed less than a smaller one" % diameter)
		previous = mass
		diameter += 5.0


# -- leg mass (the kick-cutoff reference) ------------------------------------

## A real human leg is roughly 10-13kg for an average adult -- sanity-bounds
## LEG_MASS_KG (derived from AVERAGE_BODY_MASS_KG x LEG_MASS_FRACTION, an
## anthropometric segment-mass fraction) against real anthropometric figures,
## so the two constants it's built from can't silently drift into something
## implausible.
func test_leg_mass_kg_is_a_plausible_real_leg_mass():
	assert_between(StoneSize.LEG_MASS_KG, 8.0, 15.0)


## The formula stays exactly what its own doc comment claims: a fraction of
## average total body mass, not a bare number with a fraction bolted on after
## the fact.
func test_leg_mass_kg_matches_its_own_formula():
	assert_almost_eq(
		StoneSize.LEG_MASS_KG,
		StoneSize.AVERAGE_BODY_MASS_KG * StoneSize.LEG_MASS_FRACTION,
		0.001
	)
