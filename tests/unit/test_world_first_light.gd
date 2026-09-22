extends GutTest

## docs/concept/arrival.md: a brand-new character opens their eyes at first
## light, whatever the wall clock says, and the real-Earth clock returns on
## its own within a few in-game days.
##
## Measured before this: the sun is driven directly by the real system
## clock at the spawn latitude, so an evening session starts in darkness
## with Cold/Freezing chips in spring. The diagnosis named that as possibly
## the single biggest factor in a bad first impression -- a player shown
## the game after work never sees the world the screenshots promise.
##
## These tests are about the WIRING, not the rule: DawnClause itself is
## pinned by test_dawn_clause.gd. What is asserted here is that World
## really asks it, really records an arrival to measure from, and really
## leaves a loaded save alone.

const World = preload("res://scenes/world.gd")
const DawnClause = preload("res://src/gameplay/dawn_clause.gd")


func _world_source() -> String:
	return FileAccess.get_file_as_string("res://scenes/world.gd")


func test_the_sun_is_asked_through_the_dawn_clause():
	assert_true(
		_world_source().contains("DawnClause.local_hour_for"),
		"the local hour the sky is computed from must pass through the clause"
	)


func test_an_arrival_is_recorded_to_measure_the_decay_from():
	var source := _world_source()
	assert_true(source.contains("_arrival_real_hour"), "the real hour the character arrived at")
	assert_true(source.contains("_arrival_unix_seconds"), "and when, so days elapsed is measurable")


## The clause is the identity for an old character: a save made on day 9
## loads on day 9 and its sky is the real one. Anything else would be the
## game lying about the planet, which is the one thing this project must
## not do.
func test_a_character_with_no_recorded_arrival_gets_the_real_hour_untouched():
	for hour in [0.0, 6.0, 13.5, 21.0, 23.9]:
		assert_almost_eq(
			DawnClause.local_hour_for(hour, DawnClause.CONVERGENCE_DAYS + 1.0, hour),
			hour, 0.0001,
			"an old character's sky is the real sky"
		)


## The case that matters for the first impression: whatever hour a player
## presses New Game at, the first frame is first light.
func test_every_real_hour_arrives_at_first_light_on_day_zero():
	for hour_index in 24:
		var hour := float(hour_index)
		assert_almost_eq(
			DawnClause.local_hour_for(hour, 0.0, hour),
			DawnClause.FIRST_LIGHT_HOUR, 0.0001,
			"pressing New Game at %02d:00 still opens at first light" % hour_index
		)


func test_the_real_clock_returns_by_the_pinned_day():
	var arrival := 21.0
	assert_almost_eq(
		DawnClause.local_hour_for(arrival, DawnClause.CONVERGENCE_DAYS, arrival),
		arrival, 0.0001,
		"and the planet's own clock is back, on its own, by the day the module names"
	)
