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
## job) if one is within `radius` (defaults to HOVER_RADIUS_PX), else an
## empty Dictionary. `radius` is an explicit param, not always the bare
## constant, so a caller can widen it -- see Spyglass.effective_hover_radius
## (docs/concept/wayfinding.md's Spyglass item), which World._update_hover_
## tooltip passes through here when a Spyglass is equipped.
func info_under(mouse_position: Vector2, candidates: Array, radius: float = HOVER_RADIUS_PX) -> Dictionary:
	var best := {}
	var best_distance := radius
	for candidate in candidates:
		var distance: float = mouse_position.distance_to(candidate["position"])
		if distance <= best_distance:
			best_distance = distance
			best = candidate
	return best
