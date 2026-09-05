extends GutTest

## Red-first spec for capture_physics.gd (docs/concept/capture_dsl.md): the
## pure, tuned, property-tested derivation of a capture attempt's real odds.
## Same discipline as spell_cost.gd -- every tuned constant pinned by a
## property test, never an eyeballed number (CLAUDE.md).

const CapturePhysics = preload("res://src/gameplay/capture_physics.gd")
const FlyerPersonality = preload("res://src/gameplay/flyer_personality.gd")

var physics: CapturePhysics


func before_each():
	physics = CapturePhysics.new()


# --- the formula's own invariants, generic over `base` -----------------------

func test_a_middling_target_gets_exactly_the_devices_own_base_chance():
	# FlyerPersonality.MIDDLING_BOLDNESS is the "unremarkable middle" every
	# personality-less target already reads as -- a hand-placed test fixture,
	# an older save. It must not nudge the device's own tuning either way.
	for base in [0.0, 0.2, 0.5, 0.65, 0.9, 1.0]:
		assert_almost_eq(
			physics.catch_chance(base, FlyerPersonality.MIDDLING_BOLDNESS), base, 0.0001,
			"base %f should be unchanged at middling boldness" % base
		)


func test_a_middling_target_is_also_the_default_when_no_boldness_is_given():
	assert_almost_eq(physics.catch_chance(0.65), physics.catch_chance(0.65, 0.5), 0.0001)


func test_boldness_is_monotonically_non_decreasing_in_its_effect_on_chance():
	# A bolder individual is never harder to catch than a shyer one -- walking
	# boldness upward must never make the chance go down.
	var previous := physics.catch_chance(0.5, 0.0)
	var step := 0.1
	var boldness := step
	while boldness <= 1.0001:
		var chance := physics.catch_chance(0.5, boldness)
		assert_true(chance >= previous - 0.0001, "chance dropped going from a shyer to a bolder target")
		previous = chance
		boldness += step


func test_chance_never_exceeds_one_even_at_maximum_base_and_boldness():
	assert_almost_eq(physics.catch_chance(1.0, 1.0), 1.0, 0.0001)


func test_chance_never_goes_below_zero_even_at_minimum_base_and_boldness():
	assert_almost_eq(physics.catch_chance(0.0, 0.0), 0.0, 0.0001)


func test_boldness_outside_the_unit_range_is_still_clamped_into_a_legal_probability():
	# A trait can be nudged a hair outside [0, 1] by genetic crossover/mutation
	# elsewhere in the codebase (see FlyerPersonality.boldness_of's own
	# clamping) -- this formula must stay a legal probability regardless.
	assert_between(physics.catch_chance(0.9, 5.0), 0.0, 1.0)
	assert_between(physics.catch_chance(0.1, -5.0), 0.0, 1.0)


# --- the concept doc's own worked numbers, pinned ---------------------------
# (docs/concept/capture_dsl.md: "With butterfly_net's own base := 0.65, real
# odds land in [0.5, 0.8]" -- this is where that specific claim is checked.)

func test_at_base_0_65_a_middling_target_gets_0_65():
	assert_almost_eq(physics.catch_chance(0.65, FlyerPersonality.MIDDLING_BOLDNESS), 0.65, 0.0001)


func test_at_base_0_65_the_boldest_possible_target_gets_0_80():
	assert_almost_eq(physics.catch_chance(0.65, 1.0), 0.8, 0.0001)


func test_at_base_0_65_the_shyest_possible_target_gets_0_50():
	assert_almost_eq(physics.catch_chance(0.65, 0.0), 0.5, 0.0001)
