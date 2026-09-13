extends GutTest

## Structure workers are only real if they are wired to the world they work
## in. Found while building the bread chain on the Sägewerk's own template
## (docs/concept/milling_and_baking.md): EarthChunkManager._spawn_lumberjack_
## for never set `marker.earth`, so LumberjackMarker._step_production bailed
## on `earth == null` every frame and every beam/plank the Sägewerk ever
## shaped in live play was silently discarded -- its logistics haulers and
## Player._collect_step never found any stock. Only the unit test set
## `earth`, which is exactly why it passed. The Farmer's own spawn already
## did this right (`marker.earth = self`); this file pins it for every
## structure worker EarthChunkManager spawns, so the next one cannot repeat
## the mistake.
##
## Uses `_load_chunk` directly rather than `update()` (see CONTRIBUTING.md /
## test_earth_chunk_manager.gd's own known-slow-file note).

const EarthChunkManager = preload("res://src/world/earth_chunk_manager.gd")

var manager: EarthChunkManager
var tile_map_layer: TileMapLayer
var entities_parent: Node2D
var creatures_parent: Node2D
var _chunk_coord := Vector2i(0, 0)
var _tile := Vector2i(6, 6)


func before_each():
	tile_map_layer = TileMapLayer.new()
	entities_parent = Node2D.new()
	creatures_parent = Node2D.new()
	add_child(tile_map_layer)
	add_child(entities_parent)
	manager = EarthChunkManager.new(tile_map_layer, entities_parent, creatures_parent)
	manager._load_chunk(_chunk_coord)


func after_each():
	tile_map_layer.free()
	entities_parent.free()
	creatures_parent.free()


func test_a_spawned_lumberjack_is_wired_to_the_world_it_shapes_logs_for():
	manager.build_at_global(_tile.x, _tile.y, "sagewerk")
	var by_cell: Dictionary = manager._sagewerk_lumberjacks[_chunk_coord]
	assert_eq(by_cell.size(), 1, "precondition: the Sägewerk's own Lumberjack moved in")
	var marker = by_cell.values()[0]
	assert_eq(marker.earth, manager, "without `earth`, every beam/plank it shapes is thrown away")


func test_a_spawned_farmer_is_wired_to_the_world_it_harvests_into():
	manager.build_at_global(_tile.x, _tile.y, "farm")
	manager.build_at_global(_tile.x + 1, _tile.y, "wooden_fence")  # the Farm's own gate
	var by_cell: Dictionary = manager._farm_farmers[_chunk_coord]
	assert_eq(by_cell.size(), 1, "precondition: a fenced Farm gets its Farmer")
	assert_eq(by_cell.values()[0].earth, manager)
