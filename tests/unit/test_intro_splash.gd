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


## Reported live: "make it smaller, about the size of the new character
## panel... otherwise it looks pixelated and wobbly" -- the root Control
## (backdrop included) stays full-viewport (see the test above), but the
## actual animated TextureRect is deliberately NOT stretched across all of
## it any more, so a much smaller upscale factor reaches the screen.
## Revised (2026-09-09, "An eighth pass"): the box itself shrank again, to
## a genuine pixel-perfect integer multiple of the sheet's own native frame
## size rather than an arbitrary literal -- see IntroSplash.DISPLAY_SIZE's
## own doc comment. This test reads the live constant rather than a
## hardcoded literal, so it keeps proving "centered, not cropped/stretched
## across the viewport" regardless of which pass last changed the exact
## size -- test_display_size_is_a_clean_integer_multiple_of_the_native_
## frame_size and test_display_is_pixel_perfect below cover the size/
## filtering specifics this test deliberately doesn't.
func test_display_is_sized_and_centered_to_a_pixel_perfect_box():
	var intro := _splash()
	await wait_process_frames(2)
	# Same pre-existing, expected warning test_size_fills_the_viewport_
	# once_ready_settles already documents and consumes -- `self`'s own
	# set_deferred("size", ...) write (unrelated to _display, untouched by
	# this pass) fires it on every settle, not just that one test.
	assert_engine_error_count(
		1, "the top-level Control's own set_deferred(\"size\", ...) write"
	)
	var expected_position := (intro.get_viewport_rect().size - IntroSplash.DISPLAY_SIZE) / 2.0
	assert_eq(
		intro.display_rect().size, IntroSplash.DISPLAY_SIZE,
		"the animation itself should be shrunk, not stretched across the full viewport"
	)
	assert_eq(
		intro.display_rect().position, expected_position,
		"a shrunk display should stay centered, not pinned to a corner"
	)


## Reported live, again, on top of the seventh pass's already-shipped fix:
## "the intro is still full window... it should be much smaller." The
## seventh pass's own 880x620 (matching MainMenu.PANEL_SIZE) was smaller
## than full-screen but still an ARBITRARY target size -- the same
## STRETCH_KEEP_ASPECT_COVERED just covering a smaller box, not a clean
## integer scale of the sheet's own native resolution. Pins the actual
## fix: DISPLAY_SIZE must be exactly the sheet's own measured native frame
## size times a whole number, the same "roundi/whole-number scale of a
## real source size" discipline MainMenu.STANDARD_PORTRAIT_DISPLAY_SIZE
## already established (see test_standard_portrait_display_size_is_a_
## whole_number_scale_of_the_source_texture in test_main_menu.gd).
func test_display_size_is_a_clean_integer_multiple_of_the_native_frame_size():
	assert_eq(
		IntroSplash.DISPLAY_SIZE, IntroSplash._NATIVE_FRAME_SIZE * IntroSplash.DISPLAY_SCALE,
		"DISPLAY_SIZE must be derived from the native frame size times a whole number, not a separately hand-picked literal"
	)


## A regression guard, not just a restatement of the constant: the whole
## point of this pass was "smaller than the seventh pass's already-shipped
## 880x620 box", not merely "some other integer-scaled size that happens to
## be bigger".
func test_display_size_is_smaller_than_the_prior_character_panel_sized_box():
	assert_lt(IntroSplash.DISPLAY_SIZE.x, 880.0)
	assert_lt(IntroSplash.DISPLAY_SIZE.y, 620.0)


## The other half of "pixelated and wobbly", not fixed by shrinking the box
## alone: Godot's default TextureRect filter is smooth/linear, which blurs
## and shimmers hard pixel-art edges at any non-1:1 scale -- exactly the
## "wobbly" look reported, independent of how big or small the box is. This
## game's other generated/sliced pixel art (e.g. MainMenu._standard_
## portrait) already renders via TEXTURE_FILTER_NEAREST at a whole-number
## scale for exactly this reason; the intro never did until now.
func test_display_is_pixel_perfect():
	var intro := _splash()
	assert_true(
		intro.display_is_pixel_perfect(),
		"the animation should render with NEAREST filtering at a non-cropping integer scale"
	)
