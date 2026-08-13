extends RefCounted

## A seed and a footprint become a list of building pieces (see
## docs/concept/building.md#one-system-two-builders).
##
## This is what makes an NPC village house a REAL house rather than a
## painted sprite: the settlement generator stamps blueprints built from the
## very same pieces the player places by hand, so a villager's house
## encloses a real room the player can walk into, on the same terms as one
## they built themselves.
##
## Pure logic -- returns cells, places nothing. The caller decides where the
## footprint sits in the world and how the pieces get into a chunk.

const BuildingPiece = preload("res://src/gameplay/building_piece.gd")
const PixelNoise = preload("res://src/rendering/pixel_noise.gd")

## The smallest footprint that can hold an interior: a wall ring plus at
## least one interior cell needs 3x3.
const MINIMUM_FOOTPRINT := 3


## The house's ground-plane pieces: Vector2i cell (relative to the
## footprint's top-left) -> piece_id. A wall ring around a floor interior,
## with exactly one door punched through the wall.
##
## Returns an empty Dictionary for a footprint too small to hold a room --
## a caller asking for a 2x2 house gets nothing rather than a malformed one.
func build(
	footprint: Vector2i,
	seed_value: int,
	material: String = BuildingPiece.MATERIAL_WOOD
) -> Dictionary:
	if footprint.x < MINIMUM_FOOTPRINT or footprint.y < MINIMUM_FOOTPRINT:
		return {}

	var pieces := {}
	for x in footprint.x:
		for y in footprint.y:
			var cell := Vector2i(x, y)
			var on_edge := x == 0 or y == 0 or x == footprint.x - 1 or y == footprint.y - 1
			pieces[cell] = _piece(BuildingPiece.CATEGORY_WALL if on_edge else BuildingPiece.CATEGORY_FLOOR, material)

	pieces[_door_cell(footprint, seed_value)] = _piece(BuildingPiece.CATEGORY_DOOR, material)
	return pieces


## The roof layer, covering the interior. Separate from `build` because
## roofs sit ABOVE the room rather than on its plane (see
## BuildingPlacement), so they live on their own layer.
func build_roofs(
	footprint: Vector2i,
	_seed_value: int,
	material: String = BuildingPiece.MATERIAL_WOOD
) -> Dictionary:
	if footprint.x < MINIMUM_FOOTPRINT or footprint.y < MINIMUM_FOOTPRINT:
		return {}
	var roofs := {}
	for x in range(1, footprint.x - 1):
		for y in range(1, footprint.y - 1):
			roofs[Vector2i(x, y)] = _piece(BuildingPiece.CATEGORY_ROOF, material)
	return roofs


## Where the single door goes: somewhere along the wall ring, never a
## corner (a corner door would open into the wall's own thickness). Seeded,
## so a village's houses face different ways instead of reading as one hut
## stamped repeatedly.
func _door_cell(footprint: Vector2i, seed_value: int) -> Vector2i:
	# Candidate positions: the non-corner cells of each of the four walls.
	var candidates: Array[Vector2i] = []
	for x in range(1, footprint.x - 1):
		candidates.append(Vector2i(x, 0))
		candidates.append(Vector2i(x, footprint.y - 1))
	for y in range(1, footprint.y - 1):
		candidates.append(Vector2i(0, y))
		candidates.append(Vector2i(footprint.x - 1, y))
	if candidates.is_empty():
		return Vector2i(1, 0)
	return candidates[PixelNoise.range_index(seed_value, footprint.x, footprint.y, candidates.size())]


func _piece(category: String, material: String) -> String:
	return "%s_%s" % [material, category]
