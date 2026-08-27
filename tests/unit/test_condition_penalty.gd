extends GutTest

## What poor overall CONDITION costs you (see docs/concept/survival.md's
## "What poor condition costs you", ConditionPenalty). Pure and static, so
## there is nothing to set up per test.

const ConditionPenalty = preload("res://src/gameplay/condition_penalty.gd")


func test_full_condition_costs_no_speed():
	assert_eq(ConditionPenalty.speed_multiplier(1.0), 1.0, "a healthy player must move at exactly full speed")


func test_rock_bottom_condition_costs_the_worst_penalty():
	assert_almost_eq(ConditionPenalty.speed_multiplier(0.0), ConditionPenalty.WORST_SPEED_MULTIPLIER, 0.0001)


func test_the_penalty_worsens_monotonically_as_condition_falls():
	var previous := ConditionPenalty.speed_multiplier(1.0)
	for i in 20:
		var fitness := 1.0 - (i + 1) / 20.0
		var m := ConditionPenalty.speed_multiplier(fitness)
		assert_lt(m, previous, "every step down in condition should cost a little more speed")
		previous = m


func test_the_penalty_never_immobilises_the_player():
	# "Debuffs, not death": a neglected player is slow, never stuck.
	for i in 21:
		assert_gt(ConditionPenalty.speed_multiplier(i / 20.0), 0.0)


func test_out_of_range_condition_is_clamped():
	assert_eq(ConditionPenalty.speed_multiplier(5.0), 1.0)
	assert_almost_eq(ConditionPenalty.speed_multiplier(-5.0), ConditionPenalty.WORST_SPEED_MULTIPLIER, 0.0001)


## The no-eyeballed-constants pin: the worst-case magnitude is NOT a second
## invented number, it is the one this codebase already committed to for its
## one existing severe exposure debuff.
func test_the_worst_penalty_is_the_same_magnitude_as_the_freezing_slow():
	assert_eq(
		ConditionPenalty.WORST_SPEED_MULTIPLIER,
		Player.FREEZING_SPEED_PENALTY,
		"the condition penalty deliberately reuses the freezing slow's already-committed magnitude, not a second invented number"
	)
