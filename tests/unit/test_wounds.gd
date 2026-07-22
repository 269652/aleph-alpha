extends GutTest

const Wounds = preload("res://src/gameplay/wounds.gd")

var wounds: Wounds


func before_each():
	wounds = Wounds.new()


func test_starts_unwounded_with_zero_bleed_damage():
	assert_eq(wounds.severity, 0.0)
	assert_eq(wounds.bleed_damage_per_second(), 0.0)


func test_add_wound_increases_severity():
	wounds.add_wound(5.0)
	assert_eq(wounds.severity, 5.0)


func test_add_wound_increases_bleed_damage_per_second():
	wounds.add_wound(5.0)
	assert_gt(wounds.bleed_damage_per_second(), 0.0)


func test_advance_returns_positive_bleed_damage_when_wounded():
	wounds.add_wound(10.0)
	var damage := wounds.advance(1.0)
	assert_gt(damage, 0.0)


func test_advance_returns_zero_when_severity_already_zero():
	var damage := wounds.advance(1.0)
	assert_eq(damage, 0.0)


func test_advance_reduces_severity_over_time():
	wounds.add_wound(10.0)
	wounds.advance(1.0)
	assert_lt(wounds.severity, 10.0)


func test_severity_never_goes_negative_from_repeated_advance():
	wounds.add_wound(0.1)
	for i in range(1000):
		wounds.advance(1.0)
	assert_gte(wounds.severity, 0.0)


func test_bandage_reduces_severity_by_more_than_single_advance():
	var natural_tracker: Wounds = Wounds.new()
	natural_tracker.add_wound(10.0)
	natural_tracker.advance(1.0)
	var natural_reduction: float = 10.0 - natural_tracker.severity

	wounds.add_wound(10.0)
	wounds.bandage(1.0)
	var bandage_reduction: float = 10.0 - wounds.severity

	assert_gt(bandage_reduction, natural_reduction)


func test_bandage_clamps_at_zero():
	wounds.add_wound(2.0)
	wounds.bandage(100.0)
	assert_eq(wounds.severity, 0.0)


func test_is_wounded_true_when_severity_positive():
	wounds.add_wound(1.0)
	assert_true(wounds.is_wounded())


func test_is_wounded_false_when_severity_zero():
	assert_false(wounds.is_wounded())


func test_repeated_advance_eventually_fully_heals():
	wounds.add_wound(5.0)
	for i in range(1000):
		wounds.advance(1.0)
	assert_eq(wounds.severity, 0.0)
	assert_false(wounds.is_wounded())
