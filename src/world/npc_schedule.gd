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
