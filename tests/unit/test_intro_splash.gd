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


## Reported live, repeatedly, as "no intro plays" even after the third and
## fourth passes fixed every timing/gating issue upstream of this node
## actually being added to the tree: a real, non-headless, timestamped
## launch showed the intro's own Control (and its backdrop/display
## children) stuck at size=(0.0, 0.0) for the ENTIRE playback, despite
## set_anchors_preset(PRESET_FULL_RECT) and visible/is_visible_in_tree()
## both true throughout -- so nothing was ever actually drawn, on a node
## that was otherwise behaving perfectly. This is a documented Godot
## engine quirk, not a logic bug: a freshly created top-level Control with
## non-equal opposite anchors has its size silently overridden back to
## whatever the anchors alone resolve to -- here (0,0) -- in an internal
## layout pass that runs AFTER _ready() returns, stomping any direct same-
## frame `size = ...` assignment. Godot's own engine warning names the
## fix verbatim: "consider using set_deferred()". Needs a real awaited
## frame to observe (the direct assignment looks correct for one instant,
## immediately in _ready(), before that internal pass overrides it back
## down) -- confirmed red against the unfixed function first.
##
## The fix itself (set_deferred) unavoidably re-triggers the SAME engine
## warning it's named after -- Godot warns on a manual write to `size`
## while anchors are non-equal, regardless of whether the write is direct
## or deferred; the warning is about the technique, not about which one is
## correct. Only `self` actually surfaces it here: backdrop/display are
## children of an already-sized parent by the time their own deferred
## write lands, which resolves differently. Expected, not a regression, so
## consumed here rather than left to auto-fail the test as an "Unexpected
## Error".
func test_size_fills_the_viewport_once_ready_settles():
	var intro := _splash()
	await wait_process_frames(2)
	assert_engine_error_count(
		1, "the top-level Control's own set_deferred(\"size\", ...) write"
	)
	assert_eq(
		intro.size, intro.get_viewport_rect().size,
		"a zero-size intro draws nothing, even while fully visible/in-tree"
	)
