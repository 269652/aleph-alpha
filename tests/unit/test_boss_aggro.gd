extends GutTest

## BossAggro (docs/concept/worldbosses.md): a world boss doesn't perceive a
## low-level player's weak hit as real damage -- a hit must clear a
## fraction of the boss's own max_health to count as provocation. Self-
## scaling (ties to data every boss already has via CreatureInfo.max_health)
## rather than a flat number or a new player-level-vs-creature-level
## comparison system, neither of which exist anywhere else in this codebase.

const BossAggro = preload("res://src/gameplay/boss_aggro.gd")

var aggro: BossAggro


func before_each():
	aggro = BossAggro.new()


func test_min_damage_to_aggro_scales_with_max_health():
	assert_almost_eq(
		aggro.min_damage_to_aggro(100.0), 100.0 * BossAggro.MIN_DAMAGE_FRACTION_OF_MAX_HEALTH, 0.001
	)
	assert_gt(aggro.min_damage_to_aggro(200.0), aggro.min_damage_to_aggro(100.0))


func test_deals_real_damage_false_below_threshold():
	var max_health := 100.0
	var below := aggro.min_damage_to_aggro(max_health) - 0.01
	assert_false(aggro.deals_real_damage(below, max_health))


func test_deals_real_damage_true_at_or_above_threshold():
	var max_health := 100.0
	var at_threshold := aggro.min_damage_to_aggro(max_health)
	assert_true(aggro.deals_real_damage(at_threshold, max_health))
	assert_true(aggro.deals_real_damage(at_threshold * 10.0, max_health))


## A hit that would count as "real" against a weak boss should not
## automatically count against a much tougher one -- the threshold is
## relative to THIS boss's own toughness, not a shared flat number.
func test_a_tougher_boss_needs_a_bigger_hit_to_count():
	var weak_boss_threshold := aggro.min_damage_to_aggro(50.0)
	assert_false(aggro.deals_real_damage(weak_boss_threshold, 500.0))
	assert_true(aggro.deals_real_damage(aggro.min_damage_to_aggro(500.0), 500.0))
