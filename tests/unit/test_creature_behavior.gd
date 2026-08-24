extends GutTest

const CreatureBehavior = preload("res://src/gameplay/creature_behavior.gd")

var behavior: CreatureBehavior


func before_each():
	behavior = CreatureBehavior.new()


## Builds a full decision context with sensible "nothing happening" defaults,
## overridden per-test.
func _context(overrides: Dictionary) -> Dictionary:
	var base := {
		"position": Vector2.ZERO,
		"temperament": "calm",
		"is_predator": false,
		"health_fraction": 1.0,
		"hungry": false,
		"thirsty": false,
		"threats": [],
		"prey": [],
		"food_direction": Vector2.ZERO,
		"water_direction": Vector2.ZERO,
	}
	for key in overrides:
		base[key] = overrides[key]
	return base


func test_wanders_when_nothing_is_happening():
	var decision := behavior.decide(_context({}))
	assert_eq(decision.intent, "wander")


func test_calm_creature_flees_a_nearby_threat():
	var decision := behavior.decide(_context({
		"position": Vector2.ZERO, "temperament": "calm", "threats": [Vector2(10, 0)]
	}))
	assert_eq(decision.intent, "flee")
	# Away from the threat -> negative x.
	assert_lt(decision.direction.x, 0.0)


func test_aggressive_strong_creature_attacks_a_nearby_threat():
	var decision := behavior.decide(_context({
		"position": Vector2.ZERO, "temperament": "aggressive", "health_fraction": 1.0,
		"threats": [Vector2(10, 0)]
	}))
	assert_eq(decision.intent, "attack")
	# Toward the threat -> positive x.
	assert_gt(decision.direction.x, 0.0)


func test_aggressive_but_weak_creature_flees_instead_of_attacking():
	var decision := behavior.decide(_context({
		"position": Vector2.ZERO, "temperament": "aggressive", "health_fraction": 0.1,
		"threats": [Vector2(10, 0)]
	}))
	assert_eq(decision.intent, "flee")


func test_flees_from_the_nearest_of_several_threats():
	var decision := behavior.decide(_context({
		"position": Vector2.ZERO, "temperament": "calm",
		"threats": [Vector2(100, 0), Vector2(0, 5)]
	}))
	# Nearest threat is below (positive y), so flee upward (negative y).
	assert_lt(decision.direction.y, 0.0)


func test_hungry_predator_hunts_the_nearest_prey():
	var decision := behavior.decide(_context({
		"position": Vector2.ZERO, "temperament": "aggressive", "is_predator": true,
		"hungry": true, "prey": [Vector2(10, 0), Vector2(50, 0)]
	}))
	assert_eq(decision.intent, "hunt")
	# Toward the nearer prey (positive x).
	assert_gt(decision.direction.x, 0.0)


func test_sated_predator_does_not_hunt():
	var decision := behavior.decide(_context({
		"temperament": "aggressive", "is_predator": true, "hungry": false,
		"prey": [Vector2(10, 0)]
	}))
	assert_eq(decision.intent, "wander")


func test_thirsty_creature_seeks_water():
	var decision := behavior.decide(_context({
		"thirsty": true, "water_direction": Vector2(1, 0)
	}))
	assert_eq(decision.intent, "seek_water")
	assert_almost_eq(decision.direction.x, 1.0, 0.001)


func test_hungry_herbivore_seeks_food():
	var decision := behavior.decide(_context({
		"hungry": true, "food_direction": Vector2(0, 1)
	}))
	assert_eq(decision.intent, "seek_food")
	assert_almost_eq(decision.direction.y, 1.0, 0.001)


func test_threat_takes_priority_over_hunger_and_thirst():
	var decision := behavior.decide(_context({
		"position": Vector2.ZERO, "temperament": "calm",
		"threats": [Vector2(10, 0)],
		"thirsty": true, "water_direction": Vector2(1, 0),
		"hungry": true, "food_direction": Vector2(1, 0),
	}))
	assert_eq(decision.intent, "flee")


func test_thirst_takes_priority_over_hunger():
	var decision := behavior.decide(_context({
		"thirsty": true, "water_direction": Vector2(1, 0),
		"hungry": true, "food_direction": Vector2(0, 1),
	}))
	assert_eq(decision.intent, "seek_water")


