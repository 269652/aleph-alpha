extends GutTest

## The upper floor's own interior furniture (docs/concept/housing.md's
## "Interior furniture" section) -- reported directly alongside two-story
## houses themselves ("no room decoration"), then again ("no do both
## floors"): ground-floor furnishing (`EarthChunkManager.furnish_house_
## at_global`, occupation-linked via `HouseDecor`) already has its own real
## coverage in `test_earth_chunk_manager.gd`. This file covers only what's
## NEW here: `furnish_upper_floor_at_global`'s own real mechanics -- real
## placement validation against the UPPER floor's own grid, the two
## floors' real independence at the identical cell, and the upper floor's
## own real hide-in-lockstep visibility rule (deliberately the OPPOSITE of
## ground furniture's own "never hidden" rule -- see Chunk.upper_floor_
## furniture_modifications' own doc comment for why).
##
## Uses `_load_chunk` directly rather than `update()` (see CONTRIBUTING.md /
## test_earth_chunk_manager.gd's own known-slow-file note).

const EarthChunkManager = preload("res://src/world/earth_chunk_manager.gd")
const BuildingPiece = preload("res://src/gameplay/building_piece.gd")

var manager: EarthChunkManager
var tile_map_layer: TileMapLayer
var entities_parent: Node2D
var creatures_parent: Node2D
var _chunk_coord := Vector2i(0, 0)
var _origin := Vector2i(4, 4)  # comfortably inside the origin chunk


func before_each():
	tile_map_layer = TileMapLayer.new()
	entities_parent = Node2D.new()
	creatures_parent = Node2D.new()
	manager = EarthChunkManager.new(tile_map_layer, entities_parent, creatures_parent)
	add_child(entities_parent)
	manager._load_chunk(_chunk_coord)


func after_each():
	tile_map_layer.free()
	entities_parent.free()
	creatures_parent.free()


## A real, genuinely ENCLOSED 3x3 room (FurniturePlacement.can_place's own
## real rule requires RoomDetector.is_indoors, not merely "there is a
## floor here" -- a bare, wall-less floor cell reads as open ground, not a
## room, the same way it would for a player's own build cursor). `center`
## is the one real FLOOR cell (footprint-local, matching `furnish_upper_
## floor_at_global`'s own frame); every cell around it is a real wall.
func _room_grid(center: Vector2i) -> Dictionary:
	var grid := {}
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			var cell := center + Vector2i(dx, dy)
			grid[cell] = "wood_floor" if cell == center else "wood_wall"
	return grid


## Stamps a real enclosed room directly onto the upper floor (piece by
## piece, via the real per-cell build_upper_floor_at_global -- the same
## entry point BuilderMarker itself uses), so both FurniturePlacement's own
## RoomDetector call and _update_upper_floor_visibility's have a genuine
## room to find.
func _build_real_upper_room() -> void:
	var grid := _room_grid(Vector2i(0, 0))
	for cell in grid:
		var global_cell: Vector2i = _origin + cell
		manager.build_upper_floor_at_global(global_cell.x, global_cell.y, grid[cell])


func test_furnish_upper_floor_at_global_places_a_real_piece_onto_real_upper_floor():
	_build_real_upper_room()
	var placed: int = manager.furnish_upper_floor_at_global(_chunk_coord, _origin, _room_grid(Vector2i(0, 0)), ["wood_bed"])
	assert_eq(placed, 1)
	assert_eq(manager.upper_floor_furniture_at_global(_origin.x, _origin.y), "wood_bed")


