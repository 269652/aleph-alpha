extends GutTest

## The hour a brand-new character opens their eyes (see
## docs/concept/arrival.md). The load-bearing tests here are not the two
## the spec names out loud -- day 0 is always first light, day
## CONVERGENCE_DAYS is always the real hour -- but the two that stop a
## later session from getting there by cheating: the clock must never run
## BACKWARDS and never STALL while it converges, because either one is a
## visible lurch in the sky, and the naive "re-derive the offset from the
## hour it is now" implementation fails both for an evening arrival.
##
## FIRST_LIGHT_HOUR is checked against the repo's own astronomy
## (SolarPosition) rather than asserted, so it cannot drift into being a
## number somebody liked.

const DawnClause = preload("res://src/gameplay/dawn_clause.gd")
const SolarPosition = preload("res://src/world/solar_position.gd")
const SeasonCycle = preload("res://src/world/season_cycle.gd")

## The day of year at which SolarPosition's own declination approximation
## (-23.44 * cos(360/365 * (day + 10))) crosses zero: 360/365 * (day + 10)
## = 90 degrees at day 81.25. The March equinox, in the model's own terms.
const EQUINOX_DAY_OF_YEAR := 81

## Greenwich, so local solar hour and UTC hour are the same number and the
## test reads as the astronomy it is checking.
const PRIME_MERIDIAN := 0.0

## The declination approximation is not exact at the sampled day and the
## elevation formula is itself approximate (no equation of time), so the
## horizon checks allow a fifth of a degree -- far tighter than the 24
## minutes of twilight the constant is derived from, and far too tight to
## pass for an hour somebody picked.
const HORIZON_TOLERANCE_DEGREES := 0.2

var sun: SolarPosition


func before_each():
	sun = SolarPosition.new()


func _elevation_at_local_hour(latitude: float, local_hour: float) -> float:
	return sun.elevation_degrees(latitude, PRIME_MERIDIAN, EQUINOX_DAY_OF_YEAR, local_hour)


# -- the constants are real astronomy, not taste --------------------------


func test_the_equinox_sunrise_hour_really_puts_the_sun_on_the_horizon_everywhere():
	# The one sunrise hour the whole planet agrees on: with declination at
	# zero the hour angle at sunrise is -90 degrees at every latitude.
	for latitude in [-60.0, -45.0, -23.5, 0.0, 23.5, 45.0, 60.0]:
		var elevation := _elevation_at_local_hour(latitude, DawnClause.EQUINOX_SUNRISE_HOUR)
		assert_almost_eq(
			elevation,
			0.0,
			HORIZON_TOLERANCE_DEGREES,
			"the sun is not on the horizon at %.1f at latitude %.1f" % [
				DawnClause.EQUINOX_SUNRISE_HOUR, latitude
			]
		)


func test_first_light_is_civil_twilight_before_that_sunrise():
	# Civil dawn: the sun's centre 6 degrees below the horizon, the real
	# definition of "light enough to work outside without a lamp".
	var elevation := _elevation_at_local_hour(0.0, DawnClause.FIRST_LIGHT_HOUR)
	assert_almost_eq(
		elevation,
		DawnClause.CIVIL_TWILIGHT_DEGREES,
		HORIZON_TOLERANCE_DEGREES,
		"FIRST_LIGHT_HOUR is not civil dawn at the equator"
	)
	assert_true(
		DawnClause.FIRST_LIGHT_HOUR < DawnClause.EQUINOX_SUNRISE_HOUR,
		"first light must come before sunrise"
	)


func test_first_light_is_derived_from_the_suns_own_rate_of_climb():
	# 6 degrees at 15 degrees per hour is 24 minutes -- the length of civil
	# twilight at the equator, and the whole of the offset from sunrise.
	assert_almost_eq(
		DawnClause.EQUINOX_SUNRISE_HOUR - DawnClause.FIRST_LIGHT_HOUR,
		-DawnClause.CIVIL_TWILIGHT_DEGREES / DawnClause.DEGREES_PER_HOUR,
		0.0000001,
		"first light must be derived from the twilight angle and Earth's rotation"
	)
	assert_almost_eq(
		DawnClause.DEGREES_PER_HOUR * 24.0,
		360.0,
		0.0000001,
		"DEGREES_PER_HOUR must be one rotation of the planet per day"
	)


func test_an_in_game_day_is_the_season_cycles_own_day():
	assert_almost_eq(
		DawnClause.REAL_HOURS_PER_IN_GAME_DAY,
		SeasonCycle.SECONDS_PER_DAY / 3600.0,
		0.0000001,
		"the clause's day must be the world's day, or the convergence is fiction"
	)


