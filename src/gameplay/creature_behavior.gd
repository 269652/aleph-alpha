extends RefCounted

## Pure decision logic for creature AI: given what a creature senses around it
## (threats, prey, food/water directions) plus its own temperament, health and
## needs, decides what it should do this frame and which way to move. No engine
## dependency -- CreatureMarker gathers the context and applies the result.
##
## Priority (most urgent first):
##   1. A nearby threat -> flee (calm, or weak) / attack (aggressive AND strong)
##   2. Thirsty -> seek water (in reach) or search for it (roam) if none sensed
##   3. Hungry predator with prey in reach -> hunt (its way of feeding)
##   4. Hungry -> seek food (in reach) or search for it (roam) if none sensed
##   5. Nothing pressing -> wander
##
## "seek_*" heads toward a sensed resource; "search_*" means the need exists
## but nothing's in range, so the creature should roam to look (the caller
## supplies the roaming heading, same as it does for "wander").

## A creature only stands and fights a threat if it's at least this healthy;
## below it, even an aggressive creature flees ("weak monsters should flee").
const STRONG_HEALTH_FRACTION := 0.5

## Fallback so a creature exactly overlapping a threat still flees somewhere
## rather than producing a zero-length (no-op) direction.
const OVERLAP_FALLBACK := Vector2.UP


func decide(context: Dictionary) -> Dictionary:
	var position: Vector2 = context["position"]
	var threats: Array = context["threats"]
	var prey: Array = context["prey"]

	if not threats.is_empty() and _perceives_threats(context):
		var nearest_threat := _nearest(position, threats)
		if _will_fight(context):
			return {"intent": "attack", "direction": _toward(position, nearest_threat)}
		return {"intent": "flee", "direction": _away_from(position, nearest_threat)}

	if context["thirsty"]:
		var water_direction: Vector2 = context["water_direction"]
		if water_direction != Vector2.ZERO:
			return {"intent": "seek_water", "direction": water_direction.normalized()}
		return {"intent": "search_water", "direction": Vector2.ZERO}

	if context["is_predator"] and context["hungry"] and not prey.is_empty():
		var nearest_prey := _nearest(position, prey)
		return {"intent": "hunt", "direction": _toward(position, nearest_prey)}

	if context["hungry"]:
		var food_direction: Vector2 = context["food_direction"]
		if food_direction != Vector2.ZERO:
			return {"intent": "seek_food", "direction": food_direction.normalized()}
		return {"intent": "search_food", "direction": Vector2.ZERO}

	return {"intent": "wander", "direction": Vector2.ZERO}


## An aggressive creature that's still strong enough stands and fights;
## everything else (calm, or weakened) flees.
func _will_fight(context: Dictionary) -> bool:
	return context["temperament"] == "aggressive" and context["health_fraction"] >= STRONG_HEALTH_FRACTION


## Whether this creature reacts to `threats` at all this tick (docs/concept/
## worldbosses.md: "bosses should not attack low-level players on their
## own, even if they attack -- only if they deal actual damage do they pull
## aggro"). An ordinary creature always perceives threats, unchanged. A
## world boss perceives NONE of them -- doesn't attack, and doesn't flee
## either, which a bare "skip only the attack branch" gate would have
## accidentally produced by falling through to the flee case -- until
## BossAggro/CreatureMarker.take_damage has flipped is_aggroed on via a
## real hit. `.get(..., false)` defaults both new keys to "ordinary
## creature" so a context dict built before this feature existed (as every
## test predating it does) keeps behaving exactly as it always did.
func _perceives_threats(context: Dictionary) -> bool:
	if not context.get("is_world_boss", false):
		return true
	return context.get("is_aggroed", false)


func _nearest(origin: Vector2, points: Array) -> Vector2:
	var best: Vector2 = points[0]
	var best_distance := origin.distance_squared_to(best)
	for point in points:
		var distance: float = origin.distance_squared_to(point)
		if distance < best_distance:
			best = point
			best_distance = distance
	return best


func _toward(origin: Vector2, target: Vector2) -> Vector2:
	var direction := target - origin
	if direction.length() < 0.001:
		return OVERLAP_FALLBACK
	return direction.normalized()


func _away_from(origin: Vector2, target: Vector2) -> Vector2:
	var direction := origin - target
	if direction.length() < 0.001:
		return OVERLAP_FALLBACK
	return direction.normalized()
