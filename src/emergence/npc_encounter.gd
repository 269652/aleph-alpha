extends RefCounted

## Which NPCs are at the same shared landmark right now (docs/concept/npc.md
## "Memory, beliefs, and rumor propagation": "NPCs already meet at a
## settlement's shared landmarks (well/stall/gate) on their daily schedule
## (npc_schedule.gd) -- that existing contact point is where memory
## propagates... No new movement, scheduling, or social-graph code
## required -- it rides the schedule system that already exists").
##
## Pure grouping logic -- the caller (EarthChunkManager.step_npc_encounters)
## supplies each NPC's own already-real schedule (read straight off live
## NpcMarker state) and a REAL SHARED hour-of-day derived from the world
## clock. Deliberately NOT NpcMarker's own `_current_hour()`: that is a
## private per-marker clock (elapsed real seconds since THAT marker
## happened to spawn, never synced across markers) -- fine for its own
## walk-toward-target movement, useless for comparing two different NPCs'
## schedules against each other, which is exactly what grouping needs.

const NpcSchedule = preload("res://src/world/npc_schedule.gd")

## "home" is never a shared meeting point -- every NPC's home is a
## different building, so two NPCs both "at home" have not actually met.
## "" is the empty-schedule sentinel NpcSchedule.current_entry falls back
## to -- also never shared.
const _NON_SHARED_TAGS := ["home", ""]


## `npc_schedules`: Dictionary of npc_id -> schedule (Array, NpcMarker's own
## shape). Returns Dictionary of location_tag -> Array[String] (npc_ids),
## one entry per landmark with 2 OR MORE npcs currently there -- a landmark
## with only one npc has nobody to meet, so it is not a group.
static func group_by_shared_landmark(npc_schedules: Dictionary, hour: int) -> Dictionary:
	var by_tag: Dictionary = {}
	for npc_id in npc_schedules:
		var schedule: Array = npc_schedules[npc_id]
		if schedule.is_empty():
			continue
		var tag: String = NpcSchedule.current_entry(schedule, hour).get("location_tag", "")
		if _NON_SHARED_TAGS.has(tag):
			continue
		if not by_tag.has(tag):
			by_tag[tag] = []
		by_tag[tag].append(npc_id)

	var groups: Dictionary = {}
	for tag in by_tag:
		if by_tag[tag].size() >= 2:
			groups[tag] = by_tag[tag]
	return groups
