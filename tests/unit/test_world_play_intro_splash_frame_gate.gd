extends GutTest

## World._play_intro_splash() -- real, run-for-real regression coverage (see
## docs/concept/intro_splash.md's "A fourth pass"). This is deliberately NOT
## the source-text technique test_world_intro_splash_after_load_fanout.gd
## uses (that technique exists there because standing up a real World means
## paying its full heavy _ready() -- license gate, EarthChunkManager, every
## shader layer -- none of which _play_intro_splash() itself actually
## touches). Here a bare World.new() is never added to any tree (so that
## heavy _ready() never runs at all), and _ui is wired directly to a real
## CanvasLayer that IS parented into this test's own live tree -- the ONLY
## field _play_intro_splash() reads. That lets this file call the real,
## unmodified _play_intro_splash() as a live coroutine and assert on real,
## observable scene-tree state (child counts, real node types) driven by
## real engine process_frame signals -- not a reimplementation of its logic.
##
## Reproduced live 2026-09-08 (the third reported recurrence of "the intro
## isn't showing", immediately after a fresh relaunch on a build already
## descended from fix/intro-splash-plays-after-menu-loads). A real,
## timestamped, non-headless launch (flushed FileAccess + Time.get_ticks_
## msec(), the same technique this exact investigation area already
## established) measured:
##   - world._ready()'s heavy setup: ~57.9s, already known and unaddressed.
##   - _show_main_menu() ALONE, immediately after: 13,534ms -- a SECOND, real,
##     fully synchronous, entirely unyielded stretch (7 procedural class-icon
##     portraits, a live diorama SubViewport scene, the skill web, the menu
##     backdrop image -- see MainMenu._ready()/_build_create_screen()) sitting
##     directly, immediately before the intro was even added to the tree.
##   - The intro itself, once actually added, played back perfectly cleanly:
##     32/32 real per-frame timestamps at ~100ms spacing, finishing at
##     elapsed=3.204s -- confirming the THIRD pass's own fix (moving the
##     trigger past the heavy _ready() setup) genuinely works as intended.
## Total unyielded stretch immediately before the intro's first frame: ~72
## real seconds, with NOT ONE yielded engine frame anywhere in it. The third
## pass moved the intro past the WORSE of two adjacent freezes but never gave
## the engine a single presented-frame checkpoint between the end of the
## second one (menu construction) and the intro appearing -- so a player
## still sees one continuous, Windows-"Not Responding"-eligible grey stretch
## running right up to the point the intro flashes past, reproducing the
## identical complaint shape the third pass's own writeup already diagnosed,
## just with a shorter (but still real, and here even LARGER than this
## docs' own previous "~11s" estimate) freeze immediately upstream of it.
##
## World._show_loading_overlay already established, and proved ("verified
## against a real running instance"), that a Control which just became
## visible needs TWO yielded process_frame calls before more synchronous work
## runs, or its own first queued draw is not guaranteed to ever actually
## reach the screen (Godot can defer that first presentation one frame
## further than a single await accounts for). That exact guard already
## existed in this file for the loading overlay, but was never applied to
## the menu-then-intro handoff it sits right next to.

const World = preload("res://scenes/world.gd")
const IntroSplash = preload("res://scenes/intro_splash.gd")


## The body of one named function, read straight from source -- same helper
## as test_world_intro_splash_after_load_fanout.gd's own.
func _function_body(function_name: String) -> String:
	var source := FileAccess.get_file_as_string("res://scenes/world.gd")
	var needle := "func %s(" % function_name
	var start := source.find(needle)
	assert_gt(start, -1, "World.%s should exist" % function_name)
	var body_end := source.find("\nfunc ", start + 1)
	if body_end == -1:
		body_end = source.length()
	return source.substr(start, body_end - start)


## A real World, deliberately never added to any tree (see this file's own
## doc comment on why) -- _ui wired directly to a real, in-tree CanvasLayer,
## the only field _play_intro_splash() touches.
func _world_with_real_ui() -> World:
	var world: World = autofree(World.new())
	var ui := CanvasLayer.new()
	add_child_autofree(ui)
	world._ui = ui
	return world


# -- real, behavioral coverage ------------------------------------------------

func test_the_intro_is_not_added_before_any_real_frame_has_elapsed():
	var world := _world_with_real_ui()
	# Fire-and-forget: a GDScript coroutine runs synchronously up to its own
	# first genuine suspension point, then returns control here -- the same
	# technique World._ready() itself already relies on for its GitHub-
	# identity mid-function await (see that function's own doc comment).
	world._play_intro_splash()
	assert_eq(
		world._ui.get_child_count(), 0,
		(
			"the intro must not be added before at least one real frame has "
			+ "had a chance to present whatever was already on screen -- "
			+ "adding it immediately is the exact bug reproduced live"
		)
	)
	# Let the still-pending intro.finished await resolve so it doesn't leak
	# into the next test.
	await wait_process_frames(3)
	# The real IntroSplash._ready() that ran during those 3 frames now
	# unavoidably fires its own known/expected engine warning (see
	# test_intro_splash.gd's test_size_fills_the_viewport_once_ready_
	# settles for why) -- consumed here so it doesn't also auto-fail this
	# test as an "Unexpected Error" unrelated to what this test covers.
	assert_engine_error_count(1, "IntroSplash's own set_deferred(\"size\", ...) write")
	if world._ui.get_child_count() > 0:
		(world._ui.get_child(0) as IntroSplash)._finish()
	await wait_process_frames(1)


func test_the_intro_is_showing_once_the_gate_has_actually_elapsed():
	var world := _world_with_real_ui()
	world._play_intro_splash()
	# 3, not 2: a deliberate one-frame safety margin over the fix's own
	# 2-frame gate, so this assertion is never sensitive to exactly which of
	# two same-frame-emitted coroutines the engine happens to resume first --
	# it only claims "the gate has had time to fully elapse", which 3 frames
	# guarantees regardless of that ordering detail.
	await wait_process_frames(3)
	assert_eq(
		world._ui.get_child_count(), 1,
		"the intro should be showing once the frame gate has actually elapsed"
	)
	assert_true(
		world._ui.get_child_count() > 0 and world._ui.get_child(0) is IntroSplash,
		"the one child added should be the real IntroSplash node, not a stand-in"
	)
	# See the sibling test above for why this is expected, not a regression.
	assert_engine_error_count(1, "IntroSplash's own set_deferred(\"size\", ...) write")
	world._ui.get_child(0)._finish()
	await wait_process_frames(1)


# -- source-text pin, same technique as test_world_intro_splash_after_load_ --
# -- fanout.gd, for the same reason (a heavier real-World test can't cover --
# -- the EXACT frame count cheaply or deterministically every run) ----------

func test_play_intro_splash_yields_two_frames_before_creating_the_intro_node():
	var body := _function_body("_play_intro_splash")
	var intro_new_at := body.find("IntroSplash.new()")
	assert_gt(intro_new_at, -1, "the intro should still be created here")
	var gate_section := body.substr(0, intro_new_at)
	# Exactly two -- matching _show_loading_overlay's own already-proven
	# "two frames, not one" convention (see that function's own doc comment:
	# a single await is not guaranteed to have been presented by).
	assert_eq(
		gate_section.count("await"), 2,
		"two process_frame awaits should run before the intro node is created"
	)