## The same real FurniturePlacement.can_place rule the ground floor's own
## furnish_house_at_global already enforces -- validated against the
## UPPER floor's own real grid (chunk.upper_floor_modifications), never
## the ground floor's.
func test_furnish_upper_floor_at_global_refuses_a_cell_that_isnt_real_upper_floor():
	# No real upper-floor piece built at all -- upper_floor_modifications
	# stays empty, so the one cell in `upper_pieces` below (footprint-local
	# floor) has nothing real backing it on the actual upper layer yet.
	var placed: int = manager.furnish_upper_floor_at_global(
		_chunk_coord, _origin, {Vector2i(0, 0): "wood_floor"}, ["wood_chair"]
	)
	assert_eq(placed, 0, "furniture must never land where the real upper floor has no matching piece")
	assert_eq(manager.upper_floor_furniture_at_global(_origin.x, _origin.y), "")


## The two floors' furniture must never collide -- a real regression test
## for the exact reason the upper floor needed its own layer rather than
## reusing chunk.furniture_modifications for both.
func test_ground_and_upper_floor_furniture_coexist_independently_at_the_same_cell():
	_build_real_upper_room()
	manager.build_at_global(_origin.x, _origin.y, "wood_floor")  # a real ground floor cell at the SAME (x, y)
	manager.furnish_house_at_global(_chunk_coord, _origin, {Vector2i(0, 0): "wood_floor"}, ["wood_table"])
	manager.furnish_upper_floor_at_global(_chunk_coord, _origin, _room_grid(Vector2i(0, 0)), ["wood_bed"])
	assert_eq(manager.furniture_at_global(_origin.x, _origin.y), "wood_table")
	assert_eq(manager.upper_floor_furniture_at_global(_origin.x, _origin.y), "wood_bed")


# -- the upper floor's own hide-in-lockstep rule -----------------------------
#
# Ground furniture is never hidden by anything (nothing occludes the ground
# layer's own room from a bird's-eye view). The upper floor's own room
# genuinely IS hidden while a player stands inside it -- its furniture must
# hide in the same step, or it would float visibly over bare ground with no
# walls or floor around it.

func test_upper_floor_furniture_hides_while_the_player_stands_in_that_room():
	var upper_floor_layer := TileMapLayer.new()
	add_child(upper_floor_layer)
	manager.set_upper_floor_layer(upper_floor_layer)
	var upper_floor_furniture_layer := TileMapLayer.new()
	add_child(upper_floor_furniture_layer)
	manager.set_upper_floor_furniture_layer(upper_floor_furniture_layer)

	_build_real_upper_room()
	manager.furnish_upper_floor_at_global(_chunk_coord, _origin, _room_grid(Vector2i(0, 0)), ["wood_bed"])
	assert_ne(
		upper_floor_furniture_layer.get_cell_source_id(_origin), -1,
		"precondition: the bed should be painted while nobody is standing in the room"
	)

	manager.set_current_player_floor(1)
	manager._update_upper_floor_visibility(_origin)

	assert_eq(
		upper_floor_furniture_layer.get_cell_source_id(_origin), -1,
		"the bed should hide in lockstep with the room's own walls/floor while the player stands inside it"
	)

	upper_floor_layer.free()
	upper_floor_furniture_layer.free()


func test_upper_floor_furniture_reappears_once_the_player_leaves_the_room():
	var upper_floor_layer := TileMapLayer.new()
	add_child(upper_floor_layer)
	manager.set_upper_floor_layer(upper_floor_layer)
	var upper_floor_furniture_layer := TileMapLayer.new()
	add_child(upper_floor_furniture_layer)
	manager.set_upper_floor_furniture_layer(upper_floor_furniture_layer)

	_build_real_upper_room()
	manager.furnish_upper_floor_at_global(_chunk_coord, _origin, _room_grid(Vector2i(0, 0)), ["wood_bed"])
	manager.set_current_player_floor(1)
	manager._update_upper_floor_visibility(_origin)

	# Stepping back downstairs and far away from the room.
	manager.set_current_player_floor(0)
	manager._update_upper_floor_visibility(_origin + Vector2i(20, 20))

	assert_ne(
		upper_floor_furniture_layer.get_cell_source_id(_origin), -1,
		"the bed should be restored once nobody is standing in the room any more"
	)

	upper_floor_layer.free()
	upper_floor_furniture_layer.free()
