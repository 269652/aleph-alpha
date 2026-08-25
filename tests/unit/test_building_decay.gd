extends GutTest

## Withering: decay as a bounded, closed-form catch-up (see
## docs/concept/timber_construction.md#withering-decay-as-a-bounded-closed-
## form-catch-up, src/gameplay/building_decay.gd). Mirrors
## test_chunk_ecology_catchup.gd's own style for the shared closed-form
## shape this module reuses.

const BuildingDecay = preload("res://src/gameplay/building_decay.gd")
const MaterialProperties = preload("res://src/gameplay/material_properties.gd")

var decay: BuildingDecay
var materials: RefCounted


func before_each():
	decay = BuildingDecay.new()
	materials = MaterialProperties.new()


# -- the closed-form formula itself ------------------------------------------

func test_zero_elapsed_days_leaves_condition_unchanged():
	var result := decay.advance_condition(1.0, "wood", BuildingDecay.EXPOSURE_EXPOSED, 0.0)
	assert_almost_eq(result, 1.0, 0.0001)


func test_negative_elapsed_days_is_treated_as_zero():
	var zero := decay.advance_condition(0.8, "wood", BuildingDecay.EXPOSURE_EXPOSED, 0.0)
	var negative := decay.advance_condition(0.8, "wood", BuildingDecay.EXPOSURE_EXPOSED, -5.0)
	assert_almost_eq(negative, zero, 0.0001)


func test_condition_decays_monotonically_as_elapsed_days_increase():
	var earlier := decay.advance_condition(1.0, "wood", BuildingDecay.EXPOSURE_EXPOSED, 1.0)
	var later := decay.advance_condition(1.0, "wood", BuildingDecay.EXPOSURE_EXPOSED, 2.0)
	assert_lt(later, earlier, "more elapsed time should leave LESS condition remaining")
	assert_lt(earlier, 1.0, "any positive elapsed time should decay something")


func test_decay_never_overshoots_below_zero_even_for_a_huge_elapsed_jump():
	var result := decay.advance_condition(1.0, "wood", BuildingDecay.EXPOSURE_EXPOSED, 1000000.0)
	assert_gte(result, 0.0, "condition must never go negative")
	assert_almost_eq(result, 0.0, 0.0001, "a huge jump should converge to (effectively) zero")


func test_decay_never_exceeds_the_starting_condition():
	var result := decay.advance_condition(0.6, "wood", BuildingDecay.EXPOSURE_EXPOSED, 3.0)
	assert_lte(result, 0.6, "decay can only ever reduce condition, never raise it")


## A large elapsed-days jump is safe and deterministic in ONE call -- no
## need to iterate day by day, matching ChunkEcologyCatchup's own precedent.
func test_a_large_elapsed_days_jump_is_safe_and_deterministic_in_one_call():
	var a := decay.advance_condition(1.0, "wood", BuildingDecay.EXPOSURE_EXPOSED, 36500.0)
	var b := decay.advance_condition(1.0, "wood", BuildingDecay.EXPOSURE_EXPOSED, 36500.0)
	assert_eq(a, b, "the same huge jump must reproduce identically")
	assert_false(is_nan(a), "a huge exponent must not produce NaN")
	assert_false(is_inf(a), "a huge exponent must not produce infinity")


## Pins the EXACT closed-form shape the concept doc names:
## new_condition := condition * exp(-decay_rate * exposure_multiplier * elapsed_days)
func test_formula_matches_the_documented_closed_form():
	var condition := 0.7
	var days := 2.5
	var expected := condition * exp(
		-materials.property_value("iron", "decay_rate") * BuildingDecay.EXPOSURE_MULTIPLIER[BuildingDecay.EXPOSURE_EXPOSED] * days
	)
	var actual := decay.advance_condition(condition, "iron", BuildingDecay.EXPOSURE_EXPOSED, days)
	assert_almost_eq(actual, expected, 0.00001)


func test_advance_condition_is_deterministic():
	var a := decay.advance_condition(0.9, "stone", BuildingDecay.EXPOSURE_SHELTERED, 12.0)
	var b := decay.advance_condition(0.9, "stone", BuildingDecay.EXPOSURE_SHELTERED, 12.0)
	assert_eq(a, b)


# -- exposure modulation ------------------------------------------------------

