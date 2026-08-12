extends GutTest

## NpcMarker: the cheap local FSM half of docs/concept/npc.md's "Planning
## architecture" -- walks toward wherever its current schedule entry's
## location_tag resolves to (home / a shared village landmark / a personal
## workspot for occupations without a dedicated building yet), zero planner
## calls mid-day. Deliberately much lighter than CreatureMarker/FishMarker's
## AI -- just "walk toward today's plan".

const NpcMarker = preload("res://src/rendering/npc_marker.gd")
const NpcIdentity = preload("res://src/world/npc_identity.gd")

var marker: NpcMarker


func before_each():
	marker = NpcMarker.new()
	marker.identity = NpcIdentity.new(1)
	marker.home_position = Vector2(1000, 1000)
	marker.workspot_position = Vector2(1000, 1050)
	marker.landmarks = {"well": Vector2(900, 900), "stall": Vector2(950, 900), "gate": Vector2(850, 900)}
	marker.position = Vector2(1000, 1000)
	add_child(marker)


func after_each():
	remove_child(marker)
	marker.free()


func test_lazily_generates_a_schedule_on_first_process():
	assert_eq(marker.schedule.size(), 0)
	marker._process(0.1)
	assert_gt(marker.schedule.size(), 0)


func test_position_moves_toward_the_resolved_target():
	# Force a schedule where "night" (a reachable hour) sends the NPC home,
	# and start away from home so movement is observable.
	marker.schedule = [
		{"time_block": "morning", "location_tag": "home", "activity": "idle"},
		{"time_block": "midday", "location_tag": "home", "activity": "idle"},
		{"time_block": "evening", "location_tag": "home", "activity": "idle"},
		{"time_block": "night", "location_tag": "home", "activity": "sleep"},
	]
	marker.position = Vector2(1000, 1200)  # far from home_position (1000, 1000)
	var before_distance: float = marker.position.distance_to(marker.home_position)

	marker._process(0.5)

	assert_lt(marker.position.distance_to(marker.home_position), before_distance)


func test_resolves_a_landmark_tag_to_the_shared_landmark_position():
	marker.schedule = [
		{"time_block": "morning", "location_tag": "stall", "activity": "work"},
		{"time_block": "midday", "location_tag": "stall", "activity": "work"},
		{"time_block": "evening", "location_tag": "stall", "activity": "work"},
		{"time_block": "night", "location_tag": "stall", "activity": "work"},
	]
	marker.position = Vector2(0, 0)
	for i in 200:
		marker._process(1.0)
	assert_lt(marker.position.distance_to(marker.landmarks["stall"]), 1.0)


## An occupation whose work tag isn't one of the 3 shared landmarks (e.g.
## "field") falls back to the NPC's own personal workspot rather than
## crashing on a missing landmark.
func test_resolves_a_non_landmark_work_tag_to_the_personal_workspot():
	marker.schedule = [
		{"time_block": "morning", "location_tag": "field", "activity": "work"},
		{"time_block": "midday", "location_tag": "field", "activity": "work"},
		{"time_block": "evening", "location_tag": "field", "activity": "work"},
		{"time_block": "night", "location_tag": "field", "activity": "work"},
	]
	marker.position = Vector2(0, 0)
	for i in 200:
		marker._process(1.0)
	assert_lt(marker.position.distance_to(marker.workspot_position), 1.0)
