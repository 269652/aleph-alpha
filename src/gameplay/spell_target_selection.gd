extends RefCounted

## Explicit spell target selection (docs/concept/spell_runtime.md, "Explicit
## target selection") -- pure, index/identity-based, the same shape
## SpellTargeting/HoverTargetFinder already establish: a loop over an
## already-filtered candidate list, nothing about the scene tree, nothing
## about which creatures qualify (that is the caller's job, same as
## SpellTargeting never scans groups itself). Two independent questions:
## "what comes next in the cycle" (identity, no positions needed) and
## "what did a click land on" (position, no identity needed).

const CreatureMarker = preload("res://src/rendering/creature_marker.gd")
const HoverTargetFinder = preload("res://src/rendering/hover_target_finder.gd")

## How far out a hostile creature can join the selectable pool -- read from
## CreatureMarker, not restated: CAUTION_RADIUS already means "a creature's
## own behaviour changes because it has noticed you", which is the
## right-shaped answer to "how far out can the player select something",
## not a second number invented for this feature alone.
const TARGET_RADIUS := CreatureMarker.CAUTION_RADIUS

## Click tolerance for "which creature did this click land on" -- the same
## tolerance the hover tooltip already uses for every other clickable thing
## in the world (HoverTargetFinder.HOVER_RADIUS_PX), not a second tuned
## radius.
const CLICK_RADIUS := HoverTargetFinder.HOVER_RADIUS_PX


## The next candidate in `candidates` (already ordered nearest-first by the
## caller) after `current`, wrapping back to the first past the last.
## `current` not present in `candidates` -- dead, despawned, or walked out
## of TARGET_RADIUS since the last press -- restarts the cycle at the
## first (nearest) candidate rather than advancing from a position the
## list no longer contains, which would be arbitrary once "it" is gone.
## Null when there is nothing to select at all.
static func next_target(candidates: Array, current):
	if candidates.is_empty():
		return null
	var current_index := candidates.find(current)
	if current_index == -1:
		return candidates[0]
	return candidates[(current_index + 1) % candidates.size()]


## Index into `candidate_positions` nearest `click_position`, within
## `radius` -- the same "loop, track best-by-distance-within-range"
## skeleton SpellTargeting._nearest_within/HoverTargetFinder.info_under
## already use, kept as its own copy (a different pure module, a different
## candidate shape: this one bare positions, not {"position": ...} dicts)
## rather than inventing a shared base for three small callers. -1 when
## nothing qualifies.
static func index_at_point(click_position: Vector2, candidate_positions: Array, radius: float = CLICK_RADIUS) -> int:
	var best_index := -1
	var best_distance := radius
	for i in candidate_positions.size():
		var distance: float = click_position.distance_to(candidate_positions[i])
		if distance <= best_distance:
			best_distance = distance
			best_index = i
	return best_index
