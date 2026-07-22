extends RefCounted

## Pure fill math for a health bar: how wide (in pixels) the "fill" portion
## should be for a given health/max_health, clamped to the bar's own width.


func fill_width(health: float, max_health: float, bar_width: float) -> float:
	if max_health <= 0.0:
		return 0.0
	return bar_width * clampf(health / max_health, 0.0, 1.0)
