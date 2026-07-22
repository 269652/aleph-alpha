extends RefCounted

## Pure targeting logic for a melee swing: which nearby positions are in
## range, and what knockback vector each should receive -- kept separate from
## Player so the "who gets hit" and "which way do they fly" math is testable
## without CharacterBody2D physics.


## Damage a swing deals: the equipped weapon's damage, or unarmed_damage if
## nothing (or a non-weapon item) is equipped.
func attack_damage(weapon, unarmed_damage: float) -> float:
	if weapon != null and weapon.is_weapon():
		return weapon.weapon_damage
	return unarmed_damage


## Returns the indices into candidate_positions that fall within `range` of
## attacker_position (an AOE swing, not single-target).
func targets_in_range(attacker_position: Vector2, candidate_positions: Array, range: float) -> Array[int]:
	var hit_indices: Array[int] = []
	for i in candidate_positions.size():
		if attacker_position.distance_to(candidate_positions[i]) <= range:
			hit_indices.append(i)
	return hit_indices


## A vector of length `force` pointing from the attacker toward the target.
## Exactly-overlapping positions (degenerate zero-length direction) fall back
## to an arbitrary fixed direction rather than a zero vector, so a knockback
## always actually displaces the target.
func knockback_vector(attacker_position: Vector2, target_position: Vector2, force: float) -> Vector2:
	var direction := target_position - attacker_position
	if direction.length() < 0.001:
		direction = Vector2.DOWN
	return direction.normalized() * force
