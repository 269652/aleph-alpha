extends GutTest

## LoadingSpinner: which spinner frame to show given how long the loading
## overlay (see scenes/loading_overlay.gd) has been visible. Pure and
## tuned-constant-driven per CLAUDE.md ("no eyeballed values") -- the overlay
## covers World's New Game/Load Game/Join stall (EarthChunkManager.update()'s
## first call, measured ~39-90s+ in this dev sandbox -- see docs/progress.md).
## This glyph itself is still indeterminate (no percent-done concept), but
## EarthChunkManager.update_with_progress now yields a frame between chunks
## so it can actually be SEEN to animate, alongside a real "N / M chunks"
## count LoadingOverlay.set_progress shows next to it -- see
## docs/concept/persistence.md's "Loading screens" section.

const LoadingSpinner = preload("res://src/ui/loading_spinner.gd")


func test_starts_on_the_first_frame():
	assert_eq(LoadingSpinner.frame_for_elapsed(0.0), LoadingSpinner.FRAMES[0])


func test_advances_to_the_next_frame_after_one_interval():
	assert_eq(
		LoadingSpinner.frame_for_elapsed(LoadingSpinner.FRAME_INTERVAL_SECONDS),
		LoadingSpinner.FRAMES[1]
	)


func test_stays_on_the_same_frame_just_before_the_next_interval():
	var just_before := LoadingSpinner.FRAME_INTERVAL_SECONDS * 2 - 0.001
	assert_eq(LoadingSpinner.frame_for_elapsed(just_before), LoadingSpinner.FRAMES[1])


func test_wraps_back_to_the_first_frame_after_a_full_cycle():
	var full_cycle := LoadingSpinner.FRAME_INTERVAL_SECONDS * LoadingSpinner.FRAMES.size()
	assert_eq(LoadingSpinner.frame_for_elapsed(full_cycle), LoadingSpinner.FRAMES[0])


func test_negative_elapsed_is_clamped_to_the_first_frame():
	assert_eq(LoadingSpinner.frame_for_elapsed(-1.0), LoadingSpinner.FRAMES[0])
