extends RefCounted

## May this piece go on this cell (see
## docs/concept/building.md#placement-rules).
##
## Pure logic over a grid, deliberately: the player's build cursor and the
## village generator ask the same question of the same code, so anything
## true of a player's house is true of a villager's. Nothing here knows
## about biomes, chunks or nodes -- callers pass a `buildable_ground`
## Callable that answers "is this cell's terrain buildable", so water and
## cliff rules live with the world, not with the rules of construction.
##
## The rules exist to stop floating nonsense, not to nag: a wall belongs to
## a building, a roof belongs over a room, and nothing may overlap.

const BuildingPiece = preload("res://src/gameplay/building_piece.gd")

## Cardinal neighbours -- a wall is "attached" if a floor is on or beside it.
const _NEIGHBORS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]


## `grid`: Vector2i cell -> piece_id for everything standing on the ground
## plane. `roofs` is a separate layer (roofs sit ABOVE the room, so they
## legitimately share a cell with the floor below them).
func can_place(
	piece_id: String,
	cell: Vector2i,
	grid: Dictionary,
	buildable_ground: Callable,
	roofs: Dictionary = {}
) -> bool:
	return refusal_reason(piece_id, cell, grid, buildable_ground, roofs) == ""


## Why a placement is refused, or "" when it is legal. The build cursor
## should explain itself rather than silently doing nothing.
func refusal_reason(
	piece_id: String,
	cell: Vector2i,
	grid: Dictionary,
	buildable_ground: Callable,
	roofs: Dictionary = {}
) -> String:
	if not BuildingPiece.has_piece(piece_id):
		return "Unknown piece."

	var category := BuildingPiece.category_of(piece_id)

	# Roofs live on their own layer above the room.
	if category == BuildingPiece.CATEGORY_ROOF:
		if roofs.has(cell):
			return "There is already a roof here."
		if BuildingPiece.category_of(grid.get(cell, "")) != BuildingPiece.CATEGORY_FLOOR:
			return "A roof needs a floor beneath it."
		return ""

	if grid.has(cell):
		return "Something is already built here."

	if not buildable_ground.call(cell):
		return "You can't build on this ground."

	if category == BuildingPiece.CATEGORY_FLOOR:
		return ""

	# Walls, doors and windows belong to a building: they must stand on or
	# beside a floor, so they can't be strung across open wilderness.
	if _touches_floor(cell, grid):
		return ""
	return "This must be built on or beside a floor."


## The materials returned by removing a piece -- the same cost it took to
## build, mirroring the existing build/destroy loop.
func refund_for(piece_id: String) -> Dictionary:
	return BuildingPiece.cost_of(piece_id)


func _touches_floor(cell: Vector2i, grid: Dictionary) -> bool:
	if BuildingPiece.category_of(grid.get(cell, "")) == BuildingPiece.CATEGORY_FLOOR:
		return true
	for offset in _NEIGHBORS:
		if BuildingPiece.category_of(grid.get(cell + offset, "")) == BuildingPiece.CATEGORY_FLOOR:
			return true
	return false
