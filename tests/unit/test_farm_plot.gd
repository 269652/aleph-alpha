extends GutTest

const FarmPlot = preload("res://src/gameplay/farm_plot.gd")

var plot: FarmPlot


func before_each():
	plot = FarmPlot.new()


## Waters and advances in small steps (never exceeding the grace window) until
## the plot reaches "ready", overshooting slightly to absorb float rounding.
func _grow_to_ready(a_plot: FarmPlot) -> void:
	var step: float = a_plot.growth_time / 10.0
	for i in 12:
		a_plot.water()
		a_plot.advance(step)


func test_starts_empty():
	assert_eq(plot.state, "empty")
	assert_false(plot.is_ready())
	assert_false(plot.is_withered())


func test_plant_sets_state_to_growing_and_stores_crop_id():
	plot.plant("wheat", 42)
	assert_eq(plot.state, "growing")
	assert_eq(plot.crop_id, "wheat")


func test_growth_time_is_within_expected_range():
	plot.plant("wheat", 42)
	assert_between(plot.growth_time, FarmPlot.MIN_GROWTH_TIME, FarmPlot.MAX_GROWTH_TIME)


func test_growth_time_is_deterministic_for_the_same_seed_value():
	var a := FarmPlot.new()
	var b := FarmPlot.new()
	a.plant("wheat", 123)
	b.plant("wheat", 123)
	assert_eq(a.growth_time, b.growth_time)


func test_advancing_time_while_regularly_watered_reaches_ready():
	plot.plant("wheat", 42)
	_grow_to_ready(plot)
	assert_true(plot.is_ready())
	assert_eq(plot.state, "ready")


func test_advancing_time_without_watering_past_grace_threshold_withers():
	plot.plant("wheat", 42)
	plot.advance(plot.grace_seconds() + 0.01)
	assert_true(plot.is_withered())
	assert_false(plot.is_ready())
	assert_eq(plot.state, "withered")


func test_watering_resets_the_neglect_clock():
	plot.plant("wheat", 42)
	var near_threshold: float = plot.grace_seconds() - 0.1
	plot.advance(near_threshold)
	plot.water()
	plot.advance(near_threshold)
	# Alive is the claim, not still-growing: a grace window is now a whole
	# night (see MIN_WATER_GRACE_SECONDS), which is longer than some crops
	# take to ripen, so a watered bed left that long may well be READY by
	# the end of it. Either way it is not dead, which is what watering buys.
	assert_false(plot.is_withered())
	assert_ne(plot.state, "empty")


func test_harvest_on_ready_plot_returns_positive_count_and_resets_to_empty():
	plot.plant("wheat", 42)
	_grow_to_ready(plot)
	var result: Dictionary = plot.harvest()
	assert_eq(result["crop_id"], "wheat")
	assert_gt(result["count"], 0)
	assert_eq(plot.state, "empty")
	assert_eq(plot.crop_id, "")


func test_harvest_on_growing_plot_is_a_noop():
	plot.plant("wheat", 42)
	var result: Dictionary = plot.harvest()
	assert_eq(result["crop_id"], "")
	assert_eq(result["count"], 0)
	assert_eq(plot.state, "growing")


func test_harvest_on_withered_plot_is_a_noop():
	plot.plant("wheat", 42)
	plot.advance(plot.grace_seconds() + 0.01)
	var result: Dictionary = plot.harvest()
	assert_eq(result["crop_id"], "")
	assert_eq(result["count"], 0)
	assert_eq(plot.state, "withered")


func test_harvest_on_empty_plot_is_a_noop():
	var result: Dictionary = plot.harvest()
	assert_eq(result["crop_id"], "")
	assert_eq(result["count"], 0)
	assert_eq(plot.state, "empty")


func test_yield_count_is_deterministic_for_the_same_seed_value():
	var a := FarmPlot.new()
	var b := FarmPlot.new()
	a.plant("wheat", 99)
	b.plant("wheat", 99)
	_grow_to_ready(a)
	_grow_to_ready(b)
	var result_a: Dictionary = a.harvest()
	var result_b: Dictionary = b.harvest()
	assert_eq(result_a["count"], result_b["count"])


func test_planting_again_after_harvest_resets_to_growing():
	plot.plant("wheat", 42)
	_grow_to_ready(plot)
	plot.harvest()
	plot.plant("carrot", 7)
	assert_eq(plot.state, "growing")
	assert_eq(plot.crop_id, "carrot")


