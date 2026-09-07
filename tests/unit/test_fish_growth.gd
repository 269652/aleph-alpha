extends GutTest

## Forage-coupled mass growth for fish -- see docs/concept/aquatic_foraging.md's
## "Revised (2026-09-07): real per-species diet and forage-coupled mass".
##
## Unlike MammalGrowth (a land creature grows from a fixed newborn fraction
## to full size over a fixed real-time duration, whether or not it ever
## finds food), a fish's mass only advances on a REAL successful graze --
## reported directly: "so every fish can properly forage and grow mass",
## one connected fact, not two independent ones.

const FishGrowth = preload("res://src/gameplay/fish_growth.gd")


func test_juvenile_start_fraction_is_half_adult_mass():
	assert_almost_eq(FishGrowth.JUVENILE_START_FRACTION, 0.5, 0.0001)


func test_starting_mass_for_is_half_the_species_adult_mass():
	assert_almost_eq(FishGrowth.starting_mass_for(2.0), 1.0, 0.0001)


func test_a_successful_meal_grows_mass_toward_the_adult_cap():
	var grown := FishGrowth.feed(1.0, 2.0)
	assert_gt(grown, 1.0, "a real meal should grow mass")
	assert_lte(grown, 2.0, "never past the species' own adult mass")


## A FRACTION of the species' own adult mass per meal, not a flat kg amount
## -- a small species and a large one both take roughly the same NUMBER of
## good meals to mature, proportional to their own real size (the identical
## species-scaled-by-proportion reasoning MammalGrowth already applies to
## maturation DURATION).
func test_growth_per_meal_is_proportional_to_adult_mass():
	var small_species_gain := FishGrowth.feed(0.125, 0.25) - 0.125  # half-grown bluegill
	var large_species_gain := FishGrowth.feed(1.75, 3.5) - 1.75  # half-grown koi, same fraction
	assert_almost_eq(small_species_gain / 0.25, large_species_gain / 3.5, 0.0001)


func test_growth_is_capped_at_the_adult_mass():
	var grown := FishGrowth.feed(1.99, 2.0)
	assert_lte(grown, 2.0)
	# Many more meals in a row must never push mass past the cap either.
	for i in 50:
		grown = FishGrowth.feed(grown, 2.0)
	assert_almost_eq(grown, 2.0, 0.0001)


func test_growth_is_monotonic_never_shrinks():
	var mass := FishGrowth.starting_mass_for(1.0)
	for i in 10:
		var grown := FishGrowth.feed(mass, 1.0)
		assert_gte(grown, mass, "a successful meal must never reduce mass")
		mass = grown


# -- visual scale: mass follows the cube of a linear dimension --------------

func test_visual_scale_fraction_at_full_adult_mass_is_one():
	assert_almost_eq(FishGrowth.visual_scale_fraction(2.0, 2.0), 1.0, 0.0001)


## The same real cube-law relationship CreatureMass._mass_from_world_scale
## already uses in the other direction (deriving mass FROM visual scale) --
## reused here to derive visual scale FROM real mass.
func test_visual_scale_fraction_is_the_cube_root_of_the_mass_fraction():
	assert_almost_eq(FishGrowth.visual_scale_fraction(0.125, 1.0), 0.5, 0.0001)


## A linear mass-to-scale mapping would make a half-massed fish look
## comically flat/thin (the same "distorted... very large/small" failure
## shape this project already hit and fixed once for SquashCrushEffect) --
## the cube root reads as visibly, believably smaller instead of half-size
## outright.
func test_visual_scale_fraction_is_not_a_linear_mapping():
	var linear := 0.5 / 1.0
	assert_gt(FishGrowth.visual_scale_fraction(0.5, 1.0), linear)
