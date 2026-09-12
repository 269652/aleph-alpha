extends GutTest

## EarthChunkManager's Farm wiring (see docs/concept/npc_farm_production.md):
## a placed "farm" only gets a real FarmerMarker once a real "wooden_fence"
## stands nearby -- reported directly: "buildings like the farm require a
## fence and then an NPC can get hired." Mirrors test_earth_chunk_manager_
## bees.gd's own dedicated-file shape -- uses `_load_chunk` directly, never
## the slow real `update()`.

const EarthChunkManager = preload("res://src/world/earth_chunk_manager.gd")
const EarthChunkGenerator = preload("res://src/world/earth_chunk_generator.gd")
const GeoCoordinates = preload("res://src/world/geo_coordinates.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")
const FarmerMarker = preload("res://src/rendering/farmer_marker.gd")
const LogisticsMarker = preload("res://src/rendering/logistics_marker.gd")

var manager: EarthChunkManager
var tile_map_layer: TileMapLayer
var entities_parent: Node2D
var creatures_parent: Node2D
var _berlin_tile: Vector2i
var _berlin_chunk: Vector2i


func before_each():
	tile_map_layer = TileMapLayer.new()
	entities_parent = Node2D.new()
	creatures_parent = Node2D.new()
	manager = EarthChunkManager.new(tile_map_layer, entities_parent, creatures_parent)
	add_child(entities_parent)
	var geo_coordinates := GeoCoordinates.new()
	_berlin_tile = Vector2i(
		geo_coordinates.tile_for_longitude(13.405, EarthChunkGenerator.WORLD_WIDTH_TILES),
		geo_coordinates.tile_for_latitude(52.52, EarthChunkGenerator.WORLD_HEIGHT_TILES)
	)
	_berlin_chunk = Vector2i(
		floori(float(_berlin_tile.x) / EarthChunkManager.CHUNK_SIZE),
		floori(float(_berlin_tile.y) / EarthChunkManager.CHUNK_SIZE)
	)
	manager._load_chunk(_berlin_chunk)


func after_each():
	tile_map_layer.free()
	entities_parent.free()
	creatures_parent.free()


func _farmers_in_entities_parent() -> Array:
	var found: Array = []
	for child in entities_parent.get_children():
		if child is FarmerMarker:
			found.append(child)
	return found


func test_a_farm_with_no_fence_nearby_gets_no_farmer():
	manager.build_at_global(_berlin_tile.x, _berlin_tile.y, "farm")
	assert_eq(_farmers_in_entities_parent().size(), 0)


func test_a_farm_with_a_fence_already_nearby_gets_a_farmer():
	manager.build_at_global(_berlin_tile.x + 2, _berlin_tile.y, "wooden_fence")
	manager.build_at_global(_berlin_tile.x, _berlin_tile.y, "farm")
	assert_eq(_farmers_in_entities_parent().size(), 1)


## The real ask: a fence built AFTER the farm still gets it staffed --
## "buildings like the farm require a fence and THEN an NPC can get hired,"
## not only a fence built first.
func test_building_a_fence_after_the_farm_retroactively_staffs_it():
	manager.build_at_global(_berlin_tile.x, _berlin_tile.y, "farm")
	assert_eq(_farmers_in_entities_parent().size(), 0, "no farmer yet -- no fence")
	manager.build_at_global(_berlin_tile.x + 2, _berlin_tile.y, "wooden_fence")
	assert_eq(_farmers_in_entities_parent().size(), 1, "building the fence should staff the farm")


func test_destroying_the_only_fence_despawns_the_farmer():
	manager.build_at_global(_berlin_tile.x + 2, _berlin_tile.y, "wooden_fence")
	manager.build_at_global(_berlin_tile.x, _berlin_tile.y, "farm")
	assert_eq(_farmers_in_entities_parent().size(), 1)
	manager.destroy_at_global(_berlin_tile.x + 2, _berlin_tile.y)
	assert_eq(_farmers_in_entities_parent().size(), 0)


func test_destroying_the_farm_despawns_its_farmer():
	manager.build_at_global(_berlin_tile.x + 2, _berlin_tile.y, "wooden_fence")
	manager.build_at_global(_berlin_tile.x, _berlin_tile.y, "farm")
	manager.destroy_at_global(_berlin_tile.x, _berlin_tile.y)
	assert_eq(_farmers_in_entities_parent().size(), 0)


## A Farm pairs with a real nearby Storage the same way a Sagewerk does --
## reusing LogisticsMarker/LogisticsBehavior unmodified.
func test_a_fenced_farm_and_a_nearby_storage_get_a_wheat_logistics_worker():
	manager.build_at_global(_berlin_tile.x + 2, _berlin_tile.y, "wooden_fence")
	manager.build_at_global(_berlin_tile.x, _berlin_tile.y, "farm")
	manager.build_at_global(_berlin_tile.x + 3, _berlin_tile.y + 3, "storage")
	var found := false
	for child in entities_parent.get_children():
		if child is LogisticsMarker and child.item_id == "wheat" and child.source_structure_id == "farm":
			found = true
	assert_true(found, "a fenced farm with a nearby storage should get a real wheat logistics worker")


## Re-loading a chunk with a persisted, already-fenced farm re-stages its
## farmer -- the same "an NPC moves in" applies to a revisited worksite"
## reasoning the Sagewerk's own Lumberjack already gets.
func test_reloading_a_chunk_with_a_persisted_fenced_farm_respawns_its_farmer():
	manager.build_at_global(_berlin_tile.x + 2, _berlin_tile.y, "wooden_fence")
	manager.build_at_global(_berlin_tile.x, _berlin_tile.y, "farm")
	manager._unload_chunk(_berlin_chunk)
	assert_eq(_farmers_in_entities_parent().size(), 0, "unloading should free the farmer")
	manager._load_chunk(_berlin_chunk)
	assert_eq(_farmers_in_entities_parent().size(), 1, "reloading should respawn it")