# -- a bed has to survive the night ------------------------------------------
#
# Reported in play, three times over: *"No crops (wheat) grow and get
# harvested.. it plants then nothing happens"*, then *"The Farmhous Wheat
# stock should increase"*, and again with the field in shot: *"Planted crops
# still vanish and don't grow and no harvest happens"*.
#
# Measured against a real village (tools/probe_village_farming.gd): over ten
# simulated days, THIRTEEN of eighteen beds ended WITHERED, one farmhouse
# took in fifteen wheat and the other two took in none at all. The farmer is
# not idle -- the probe has them working 2750 of 6000 ticks. They simply
# cannot be there.
#
# The arithmetic says why, and it is not close. A bed's whole drought
# tolerance was half its own growth time: ten to thirty seconds. A villager's
# day is sixty seconds across four blocks, and nobody farms while they sleep,
# so a field goes untended for up to three blocks -- forty-five seconds -- on
# every single day of its life. Every bed died every night, and the farmer
# spent the next morning replanting ground that would die again that evening.
#
# So a bed's drought tolerance has a FLOOR, and the floor is one night. This
# is not a forgiving number chosen to make the numbers work: a field is not a
# pot on a windowsill, and a crop that dies because nobody came for one
# evening is a crop nobody in this world could ever farm, the player
# included.

const EarthChunkManagerForDay = preload("res://src/world/earth_chunk_manager.gd")
const NpcSchedule = preload("res://src/world/npc_schedule.gd")


## The floor is the village's own night, not a number of its own: the part
## of a simulated day a villager is not at work, at worst (one work block of
## four). Pinned here rather than imported, because a pure gameplay rule does
## not reach into the chunk manager -- so this test is what keeps the two
## from drifting.
func test_the_night_a_bed_must_survive_is_the_villages_own_night():
	var blocks := float(NpcSchedule.TIME_BLOCKS.size())
	assert_almost_eq(
		FarmPlot.MIN_WATER_GRACE_SECONDS,
		float(EarthChunkManagerForDay.SECONDS_PER_SIMULATED_DAY) * (blocks - 1.0) / blocks,
		0.001
	)


func test_a_bed_nobody_waters_survives_one_night():
	plot.plant("wheat", 1)
	plot.advance(FarmPlot.MIN_WATER_GRACE_SECONDS)
	assert_false(plot.is_withered(), "a field left overnight is still a field in the morning")


## Every seed, not just this one: a fast-growing crop used to have the
## SHORTEST tolerance of all, which is exactly backwards for a field whose
## keeper is away the same length of time whatever is sown in it.
func test_no_seed_produces_a_bed_that_dies_overnight():
	for seed_value in range(1, 40):
		var bed := FarmPlot.new()
		bed.plant("wheat", seed_value)
		bed.advance(FarmPlot.MIN_WATER_GRACE_SECONDS)
		assert_false(bed.is_withered(), "seed %d died overnight" % seed_value)


## Still a real mechanic, not an exemption: a bed nobody comes back to at
## all still dies.
func test_a_bed_left_far_longer_than_a_night_still_withers():
	plot.plant("wheat", 1)
	plot.advance(plot.grace_seconds() + 0.01)
	assert_true(plot.is_withered())


## The floor RAISES a short window and never shortens a long one -- a crop
## slow enough to earn a longer tolerance than a night keeps it.
func test_the_floor_only_ever_raises_a_beds_own_window():
	for seed_value in range(1, 60):
		var bed := FarmPlot.new()
		bed.plant("wheat", seed_value)
		assert_almost_eq(
			bed.grace_seconds(),
			maxf(bed.growth_time * FarmPlot.WATER_GRACE_FRACTION, FarmPlot.MIN_WATER_GRACE_SECONDS),
			0.001
		)


## And the honest state of that today, said out loud rather than implied:
## with growth times of 20-60s, HALF of even the slowest is 30s, so the
## night governs every crop in the game and the proportional half of the
## rule currently decides nothing. It is kept because it is the real
## relationship (a slow crop does tolerate more drought) and because a
## longer-cycle crop would revive it -- not because it is doing work now.
func test_today_the_night_governs_every_crop_there_is():
	assert_lt(
		FarmPlot.MAX_GROWTH_TIME * FarmPlot.WATER_GRACE_FRACTION,
		FarmPlot.MIN_WATER_GRACE_SECONDS,
		"if this ever flips, the proportional window is live again and says so"
	)
	for seed_value in range(1, 60):
		var bed := FarmPlot.new()
		bed.plant("wheat", seed_value)
		assert_almost_eq(bed.grace_seconds(), FarmPlot.MIN_WATER_GRACE_SECONDS, 0.001)


## And watering still resets the clock it always did.
func test_watering_still_buys_another_whole_grace_window():
	plot.plant("wheat", 1)
	plot.advance(plot.grace_seconds() - 0.1)
	plot.water()
	plot.advance(plot.grace_seconds() - 0.1)
	assert_false(plot.is_withered())
