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


# --- mesh physics: what a net holds (docs/concept/capture_dsl.md, 2026-09-05) ---
#
# Two comparisons over a subject's sorted body extents and a bag's real
# geometry. A body passes a square opening when its two smaller extents both
# do, and the larger of those two -- the MIDDLE extent -- is the one that
# binds. It has to go through the mouth before it turns, so the LARGEST
# extent is what the mouth is compared against.

const BodyDimensions = preload("res://src/gameplay/body_dimensions.gd")

const STANDARD_MESH_MM := 10.0
const STANDARD_MOUTH_MM := 300.0


func test_a_bee_slips_through_the_standard_mesh_and_a_monarch_does_not():
	assert_true(physics.slips_through(BodyDimensions.extents_mm("bee"), STANDARD_MESH_MM))
	assert_true(physics.slips_through(BodyDimensions.extents_mm("fly"), STANDARD_MESH_MM))
	assert_false(physics.slips_through(BodyDimensions.extents_mm("monarch"), STANDARD_MESH_MM))
	assert_false(physics.slips_through(BodyDimensions.extents_mm("sparrow"), STANDARD_MESH_MM))
	assert_false(physics.slips_through(BodyDimensions.extents_mm("goldfish"), STANDARD_MESH_MM))


func test_a_finer_mesh_holds_the_bee_and_a_finer_one_still_the_fly():
	# A 3 mm mesh holds the 6 mm-across bee; the 3 mm-across fly still slips a
	# 4 mm mesh and is held by a 2 mm one. (At exactly its own size a body is
	# HELD -- the rule is strict -- which is the boundary the concept doc's
	# "a 2 mm mesh holds the fly" rests on.)
	assert_false(physics.slips_through(BodyDimensions.extents_mm("bee"), 3.0))
	assert_true(physics.slips_through(BodyDimensions.extents_mm("fly"), 4.0))
	assert_false(physics.slips_through(BodyDimensions.extents_mm("fly"), 3.0))
	assert_false(physics.slips_through(BodyDimensions.extents_mm("fly"), 2.0))


func test_the_middle_extent_is_what_binds_at_a_mesh():
	# 20 x 12 x 4: a 4 mm depth alone would slip a 10 mm mesh, but the body
	# still has to get its 12 mm breadth through the same hole.
	assert_false(physics.slips_through([20.0, 12.0, 4.0], STANDARD_MESH_MM))
	assert_true(physics.slips_through([20.0, 9.0, 4.0], STANDARD_MESH_MM))


func test_small_fish_and_birds_fit_the_standard_mouth_and_big_fish_do_not():
	for species in ["goldfish", "bluegill", "sparrow", "robin", "monarch"]:
		assert_true(physics.fits_mouth(BodyDimensions.extents_mm(species), STANDARD_MOUTH_MM), species)
	for species in ["trout", "koi"]:
		assert_false(physics.fits_mouth(BodyDimensions.extents_mm(species), STANDARD_MOUTH_MM), species)


func test_a_forty_centimetre_landing_net_takes_the_trout():
	assert_true(physics.fits_mouth(BodyDimensions.extents_mm("trout"), 400.0))
	assert_false(physics.fits_mouth(BodyDimensions.extents_mm("koi"), 400.0))


func test_the_verdict_holds_exactly_what_neither_slips_nor_overflows():
	var held := physics.mesh_verdict(BodyDimensions.extents_mm("monarch"), STANDARD_MESH_MM, STANDARD_MOUTH_MM)
	assert_true(held["holds"])
	assert_eq(held["reason"], "")
	var slipped := physics.mesh_verdict(BodyDimensions.extents_mm("bee"), STANDARD_MESH_MM, STANDARD_MOUTH_MM)
	assert_false(slipped["holds"])
	assert_true(slipped["reason"].contains("slips through"), slipped["reason"])
	assert_true(slipped["reason"].contains("10"), "the reason names the mesh: %s" % slipped["reason"])
	var too_big := physics.mesh_verdict(BodyDimensions.extents_mm("koi"), STANDARD_MESH_MM, STANDARD_MOUTH_MM)
	assert_false(too_big["holds"])
	assert_true(too_big["reason"].contains("too big"), too_big["reason"])
	assert_true(too_big["reason"].contains("30"), "the reason names the mouth in cm: %s" % too_big["reason"])


func test_an_unmeasured_subject_is_refused_with_its_own_reason_rather_than_guessed():
	var verdict := physics.mesh_verdict([], STANDARD_MESH_MM, STANDARD_MOUTH_MM)
	assert_false(verdict["holds"])
	assert_true(verdict["reason"].contains("size"), verdict["reason"])
	assert_false(physics.slips_through([], STANDARD_MESH_MM))
	assert_false(physics.fits_mouth([], STANDARD_MOUTH_MM))


func test_a_finer_mesh_never_releases_what_a_coarser_one_held():
	for species in BodyDimensions.known_ids():
		var extents: Array = BodyDimensions.extents_mm(species)
		var previously_held := false
		var aperture := 40.0
		while aperture >= 0.5:
			var held: bool = not physics.slips_through(extents, aperture)
			if previously_held:
				assert_true(held, "%s slipped a %.1f mm mesh after a coarser one held it" % [species, aperture])
			previously_held = held
			aperture -= 0.5


func test_a_wider_mouth_never_refuses_what_a_narrower_one_took():
	for species in BodyDimensions.known_ids():
		var extents: Array = BodyDimensions.extents_mm(species)
		var previously_fit := false
		var mouth := 50.0
		while mouth <= 800.0:
			var fits: bool = physics.fits_mouth(extents, mouth)
			if previously_fit:
				assert_true(fits, "%s stopped fitting at a %.0f mm mouth" % [species, mouth])
			previously_fit = fits
			mouth += 25.0
