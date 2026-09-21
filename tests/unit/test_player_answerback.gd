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


# -- the blow that lands ON the player ------------------------------------

## The one thing in this game that happens TO the player, and it answered
## with nothing: a bear could close, bite and take a fifth of the health bar
## in silence. Raised from the real `take_damage` path, not a hook.
func test_a_blow_landing_on_the_player_really_answers():
	var seen := _answers()
	player.take_damage(12.0)
	assert_eq(seen.size(), 1, "being bitten is an event")
	assert_eq(String(seen[0]["action"]), Answerback.HURT)
	assert_eq(String(seen[0]["flash"]), Answerback.FLASH_HIT)


## What floats is what it COST, after the block, the shield and the armour
## have had their say -- the number on the health bar, not the number the
## animal swung. A receipt that disagrees with the bar teaches the player to
## distrust both.
func test_the_float_is_what_the_blow_actually_took():
	var seen := _answers()
	var before: float = player.health
	player.take_damage(12.0)
	var really_lost := int(before - player.health)
	assert_gt(really_lost, 0, "precondition: the blow really landed")
	assert_eq(String(seen[0]["float_text"]), "-%d" % really_lost)


## Continuous harm is a condition, not a blow (docs/concept/feedback.md).
## A venom tick runs every frame; a receipt per frame is a buzz.
func test_a_tick_of_venom_answers_nothing():
	var seen := _answers()
	player.take_tick_damage(0.025)
	assert_eq(seen.size(), 0, "a poison is a condition, not an event")


## A blow that cost nothing at all is a non-event, the same rule every
## other float source in the table already follows.
func test_a_blow_on_an_already_dead_character_answers_nothing():
	player.take_damage(player.health + 10.0)
	var seen := _answers()
	player.take_damage(12.0)
	assert_eq(seen.size(), 0)


## Raised from `take_damage` itself and nowhere else -- not from a hook, and
## crucially not from `_suffer`, which the damage-over-time ticks share.
func test_the_real_damage_path_raises_it_rather_than_a_test_hook():
	var body := _function_body("take_damage")
	assert_false(body.is_empty(), "precondition: take_damage was found")
	assert_true(body.contains("answer("), "take_damage itself raises the answer")
	assert_true(body.contains("Answerback.HURT"), "and it raises the hurt row")
	assert_false(
		_function_body("_suffer").contains("Answerback.HURT"),
		"_suffer is the shared path every venom tick takes -- it must stay silent"
	)


func _function_body(name: String) -> String:
	var source := FileAccess.get_file_as_string("res://scenes/player.gd")
	var start := source.find("func %s(" % name)
	if start < 0:
		return ""
	var rest := source.substr(start)
	var next := rest.find("\nfunc ")
	return rest if next < 0 else rest.substr(0, next)


## And it says how much of the WHOLE bar that blow took, so the screen can
## answer a scratch differently from a near-killing blow rather than
## flashing one colour for both.
func test_the_answer_says_how_much_of_the_bar_the_blow_took():
	var seen := _answers()
	var before: float = player.health
	player.take_damage(player.max_health * 0.5)
	var really_lost: float = before - player.health
	assert_almost_eq(
		float(seen[0]["severity"]), really_lost / player.max_health, 0.0001
	)


func test_a_scratch_reports_a_smaller_share_than_a_maiming():
	var scratch := _answers()
	player.take_damage(1.0)
	var light: float = float(scratch[0]["severity"])
	var heavy_player = PlayerScene.instantiate()
	add_child(heavy_player)
	var heavy: Array = []
	heavy_player.answered.connect(func(feedback): heavy.append(feedback))
	heavy_player.take_damage(heavy_player.max_health * 0.6)
	assert_gt(float(heavy[0]["severity"]), light)
	heavy_player.queue_free()


# -- a refusal keeps its own clock ----------------------------------------

## Found by giving the dodge a key. `_answered_at` was keyed by action id
## alone, so a refusal and a success of the same verb shared one cooldown --
## and pressing dodge again the instant after a roll, which is the
## commonest press in the game, was muted by the roll that caused it.
##
## A press that says nothing teaches a player the key is broken, which is
## the exact failure docs/concept/feedback.md's third pillar exists to
## prevent: "a refusal is feedback too".
func test_a_refusal_is_not_muted_by_the_success_that_caused_it():
	var seen := _answers()
	player.answer("attack", {"damage": 4.0})
	player.answer("attack", {"failed": true, "reason": "Nothing in reach."})
	assert_eq(seen.size(), 2, "the no is not swallowed by the yes")
	assert_false(bool(seen[0]["failed"]))
	assert_true(bool(seen[1]["failed"]))


## And each half still rate-limits itself: holding a key against a wall
## hears one "no", not forty.
func test_two_refusals_inside_the_interval_still_answer_once():
	var seen := _answers()
	player.answer("attack", {"failed": true, "reason": "Nothing in reach."})
	player.answer("attack", {"failed": true, "reason": "Nothing in reach."})
	assert_eq(seen.size(), 1)
