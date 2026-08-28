extends RefCounted

## Pure targeting for a spell cast (docs/concept/spell_runtime.md). Mirrors
## melee_attack.gd's own shape (pure, index-based, testable without physics)
## but for a DIRECTED cast: melee's targets_in_range is a radius-only AOE
## sweep centered on the attacker, which is right for a sword swing and wrong
## for "self"/"touch"/"projectile"/"area" delivery -- a spell needs a facing
## cone for a directed shot and a resolved point (not the caster) for area.

const TOUCH_RANGE := 24.0
const PROJECTILE_RANGE := 120.0
const PROJECTILE_HALF_ANGLE_DEG := 30.0
const AREA_RADIUS := 40.0


## Index into candidate_positions nearest to caster_position, within `range`,
## with no facing requirement at all -- point-blank contact, same shape as
## EarthChunkManager.nearest_npc_near/nearest_liftable_stone_near's own
## "loop, track best-by-distance-within-range" skeleton. -1 if nothing
## qualifies.
func nearest_touch(caster_position: Vector2, candidate_positions: Array, range: float = TOUCH_RANGE) -> int:
	return _nearest_within(caster_position, candidate_positions, range)


## Index into candidate_positions nearest to caster_position, within `range`
## AND within `half_angle_deg` of `facing_direction` -- a directed shot. A
## zero-length facing direction can't define a cone, so it hits nothing
## rather than falling back to omnidirectional (the caller should already
## have a real last-moved-or-faced direction, per Player._last_facing_
## direction; a genuinely undefined one means "can't determine where this
## is even aimed").
func nearest_in_facing(
	caster_position: Vector2,
	facing_direction: Vector2,
	candidate_positions: Array,
	range: float = PROJECTILE_RANGE,
	half_angle_deg: float = PROJECTILE_HALF_ANGLE_DEG
) -> int:
	if facing_direction.length() < 0.001:
		return -1
	var facing := facing_direction.normalized()
	var best_index := -1
	var best_distance := INF
	for i in candidate_positions.size():
		var offset: Vector2 = candidate_positions[i] - caster_position
		var distance := offset.length()
		if distance < 0.001 or distance > range or distance >= best_distance:
			continue
		var angle_deg := rad_to_deg(absf(facing.angle_to(offset.normalized())))
		# A tiny epsilon, not a tuned threshold: a point constructed to sit
		# exactly at half_angle_deg via cos/sin can round-trip a few ULPs
		# past it through angle_to's own atan2, and the edge is meant to be
		# inclusive (see test_..._right_at_the_cone_edge).
		if angle_deg > half_angle_deg + 0.0001:
			continue
		best_distance = distance
		best_index = i
	return best_index


## Every index into candidate_positions within `radius` of `center` -- an
## instant AOE burst at a resolved point, structurally identical to
## MeleeAttack.targets_in_range except `center` is not assumed to be the
## caster's own position (see area_center).
func in_area(center: Vector2, candidate_positions: Array, radius: float = AREA_RADIUS) -> Array[int]:
	var hit_indices: Array[int] = []
	for i in candidate_positions.size():
		if center.distance_to(candidate_positions[i]) <= radius:
			hit_indices.append(i)
	return hit_indices


## The point an "area" cast centers on: a fixed distance in front of the
## caster along their facing direction, so the burst lands ahead of them
## rather than centered on their own feet. Falls back to the caster's own
## position with no facing direction, same "can't determine where this is
## aimed, so don't guess a direction" reasoning as nearest_in_facing.
func area_center(caster_position: Vector2, facing_direction: Vector2, distance: float = AREA_RADIUS) -> Vector2:
	if facing_direction.length() < 0.001:
		return caster_position
	return caster_position + facing_direction.normalized() * distance


func _nearest_within(origin: Vector2, candidate_positions: Array, range: float) -> int:
	var best_index := -1
	var best_distance := INF
	for i in candidate_positions.size():
		var distance := origin.distance_to(candidate_positions[i])
		if distance <= range and distance < best_distance:
			best_distance = distance
			best_index = i
	return best_index
