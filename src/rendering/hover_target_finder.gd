extends RefCounted

## Pure "what's under the mouse" lookup for the hover tooltip (see
## World._update_hover_tooltip). Covers every hoverable entity -- animals,
## fish, ambient flyers, dropped items, stones, ore, trees, tall grass --
## via one shared group (GROUP_NAME); an entity joins it and answers
## get_display_name() (and, for anything with a player interaction,
## get_hover_actions()) to participate. Kept pure/testable; the actual
## Node2D group-scanning, action-label formatting (verb + live keybinding),
## and Label positioning live in World.gd (untested scene glue, same as
## this project's other top-level scene scripts, e.g. CreaturePanel).

const HOVER_RADIUS_PX := 20.0

## Every hoverable entity joins this one Godot group. Named generically
## (not "hoverable_animal") because it now covers non-animal interactables
## too -- see docs/progress.md's UI section for the full roster.
const GROUP_NAME := "hoverable"


## `candidates` is an Array of {"position": Vector2, "name": String,
## "actions": Array} (actions is a list of {"verb": String, "action":
## String} dicts, or [] for a name-only entity). Returns the closest
## candidate's full dict (untouched -- action formatting is the caller's
## job) if one is within HOVER_RADIUS_PX, else an empty Dictionary.
func info_under(mouse_position: Vector2, candidates: Array) -> Dictionary:
	var best := {}
	var best_distance := HOVER_RADIUS_PX
	for candidate in candidates:
		var distance: float = mouse_position.distance_to(candidate["position"])
		if distance <= best_distance:
			best_distance = distance
			best = candidate
	return best