func test_sheltered_decays_slower_than_exposed_for_the_same_material_and_time():
	var sheltered := decay.advance_condition(1.0, "wood", BuildingDecay.EXPOSURE_SHELTERED, 5.0)
	var exposed := decay.advance_condition(1.0, "wood", BuildingDecay.EXPOSURE_EXPOSED, 5.0)
	assert_gt(sheltered, exposed, "a roofed/maintained piece should retain more condition than an exposed one")


func test_unknown_exposure_string_falls_back_to_exposed():
	var unknown := decay.advance_condition(1.0, "wood", "made_up_exposure", 5.0)
	var exposed := decay.advance_condition(1.0, "wood", BuildingDecay.EXPOSURE_EXPOSED, 5.0)
	assert_almost_eq(unknown, exposed, 0.0001, "an unrecognized exposure must assume the worst case, not the best")


func test_exposure_multiplier_values_are_pinned():
	assert_almost_eq(BuildingDecay.EXPOSURE_MULTIPLIER[BuildingDecay.EXPOSURE_SHELTERED], 0.2, 0.0001)
	assert_almost_eq(BuildingDecay.EXPOSURE_MULTIPLIER[BuildingDecay.EXPOSURE_EXPOSED], 1.0, 0.0001)


func test_exposure_for_is_sheltered_when_roofed():
	assert_eq(decay.exposure_for(true, ""), BuildingDecay.EXPOSURE_SHELTERED)


func test_exposure_for_is_sheltered_when_owned_even_if_not_roofed():
	assert_eq(decay.exposure_for(false, "household_1"), BuildingDecay.EXPOSURE_SHELTERED)


func test_exposure_for_is_sheltered_when_both_roofed_and_owned():
	assert_eq(decay.exposure_for(true, "household_1"), BuildingDecay.EXPOSURE_SHELTERED)


func test_exposure_for_is_exposed_when_neither_roofed_nor_owned():
	assert_eq(decay.exposure_for(false, ""), BuildingDecay.EXPOSURE_EXPOSED)


# -- collapse threshold (see docs/concept/materials.md's "Topple / collapse" --
# -- verb; condition crossing this feeds the SAME collapse path a severed
# -- support does, not a parallel mechanism -- see EarthChunkManager wiring)

func test_ruined_condition_threshold_is_pinned():
	assert_almost_eq(BuildingDecay.RUINED_CONDITION_THRESHOLD, 0.05, 0.0001)


func test_is_ruined_is_false_above_the_threshold():
	assert_false(decay.is_ruined(BuildingDecay.RUINED_CONDITION_THRESHOLD + 0.01))


func test_is_ruined_is_true_at_or_below_the_threshold():
	assert_true(decay.is_ruined(BuildingDecay.RUINED_CONDITION_THRESHOLD))
	assert_true(decay.is_ruined(0.0))


## A fully exposed wood piece decays down to the ruined threshold well
## within the same order of magnitude of elapsed time this module's own
## EarthChunkManager wiring will actually use -- a real regression guard on
## the interaction between the formula and the threshold, not just each in
## isolation.
func test_a_fully_exposed_wood_piece_eventually_crosses_the_ruined_threshold():
	var condition := 1.0
	condition = decay.advance_condition(condition, "wood", BuildingDecay.EXPOSURE_EXPOSED, 10.0)
	assert_true(decay.is_ruined(condition), "10 days fully exposed should be more than enough to ruin plain wood")


# -- material grounding: timber vs. wood/stone --------------------------------

func test_timber_decays_slower_than_raw_wood_for_the_same_elapsed_time():
	var timber := decay.advance_condition(1.0, "timber", BuildingDecay.EXPOSURE_EXPOSED, 3.0)
	var wood := decay.advance_condition(1.0, "wood", BuildingDecay.EXPOSURE_EXPOSED, 3.0)
	assert_gt(timber, wood, "seasoned, squared timber should resist decay better than raw wood")


func test_stone_decays_far_slower_than_wood_for_the_same_elapsed_time():
	var stone := decay.advance_condition(1.0, "stone", BuildingDecay.EXPOSURE_EXPOSED, 3.0)
	var wood := decay.advance_condition(1.0, "wood", BuildingDecay.EXPOSURE_EXPOSED, 3.0)
	assert_gt(stone, wood, "stone endures; organics rot -- materials.md's own framing")
