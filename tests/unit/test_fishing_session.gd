extends GutTest

const FishingSession = preload("res://src/gameplay/fishing_session.gd")

var session: FishingSession


func before_each():
	session = FishingSession.new()


func test_starts_idle():
	assert_eq(session.phase(), FishingSession.IDLE)


func test_casting_puts_the_line_in_the_water():
	session.cast(1, 0.0)
	assert_eq(session.phase(), FishingSession.WAITING)


func test_waiting_eventually_becomes_a_bite():
	session.cast(1, 0.0)
	# bite_delay is at most MAX (15s); 20s guarantees the bite has come.
	session.advance(20.0)
	assert_eq(session.phase(), FishingSession.BITING)


func test_reacting_during_a_bite_catches_a_fish():
	session.cast(1, 0.0)
	session.advance(20.0)
	session.react()
	assert_eq(session.phase(), FishingSession.CAUGHT)
	assert_ne(session.rarity(), "", "a caught fish has a rarity")


func test_reacting_too_early_misses():
	session.cast(1, 0.0)
	session.advance(0.5)  # still waiting for the bite
	session.react()
	assert_eq(session.phase(), FishingSession.MISSED)


func test_letting_the_bite_window_lapse_misses():
	session.cast(1, 0.0)
	session.advance(20.0)  # now biting
	session.advance(FishingSession.BITE_WINDOW + 0.5)  # too slow to react
	assert_eq(session.phase(), FishingSession.MISSED)


func test_bite_timing_is_deterministic_per_seed():
	var a := FishingSession.new()
	var b := FishingSession.new()
	a.cast(42, 0.0)
	b.cast(42, 0.0)
	# Same seed -> same bite delay -> same phase after the same elapse.
	a.advance(3.0)
	b.advance(3.0)
	assert_eq(a.phase(), b.phase())


# -- phase_elapsed_seconds (drives the bobber's bite-dip animation) ----------

func test_phase_elapsed_seconds_is_zero_right_after_a_bite_starts():
	session.cast(1, 0.0)
	session.advance(20.0)  # now biting
	assert_eq(session.phase(), FishingSession.BITING)
	assert_eq(session.phase_elapsed_seconds(), 0.0)


func test_phase_elapsed_seconds_grows_while_biting():
	session.cast(1, 0.0)
	session.advance(20.0)
	session.advance(0.4)
	assert_almost_eq(session.phase_elapsed_seconds(), 0.4, 0.001)


func test_phase_elapsed_seconds_resets_on_a_fresh_cast():
	session.cast(1, 0.0)
	session.advance(0.5)
	assert_gt(session.phase_elapsed_seconds(), 0.0)

	session.cast(2, 0.0)
	assert_eq(session.phase_elapsed_seconds(), 0.0)


func test_is_active_only_while_a_line_is_out():
	assert_false(session.is_active())
	session.cast(1, 0.0)
	assert_true(session.is_active())
	session.advance(20.0)
	session.react()  # caught -> line is in, no longer active
	assert_false(session.is_active())
