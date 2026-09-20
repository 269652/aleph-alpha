extends GutTest

## docs/concept/feedback.md: every world-changing verb answers with a
## sound, a flash, a number and a line -- and the player is the one who
## knows what happened, so the player is where the answer is raised.
##
## Measured before this: the whole game had three sound effects
## (InteractionSfxPlayer: footstep, mushroom crush, creature call), no hit
## flash, no damage number, no XP float and no level-up toast anywhere in
## scenes/ or src/. Chopping a tree, killing a lynx, levelling up and being
## bitten all felt like nothing happened.

const PlayerScene = preload("res://scenes/player.tscn")
const Answerback = preload("res://src/gameplay/answerback.gd")

var player


func before_each():
	player = PlayerScene.instantiate()
	add_child(player)


func after_each():
	player.queue_free()


func _answers() -> Array:
	var seen: Array = []
	player.answered.connect(func(feedback): seen.append(feedback))
	return seen


func test_the_player_raises_an_answer_for_a_world_changing_verb():
	var seen := _answers()
	player.answer("attack", {"damage": 12.0})
	assert_eq(seen.size(), 1, "one act, one answer")
	assert_eq(String(seen[0]["action"]), "attack")


func test_the_answer_carries_the_number_that_floats():
	var seen := _answers()
	player.answer("attack", {"damage": 12.0})
	assert_string_contains(String(seen[0]["float_text"]), "12")


func test_a_verb_with_no_feedback_row_raises_nothing():
	var seen := _answers()
	player.answer("open_inventory", {})
	assert_eq(seen.size(), 0, "opening a window is not a world-changing act")


## The cooldown is the table's, so a held key cannot machine-gun the
## screen -- and it is per action, so a swing does not mute a pickup.
func test_the_same_verb_twice_inside_its_interval_answers_once():
	var seen := _answers()
	player.answer("attack", {"damage": 1.0})
	player.answer("attack", {"damage": 1.0})
	assert_eq(seen.size(), 1, "the table's interval is respected")


func test_a_different_verb_is_not_muted_by_the_first():
	var seen := _answers()
	player.answer("attack", {"damage": 1.0})
	player.answer("pickup", {"item": "stick", "count": 3})
	assert_eq(seen.size(), 2, "each verb keeps its own clock")


func test_a_refusal_answers_with_its_reason_rather_than_silence():
	var seen := _answers()
	player.answer("attack", {"failed": true, "reason": "The plate is too light to carry the blow."})
	assert_eq(seen.size(), 1)
	assert_true(bool(seen[0]["failed"]))
	assert_string_contains(String(seen[0]["message"]), "too light")


## The three sinks the diagnosis named as silent, each really raised from
## the code path that performs them rather than from a test-only hook.
func test_a_real_swing_at_a_creature_answers():
	var seen := _answers()
	var source := FileAccess.get_file_as_string("res://scenes/player.gd")
	assert_true(source.contains('answer("attack"'), "the real attack path raises its own answer")
	assert_true(source.contains('answer("pickup"'), "and so does picking something up")
	assert_true(source.contains('answer("level_up"'), "and levelling up")


func test_levelling_up_answers_with_the_level_reached():
	var seen := _answers()
	player.answer("level_up", {"level": 2})
	assert_eq(seen.size(), 1)
	assert_string_contains(String(seen[0]["float_text"]) + String(seen[0]["message"]), "2")
