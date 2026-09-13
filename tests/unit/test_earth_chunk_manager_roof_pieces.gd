extends GutTest

## roof_at_global/build_roof_at_global: the roof layer's own per-cell
## read/write pair, mirroring modification_at_global/build_at_global and
## upper_floor_at_global/build_upper_floor_at_global exactly. Needed so a
## hired BuilderMarker can place a roof one real piece at a time -- before
## this, `chunk.roof_modifications` could only ever be written in BULK
## (stamp_structure_at_global), which is fine for the player's own instant
## self-build and the village generator, but gives a piece-by-piece worker
## nothing to call. Closes docs/concept/timber_construction.md's own
## long-named "a hired house gets no roof at all" gap (see BuilderMarker's
## own file header and test_builder_marker.gd's own new roof tests).
##
## Uses `_load_chunk` directly rather than `update()` (see CONTRIBUTING.md /
## test_earth_chunk_manager.gd's own known-slow-file note) -- roof
## bookkeeping needs no biome/ecosystem simulation.

const EarthChunkManager = preload("res://src/world/earth_chunk_manager.gd")

var manager: EarthChunkManager
var tile_map_layer: TileMapLayer
var entities_parent: Node2D
var creatures_parent: Node2D
var _chunk_coord := Vector2i(0, 0)
var _tile := Vector2i(4, 4)  # comfortably inside the origin chunk


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


func test_roof_at_global_is_empty_before_anything_is_built():
	assert_eq(manager.roof_at_global(_tile.x, _tile.y), "")


func test_building_a_roof_piece_is_readable_back():
	manager.build_roof_at_global(_tile.x, _tile.y, "wood_roof")
	assert_eq(manager.roof_at_global(_tile.x, _tile.y), "wood_roof")


func test_overwriting_a_roof_piece_replaces_it():
	manager.build_roof_at_global(_tile.x, _tile.y, "wood_roof")
	manager.build_roof_at_global(_tile.x, _tile.y, "stone_roof")
	assert_eq(manager.roof_at_global(_tile.x, _tile.y), "stone_roof")


func test_build_roof_at_global_returns_true_on_success():
	assert_true(manager.build_roof_at_global(_tile.x, _tile.y, "wood_roof"))


func test_build_roof_at_global_returns_false_for_an_unloaded_chunk():
	var far_tile := _tile + Vector2i(EarthChunkManager.CHUNK_SIZE * 50, 0)
	assert_false(manager.build_roof_at_global(far_tile.x, far_tile.y, "wood_roof"))


func test_roof_at_global_is_empty_for_an_unloaded_chunk():
	var far_tile := _tile + Vector2i(EarthChunkManager.CHUNK_SIZE * 50, 0)
	assert_eq(manager.roof_at_global(far_tile.x, far_tile.y), "")


## A roof piece is always walkable (see BuildingPiece._PIECES), so unlike
## build_at_global/build_upper_floor_at_global this must never add a
## collision body -- a roof caps a room, it does not block anyone from
## standing in it.
func test_building_a_roof_piece_adds_no_collision_body():
	var before := entities_parent.get_child_count()
	manager.build_roof_at_global(_tile.x, _tile.y, "wood_roof")
	assert_eq(entities_parent.get_child_count(), before, "a roof must never block movement")
