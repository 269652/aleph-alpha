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


# -- fitness -> how fast your wind comes back ------------------------------
#
# survival.md's "debuffs, not death" pillar names four effect kinds that
# poor condition should have, and listed stamina regen as unbuilt -- unbuilt
# precisely because nothing in the game spent stamina, so a slower refill
# would have been invisible. A villager hunter who runs (docs/concept/npc.md,
# "A hunter runs, and the run is paid for in stamina") is that missing sink,
# so this second curve is now real and visible.


func test_full_condition_gets_your_wind_back_at_the_full_rate():
	assert_eq(
		ConditionPenalty.stamina_regen_multiplier(1.0), 1.0,
		"a well-fed body recovers at exactly the meter's own rate"
	)


func test_neglect_slows_recovery_without_ever_stopping_it():
	# Same "debuffs, not death" rule the speed curve above follows: a
	# starving hunter takes far longer to get their wind back, but they do
	# get it back -- a zero here would strand them at a walk forever.
	for i in 21:
		assert_gt(ConditionPenalty.stamina_regen_multiplier(i / 20.0), 0.0)


func test_recovery_worsens_monotonically_as_condition_falls():
	var previous := ConditionPenalty.stamina_regen_multiplier(1.0)
	for i in 20:
		var fitness := 1.0 - (i + 1) / 20.0
		var m := ConditionPenalty.stamina_regen_multiplier(fitness)
		assert_lt(m, previous, "every step down in condition should cost a little more recovery")
		previous = m


## Pinned, not eyeballed: at rock bottom, getting your wind back takes FOUR
## TIMES as long. Deliberately harsher than the movement penalty's own worst
## case -- being slow and being unable to recover are different orders of
## consequence, and unlike speed this one can never strand anybody, since a
## villager who cannot run simply walks.
func test_rock_bottom_condition_quadruples_how_long_recovery_takes():
	assert_almost_eq(ConditionPenalty.stamina_regen_multiplier(0.0), 0.25, 0.0001)
	assert_almost_eq(
		ConditionPenalty.stamina_regen_multiplier(0.0), ConditionPenalty.WORST_STAMINA_REGEN_MULTIPLIER, 0.0001
	)
	assert_lt(
		ConditionPenalty.WORST_STAMINA_REGEN_MULTIPLIER, ConditionPenalty.WORST_SPEED_MULTIPLIER,
		"recovery is allowed to bite harder than speed: it never immobilises anyone"
	)


func test_out_of_range_condition_is_clamped_for_recovery_too():
	assert_eq(ConditionPenalty.stamina_regen_multiplier(5.0), 1.0)
	assert_almost_eq(
		ConditionPenalty.stamina_regen_multiplier(-5.0), ConditionPenalty.WORST_STAMINA_REGEN_MULTIPLIER, 0.0001
	)
