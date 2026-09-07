extends GutTest

## Pure frame-timing math for the boot intro splash (see
## docs/concept/intro_splash.md) -- deliberately separate from the thin
## IntroSplash Node that actually displays a texture, mirroring this
## codebase's usual "pure model, thin engine glue" split (e.g.
## LeafLitterRenderer's own static functions vs. its fill() wrapper): a
## frame index is a pure function of elapsed time, fully headless-testable
## with no scene tree, no _process(), no real texture required at all.

const IntroSplashSequencer = preload("res://src/rendering/intro_splash_sequencer.gd")


func test_frame_index_starts_at_zero():
	assert_eq(IntroSplashSequencer.frame_index_at(0.0), 0)


func test_frame_index_advances_with_elapsed_time():
	var half_frame := 0.5 / IntroSplashSequencer.FPS
	assert_eq(IntroSplashSequencer.frame_index_at(half_frame), 0)
	var one_and_a_half_frames := 1.5 / IntroSplashSequencer.FPS
	assert_eq(IntroSplashSequencer.frame_index_at(one_and_a_half_frames), 1)


func test_frame_index_never_exceeds_the_last_frame():
	assert_eq(
		IntroSplashSequencer.frame_index_at(IntroSplashSequencer.duration_seconds() * 10.0),
		IntroSplashSequencer.FRAME_COUNT - 1
	)


func test_frame_index_reaches_every_frame_across_the_full_duration():
	# Not just "clamped at the end" -- a real walk through elapsed time must
	# actually visit every frame in order, or a dropped index would silently
	# skip a beat (e.g. the text build-in) without any test catching it.
	var seen: Dictionary = {}
	var steps := 1000
	for i in steps:
		var elapsed := IntroSplashSequencer.duration_seconds() * float(i) / float(steps)
		seen[IntroSplashSequencer.frame_index_at(elapsed)] = true
	assert_eq(seen.size(), IntroSplashSequencer.FRAME_COUNT)


func test_is_not_finished_before_the_last_frames_own_duration_elapses():
	assert_false(IntroSplashSequencer.is_finished(IntroSplashSequencer.duration_seconds() - 0.01))


func test_is_finished_once_the_full_duration_elapses():
	assert_true(IntroSplashSequencer.is_finished(IntroSplashSequencer.duration_seconds()))


## Not an eyeballed number -- FRAME_COUNT/FPS exactly, so the two constants
## can never silently drift apart from whatever duration_seconds() actually
## returns.
func test_duration_is_pinned_to_frame_count_over_fps():
	assert_almost_eq(
		IntroSplashSequencer.duration_seconds(),
		float(IntroSplashSequencer.FRAME_COUNT) / IntroSplashSequencer.FPS,
		0.001
	)
