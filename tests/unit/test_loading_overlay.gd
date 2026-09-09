extends GutTest

## LoadingOverlay (see World._show_loading_overlay and, as of this pass,
## MainMenu's own character-creator build -- docs/concept/intro_splash.md).
## Previously only exercised indirectly, through World's own source-text
## ordering tests (test_world_intro_splash_after_load_fanout.gd) -- this is
## its first direct coverage, added alongside set_progress's own new `unit`
## parameter.

const LoadingOverlay = preload("res://scenes/loading_overlay.gd")
const LoadingTips = preload("res://src/ui/loading_tips.gd")


func _overlay() -> LoadingOverlay:
	var overlay := LoadingOverlay.new()
	add_child_autofree(overlay)
	return overlay


## The pre-existing chunk-loading callers (World._on_chunk_load_progress)
## pass no unit at all -- the new parameter must default to exactly the
## wording they already show, or every existing "N / M chunks" loading
## screen silently changes.
func test_set_progress_defaults_to_chunks_for_existing_callers():
	var overlay := _overlay()
	overlay.show_with_text("Loading your world...")

	overlay.set_progress(3, 10)

	assert_eq(overlay.status_text(), "Loading your world... (3 / 10 chunks)")


## New callers (MainMenu's own character-creator build, see test_main_menu.gd)
## need real, correctly-worded progress too -- "3 / 7 chunks" would be a
## real, honest lie about what's actually being counted.
func test_set_progress_accepts_a_different_unit_for_non_chunk_callers():
	var overlay := _overlay()
	overlay.show_with_text("Building character creator...")

	overlay.set_progress(2, 7, "portraits")

	assert_eq(overlay.status_text(), "Building character creator... (2 / 7 portraits)")


# -- witty tips: "SIMS 4 style loading descriptions" ------------------------

## Requested live: "make the loading screens use SIMS 4 style loading
## descriptions (funny witty progress lines) and put the real progress in
## the bottom right corner." The tip is the new primary readout, real
## progress moves to the corner (see status_text's own tests above, which
## still pass unchanged -- proving the corner readout kept its exact prior
## content contract even though the Control it lives on moved).
func test_shows_a_real_tip_from_the_pool_after_show_with_text():
	var overlay := _overlay()
	overlay.show_with_text("Loading your world...")
	assert_true(LoadingTips.TIPS.has(overlay.tip_text()))


func test_tip_changes_once_the_rotation_interval_elapses():
	var overlay := _overlay()
	overlay.show_with_text("Loading your world...")
	var first_tip := overlay.tip_text()

	overlay._advance_to(Time.get_ticks_msec() + int((LoadingTips.TIP_INTERVAL_SECONDS + 0.01) * 1000.0))

	assert_ne(overlay.tip_text(), first_tip)
	assert_true(LoadingTips.TIPS.has(overlay.tip_text()))


## The tip rotation and the corner's real progress are two independent
## readouts -- advancing one must never disturb the other.
func test_tip_rotation_does_not_disturb_the_corner_progress_text():
	var overlay := _overlay()
	overlay.show_with_text("Loading your world...")
	overlay.set_progress(3, 10)

	overlay._advance_to(Time.get_ticks_msec() + int((LoadingTips.TIP_INTERVAL_SECONDS + 0.01) * 1000.0))

	assert_eq(overlay.status_text(), "Loading your world... (3 / 10 chunks)")


## Reported live: "the new witty loading screen texts should change every
## few seconds not stay the same for 1 min loading." Real, measured cause
## (a temporary diagnostic test, not committed): Godot's delta smoothing
## (application/run/delta_smoothing, ON by default -- OS.
## is_delta_smoothing_enabled() confirmed true with no project.godot
## override) silently replaces the real, large `delta` a genuine multi-
## second synchronous stall produces with a much smaller smoothed estimate.
## Measured live against the real boot-time MushroomMarker.warm_art_cache()
## call: ~144 real seconds elapsed (Time.get_ticks_msec) while _process's
## OWN accumulated delta only reached ~4.9 "seconds" -- a ~29x gap. Since
## the tip (and the spinner glyph, which reads the same _elapsed_seconds)
## both advanced by accumulating `delta` every _process call, both froze on
## their opening frame for nearly the entire real load.
##
## This is a direct regression guard, inverted: `_process`'s own `delta`
## argument must never be trusted for this bookkeeping AT ALL -- only real
## elapsed wall-clock time (Time.get_ticks_msec(), via _advance_to below)
## may move the tip. A single misleadingly LARGE delta, called essentially
## the instant after show_with_text (near-zero real time actually passed),
## proves this: the pre-fix code did `_elapsed_seconds += delta` directly,
## so this exact call would have jumped straight past TIP_INTERVAL_SECONDS
## and changed the tip immediately -- the same trust-delta-blindly shape
## that (in the opposite direction, with Godot's real smoothed-too-SMALL
## deltas during a genuine stall) caused the live bug. Guarding both
## directions is what actually proves elapsed-time bookkeeping is now
## fully decoupled from whatever `delta` claims.
func test_a_misleading_process_delta_does_not_advance_the_tip_without_real_time_passing():
	var overlay := _overlay()
	overlay.show_with_text("Loading your world...")
	var first_tip := overlay.tip_text()

	overlay._process(100.0)  # would have blown past TIP_INTERVAL_SECONDS pre-fix

	assert_eq(
		overlay.tip_text(), first_tip,
		"a delta value alone, with no real wall-clock time actually passing, must not rotate the tip"
	)
