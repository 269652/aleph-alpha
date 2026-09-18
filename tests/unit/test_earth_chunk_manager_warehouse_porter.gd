extends GutTest

## The warehouse binds its own porter (docs/concept/village_warehouse.md,
## Mechanism 4). Asked directly, with the empty store in shot: "The warehouse
## also needs to bind a worker which then collects all ressources from every
## production building", and "the warehouse stays empty".
##
## The whole logistics system was wired for the `sagewerk` -> `storage`
## single-tile placeables. A real village raises a `sawmill` and a
## `warehouse`, which are whole-building catalog entities, and place_building
## staffs nobody -- so every village producer filled its own shelf and
## nothing ever moved it.
##
## Drives the REAL EarthChunkManager on a real chunk, loaded via _load_chunk
## (see test_earth_chunk_manager.gd's own known-slow-file note).

const EarthChunkManager = preload("res://src/world/earth_chunk_manager.gd")
const EarthChunkGenerator = preload("res://src/world/earth_chunk_generator.gd")
const GeoCoordinates = preload("res://src/world/geo_coordinates.gd")
const BuildingCatalog = preload("res://src/gameplay/building_catalog.gd")
const LogisticsMarker = preload("res://src/rendering/logistics_marker.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")

const CHUNK_SIZE := EarthChunkManager.CHUNK_SIZE

var manager: EarthChunkManager
var tile_map_layer: TileMapLayer
var entities_parent: Node2D
var creatures_parent: Node2D
var _chunk_coord: Vector2i
var _store_origin: Vector2i
var _mill_origin: Vector2i


func before_each():
	tile_map_layer = TileMapLayer.new()
	entities_parent = Node2D.new()
	creatures_parent = Node2D.new()
	add_child(tile_map_layer)
	add_child(entities_parent)
	manager = EarthChunkManager.new(tile_map_layer, entities_parent, creatures_parent)
	var geo := GeoCoordinates.new()
	_chunk_coord = Vector2i(
		floori(float(geo.tile_for_longitude(13.405, EarthChunkGenerator.WORLD_WIDTH_TILES)) / float(CHUNK_SIZE)),
		floori(float(geo.tile_for_latitude(52.52, EarthChunkGenerator.WORLD_HEIGHT_TILES)) / float(CHUNK_SIZE)),
	)
	_scrub()
	manager._load_chunk(_chunk_coord)
	_store_origin = _clear_origin(Vector2i(4, 4), "warehouse")
	_mill_origin = _clear_origin(_store_origin + Vector2i(8, 0), "sawmill")


func after_each():
	_scrub()
	tile_map_layer.free()
	entities_parent.free()
	creatures_parent.free()


func _scrub() -> void:
	for path in [
		manager._modifications_path(_chunk_coord), manager._buildings_path(_chunk_coord),
		manager._roof_modifications_path(_chunk_coord), manager._furniture_modifications_path(_chunk_coord),
	]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


## The first origin at or after `from` whose footprint and doorstep are all
## unmodified, so a real place_building on it can actually succeed.
func _clear_origin(from: Vector2i, building_id: String) -> Vector2i:
	var chunk = manager._loaded_chunks[_chunk_coord]
	for y in range(from.y, CHUNK_SIZE - 6):
		for x in range(from.x, CHUNK_SIZE - 6):
			var origin := Vector2i(x, y)
			var clear := true
			var cells: Array = BuildingCatalog.footprint_cells(building_id, origin)
			cells.append(origin + BuildingCatalog.doorstep_of(building_id))
			for local in cells:
				if chunk.modifications.get(local, "") != "":
					clear = false
					break
			if clear:
				return origin
	fail_test("no clear origin for %s" % building_id)
	return from


## Freed nodes stay children until the next frame boundary (the same reason
## DecomposerMarker's own _target_still_here checks it directly), so a porter
## the manager has just let go is not one the store still employs.
func _porters() -> Array:
	var out: Array = []
	for node in entities_parent.get_children():
		if node is LogisticsMarker and not node.is_queued_for_deletion():
			out.append(node)
	return out


