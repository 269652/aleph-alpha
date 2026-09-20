extends GutTest

## docs/concept/village_economy_balance.md mechanism 6, fault 2: a
## settlement counts the farmhouses that stand, not the kinds of building
## that stand.
##
## MEASURED (tools/probe_field_room.gd): a real village with three
## farmhouses at (20,19), (24,19) and (6,24) reported `"farmhouse": 1`,
## because _standing_building_ids_in_chunk deduplicates by id and the count
## was built from that list. Mechanism 7's "outnumbered" test was therefore
## always judged against one farmhouse however many stood.
##
## Berlin's real chunk, loaded directly, exactly as
## test_earth_chunk_manager_buildings.gd does -- whole buildings need real
## dry ground, which the fast (0, 0) chunk has none of.

const EarthChunkManager = preload("res://src/world/earth_chunk_manager.gd")
const GeoCoordinates = preload("res://src/world/geo_coordinates.gd")
const EarthChunkGenerator = preload("res://src/world/earth_chunk_generator.gd")
const BuildingCatalog = preload("res://src/gameplay/building_catalog.gd")
const VillageFarm = preload("res://src/gameplay/village_farm.gd")

var manager: EarthChunkManager
var tile_map_layer: TileMapLayer
var entities_parent: Node2D
var creatures_parent: Node2D
var _chunk_coord: Vector2i


func before_each():
	tile_map_layer = TileMapLayer.new()
	entities_parent = Node2D.new()
	creatures_parent = Node2D.new()
	add_child(tile_map_layer)
	add_child(entities_parent)
	manager = EarthChunkManager.new(tile_map_layer, entities_parent, creatures_parent)
	var geo := GeoCoordinates.new()
	var berlin := Vector2i(
		geo.tile_for_longitude(13.405, EarthChunkGenerator.WORLD_WIDTH_TILES),
		geo.tile_for_latitude(52.52, EarthChunkGenerator.WORLD_HEIGHT_TILES)
	)
	_chunk_coord = Vector2i(
		floori(float(berlin.x) / EarthChunkManager.CHUNK_SIZE), floori(float(berlin.y) / EarthChunkManager.CHUNK_SIZE)
	)
	_scrub()
	manager._load_chunk(_chunk_coord)


func after_each():
	_scrub()
	tile_map_layer.free()
	entities_parent.free()
	creatures_parent.free()


func _scrub() -> void:
	for path in [manager._modifications_path(_chunk_coord), manager._buildings_path(_chunk_coord)]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


## The next local origin, walking the chunk with a margin, where the whole
## footprint of `building_id` and its doorstep are dry buildable ground with
## nothing modified there yet -- so each call after a placement finds
## somewhere new.
func _a_clear_origin_for(building_id: String) -> Vector2i:
	var footprint := BuildingCatalog.footprint_of(building_id)
	for y in range(2, EarthChunkManager.CHUNK_SIZE - footprint.y - 3):
		for x in range(2, EarthChunkManager.CHUNK_SIZE - footprint.x - 3):
			var origin := Vector2i(x, y)
			var ok := true
			for cell in BuildingCatalog.footprint_cells(building_id, origin) + [origin + BuildingCatalog.doorstep_of(building_id)]:
				var g: Vector2i = _chunk_coord * EarthChunkManager.CHUNK_SIZE + cell
				if not manager.is_buildable_terrain_at(g.x, g.y) or manager.modification_at_global(g.x, g.y) != "":
					ok = false
					break
			if ok:
				return origin
	fail_test("no clear origin for a %s in this chunk" % building_id)
	return Vector2i.ZERO


func _raise(building_id: String) -> void:
	var origin := _a_clear_origin_for(building_id)
	assert_true(
		manager.place_building(_chunk_coord, origin, building_id, Vector2i(0, 1), 1, ""),
		"precondition: a %s stands at %s" % [building_id, str(origin)]
	)


func test_two_farmhouses_count_as_two():
	_raise(VillageFarm.FARM_BUILDING_ID)
	_raise(VillageFarm.FARM_BUILDING_ID)
	var counts: Dictionary = manager._settlement_building_counts(_chunk_coord)
	assert_eq(int(counts.get(VillageFarm.FARM_BUILDING_ID, 0)), 2)


func test_three_farmhouses_count_as_three_and_a_sawmill_as_one():
	for _i in 3:
		_raise(VillageFarm.FARM_BUILDING_ID)
	_raise("sawmill")
	var counts: Dictionary = manager._settlement_building_counts(_chunk_coord)
	assert_eq(int(counts.get(VillageFarm.FARM_BUILDING_ID, 0)), 3)
	assert_eq(int(counts.get("sawmill", 0)), 1)


## The list of WHAT stands is still a list of kinds, each once -- the
## present_building_ids every charter and "already stands" check reads.
func test_the_list_of_kinds_standing_still_names_each_kind_once():
	_raise(VillageFarm.FARM_BUILDING_ID)
	_raise(VillageFarm.FARM_BUILDING_ID)
	var ids: Array = manager._standing_building_ids_in_chunk(_chunk_coord)
	assert_eq(ids.count(VillageFarm.FARM_BUILDING_ID), 1)
