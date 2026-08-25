extends GutTest

## ConstructionStartHysteresis: InstitutionFormation's own asymmetric
## hysteresis PATTERN (institution_formation.gd -- "cross a bar to start,
## drop WELL below it, not just below it, to abandon") applied to a
## different real number: a settlement's material stock measured against a
## blueprint's own requirement (docs/concept/timber_construction.md's
## "Settlement construction ledger" section). A fresh, small, test-pinned
## module -- deliberately NOT a reuse of InstitutionFormation itself
## (contract-specific), same shape only.

const ConstructionStartHysteresis = preload("res://src/emergence/construction_start_hysteresis.gd")


# -- should_start: crossing the bar starts -----------------------------------

func test_should_start_is_false_below_the_requirement():
	assert_false(ConstructionStartHysteresis.should_start(2.0, 3.0))


func test_should_start_is_true_at_the_requirement():
	assert_true(ConstructionStartHysteresis.should_start(3.0, 3.0))


func test_should_start_is_true_above_the_requirement():
	assert_true(ConstructionStartHysteresis.should_start(10.0, 3.0))


# -- should_abandon: only a real, well-below collapse abandons ---------------

## The abandon bar sits a real gap BELOW the start bar -- otherwise a stock
## count sitting exactly at the requirement would flicker the moment a
## single unit changes hands, the same reasoning
## InstitutionFormation.DISSOLUTION_THRESHOLD's own doc comment gives.
func test_the_abandon_fraction_is_a_real_gap_below_the_start_bar():
	assert_lt(ConstructionStartHysteresis.ABANDON_FRACTION, 1.0)
	assert_gt(ConstructionStartHysteresis.ABANDON_FRACTION, 0.0)


func test_should_abandon_is_false_right_at_the_requirement():
	assert_false(ConstructionStartHysteresis.should_abandon(3.0, 3.0))


## Dropping JUST below the requirement (still well above the abandon
## fraction) must NOT abandon -- this is the flicker case hysteresis exists
## to prevent.
func test_should_abandon_is_false_just_below_the_requirement():
	assert_false(ConstructionStartHysteresis.should_abandon(2.9, 3.0))


func test_should_abandon_is_false_right_at_the_abandon_fraction_boundary():
	var required := 10.0
	var at_boundary := required * ConstructionStartHysteresis.ABANDON_FRACTION
	assert_false(ConstructionStartHysteresis.should_abandon(at_boundary, required))


## Dropping WELL below the requirement -- past the abandon fraction -- does
## abandon.
func test_should_abandon_is_true_well_below_the_requirement():
	var required := 10.0
	var well_below := required * ConstructionStartHysteresis.ABANDON_FRACTION - 0.01
	assert_true(ConstructionStartHysteresis.should_abandon(well_below, required))


func test_should_abandon_is_true_with_zero_stock():
	assert_true(ConstructionStartHysteresis.should_abandon(0.0, 5.0))
