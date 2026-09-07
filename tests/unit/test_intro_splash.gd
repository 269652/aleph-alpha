extends GutTest

## Thin engine glue for the boot intro (see docs/concept/intro_splash.md,
## IntroSplashSequencer, IntroSplashSheet). All real timing/slicing logic
## is covered directly in those pure classes' own test files -- this only
## proves the Node-level wiring around them: `finished` fires once the
## sequence plays out OR the player skips it, and never fires twice.
##
## Drives time the same way this codebase's other _process-driven markers
## already do (see test_decomposer_marker.gd): calling _process(delta)
## directly, not a real per-frame engine loop.

const IntroSplash = preload("res://scenes/intro_splash.gd")
const IntroSplashSequencer = preload("res://src/rendering/intro_splash_sequencer.gd")


func _splash() -> IntroSplash:
	var intro := IntroSplash.new()
	add_child_autofree(intro)
	watch_signals(intro)
	return intro


func _key_press() -> InputEventKey:
	var event := InputEventKey.new()
	event.pressed = true
	event.keycode = KEY_SPACE
	return event


func test_does_not_finish_before_the_full_duration_or_any_input():
	var intro := _splash()
	intro._process(IntroSplashSequencer.duration_seconds() - 0.1)
	assert_signal_not_emitted(intro, "finished")


func test_finishes_once_the_full_duration_elapses():
	var intro := _splash()
	intro._process(IntroSplashSequencer.duration_seconds() + 0.1)
	assert_signal_emitted(intro, "finished")


func test_a_key_press_skips_straight_to_finished():
	var intro := _splash()
	intro._process(0.1)  # barely started
	intro._input(_key_press())
	assert_signal_emitted(intro, "finished")


func test_a_released_key_does_not_skip():
	var intro := _splash()
	var event := InputEventKey.new()
	event.pressed = false
	intro._input(event)
	assert_signal_not_emitted(intro, "finished")


func test_finished_never_fires_twice():
	var intro := _splash()
	intro._input(_key_press())
	intro._input(_key_press())
	intro._process(IntroSplashSequencer.duration_seconds() + 0.1)
	assert_signal_emit_count(intro, "finished", 1)
