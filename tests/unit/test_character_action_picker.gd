extends GutTest

const CharacterActionPicker = preload("res://src/rendering/character_action_picker.gd")


func test_pick_next_returns_a_known_action():
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var result := CharacterActionPicker.pick_next(rng)
	assert_true(CharacterActionPicker.WEIGHTS.has(result.action))


func test_pick_next_returns_a_positive_duration():
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	for i in 30:
		var result := CharacterActionPicker.pick_next(rng)
		assert_gt(result.duration, 0.0)


func test_pick_next_is_deterministic_for_the_same_rng_seed():
	var rng_a := RandomNumberGenerator.new()
	rng_a.seed = 42
	var rng_b := RandomNumberGenerator.new()
	rng_b.seed = 42
	var a := CharacterActionPicker.pick_next(rng_a)
	var b := CharacterActionPicker.pick_next(rng_b)
	assert_eq(a.action, b.action)
	assert_eq(a.duration, b.duration)


## WANDER is the default ambient state -- weighted heaviest so a long
## enough sample skews toward it, not an even 1-in-4 split.
func test_wander_is_picked_more_often_than_any_single_other_action():
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var counts := {}
	for action in CharacterActionPicker.WEIGHTS:
		counts[action] = 0
	for i in 400:
		var result := CharacterActionPicker.pick_next(rng)
		counts[result.action] += 1
	for action in CharacterActionPicker.WEIGHTS:
		if action != CharacterActionPicker.Action.WANDER:
			assert_gt(
				counts[CharacterActionPicker.Action.WANDER], counts[action],
				"WANDER (%d) should beat action %d (%d)" % [counts[CharacterActionPicker.Action.WANDER], action, counts[action]]
			)


## A swing has its own fixed real animation length (Player.SWING_DURATION)
## regardless of how long the ambient state machine holds the action for --
## not an arbitrary range like the other three.
func test_swing_duration_matches_the_real_attack_swing_length():
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for i in 100:
		var result := CharacterActionPicker.pick_next(rng)
		if result.action == CharacterActionPicker.Action.SWING:
			assert_almost_eq(result.duration, CharacterActionPicker.SWING_DURATION, 0.001)
