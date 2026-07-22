extends GutTest

const Dodge = preload("res://src/gameplay/dodge.gd")

var dodge: Dodge


func before_each():
	dodge = Dodge.new()


func test_can_dodge_true_when_cooldown_is_zero():
	assert_true(dodge.can_dodge(0.0))


func test_can_dodge_true_when_cooldown_is_negative():
	assert_true(dodge.can_dodge(-1.0))


func test_can_dodge_false_when_cooldown_is_positive():
	assert_false(dodge.can_dodge(0.5))


func test_start_dodge_returns_expected_fixed_durations():
	var result := dodge.start_dodge()
	assert_eq(result.invincible_time_remaining, Dodge.INVINCIBLE_DURATION)
	assert_eq(result.cooldown_remaining, Dodge.COOLDOWN_DURATION)


func test_advance_decrements_both_values_by_delta():
	var result := dodge.advance(0.25, 1.5, 0.1)
	assert_almost_eq(result.invincible_time_remaining, 0.15, 0.001)
	assert_almost_eq(result.cooldown_remaining, 1.4, 0.001)


func test_advance_clamps_invincible_time_at_zero():
	var result := dodge.advance(0.05, 1.5, 0.1)
	assert_eq(result.invincible_time_remaining, 0.0)


func test_advance_clamps_cooldown_at_zero():
	var result := dodge.advance(0.0, 0.05, 0.1)
	assert_eq(result.cooldown_remaining, 0.0)


func test_is_invincible_true_during_invincible_window():
	assert_true(dodge.is_invincible(0.1))


func test_is_invincible_false_once_it_reaches_zero():
	assert_false(dodge.is_invincible(0.0))


func test_full_dodge_and_advance_cycle_ends_with_invincible_false_and_cooldown_zero():
	var state := dodge.start_dodge()
	var invincible_time_remaining: float = state.invincible_time_remaining
	var cooldown_remaining: float = state.cooldown_remaining
	var steps := 0
	while cooldown_remaining > 0.0 and steps < 1000:
		var result := dodge.advance(invincible_time_remaining, cooldown_remaining, 0.1)
		invincible_time_remaining = result.invincible_time_remaining
		cooldown_remaining = result.cooldown_remaining
		steps += 1
	assert_false(dodge.is_invincible(invincible_time_remaining))
	assert_eq(cooldown_remaining, 0.0)
