extends RefCounted

const BLUEPRINTS: Dictionary = {
	"small_house": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)],
	"wall_segment": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)],
	"l_shape_workshop": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(0, 2)],
}


## Absolute tile coordinates a blueprint occupies when anchored at anchor, or [] if unknown.
func footprint_tiles(blueprint_id: String, anchor: Vector2i) -> Array:
	if not BLUEPRINTS.has(blueprint_id):
		return []
	var tiles: Array = []
	for offset in BLUEPRINTS[blueprint_id]:
		tiles.append(anchor + offset)
	return tiles


## True only if the blueprint is known and none of its tiles overlap occupied_tiles.
func can_place(blueprint_id: String, anchor: Vector2i, occupied_tiles: Array) -> bool:
	if not BLUEPRINTS.has(blueprint_id):
		return false
	for tile in footprint_tiles(blueprint_id, anchor):
		if occupied_tiles.has(tile):
			return false
	return true


func blueprint_ids() -> Array:
	return BLUEPRINTS.keys()
