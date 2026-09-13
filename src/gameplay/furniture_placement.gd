extends RefCounted

## May this furniture piece go on this cell (see docs/concept/housing.md's
## "Interior furniture" section).
##
## Pure logic over two grids, the exact "the player's build cursor and the
## village generator ask the same question of the same code" shape
## BuildingPlacement already establishes for the ground layer -- nothing
## here knows about biomes, chunks or nodes. Deliberately its OWN module
## rather than a branch inside BuildingPlacement: unlike a roof (which only
## needs "a floor beneath it"), furniture needs the cell to be genuinely
## INDOORS -- a real, walled, enclosed room via RoomDetector, not merely
## resting on a floor piece that happens to exist. That is a different
## question from anything BuildingPlacement already answers, not a
## duplicate of one.
##
## `ground_grid`: Vector2i cell -> piece_id for the structural ground plane
## (walls/floor/door/window/roof-bearing pieces), the same grid
## BuildingPlacement/RoomDetector already read. `furniture_grid`: Vector2i
## cell -> furniture piece_id, its OWN layer -- mirrors Chunk.
## roof_modifications' own reasoning exactly: a table sits ON a floor the
## same way a roof sits above a room, and one modification dict can only
## ever hold one piece per cell, so furniture needs a separate Dictionary
## to coexist with the floor underneath it.

const BuildingPiece = preload("res://src/gameplay/building_piece.gd")
const RoomDetector = preload("res://src/gameplay/room_detector.gd")

var _room_detector := RoomDetector.new()


func can_place(piece_id: String, cell: Vector2i, ground_grid: Dictionary, furniture_grid: Dictionary) -> bool:
	return refusal_reason(piece_id, cell, ground_grid, furniture_grid) == ""


## Why a placement is refused, or "" when it is legal -- mirrors
## BuildingPlacement.refusal_reason's own "explain itself" convention.
func refusal_reason(
	piece_id: String, cell: Vector2i, ground_grid: Dictionary, furniture_grid: Dictionary
) -> String:
	if not BuildingPiece.has_piece(piece_id):
		return "Unknown piece."
	if BuildingPiece.category_of(piece_id) != BuildingPiece.CATEGORY_FURNITURE:
		return "Not a piece of furniture."
	if furniture_grid.has(cell):
		return "Something is already furnishing this spot."
	if BuildingPiece.category_of(ground_grid.get(cell, "")) != BuildingPiece.CATEGORY_FLOOR:
		return "Furniture needs a real floor beneath it."
	if not _room_detector.is_indoors(cell, ground_grid):
		return "Furniture must be placed inside a real, enclosed room."
	return ""
