extends RefCounted

## Tracks which waypoints a player has unlocked out of the fixed world table
## below. Distinct from fast_travel.gd, which handles cost/cooldown math once
## a jump is attempted -- this module only concerns itself with which
## waypoint_ids are known/reachable.

## waypoint_id -> world position: Vector2
const KNOWN_WAYPOINTS := {
	"old_mill": Vector2(120.0, 40.0),
	"harbor_docks": Vector2(400.0, 260.0),
	"stonepeak_pass": Vector2(-300.0, 500.0),
	"sunken_ruins": Vector2(50.0, -600.0),
	"north_watch": Vector2(-150.0, -900.0),
}


## Returns a new array with waypoint_id added if it is known and not already
## present. Adding an unknown id or a duplicate is a documented no-op that
## returns the input unchanged; the caller's array is never mutated.
func unlock(unlocked: Array, waypoint_id: String) -> Array:
	if not KNOWN_WAYPOINTS.has(waypoint_id) or unlocked.has(waypoint_id):
		return unlocked
	var result: Array = unlocked.duplicate()
	result.append(waypoint_id)
	return result


func is_unlocked(unlocked: Array, waypoint_id: String) -> bool:
	return unlocked.has(waypoint_id)


## Every position for waypoint_ids present in both unlocked and the known
## table, filtering out any bogus entries that might have snuck into unlocked.
func reachable_waypoints(unlocked: Array) -> Array:
	var positions: Array = []
	for waypoint_id in unlocked:
		if KNOWN_WAYPOINTS.has(waypoint_id):
			positions.append(KNOWN_WAYPOINTS[waypoint_id])
	return positions


## The waypoint_id of the closest reachable waypoint to from_position, or ""
## if none are unlocked.
func nearest_unlocked(from_position: Vector2, unlocked: Array) -> String:
	var nearest_id: String = ""
	var nearest_distance: float = INF
	for waypoint_id in unlocked:
		if not KNOWN_WAYPOINTS.has(waypoint_id):
			continue
		var distance: float = from_position.distance_to(KNOWN_WAYPOINTS[waypoint_id])
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_id = waypoint_id
	return nearest_id
