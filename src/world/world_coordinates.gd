extends RefCounted

## Wraps a coordinate onto a toroidal world of the given size: walking off
## any edge (including negative coordinates) lands on the opposite side.
func wrap(coordinate: Vector2i, world_size: Vector2i) -> Vector2i:
	return Vector2i(posmod(coordinate.x, world_size.x), posmod(coordinate.y, world_size.y))
