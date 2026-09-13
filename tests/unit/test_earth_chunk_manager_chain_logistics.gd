extends GutTest

## Hauling between the bread chain's links (docs/concept/milling_and_
## baking.md, "Hauling between the links"): the SAME LogisticsMarker that
## already moves a producer's output into Storage, configured with a
## consumer as its destination -- wheat from a Farm (or a Storage holding
## wheat) into a Mill, flour from a Mill into a Bakery, bread from a Bakery
## into Storage. One hauler per real (source, destination) pair within the
## existing pairing radius, reconciled the same way the Sägewerk's and
## Farm's Storage pairing already is (EarthChunkManager.CHAIN_LOGISTICS_
## LEGS / _resync_all_chain_legs).
##
## Uses `_load_chunk` directly rather than `update()` (see CONTRIBUTING.md /
## test_earth_chunk_manager.gd's own known-slow-file note).

const EarthChunkManager = preload("res://src/world/earth_chunk_manager.gd")
const LogisticsMarker = preload("res://src/rendering/logistics_marker.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")

var manager: EarthChunkManager
var tile_map_layer: TileMapLayer
var entities_parent: Node2D
var creatures_parent: Node2D
var _chunk_coord := Vector2i(0, 0)
var _farm := Vector2i(6, 6)
var _fence := Vector2i(7, 6)
var _mill := Vector2i(10, 6)
var _bakery := Vector2i(14, 6)
var _storage := Vector2i(18, 6)


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


func _local(tile: Vector2i) -> Vector2i:
	return tile - _chunk_coord * EarthChunkManager.CHUNK_SIZE


## The haulers currently paired for `source` tile's `destination_id` leg:
## {destination_pairing_key -> {item_id -> LogisticsMarker}}.
func _legs(source: Vector2i, destination_id: String) -> Dictionary:
	return manager._chain_logistics_workers.get(_chunk_coord, {}).get(_local(source), {}).get(destination_id, {})


func _the_one_hauler(source: Vector2i, destination_id: String, item_id: String):
	var legs := _legs(source, destination_id)
	assert_eq(legs.size(), 1, "exactly one paired %s for the %s leg" % [destination_id, item_id])
	var by_item: Dictionary = legs.values()[0]
	assert_true(by_item.has(item_id))
	return by_item[item_id]


func _build_fenced_farm() -> void:
	manager.build_at_global(_farm.x, _farm.y, "farm")
	manager.build_at_global(_fence.x, _fence.y, "wooden_fence")


func test_a_fenced_farm_near_a_mill_gets_a_wheat_hauler_bound_for_the_mill():
	_build_fenced_farm()
	manager.build_at_global(_mill.x, _mill.y, "mill")

	var hauler = _the_one_hauler(_farm, "mill", "wheat")
	assert_eq(hauler.source_structure_id, "farm")
	assert_eq(hauler.item_id, "wheat")
	assert_eq(hauler.storage_structure_id, "mill", "the destination is the Mill, not a Storage")
	var mill_pixel := (Vector2(_mill) + Vector2(0.5, 0.5)) * TerrainRenderer.TILE_SIZE
	assert_eq(hauler.preferred_storage_position, mill_pixel)
	assert_eq(hauler.earth, manager)


func test_a_mill_near_a_bakery_gets_a_flour_hauler_and_a_bakery_near_storage_a_bread_hauler():
	manager.build_at_global(_mill.x, _mill.y, "mill")
	manager.build_at_global(_bakery.x, _bakery.y, "bakery")
	manager.build_at_global(_storage.x, _storage.y, "storage")

	assert_eq(_the_one_hauler(_mill, "bakery", "flour").storage_structure_id, "bakery")
	assert_eq(_the_one_hauler(_bakery, "storage", "bread").storage_structure_id, "storage")


func test_wheat_already_in_a_storage_is_hauled_on_to_the_mill():
	manager.build_at_global(_storage.x, _storage.y, "storage")
	manager.build_at_global(_mill.x, _mill.y, "mill")
	assert_eq(_the_one_hauler(_storage, "mill", "wheat").source_structure_id, "storage")


func test_an_unfenced_farm_has_no_farmer_and_so_no_hauler_until_it_is_fenced():
	manager.build_at_global(_farm.x, _farm.y, "farm")
	manager.build_at_global(_mill.x, _mill.y, "mill")
	assert_true(_legs(_farm, "mill").is_empty(), "no Farmer, no wheat, no hauler")

	manager.build_at_global(_fence.x, _fence.y, "wooden_fence")
	assert_eq(_legs(_farm, "mill").size(), 1, "fencing the farm staffs it, and its haulers follow")


func test_destroying_the_mill_despawns_the_legs_on_both_sides_of_it():
	_build_fenced_farm()
	manager.build_at_global(_mill.x, _mill.y, "mill")
	manager.build_at_global(_bakery.x, _bakery.y, "bakery")
	assert_eq(_legs(_farm, "mill").size(), 1)
	assert_eq(_legs(_mill, "bakery").size(), 1)

	manager.destroy_at_global(_mill.x, _mill.y)

	assert_true(_legs(_farm, "mill").is_empty())
	assert_true(_legs(_mill, "bakery").is_empty())


func test_repeated_resyncs_never_double_spawn_a_leg():
	_build_fenced_farm()
	manager.build_at_global(_mill.x, _mill.y, "mill")
	manager._resync_all_chain_legs()
	manager._resync_all_chain_legs()
	assert_eq(_legs(_farm, "mill").size(), 1)
	var haulers := 0
	for node in entities_parent.get_children():
		if node is LogisticsMarker and node.storage_structure_id == "mill":
			haulers += 1
	assert_eq(haulers, 1)


func test_unloading_the_chunk_frees_its_chain_haulers():
	_build_fenced_farm()
	manager.build_at_global(_mill.x, _mill.y, "mill")
	manager._unload_chunk(_chunk_coord)
	assert_false(manager._chain_logistics_workers.has(_chunk_coord))
	var path: String = manager._modifications_path(_chunk_coord)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


## End to end, with the real hauler: wheat deposited at the Farm reaches the
## Mill's own stock -- the same real trip test_logistics_marker.gd already
## proves for a Storage destination, here with a consumer as the
## destination, which is the whole point of the leg.
func test_wheat_at_the_farm_is_actually_carried_into_the_mill():
	_build_fenced_farm()
	manager.build_at_global(_mill.x, _mill.y, "mill")
	manager.deposit_to_structure_at(_farm.x, _farm.y, "wheat", 4)
	var hauler = _the_one_hauler(_farm, "mill", "wheat")

	for i in 400:
		hauler._process(0.25)
		if manager.structure_stock_at(_mill.x, _mill.y, "wheat") > 0:
			break

	assert_gt(manager.structure_stock_at(_mill.x, _mill.y, "wheat"), 0, "wheat arrived at the Mill")
	assert_lt(manager.structure_stock_at(_farm.x, _farm.y, "wheat"), 4, "...and left the Farm -- a transfer, not a copy")
