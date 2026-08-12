extends Sprite2D

## The cheap local FSM half of docs/concept/npc.md's "Planning architecture":
## walks toward wherever the current schedule entry's location_tag resolves
## to, re-deriving the current entry from elapsed time every frame -- zero
## planner calls mid-day, matching CreatureWander/FishMarker's "pure,
## deterministic, no per-frame AI" philosophy rather than CreatureMarker's
## full sense/perceive/act loop (an NPC just walks its plan, it doesn't hunt
## or flee).

const NpcIdentity = preload("res://src/world/npc_identity.gd")
const NpcPlanner = preload("res://src/world/npc_planner.gd")
const NpcSchedule = preload("res://src/world/npc_schedule.gd")

## Walking pace -- similar order to CreatureWander.WANDER_SPEED, unhurried.
const WALK_SPEED := 20.0

## Real seconds per simulated in-game day, mirroring
## EarthChunkManager.SECONDS_PER_SIMULATED_DAY's existing pacing so a
## village's daily rhythm runs on the same clock as the rest of the world
## sim.
const SECONDS_PER_SIMULATED_DAY := 60.0

var identity: NpcIdentity
var home_position := Vector2.ZERO
## Where this NPC works when their occupation's location_tag isn't one of
## the settlement's 3 shared landmarks (well/stall/gate) -- see
## SettlementGenerator's scope note on not modeling per-occupation buildings
## yet.
var workspot_position := Vector2.ZERO
var landmarks: Dictionary = {}
var schedule: Array = []

var _elapsed_time := 0.0
var _day_index := 0
var _planner: NpcPlanner.Planner = NpcPlanner.FakeNpcPlanner.new()


## Swaps in a different planner (e.g. a future real LLM-backed one) -- see
## NpcPlanner.Planner. Defaults to the deterministic FakeNpcPlanner.
func set_planner(planner: NpcPlanner.Planner) -> void:
	_planner = planner


func _process(delta: float) -> void:
	_elapsed_time += delta
	if schedule.is_empty():
		schedule = _planner.plan_day(identity, _day_index)

	var entry := NpcSchedule.current_entry(schedule, _current_hour())
	var target := _resolve_location(entry.get("location_tag", "home"))
	position = position.move_toward(target, WALK_SPEED * delta)


func _current_hour() -> int:
	var day_fraction := fmod(_elapsed_time / SECONDS_PER_SIMULATED_DAY, 1.0)
	return int(day_fraction * 24.0)


## "home" is this NPC's own house; a shared landmark tag (well/stall/gate)
## resolves to the settlement's landmark; anything else (a work tag with no
## dedicated building yet, e.g. "field"/"forge") falls back to this NPC's
## personal workspot rather than an unresolved position.
func _resolve_location(tag: String) -> Vector2:
	if tag == "home":
		return home_position
	if landmarks.has(tag):
		return landmarks[tag]
	return workspot_position
