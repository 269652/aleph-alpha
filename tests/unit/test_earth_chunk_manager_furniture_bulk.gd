extends GutTest

## Bulk interior furniture placement (docs/concept/housing.md's "Interior
## furniture" section) -- reported directly alongside two-story houses
## themselves ("no room decoration... no do both floors"): NPC-generated
## houses never got any furniture at all before this, on either floor.
## stamp_furniture_at_global/stamp_upper_floor_furniture_at_global are the
## real, bulk (one call per house, not one repaint per piece) entry points
## VillageRenderer uses -- see test_village_renderer.gd's own furniture
## tests for that wiring. This file covers the real EarthChunkManager
## mechanics directly: real placement validation, the two floors' real
## independence, and the upper floor's own real hide-in-lockstep rule.
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
## is the one real FLOOR cell (footprint-local, matching `stamp_furniture_
## at_global`'s own frame); every cell around it is a real wall.
func _room_grid(center: Vector2i) -> Dictionary:
	var grid := {}
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			var cell := center + Vector2i(dx, dy)
			grid[cell] = "wood_floor" if cell == center else "wood_wall"
	return grid


# -- stamp_furniture_at_global (ground) --------------------------------------

func test_stamp_furniture_at_global_writes_a_real_piece_onto_real_floor():
	var ground_grid := _room_grid(Vector2i(0, 0))
	manager.stamp_furniture_at_global(_chunk_coord, _origin, {Vector2i(0, 0): "wood_chair"}, ground_grid)
	assert_eq(manager.furniture_at_global(_origin.x, _origin.y), "wood_chair")


## The same real FurniturePlacement.can_place rule the player's own
## build_furniture_at_global already enforces -- a cell the caller
## computed wrong (not real floor) is silently skipped, never forced.
func test_stamp_furniture_at_global_refuses_a_cell_that_isnt_real_floor():
	var ground_grid := {Vector2i(0, 0): "wood_wall"}
	manager.stamp_furniture_at_global(_chunk_coord, _origin, {Vector2i(0, 0): "wood_chair"}, ground_grid)
	assert_eq(manager.furniture_at_global(_origin.x, _origin.y), "", "furniture must never land on a wall cell")


# -- stamp_upper_floor_furniture_at_global (upper) ---------------------------

func test_stamp_upper_floor_furniture_at_global_writes_into_its_own_layer():
	var upper_ground_grid := _room_grid(Vector2i(0, 0))
	manager.stamp_upper_floor_furniture_at_global(_chunk_coord, _origin, {Vector2i(0, 0): "wood_bed"}, upper_ground_grid)
	assert_eq(manager.upper_floor_furniture_at_global(_origin.x, _origin.y), "wood_bed")


## The two floors' furniture must never collide -- a real regression test
## for the exact reason this needed its own layer rather than reusing
## chunk.furniture_modifications for both.
func test_ground_and_upper_floor_furniture_coexist_independently_at_the_same_cell():
	var grid := _room_grid(Vector2i(0, 0))
	manager.stamp_furniture_at_global(_chunk_coord, _origin, {Vector2i(0, 0): "wood_table"}, grid)
	manager.stamp_upper_floor_furniture_at_global(_chunk_coord, _origin, {Vector2i(0, 0): "wood_bed"}, grid)
	assert_eq(manager.furniture_at_global(_origin.x, _origin.y), "wood_table")
	assert_eq(manager.upper_floor_furniture_at_global(_origin.x, _origin.y), "wood_bed")


# -- the upper floor's own hide-in-lockstep rule -----------------------------
#
# Ground furniture is never hidden by anything (nothing occludes the ground
# layer's own room from a bird's-eye view). The upper floor's own room
# genuinely IS hidden while a player stands inside it -- its furniture must
# hide in the same step, or it would float visibly over bare ground with no
# walls or floor around it (see Chunk.upper_floor_furniture_modifications'
# own doc comment).

## Stamps a real enclosed room directly onto the upper floor (piece by
## piece, via the real per-cell build_upper_floor_at_global -- the same
## entry point BuilderMarker itself uses) so _update_upper_floor_
## visibility's own real RoomDetector call has a genuine room to find,
## then furnishes its one real floor cell.
func _build_real_upper_room_with_a_bed() -> void:
	for cell in _room_grid(Vector2i(0, 0)):
		var global_cell: Vector2i = _origin + cell
		manager.build_upper_floor_at_global(global_cell.x, global_cell.y, _room_grid(Vector2i(0, 0))[cell])
	manager.stamp_upper_floor_furniture_at_global(
		_chunk_coord, _origin, {Vector2i(0, 0): "wood_bed"}, _room_grid(Vector2i(0, 0))
	)


func test_upper_floor_furniture_hides_while_the_player_stands_in_that_room():
	var upper_floor_layer := TileMapLayer.new()
	add_child(upper_floor_layer)
	manager.set_upper_floor_layer(upper_floor_layer)
	var upper_floor_furniture_layer := TileMapLayer.new()
	add_child(upper_floor_furniture_layer)
	manager.set_upper_floor_furniture_layer(upper_floor_furniture_layer)

	_build_real_upper_room_with_a_bed()
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

	_build_real_upper_room_with_a_bed()
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