func test_the_convergence_day_is_the_first_one_past_a_stalled_sun():
	# Converging the worst possible offset (half a clock face) over
	# STALL_DAYS would make the clock rate exactly zero: a sun nailed to
	# the horizon. CONVERGENCE_DAYS is the smallest whole day past that.
	assert_almost_eq(
		DawnClause.STALL_DAYS,
		DawnClause.MAX_OFFSET_HOURS / DawnClause.REAL_HOURS_PER_IN_GAME_DAY,
		0.0000001
	)
	assert_almost_eq(
		1.0 - DawnClause.MAX_OFFSET_HOURS
		/ (DawnClause.REAL_HOURS_PER_IN_GAME_DAY * DawnClause.STALL_DAYS),
		0.0,
		0.0000001,
		"STALL_DAYS is meant to be exactly the stall"
	)
	assert_almost_eq(
		DawnClause.CONVERGENCE_DAYS, DawnClause.STALL_DAYS + 1.0, 0.0000001
	)
	assert_almost_eq(
		DawnClause.MIN_CLOCK_RATE,
		1.0 - DawnClause.MAX_OFFSET_HOURS
		/ (DawnClause.REAL_HOURS_PER_IN_GAME_DAY * DawnClause.CONVERGENCE_DAYS),
		0.0000001
	)
	assert_gt(DawnClause.MIN_CLOCK_RATE, 0.0, "the worst case must still move")


func test_the_largest_possible_offset_is_half_a_clock_face():
	var worst := 0.0
	for hour in 24:
		worst = maxf(worst, absf(DawnClause.offset_at_arrival(float(hour))))
	assert_true(
		worst <= DawnClause.MAX_OFFSET_HOURS + 0.0000001,
		"an offset past half a clock face means the shortest way round was not taken"
	)


# -- what the spec promises -----------------------------------------------


func test_day_zero_is_first_light_whatever_the_wall_clock_says():
	for hour in 24:
		assert_almost_eq(
			DawnClause.local_hour_for(float(hour), 0.0),
			DawnClause.FIRST_LIGHT_HOUR,
			0.0000001,
			"a character created at %02d:00 did not wake at first light" % hour
		)


func test_the_real_hour_comes_back_exactly_on_the_named_day_and_stays():
	for hour in 24:
		for days in [
			DawnClause.CONVERGENCE_DAYS,
			DawnClause.CONVERGENCE_DAYS + 0.5,
			DawnClause.CONVERGENCE_DAYS * 10.0,
		]:
			var half := float(hour) + 0.5
			assert_almost_eq(
				DawnClause.local_hour_for(half, days),
				half,
				0.0000001,
				"the clause still moved %.1f on day %.1f" % [half, days]
			)


func test_the_offset_decays_monotonically_and_never_comes_back():
	for hour in 24:
		var previous := DawnClause.MAX_OFFSET_HOURS + 1.0
		var steps := 40
		for step in range(steps + 1):
			var days: float = DawnClause.CONVERGENCE_DAYS * float(step) / float(steps)
			var magnitude := absf(DawnClause.offset_hours(float(hour), days))
			assert_true(
				magnitude <= previous + 0.0000001,
				"the offset grew again at day %.2f from arrival hour %d" % [days, hour]
			)
			previous = magnitude
		assert_almost_eq(
			DawnClause.offset_hours(float(hour), DawnClause.CONVERGENCE_DAYS),
			0.0,
			0.0000001
		)


func test_the_hour_is_always_a_real_clock_face():
	for hour in 24:
		for step in 33:
			var days: float = DawnClause.CONVERGENCE_DAYS * float(step) / 16.0
			var shown := DawnClause.local_hour_for(float(hour) + 0.37, days)
			assert_true(
				shown >= 0.0 and shown < 24.0,
				"%.4f is not an hour of the day (arrival %d, day %.2f)" % [shown, hour, days]
			)


# -- the two that stop a later session from cheating ----------------------