func _global(local: Vector2i) -> Vector2i:
	return _chunk_coord * CHUNK_SIZE + local


# -- the store binds the worker ---------------------------------------------

func test_a_warehouse_beside_a_producer_binds_a_porter():
	assert_true(manager.place_building(_chunk_coord, _store_origin, "warehouse"))
	assert_true(manager.place_building(_chunk_coord, _mill_origin, "sawmill"))

	assert_eq(_porters().size(), 1, "the store employs one porter for the mill")


## Either order: a producer raised beside an existing store binds one just
## as a store raised beside an existing producer does.
func test_the_order_the_two_are_raised_in_does_not_matter():
	assert_true(manager.place_building(_chunk_coord, _mill_origin, "sawmill"))
	assert_eq(_porters().size(), 0, "a mill alone has nobody to carry to")
	assert_true(manager.place_building(_chunk_coord, _store_origin, "warehouse"))

	assert_eq(_porters().size(), 1)


func test_a_warehouse_with_no_producer_employs_nobody():
	assert_true(manager.place_building(_chunk_coord, _store_origin, "warehouse"))

	assert_eq(_porters().size(), 0, "nothing to fetch, nobody to fetch it")


func test_taking_the_store_away_takes_its_porter_with_it():
	manager.place_building(_chunk_coord, _store_origin, "warehouse")
	manager.place_building(_chunk_coord, _mill_origin, "sawmill")
	assert_eq(_porters().size(), 1, "precondition")

	assert_true(manager.remove_building(_chunk_coord, _store_origin))

	assert_eq(_porters().size(), 0, "no store, no porter")


# -- and it really carries ---------------------------------------------------

## The whole point: what a producer is holding ends up in the store. A porter
## carries whatever is waiting rather than one named item id -- a village
## producer's shelf is not a fixed list (a farmhouse holds whatever crop its
## farmer sows), so naming the goods in advance would invent a catalogue that
## drifts from what the buildings really hold.
func test_a_porter_carries_what_the_producer_is_holding_into_the_store():
	manager.place_building(_chunk_coord, _store_origin, "warehouse")
	manager.place_building(_chunk_coord, _mill_origin, "sawmill")
	var mill := _global(_mill_origin)
	var store := _global(_store_origin)
	manager.deposit_to_structure_at(mill.x, mill.y, "beam", 4)

	for i in 4000:
		for porter in _porters():
			porter._process(0.25)
		if manager.structure_stock_at(store.x, store.y, "beam") > 0:
			break

	assert_gt(
		manager.structure_stock_at(store.x, store.y, "beam"), 0,
		"the store is empty because nobody was carrying"
	)
	assert_lt(
		manager.structure_stock_at(mill.x, mill.y, "beam"), 4,
		"and it really left the mill rather than being copied"
	)


# -- across a reload ---------------------------------------------------------
# A village the player walks back to has its store and its producers restored
# from disk rather than placed, so binding the porter only inside
# place_building would mean every village found its store empty again on the
# next visit -- which is exactly how the report reads.

func test_a_restored_village_binds_its_porter_again():
	manager.place_building(_chunk_coord, _store_origin, "warehouse")
	manager.place_building(_chunk_coord, _mill_origin, "sawmill")
	assert_eq(_porters().size(), 1, "precondition")

	manager._unload_chunk(_chunk_coord)
	manager._load_chunk(_chunk_coord)

	assert_eq(_porters().size(), 1, "the store employs its porter again on the next visit")


func test_a_porter_does_not_outlive_the_chunk_it_works_in():
	manager.place_building(_chunk_coord, _store_origin, "warehouse")
	manager.place_building(_chunk_coord, _mill_origin, "sawmill")

	manager._unload_chunk(_chunk_coord)

	assert_eq(_porters().size(), 0, "a porter is not left walking a chunk that is gone")
