extends GutTest

## Pure lookup for the "timed status" spell atoms (docs/concept/
## spell_runtime.md) -- generalizes VenomModel's "what does N stacks of this
## debuff actually do" role across every status atom, since DebuffStack
## itself is deliberately agnostic about that. Mirrors test_venom_model.gd's
## own shape.

const SpellStatusEffects = preload("res://src/gameplay/spell_status_effects.gd")

var effects := SpellStatusEffects.new()


func test_ignite_is_a_damage_over_time_status():
	assert_true(effects.is_dot(SpellStatusEffects.IGNITE))


func test_blight_is_a_damage_over_time_status():
	assert_true(effects.is_dot(SpellStatusEffects.BLIGHT))


func test_slow_is_not_a_damage_over_time_status():
	assert_false(effects.is_dot(SpellStatusEffects.SLOW))


func test_ignite_damage_scales_with_stacks():
	var one := effects.damage_per_second(SpellStatusEffects.IGNITE, 1)
	var two := effects.damage_per_second(SpellStatusEffects.IGNITE, 2)
	assert_gt(one, 0.0)
	assert_almost_eq(two, one * 2.0, 0.001)


func test_damage_per_second_clamps_to_max_stacks():
	var at_max := effects.damage_per_second(SpellStatusEffects.IGNITE, SpellStatusEffects.MAX_STACKS)
	var beyond_max := effects.damage_per_second(SpellStatusEffects.IGNITE, SpellStatusEffects.MAX_STACKS + 5)
	assert_almost_eq(at_max, beyond_max, 0.001)


func test_damage_per_second_is_zero_for_a_non_dot_status():
	assert_almost_eq(effects.damage_per_second(SpellStatusEffects.SLOW, 3), 0.0, 0.001)


func test_ignite_and_blight_scale_differently():
	# Different atoms in the catalog (different tier/base_cost) -- their
	# real damage shouldn't coincidentally match, or the two atoms would be
	# mechanically indistinguishable, not just visually.
	assert_ne(
		effects.damage_per_second(SpellStatusEffects.IGNITE, 1),
		effects.damage_per_second(SpellStatusEffects.BLIGHT, 1)
	)


func test_slow_speed_multiplier_meaningfully_slows_movement():
	assert_lt(SpellStatusEffects.SLOW_SPEED_MULTIPLIER, 1.0)
	assert_gt(SpellStatusEffects.SLOW_SPEED_MULTIPLIER, 0.0)


## summon_wisp is tracked the same generic way as every other timed-status
## atom -- see docs/concept/spell_runtime.md's honest scope note: a real,
## queryable status, not yet a visual companion node.
func test_summon_wisp_is_not_a_damage_over_time_status():
	assert_false(effects.is_dot(SpellStatusEffects.SUMMON_WISP))