func test_the_clock_never_runs_backwards_and_never_stalls():
	# Real time advancing, sampled the way a player lives it: the wall
	# clock moves REAL_HOURS_PER_IN_GAME_DAY per in-game day, and the
	# displayed hour must move forward every single sample. The naive
	# implementation (offset re-derived from the current hour) goes
	# backwards here for every evening arrival.
	var sample_hours := 0.25
	for arrival in 24:
		var previous := DawnClause.local_hour_for(float(arrival), 0.0)
		var elapsed := sample_hours
		while elapsed <= DawnClause.REAL_HOURS_PER_IN_GAME_DAY * (DawnClause.CONVERGENCE_DAYS + 2.0):
			var real_hour := fposmod(float(arrival) + elapsed, 24.0)
			var days := elapsed / DawnClause.REAL_HOURS_PER_IN_GAME_DAY
			var shown := DawnClause.local_hour_for(real_hour, days)
			var advanced := fposmod(shown - previous, 24.0)
			assert_gt(
				advanced,
				0.0,
				"the clock stalled at %.2f real hours after a %02d:00 arrival" % [elapsed, arrival]
			)
			assert_true(
				advanced < 1.0,
				"the clock jumped %.3f h at %.2f real hours after a %02d:00 arrival" % [
					advanced, elapsed, arrival
				]
			)
			previous = shown
			elapsed += sample_hours


func test_the_slowest_the_clock_ever_runs_is_the_pinned_floor():
	# Swept finely, because the worst case is an arrival just past the
	# antipode of first light (17:36) rather than any whole hour.
	var step := 0.01
	var slowest := 2.0
	var fastest := 0.0
	var arrival := 0.0
	while arrival < 24.0:
		var rate := DawnClause.clock_rate_for(arrival)
		slowest = minf(slowest, rate)
		fastest = maxf(fastest, rate)
		arrival += step
	assert_true(
		slowest >= DawnClause.MIN_CLOCK_RATE - 0.0000001,
		"an arrival hour runs the clock slower than the pinned floor: %.4f" % slowest
	)
	assert_true(
		slowest - DawnClause.MIN_CLOCK_RATE < 0.01,
		"the floor must be the real worst case, not padding: %.4f vs %.4f" % [
			slowest, DawnClause.MIN_CLOCK_RATE
		]
	)
	# The mirror case: the clock catching UP is bounded by the same figure,
	# so the day is never fast-forwarded either.
	assert_true(
		fastest <= 2.0 - DawnClause.MIN_CLOCK_RATE + 0.0000001,
		"an arrival hour runs the clock faster than the mirror of the floor: %.4f" % fastest
	)


func test_a_caller_that_remembers_the_arrival_hour_gets_the_same_answer():
	# The two-argument form recovers the arrival hour from the world's own
	# four-real-hours-per-day coupling; a caller that persisted the real
	# arrival hour may pass it instead, and must not get a different clock.
	for arrival in 24:
		for step in 17:
			var days: float = DawnClause.CONVERGENCE_DAYS * float(step) / 16.0
			var real_hour := fposmod(
				float(arrival) + days * DawnClause.REAL_HOURS_PER_IN_GAME_DAY, 24.0
			)
			assert_almost_eq(
				DawnClause.local_hour_for(real_hour, days),
				DawnClause.local_hour_for(real_hour, days, float(arrival)),
				0.0000001,
				"the recovered arrival hour disagreed with the remembered one"
			)


func test_a_loaded_character_past_the_clause_is_untouched_by_it():
	# Pillar 3: the clause is keyed to arrival, not to session start. A
	# save made on day 9 loads on day 9.
	for hour in 24:
		var real_hour := float(hour) + 0.25
		assert_almost_eq(
			DawnClause.local_hour_for(real_hour, 9.0), real_hour, 0.0000001
		)


func test_the_clock_runs_at_one_steady_rate_rather_than_accelerating():
	# What linear decay actually buys: no acceleration in the sky. A curve
	# here would pass every other test in this file while making the sun
	# visibly speed up partway through the second day.
	var sample := 0.25
	for arrival in 24:
		var advances: Array[float] = []
		for elapsed in [1.0, 5.0, 9.0, 13.0]:
			var days_a: float = elapsed / DawnClause.REAL_HOURS_PER_IN_GAME_DAY
			var days_b: float = (elapsed + sample) / DawnClause.REAL_HOURS_PER_IN_GAME_DAY
			var hour_a := DawnClause.local_hour_for(
				fposmod(float(arrival) + elapsed, 24.0), days_a
			)
			var hour_b := DawnClause.local_hour_for(
				fposmod(float(arrival) + elapsed + sample, 24.0), days_b
			)
			advances.append(fposmod(hour_b - hour_a, 24.0))
		for advance in advances:
			assert_almost_eq(
				advance,
				advances[0],
				0.000001,
				"the clock changed pace mid-convergence after a %02d:00 arrival" % arrival
			)
		assert_almost_eq(
			advances[0] / sample,
			DawnClause.clock_rate_for(float(arrival)),
			0.000001,
			"the rate the player sees is not the rate clock_rate_for reports"
		)
