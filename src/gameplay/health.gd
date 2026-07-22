extends RefCounted

## Pure health/damage logic shared by the player and creature markers.


func take_damage(current_health: float, amount: float) -> float:
	return maxf(0.0, current_health - amount)


func heal(current_health: float, amount: float, max_health: float) -> float:
	return minf(max_health, current_health + amount)


func is_dead(current_health: float) -> bool:
	return current_health <= 0.0
