extends RefCounted
## Path scarring: repeated walking wears grass into visible dirt paths;
## unwalked tiles slowly recover. Pure logic — worn tiles can be rendered
## via TerrainRenderer's EARTH_TILE_ID modification system.

const WEAR_PER_STEP := 0.08
const WORN_THRESHOLD := 1.0
const DECAY_PER_SECOND := 0.01
const MAX_WEAR := 1.5

var _wear: Dictionary = {}


func step_on(tile: Vector2i) -> void:
	_wear[tile] = minf(_wear.get(tile, 0.0) + WEAR_PER_STEP, MAX_WEAR)


func advance(delta: float) -> void:
	if delta <= 0.0:
		return
	var decay := DECAY_PER_SECOND * delta
	for tile in _wear.keys():
		var remaining: float = _wear[tile] - decay
		if remaining <= 0.0:
			_wear.erase(tile)
		else:
			_wear[tile] = remaining


func wear_at(tile: Vector2i) -> float:
	return _wear.get(tile, 0.0)


func is_worn(tile: Vector2i) -> bool:
	return wear_at(tile) >= WORN_THRESHOLD


func worn_tiles(threshold: float = WORN_THRESHOLD) -> Array:
	var result: Array = []
	for tile in _wear:
		if _wear[tile] >= threshold:
			result.append(tile)
	return result


func tracked_tile_count() -> int:
	return _wear.size()