func test_hungry_predator_with_no_prey_in_range_searches_for_food():
	# A hungry predator that can't see prey should roam to find some, not idle.
	var decision := behavior.decide(_context({
		"temperament": "aggressive", "is_predator": true, "hungry": true, "prey": []
	}))
	assert_eq(decision.intent, "search_food")


func test_thirsty_creature_with_no_water_sensed_searches_for_water():
	var decision := behavior.decide(_context({
		"thirsty": true, "water_direction": Vector2.ZERO
	}))
	assert_eq(decision.intent, "search_water")


func test_hungry_herbivore_with_no_food_sensed_searches_for_food():
	var decision := behavior.decide(_context({
		"hungry": true, "food_direction": Vector2.ZERO
	}))
	assert_eq(decision.intent, "search_food")


func test_searching_leaves_direction_for_the_caller_to_fill_in():
	var decision := behavior.decide(_context({"thirsty": true, "water_direction": Vector2.ZERO}))
	assert_eq(decision.direction, Vector2.ZERO)


func test_flee_direction_is_nonzero_even_when_overlapping_the_threat():
	var decision := behavior.decide(_context({
		"position": Vector2(5, 5), "temperament": "calm", "threats": [Vector2(5, 5)]
	}))
	assert_eq(decision.intent, "flee")
	assert_gt(decision.direction.length(), 0.5)


func test_wander_returns_a_zero_direction_for_the_caller_to_fill_in():
	var decision := behavior.decide(_context({}))
	assert_eq(decision.direction, Vector2.ZERO)


# -- world boss aggro gating (docs/concept/worldbosses.md) -------------------
#
# A world boss should not attack a low-level player just for being nearby,
# the way an ordinary aggressive+strong creature does -- and it shouldn't
# flee one either, which a bare "ignore the aggressive rule" toggle would
# accidentally produce (falling through to the calm-creature branch). It
# should not perceive the player as a threat AT ALL until provoked by a
# real hit (see BossAggro/CreatureMarker.take_damage, which sets
# is_aggroed). Once aggroed, it behaves exactly like any other creature of
# its temperament -- no special "bosses never flee" rule invented here.

func test_unaggroed_world_boss_ignores_a_nearby_threat_and_wanders():
	var decision := behavior.decide(_context({
		"position": Vector2.ZERO, "temperament": "aggressive", "health_fraction": 1.0,
		"threats": [Vector2(10, 0)], "is_world_boss": true, "is_aggroed": false,
	}))
	assert_eq(decision.intent, "wander")


func test_unaggroed_world_boss_does_not_flee_a_threat_either():
	var decision := behavior.decide(_context({
		"position": Vector2.ZERO, "temperament": "calm", "health_fraction": 0.1,
		"threats": [Vector2(10, 0)], "is_world_boss": true, "is_aggroed": false,
	}))
	assert_ne(decision.intent, "flee")


func test_aggroed_world_boss_fights_like_an_ordinary_aggressive_creature():
	var decision := behavior.decide(_context({
		"position": Vector2.ZERO, "temperament": "aggressive", "health_fraction": 1.0,
		"threats": [Vector2(10, 0)], "is_world_boss": true, "is_aggroed": true,
	}))
	assert_eq(decision.intent, "attack")


func test_aggroed_world_boss_still_flees_if_weak_like_any_other_creature():
	var decision := behavior.decide(_context({
		"position": Vector2.ZERO, "temperament": "aggressive", "health_fraction": 0.1,
		"threats": [Vector2(10, 0)], "is_world_boss": true, "is_aggroed": true,
	}))
	assert_eq(decision.intent, "flee")


func test_unaggroed_world_boss_still_seeks_food_and_water_normally():
	# Ignoring the player as a threat must not make it ignore everything --
	# ordinary needs still drive it exactly like any other creature.
	var decision := behavior.decide(_context({
		"position": Vector2.ZERO, "temperament": "aggressive",
		"threats": [Vector2(10, 0)], "is_world_boss": true, "is_aggroed": false,
		"thirsty": true, "water_direction": Vector2(1, 0),
	}))
	assert_eq(decision.intent, "seek_water")
