extends RefCounted

## Pure "what's under the mouse" lookup for the animal-name hover tooltip
## (see World._update_hover_tooltip) -- given the mouse's world position and
## a list of nearby hoverable candidates, finds the closest one within
## HOVER_RADIUS_PX and returns its display name, or "" if nothing qualifies.
## Kept pure/testable; the actual Node2D group-scanning and Label
## positioning live in World.gd (untested scene glue, same as this
## project's other top-level scene scripts, e.g. CreaturePanel).

const HOVER_RADIUS_PX := 20.0


## `candidates` is an Array of {"position": Vector2, "name": String}.
func name_under(mouse_position: Vector2, candidates: Array) -> String:
	var best_name := ""
	var best_distance := HOVER_RADIUS_PX
	for candidate in candidates:
		var distance: float = mouse_position.distance_to(candidate["position"])
		if distance <= best_distance:
			best_distance = distance
			best_name = candidate["name"]
	return best_name
