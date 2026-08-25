extends GutTest

## Player's momentary actions must survive a tap that lands entirely between
## two physics polls.
##
## Reported live during a playtest: at 6-8 FPS a 140ms tap was silently
## swallowed. That is a real INPUT bug, not just a symptom of low frame rate.
## Player reads every momentary action by polling `Input.is_action_pressed`
## inside `_physics_process`, and Godot delivers accumulated input once per
## rendered frame -- so when the press AND the release arrive in the same
## flush, the polled level is never true on any tick that observes it. The
## press is not delayed, it is erased, and no amount of making the game
## faster closes that window.
##
## The EVENTS are still delivered, though. So Player latches the rising edge
## in `_unhandled_input` (see InputLatch) and the physics step consumes it.
## These tests drive the two halves independently -- events with no polled
## level at all (the bug), and a polled level with no events (the old path,
## which every other player test uses and which must keep working).

const PlayerScene = preload("res://scenes/player.tscn")
const Keybindings = preload("res://src/gameplay/keybindings.gd")

## The rising-edge ("tap") actions. Each one is a single discrete thing that
## happens once per press, so losing the press loses the whole action.
const MOMENTARY_ACTIONS := ["attack", "build", "destroy", "kick", "stash", "talk", "trade"]

## Deliberately NOT latched: these are read as a LEVEL, not an edge --
## `block` is "am I holding guard up right now", and `pickup`/`fish`/`lasso`/
## `mount` drive press-and-hold cycles (the charge meter, the cast/reel, the
## rope) that genuinely need to know the key is still down. Latching them
## would turn a hold into a single tap.
const CONTINUOUS_ACTIONS := ["block", "pickup", "fish", "lasso", "mount"]

var player: Player
var _keybindings := Keybindings.new()


func before_each():
	# There is no static [input] section in project.godot -- World._apply_
	# keybindings registers the InputMap at runtime and Player._bind_wasd_
	# movement covers most of it. This test instantiates Player without a
	# World, so it registers whatever is still missing itself, exactly the
	# way test_player_kick.gd already does for "kick".
	for action in MOMENTARY_ACTIONS + CONTINUOUS_ACTIONS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		if InputMap.action_get_events(action).is_empty():
			var default_event := InputEventKey.new()
			default_event.physical_keycode = _keybindings.default_keycode_for(action)
			InputMap.action_add_event(action, default_event)

	player = PlayerScene.instantiate()
	# Player._is_local_player_instance keys off this name matching the tree's
	# own multiplayer id (see test_player.gd's own note) -- local input
	# reading, and therefore latching, only happens for that instance.
	player.name = str(multiplayer.get_unique_id())
	add_child(player)
	# Deliberately no setup(): _talk_step handles a null chunk manager (it
	# reports "no one nearby"), which is all these tests need and keeps the
	# fixture off the 25-chunk world-generation path.


func after_each():
	for action in MOMENTARY_ACTIONS + CONTINUOUS_ACTIONS:
		Input.action_release(action)
	ConsoleFocus.is_open = false
	remove_child(player)
	player.free()


## A real key event for `action`, built by copying whatever the InputMap
## actually has bound, so the event genuinely matches the action rather than
## matching a keycode this test guessed.
func _key_event(action: String, pressed: bool) -> InputEventKey:
	var bound := InputMap.action_get_events(action)
	assert_false(bound.is_empty(), "%s must be bound for this test to mean anything" % action)
	var event: InputEventKey = bound[0].duplicate()
	event.pressed = pressed
	return event


## The whole bug in one helper: the press and the release are delivered
## together, and NOTHING is ever polled as held.
func _tap_between_polls(action: String) -> void:
	player._unhandled_input(_key_event(action, true))
	player._unhandled_input(_key_event(action, false))


func _clear_talk_message() -> void:
	player._talk_result_message = ""
	player._talk_result_timer = 0.0
	player.talk_message = ""


# -- the bug ------------------------------------------------------------------

func test_a_tap_that_lands_entirely_between_two_polls_still_talks():
	_tap_between_polls("talk")
	assert_false(
		Input.is_action_pressed("talk"),
		"precondition: the physics step's poll can never see this tap -- that IS the bug"
	)

	player._talk_step(0.0)

	assert_eq(
		player.talk_message,
		"No one to talk to nearby.",
		"a 140ms tap at 6-8 FPS must still act, not be erased"
	)


func test_a_latched_tap_fires_exactly_once():
	_tap_between_polls("talk")
	player._talk_step(0.0)
	assert_eq(player.talk_message, "No one to talk to nearby.", "the tap fired")

	_clear_talk_message()
	player._talk_step(0.0)

	assert_eq(player.talk_message, "", "the same tap must not fire again on the next step")


func test_every_momentary_action_latches_from_its_key_event():
	for action in MOMENTARY_ACTIONS:
		player._unhandled_input(_key_event(action, true))
		assert_true(player._input_latch.is_latched(action), "%s must latch its press" % action)


func test_continuous_actions_are_deliberately_not_latched():
	for action in CONTINUOUS_ACTIONS:
		player._unhandled_input(_key_event(action, true))
		assert_false(
			player._input_latch.is_latched(action),
			"%s is a held LEVEL, not a tap -- latching it would turn a hold into one press" % action
		)


## Guard (green before and after the wiring, by virtue of using
## InputEvent.is_action_pressed, whose `allow_echo` defaults to false): the
## OS repeats a held key as ECHO events. Latching those would turn "hold B"
## into terraforming a tile every few milliseconds -- an auto-repeat the
## polled rising-edge read never had.
func test_the_os_key_repeat_of_a_held_key_does_not_latch_again():
	var echo := _key_event("build", true)
	echo.echo = true

	player._unhandled_input(echo)

	assert_false(player._input_latch.is_latched("build"), "key repeat must not re-fire the action")


