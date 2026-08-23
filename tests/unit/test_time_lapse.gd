extends GutTest

## Running the world's ecology fast, so a year can be watched in a minute
## (see the /ecotest console command).
##
## The point is verification: seasons turning, fruit ripening and falling,
## saplings coming up. All of that is driven by the same delta the ecology
## steps take, so the whole thing is a question of how much simulated time to
## hand them per frame -- and how to hand it over without breaking them.

const TimeLapse = preload("res://src/gameplay/time_lapse.gd")
const SeasonCycle = preload("res://src/world/season_cycle.gd")


# -- asking for a speed ------------------------------------------------------

## Asked in terms of the thing being watched -- how long a YEAR should take --
## rather than as a bare multiplier. "600x" means nothing to a person waiting
## for autumn; "a year in two minutes" does.
func test_a_requested_year_length_becomes_a_rate():
	var scale := TimeLapse.scale_for(120.0)
	assert_almost_eq(scale * 120.0, SeasonCycle.SECONDS_PER_YEAR, 1.0)


func test_a_shorter_year_runs_faster():
	assert_gt(TimeLapse.scale_for(60.0), TimeLapse.scale_for(600.0))


## Normal speed is exactly normal -- turning the lapse off must not leave the
## world running a hair fast.
func test_normal_speed_is_exactly_one():
	assert_eq(TimeLapse.scale_for(SeasonCycle.SECONDS_PER_YEAR), 1.0)


func test_a_nonsense_request_does_not_divide_by_zero():
	assert_gt(TimeLapse.scale_for(0.0), 0.0)
	assert_gt(TimeLapse.scale_for(-5.0), 0.0)


# -- handing the time over ---------------------------------------------------

## Time is handed over in SLICES, so no single call carries more world time
## than the sliced steps are built to take.
##
## The slice is much bigger than it was -- only the cheap, rate-based steps are
## sliced now -- so an ordinary rate fits in one. A high enough rate still
## divides.
func test_time_arrives_in_slices_bounded_by_the_slice_size():
	var fast := TimeLapse.slices(1.0 / 60.0, TimeLapse.scale_for(10.0))
	assert_gt(fast.size(), 1, "a very fast run should still divide its time")
	for slice in fast:
		assert_lte(slice, TimeLapse.SLICE_SECONDS + 0.001)


func test_no_slice_is_bigger_than_the_step_the_sims_can_take():
	for scale in [1.0, 100.0, 10000.0, 1000000.0]:
		for slice in TimeLapse.slices(1.0 / 60.0, scale):
			assert_lte(slice, TimeLapse.SLICE_SECONDS + 0.001, "a slice too big to simulate")


## At normal speed nothing changes: one frame, one delta, exactly as before.
func test_normal_speed_hands_over_a_single_unchanged_frame():
	var slices := TimeLapse.slices(0.016, 1.0)
	assert_eq(slices.size(), 1)
	assert_almost_eq(slices[0], 0.016, 0.0001)


## The slices add up to the time actually asked for, so the world really does
## run at the requested rate rather than merely looking busy.
func test_the_slices_add_up_to_the_time_requested():
	var delta := 1.0 / 60.0
	var scale := TimeLapse.scale_for(240.0)
	var total := 0.0
	for slice in TimeLapse.slices(delta, scale):
		total += slice
	assert_almost_eq(total, delta * scale, 0.001)


## ...up to a ceiling. There is only so much simulating a frame can do, and
## past it the world quietly runs slower than asked rather than freezing --
## which is the failure mode that matters, because a frozen game cannot be
## watched at all.
func test_an_impossible_speed_is_capped_rather_than_freezing_the_game():
	var slices := TimeLapse.slices(1.0 / 60.0, 100000000.0)
	assert_lte(slices.size(), TimeLapse.MAX_SLICES_PER_FRAME)


func test_a_zero_length_frame_asks_for_no_work():
	assert_eq(TimeLapse.slices(0.0, 1000.0).size(), 0)


# -- what it is for ----------------------------------------------------------

## A run has to actually cross the seasons, or it cannot verify what it exists
## to verify.
func test_a_default_run_crosses_every_season():
	var scale := TimeLapse.scale_for(TimeLapse.DEFAULT_SECONDS_PER_YEAR)
	var cycle := SeasonCycle.new()
	var seen := {}
	var simulated := 0.0
	# One real minute at sixty frames a second.
	for _frame in 60 * 60:
		for slice in TimeLapse.slices(1.0 / 60.0, scale):
			simulated += slice
		seen[cycle.season_at(simulated)] = true
	for season in SeasonCycle.SEASONS:
		assert_true(seen.has(season), "a default run never reaches %s" % season)


## ...and not so fast that a season flashes past unseen.
func test_a_default_run_lingers_in_each_season():
	var scale := TimeLapse.scale_for(TimeLapse.DEFAULT_SECONDS_PER_YEAR)
	var season_seconds := SeasonCycle.SECONDS_PER_YEAR / float(SeasonCycle.SEASONS.size())
	var real_seconds_per_season := season_seconds / scale
	assert_gt(real_seconds_per_season, 5.0, "a season should last long enough to look at")


## A slice must stay within reach of the cadences of the steps that are
## actually sliced.
##
## Only the fine group is sliced -- the clock, worm surfacing, and fruiting --
## and fruiting resets its accumulator rather than subtracting from it, so it
## cannot leak however big the slice is. The heavy periodic steps that DO
## subtract are on the batch cadence now, taking the whole frame in one call,
## which is exactly the one call their accumulators want.
func test_a_slice_stays_within_reach_of_the_sliced_cadences():
	var EarthChunkManager := load("res://src/world/earth_chunk_manager.gd")
	assert_gte(
		TimeLapse.SLICE_SECONDS, EarthChunkManager.FRUITING_INTERVAL,
		"a slice smaller than the fruiting cadence just wastes work"
	)


## The batch steps are the ones that subtract rather than reset, and they see
## a whole frame at once -- so the shed-the-surplus guard in them is what keeps
## their cadence honest, not the slice size.
func test_the_frame_can_carry_a_useful_amount_of_world_time():
	var per_frame := TimeLapse.SLICE_SECONDS * float(TimeLapse.MAX_SLICES_PER_FRAME)
	# At least a few in-game hours a frame, or a year takes all afternoon.
	assert_gte(per_frame, 900.0, "a frame carries too little world time to be worth watching")
