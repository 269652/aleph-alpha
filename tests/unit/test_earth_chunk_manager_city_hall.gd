extends GutTest

## EarthChunkManager.city_hall_demands_near (see docs/concept/
## npc_role_consensus.md's "City Hall" section): a real City Hall's own
## "compute demands" query -- gates SettlementDemand.demands_for behind a
## real "city_hall" structure standing nearby, reading the SAME real
## settlement state (market.stock, _present_structure_ids_for_settlement_
## chunk) _apply_settlement_build_decision already uses. Mirrors
## test_earth_chunk_manager_bees.gd's own dedicated-file shape -- uses
## `_load_chunk` directly, never the slow real `update()`.
##
## This file's own tests build real structures at the shared real-world
## Berlin tile every EarthChunkManager test in this project anchors on --
## see test_builder_marker.gd's own header for the fuller account of why
## before_each/after_each below scrub this file's own real chunk_coord
## (never the whole shared directory) even though no test here calls
## _unload_chunk itself: defensive consistency with every other Berlin-tile
## test file in this project, not because this file is known to leak.

const EarthChunkManager = preload("res://src/world/earth_chunk_manager.gd")
const EarthChunkGenerator = preload("res://src/world/earth_chunk_generator.gd")
const GeoCoordinates = preload("res://src/world/geo_coordinates.gd")

var manager: EarthChunkManager
var tile_map_layer: TileMapLayer
var entities_parent: Node2D
var creatures_parent: Node2D
var _berlin_tile: Vector2i
var _berlin_chunk: Vector2i

## _present_structure_ids_for_settlement_chunk (which city_hall_demands_near
## reads through) scans from the CHUNK's own center tile, not from
## _berlin_tile itself -- Berlin's own real-world tile can sit anywhere
## within its chunk, including near an edge, so a structure built only a
## couple tiles from _berlin_tile is not reliably within
## SETTLEMENT_STRUCTURE_SCAN_RADIUS_TILES of the chunk CENTER (a real bug
## this file's own first draft hit: a sagewerk built at _berlin_tile + 4
## was invisible to _present_structure_ids_for_settlement_chunk because
## Berlin's own tile happened to sit far enough from center). Every
## structure below is built near this real chunk-center anchor instead,
## and every query below reads from it too, so both the CITY_HALL_DEMAND_
## RADIUS_TILES query-point check and the chunk-center settlement scan see
## the same structures regardless of where Berlin itself falls locally.
var _chunk_center: Vector2i


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
	_chunk_center = _berlin_chunk * EarthChunkManager.CHUNK_SIZE + Vector2i(
		EarthChunkManager.CHUNK_SIZE / 2, EarthChunkManager.CHUNK_SIZE / 2
	)
	_forget_persisted_berlin_chunk()
	manager._load_chunk(_berlin_chunk)


func after_each():
	tile_map_layer.free()
	entities_parent.free()
	creatures_parent.free()
	_forget_persisted_berlin_chunk()


func _forget_persisted_berlin_chunk() -> void:
	for dir in [
		EarthChunkManager.MODIFICATIONS_DIR,
		EarthChunkManager.ROOF_MODIFICATIONS_DIR,
		EarthChunkManager.PLANTED_TREES_DIR,
	]:
		var path := "%s/%d_%d.bin" % [dir, _berlin_chunk.x, _berlin_chunk.y]
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func _demand_for(demands: Array, recipe_id: String) -> Dictionary:
	for demand in demands:
		if demand["recipe_id"] == recipe_id:
			return demand
	return {}


## No City Hall standing nearby at all -- a silent, discoverable "nothing
## to convene about" absence, not an invented placeholder demand.
func test_no_city_hall_nearby_returns_no_demands():
	assert_eq(manager.city_hall_demands_near(_chunk_center.x, _chunk_center.y), [])


## The real "wood" case (docs/concept/npc_role_consensus.md's own worked
## example): a City Hall stands, but no Sägewerk -- the settlement's real
## demand for beam/plank surfaces.
func test_a_nearby_city_hall_with_no_sagewerk_surfaces_the_wood_demand():
	manager.build_at_global(_chunk_center.x + 1, _chunk_center.y, "city_hall")
	var demands := manager.city_hall_demands_near(_chunk_center.x, _chunk_center.y)
	var beam := _demand_for(demands, "log_to_balken")
	assert_eq(beam.get("missing_structure_id"), "sagewerk")


## Once the settlement actually has a Sägewerk, the wood demand is gone --
## the same real ConstructionPriority READY transition SettlementDemand
## already proves in isolation, now reachable through a real City Hall.
func test_a_nearby_city_hall_with_a_sagewerk_present_has_no_wood_demand():
	manager.build_at_global(_chunk_center.x + 1, _chunk_center.y, "city_hall")
	manager.build_at_global(_chunk_center.x + 3, _chunk_center.y, "sagewerk")
	var demands := manager.city_hall_demands_near(_chunk_center.x, _chunk_center.y)
	assert_eq(_demand_for(demands, "log_to_balken"), {})


## Destroying the only nearby City Hall silences the demand query again --
## the same "no City Hall, no demands" absence as never having built one.
func test_destroying_the_only_city_hall_returns_no_demands_again():
	manager.build_at_global(_chunk_center.x + 1, _chunk_center.y, "city_hall")
	manager.destroy_at_global(_chunk_center.x + 1, _chunk_center.y)
	assert_eq(manager.city_hall_demands_near(_chunk_center.x, _chunk_center.y), [])
