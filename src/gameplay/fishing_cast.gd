extends RefCounted

## Where a cast fishing line lands -- pure geometry so the visual bobber
## (Player._fishing_step) and the fish-attraction radius
## (EarthChunkManager.set_attraction_point) both target the same point.

## How far the line lands in front of the player.
const CAST_DISTANCE_PX := 28.0

const _DEFAULT_DIRECTION := Vector2.DOWN


func cast_point(player_position: Vector2, facing_direction: Vector2) -> Vector2:
	var direction := facing_direction
	if direction.length() < 0.01:
		direction = _DEFAULT_DIRECTION
	return player_position + direction.normalized() * CAST_DISTANCE_PX
