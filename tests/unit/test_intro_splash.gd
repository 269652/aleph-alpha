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
const IntroSplashSheet = preload("res://src/rendering/intro_splash_sheet.gd")


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
## point of the eighth/twelfth passes was "smaller than the seventh pass's
## already-shipped 880x620 box", not merely "some other integer-scaled size
## that happens to be bigger".
func test_display_size_is_smaller_than_the_prior_character_panel_sized_box():
	assert_lt(IntroSplash.DISPLAY_SIZE.x, 880.0)
	assert_lt(IntroSplash.DISPLAY_SIZE.y, 620.0)


## A twelfth pass (2026-09-09): reported live, twice in the same message --
## "not stabilized again" (the eleventh pass's fixed-crop-window fix DID
## hold; what regressed was THIS reference constant going stale the moment
## that fix shipped -- see the next test) and "still too big.. make it
## native size / resolution". DISPLAY_SCALE=1 pins the second, explicit ask
## directly: the on-screen box is exactly _NATIVE_FRAME_SIZE, no upscaling
## at all, so there is no scale factor left for a filter-driven artifact to
## ride on regardless of how carefully _NATIVE_FRAME_SIZE itself is kept in
## sync.
func test_display_scale_is_native_no_upscaling():
	assert_eq(
		IntroSplash.DISPLAY_SCALE, 1,
		"native size means no upscaling at all, not merely a smaller multiple"
	)


## The eleventh pass (see docs/concept/intro_splash.md) replaced
## IntroSplashSheet's own per-frame CONTENT-based crop with ONE fixed
## _FRAME_WIDTH/_FRAME_HEIGHT window -- 240x183, not the OLD 233x182
## "single most common size among the varying old crops" this file's own
## _NATIVE_FRAME_SIZE was still pinned to. That mismatch is the real root
## cause of "not stabilized again": DISPLAY_SIZE (computed from the STALE
## 233x182 reference) no longer shared the real, now-uniform texture's own
## aspect ratio, so STRETCH_KEEP_ASPECT_CENTERED silently reintroduced a
## non-integer effective scale (699/240 != 546/183) -- exactly the
## fractional-scale shimmer the eighth pass fixed, just from a different
## cause than that pass's own arbitrary-literal one. A direct equality
## check against IntroSplashSheet's own real constants, not a hand-copied
## literal, so a FUTURE re-measurement of the sheet can never silently
## desync this file's own reference again the same way.
func test_native_frame_size_matches_the_sheets_own_real_fixed_crop_size():
	assert_eq(
		IntroSplash._NATIVE_FRAME_SIZE,
		Vector2(IntroSplashSheet._FRAME_WIDTH, IntroSplashSheet._FRAME_HEIGHT),
		"the display's own reference size must track the sheet's real, current fixed-crop size, not a stale copy"
	)


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


## Flagged, not yet fixed, back when the fifth pass shipped: the skip-on-
## any-key handler is triggered by a lone Alt press -- very plausibly an
## incidental alt-tab during the long boot wait, not a deliberate "skip
## this" gesture from the player. Godot reports the modifier itself as an
## ordinary InputEventKey the instant it's pressed (keycode == KEY_ALT),
## indistinguishable at that point from a real skip key, since the window-
## manager combo it's actually part of (Alt+Tab) is consumed by Windows
## before a second, unrelated key event would ever reach this game at all --
## there is no "wait and see if another key follows" signal available here
## to tell the two apart after the fact. The same reasoning applies
## symmetrically to Ctrl/Shift/Meta: a lone modifier press, with nothing
## else, is essentially never how a player expresses "skip the intro" on
## its own -- it is how EVERY other OS-level combo (Ctrl+Tab, Win+D, ...) a
## long unattended wait might provoke begins.
func _modifier_key_press(code: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.pressed = true
	event.keycode = code
	return event


func test_a_lone_alt_press_does_not_skip_the_intro():
	var intro := _splash()
	intro._input(_modifier_key_press(KEY_ALT))
	assert_signal_not_emitted(
		intro, "finished",
		"a lone Alt press is very plausibly an incidental alt-tab during the long boot wait, not a deliberate skip"
	)


func test_a_lone_ctrl_shift_or_meta_press_does_not_skip_the_intro():
	var intro := _splash()
	for code in [KEY_CTRL, KEY_SHIFT, KEY_META]:
		intro._input(_modifier_key_press(code))
	assert_signal_not_emitted(
		intro, "finished",
		"pure modifier keys are how OS-level combos begin, not a deliberate skip gesture on their own"
	)


func test_a_real_key_still_skips_even_with_a_modifier_held():
	var intro := _splash()
	var event := _key_press()
	event.alt_pressed = true
	intro._input(event)
	assert_signal_emitted(
		intro, "finished",
		"a real key with a modifier held (e.g. Alt+Space) is still a genuine keypress, not a lone modifier"
	)
