extends GutTest

## NpcSchedule: which block of the day an hour falls in, which schedule entry
## applies now, and -- so a village does not turn as one -- whose day turns
## when.

const NpcSchedule = preload("res://src/world/npc_schedule.gd")


func test_the_day_is_cut_into_its_four_blocks():
	assert_eq(NpcSchedule.time_block_for_hour(8), "morning")
	assert_eq(NpcSchedule.time_block_for_hour(13), "midday")
	assert_eq(NpcSchedule.time_block_for_hour(19), "evening")
	assert_eq(NpcSchedule.time_block_for_hour(23), "night")
	assert_eq(NpcSchedule.time_block_for_hour(2), "night", "night wraps past midnight as one block")


func test_the_entry_that_applies_now_is_the_one_for_this_block():
	var schedule := [
		{"time_block": "morning", "location_tag": "field", "activity": "work"},
		{"time_block": "night", "location_tag": "home", "activity": "sleep"},
	]
	assert_eq(NpcSchedule.current_entry(schedule, 8)["activity"], "work")
	assert_eq(NpcSchedule.current_entry(schedule, 23)["activity"], "sleep")


func test_a_block_the_schedule_has_no_entry_for_reports_nothing():
	assert_eq(NpcSchedule.current_entry([], 8)["activity"], "")



# -- a village does not turn as one ------------------------------------------
# Reported live: "every once in a while all villagers go to the well at the
# same time and then walk away a bit later all at the same time.. that looks
# very weird... Villager behaviour should be natural and organic; not
# scripted".
#
# Every villager read the same world hour, so every villager's day turned on
# the same tick. Nothing about their plans was wrong -- they were simply all
# keeping the same clock to the second.

func test_two_villagers_keep_slightly_different_hours():
	var early := NpcSchedule.personal_hour(12.0, 1)
	var late := NpcSchedule.personal_hour(12.0, 2)
	assert_ne(early, late, "two people do not rise and eat on the same tick")


func test_a_villagers_own_hour_is_the_same_every_day():
	assert_eq(NpcSchedule.personal_hour(9.0, 77), NpcSchedule.personal_hour(9.0, 77))
	assert_ne(
		NpcSchedule.personal_hour(9.0, 77), NpcSchedule.personal_hour(10.0, 77),
		"and it still follows the world's clock rather than replacing it"
	)


## The shift is a real spread across a village, not a rounding wobble: over a
## roster's worth of seeds, some villagers turn their day meaningfully before
## others.
func test_a_villages_worth_of_villagers_spreads_across_a_real_stretch():
	var earliest := INF
	var latest := -INF
	for seed_value in range(40):
		var shift: float = NpcSchedule.personal_hour(12.0, seed_value) - 12.0
		earliest = minf(earliest, shift)
		latest = maxf(latest, shift)
	assert_gt(latest - earliest, NpcSchedule.MAX_SHIFT_HOURS * 0.5, "they really arrive at different times")


## And never so far that somebody skips a block of their own day: the shift
## either side stays under half the shortest block, so every villager still
## works, socialises and sleeps in the order their plan says.
func test_nobody_is_shifted_out_of_a_block_of_their_own_day():
	assert_lt(NpcSchedule.MAX_SHIFT_HOURS * 0.5, _shortest_block_hours() * 0.5)
	for seed_value in range(40):
		var shift: float = absf(NpcSchedule.personal_hour(6.0, seed_value) - 6.0)
		assert_lte(shift, NpcSchedule.MAX_SHIFT_HOURS * 0.5 + 0.0001)


## Measured off the block boundaries themselves rather than typed in, so
## re-cutting the day cannot leave this test agreeing with a shift that is
## now too big.
func _shortest_block_hours() -> float:
	var shortest := INF
	var run := 0.0
	var previous := NpcSchedule.time_block_for_hour(0)
	for hour in range(1, 25):
		var block := NpcSchedule.time_block_for_hour(hour % 24)
		run += 1.0
		if block != previous:
			shortest = minf(shortest, run)
			run = 0.0
			previous = block
	return shortest


## An hour past midnight is still an hour: a villager shifted back over the
## boundary keeps a real hour-of-day rather than a negative one.
func test_a_shift_across_midnight_stays_a_real_hour():
	for seed_value in range(40):
		var shifted: float = NpcSchedule.personal_hour(0.0, seed_value)
		assert_between(shifted, 0.0, 24.0)
