extends RefCounted

## Keeps a wandering animal from walking TOWARD a threat, without giving it
## an explicit "flee" state at all.
##
## Fleeing used to be the only thing that avoided the player -- ordinary idle
## wander ignored threats entirely. That meant a fleeing animal would run out
## of sensing range, drop back to plain wander, and (with no reason not to)
## often wander straight back toward a stationary player -- re-entering
## range and re-triggering flee. Repeated forever, that reads as pacing back
## and forth rather than fleeing (reported: "creatures who generally flee
## from the player simply don't try to walk in the direction facing the
## player before their movement").
##
## The fix is geometric, not a timer: a candidate step is decomposed into
## its component TOWARD the nearest threat and everything perpendicular to
## that. Any inward component is discarded; the perpendicular (sideways) part
## survives untouched. The animal can still wander freely away or sideways --
## it just never has a net closing velocity toward what it's avoiding, so it
## can't cross back into flee range under its own steam.
##
## Pure vector math, no nodes -- testable without a running creature.


func _init() -> void:
	pass


## `step` is the raw wander displacement (candidate_position - position);
## `to_threat` is the vector from position to the nearest threat. Returns a
## step with any component toward the threat removed.
##
## If the step is left with (almost) nothing after removing the inward part
## -- it was aimed nearly straight at the threat -- a small sideways nudge is
## substituted instead of returning a dead zero vector, so the animal still
## visibly moves rather than freezing in place.
static func away_biased_step(step: Vector2, to_threat: Vector2) -> Vector2:
	if to_threat.length_squared() < 0.0001:
		return step  # no threat to avoid
	var toward_unit := to_threat.normalized()
	var inward: float = maxf(0.0, step.dot(toward_unit))
	var biased := step - toward_unit * inward
	if biased.length() > 0.001:
		return biased
	# Aimed almost dead-on at the threat: step sideways (perpendicular to the
	# threat axis) at the same speed rather than stopping outright.
	var speed := step.length()
	if speed < 0.001:
		return step
	return Vector2(-toward_unit.y, toward_unit.x) * speed
