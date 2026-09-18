extends RefCounted

## Pure helpers for reading an NpcPlanner-produced daily schedule (an Array of
## {time_block, location_tag, activity}) -- what block of the day a given
## hour falls in, and which schedule entry is "current" for it. This is the
## cheap local half of docs/concept/npc.md's "Planning architecture": the FSM
## that walks an NPC through yesterday's plan reads only these, never calling
## a planner mid-day.

const TIME_BLOCKS: Array[String] = ["morning", "midday", "evening", "night"]

const _EMPTY_ENTRY := {"time_block": "", "location_tag": "", "activity": ""}


## Which of the 4 time blocks a given hour-of-day (0..23) falls in. Night
## wraps past midnight (22..23, 0..5) so a villager sleeps through it as one
## continuous block rather than two.
static func time_block_for_hour(hour: int) -> String:
	if hour < 6 or hour >= 22:
		return "night"
	if hour < 11:
		return "morning"
	if hour < 17:
		return "midday"
	return "evening"


## The schedule entry for time_block, or the empty sentinel if the schedule
## has none (e.g. an empty schedule from the base Planner).
static func entry_for_time_block(schedule: Array, time_block: String) -> Dictionary:
	for entry in schedule:
		if entry["time_block"] == time_block:
			return entry
	return _EMPTY_ENTRY


## The schedule entry that applies right now, for an hour-of-day.
static func current_entry(schedule: Array, hour: int) -> Dictionary:
	return entry_for_time_block(schedule, time_block_for_hour(hour))


## How far apart, at most, two villagers' own days may run, in hours.
##
## Reported live: *"every once in a while all villagers go to the well at the
## same time and then walk away a bit later all at the same time.. that looks
## very weird... Villager behaviour should be natural and organic; not
## scripted"*. Nothing about their plans was wrong -- every villager read the
## same world hour, so every villager's day turned on the same tick, and a
## whole village rose, worked, drank and slept in step to the second.
##
## Four hours, which is +/- two either side of the village clock. Under half
## the shortest block of the day (five hours), so a shifted villager still
## works, socialises and sleeps in the order their own plan says -- nobody is
## shifted clean out of a block. Test-pinned against the block boundaries
## themselves (test_npc_schedule.gd), so re-cutting the day cannot leave a
## shift behind that is now too big.
const MAX_SHIFT_HOURS := 4.0


## This villager's own hour of the day: the world's clock, shifted by a
## little that is theirs alone.
##
## Deterministic from `seed_value` -- the villager's own NpcIdentity seed --
## so somebody who rises early rises early every day, rather than jittering
## about from tick to tick. Wrapped into a real hour-of-day, so a villager
## shifted back across midnight keeps an hour anyone can read rather than a
## negative one.
static func personal_hour(hour_of_day: float, seed_value: int) -> float:
	return fposmod(hour_of_day + shift_hours_for(seed_value), 24.0)


## The shift that belongs to `seed_value`, in (-MAX_SHIFT_HOURS/2,
## +MAX_SHIFT_HOURS/2). Pure and stable: the same villager always gets the
## same one.
static func shift_hours_for(seed_value: int) -> float:
	var unit := float(absi(hash("%d_day_shift" % seed_value)) % 10000) / 10000.0
	return (unit - 0.5) * MAX_SHIFT_HOURS


## The schedule entry that applies to THIS villager right now -- their own
## hour, not the village's. The one callers should use; current_entry above
## stays for anything genuinely asking about the world's clock rather than a
## person's.
static func current_entry_for(schedule: Array, hour_of_day: float, seed_value: int) -> Dictionary:
	return entry_for_time_block(schedule, time_block_for_hour(int(personal_hour(hour_of_day, seed_value))))
