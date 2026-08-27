extends GutTest

## NpcEncounter: which NPCs are at the same shared landmark right now (see
## docs/concept/npc.md "Memory, beliefs, and rumor propagation": "NPCs
## already meet at a settlement's shared landmarks... on their daily
## schedule"). Pure grouping logic -- the caller supplies each NPC's own
## schedule and a real, shared hour-of-day.

const NpcEncounter = preload("res://src/emergence/npc_encounter.gd")

const _MIDDAY_ENTRY := {"time_block": "midday", "location_tag": "well", "activity": "idle"}
const _EVENING_ENTRY := {"time_block": "evening", "location_tag": "well", "activity": "idle"}
const _HOME_ENTRY := {"time_block": "midday", "location_tag": "home", "activity": "idle"}


func test_two_npcs_at_the_same_landmark_are_grouped_together():
	var schedules := {
		"npc:1": [_MIDDAY_ENTRY],
		"npc:2": [_MIDDAY_ENTRY],
	}
	var groups := NpcEncounter.group_by_shared_landmark(schedules, 12)
	assert_eq(groups.get("well", []), ["npc:1", "npc:2"])


## A landmark with only ONE npc has nobody to meet -- not a group.
func test_a_solo_npc_at_a_landmark_forms_no_group():
	var schedules := {"npc:1": [_MIDDAY_ENTRY]}
	var groups := NpcEncounter.group_by_shared_landmark(schedules, 12)
	assert_eq(groups, {})


## "home" is never a shared meeting point -- every NPC's home is a
## different building, so two NPCs both "at home" have not actually met.
func test_npcs_at_home_are_never_grouped():
	var schedules := {
		"npc:1": [_HOME_ENTRY],
		"npc:2": [_HOME_ENTRY],
	}
	var groups := NpcEncounter.group_by_shared_landmark(schedules, 12)
	assert_eq(groups, {})


## Different real schedule entries for the same hour place NPCs at
## different landmarks -- they are not grouped just because they both have
## SOME schedule.
func test_npcs_at_different_landmarks_are_not_grouped():
	var schedules := {
		"npc:1": [_MIDDAY_ENTRY],
		"npc:2": [{"time_block": "midday", "location_tag": "gate", "activity": "idle"}],
	}
	var groups := NpcEncounter.group_by_shared_landmark(schedules, 12)
	# Neither landmark has 2+ npcs, so neither forms a group at all.
	assert_eq(groups, {})


## The real hour matters -- an NPC whose CURRENT entry (per the given hour)
## resolves to a different time block than another's does not meet them,
## even if both schedules mention the same landmark tag somewhere.
func test_the_real_hour_determines_which_schedule_entry_is_current():
	var schedules := {
		"npc:1": [_MIDDAY_ENTRY],
		"npc:2": [_EVENING_ENTRY],
	}
	var midday_groups := NpcEncounter.group_by_shared_landmark(schedules, 12)
	assert_eq(midday_groups, {})  # npc:2's current entry (evening) isn't "well" at hour 12


func test_an_npc_with_no_schedule_yet_is_skipped():
	var schedules := {
		"npc:1": [_MIDDAY_ENTRY],
		"npc:2": [],
	}
	var groups := NpcEncounter.group_by_shared_landmark(schedules, 12)
	# npc:2 is skipped (no schedule), leaving npc:1 alone at "well" -- not a group.
	assert_eq(groups, {})


func test_three_npcs_at_the_same_landmark_form_one_group_of_three():
	var schedules := {
		"npc:1": [_MIDDAY_ENTRY],
		"npc:2": [_MIDDAY_ENTRY],
		"npc:3": [_MIDDAY_ENTRY],
	}
	var groups := NpcEncounter.group_by_shared_landmark(schedules, 12)
	assert_eq(groups.get("well", []).size(), 3)