## Guard: only the rising edge latches. A release is the END of an action,
## and latching it would fire the action a second time on letting go.
func test_a_release_event_does_not_latch():
	player._unhandled_input(_key_event("build", false))

	assert_false(player._input_latch.is_latched("build"), "releasing a key is not a press")


func test_nothing_is_latched_while_the_console_holds_focus():
	ConsoleFocus.is_open = true

	player._unhandled_input(_key_event("talk", true))

	assert_false(
		player._input_latch.is_latched("talk"),
		"typing into the dev console must not act in the world"
	)


# -- guards: the existing polled path must keep working exactly as before -----

## Green before AND after the fix. Every other player test drives input this
## way (Input.action_press + a direct step call), so this is the regression
## net for the whole file family.
func test_a_polled_held_key_still_fires_on_its_rising_edge():
	Input.action_press("talk")

	player._talk_step(0.0)

	assert_eq(player.talk_message, "No one to talk to nearby.", "the polled rising edge still fires")


func test_holding_the_key_across_two_steps_fires_only_once():
	Input.action_press("talk")
	player._talk_step(0.0)
	assert_eq(player.talk_message, "No one to talk to nearby.", "the press fired")

	_clear_talk_message()
	player._talk_step(0.0)  # still held, no new press

	assert_eq(player.talk_message, "", "holding the key must not repeat the action")


## The two halves must not double-count each other: a real press delivers an
## event AND is still held at the next poll, and that is still ONE action.
func test_a_real_press_seen_by_both_the_event_and_the_poll_fires_only_once():
	player._unhandled_input(_key_event("talk", true))
	Input.action_press("talk")  # the same press, still held when the step polls

	player._talk_step(0.0)
	assert_eq(player.talk_message, "No one to talk to nearby.", "the press fired")

	_clear_talk_message()
	player._talk_step(0.0)

	assert_eq(player.talk_message, "", "one press, one action -- the latch must not fire a second time")


# -- the latch must not BANK a press it never got to act on -------------------

## The latch remembers a press until something consumes it -- that is the
## whole point of it -- but "remembers forever" is a bug the polled read
## could never have had. If the dev console takes focus in the window
## between the key event and the physics tick, the world never acts on that
## press, and it must be DROPPED rather than fired whenever focus comes back.
## Otherwise a T typed a frame before opening the console greets an NPC
## thirty seconds later, when the console closes.
func test_a_press_the_console_stole_focus_from_is_dropped_not_banked():
	player._unhandled_input(_key_event("talk", true))
	ConsoleFocus.is_open = true

	player._talk_step(0.0)
	assert_eq(player.talk_message, "", "the console has focus -- the press must not act now")

	ConsoleFocus.is_open = false
	player._talk_step(0.0)

	assert_eq(player.talk_message, "", "and it must not act later either -- the press is gone")


## Guard for the above: dropping stale presses must not cost a press made
## with the world properly in focus, which is the ordinary case.
func test_a_press_made_with_the_world_in_focus_still_fires_on_the_next_step():
	_tap_between_polls("talk")

	player._talk_step(0.0)

	assert_eq(player.talk_message, "No one to talk to nearby.", "the ordinary tap still fires")


## The same rule on the networked-client half. `_local_momentary_input` is
## what a non-authority client forwards to the server each tick, and it read
## Input.is_action_pressed with no focus check at all -- so a client typing
## "b" into the dev console kept telling the server to build.
func test_the_clients_forwarded_momentary_input_is_suppressed_by_console_focus():
	Input.action_press("build")
	ConsoleFocus.is_open = true

	assert_false(
		player._local_momentary_input("build"),
		"typing into the dev console must not be forwarded to the server as a build"
	)


## Guard: with the world in focus the forwarded read still reports a tap the
## poll alone would have missed, exactly once.
func test_the_clients_forwarded_momentary_input_still_reports_a_latched_tap():
	_tap_between_polls("build")

	assert_true(player._local_momentary_input("build"), "the tap is forwarded")
	assert_false(player._local_momentary_input("build"), "one press, one forwarded report")


# -- attack: the same rule, on the one action nothing else covers -------------

## `_attack_step` has no direct coverage anywhere else in tests/unit, and it
## is the action the low-frame-rate report was actually about (spamming the
## swing key and watching swings vanish). Driven here through the same
## between-polls tap: the observable is the cooldown, which only
## `_perform_attack` sets.
func test_a_tap_that_lands_entirely_between_two_polls_still_swings():
	assert_eq(player._attack_cooldown_remaining, 0.0, "precondition: not already on cooldown")
	_tap_between_polls("attack")
	assert_false(
		Input.is_action_pressed("attack"),
		"precondition: the physics step's poll can never see this tap -- that IS the bug"
	)

	player._attack_step(0.0)

	assert_almost_eq(
		player._attack_cooldown_remaining,
		player.ATTACK_COOLDOWN,
		0.0001,
		"a tap shorter than one rendered frame must still swing, not be erased"
	)


## Guard: one tap is one swing. The latch must not let the swing repeat on
## the following ticks once the cooldown has run out.
func test_a_latched_tap_swings_exactly_once():
	_tap_between_polls("attack")
	player._attack_step(0.0)
	assert_almost_eq(player._attack_cooldown_remaining, player.ATTACK_COOLDOWN, 0.0001, "the tap swung")

	player._attack_step(player.ATTACK_COOLDOWN)

	assert_eq(
		player._attack_cooldown_remaining,
		0.0,
		"the cooldown ran out and no second swing started it again"
	)
