extends RefCounted

## Pure logic for "which tile is the player facing" -- used by build/destroy
## actions. Picks the dominant axis of the facing direction (4-directional,
## matching CharacterView's own facing model) rather than 8-directional/diagonal.


func facing_tile(player_tile: Vector2i, facing_direction: Vector2) -> Vector2i:
	if facing_direction.length() < 0.01:
		return player_tile

	if absf(facing_direction.x) > absf(facing_direction.y):
		return player_tile + Vector2i(1 if facing_direction.x > 0.0 else -1, 0)
	return player_tile + Vector2i(0, 1 if facing_direction.y > 0.0 else -1)
