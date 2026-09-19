extends GutTest

## A village's store and the round that fills it (docs/concept/
## village_warehouse.md).
##
## Asked with the empty store in shot -- "The warehouse also needs to bind a
## worker which then collects all ressources from every production building"
## -- and then corrected with the wagon in shot: *"It should be a real NPC
## pulling the cart, not an additional sprite"*.
##
## So the manager staffs NOBODY for a village store. Hauling is a trade: a
## carter is born to it, VillageRenderer hands them the round and a wagon,
## and both live and die with the village's own nodes (see
## test_village_renderer.gd and test_npc_marker_cart.gd). What is pinned
## here is that the OLD mechanism is really gone -- no second kind of person
## walking beside the villagers, and nothing left behind by a chunk that has
## unloaded.
##
## Drives the REAL EarthChunkManager on a real chunk, loaded via _load_chunk
## (see test_earth_chunk_manager.gd's own known-slow-file note).

const EarthChunkManager = preload("res://src/world/earth_chunk_manager.gd")
const EarthChunkGenerator = preload("res://src/world/earth_chunk_generator.gd")
const GeoCoordinates = preload("res://src/world/geo_coordinates.gd")
const BuildingCatalog = preload("res://src/gameplay/building_catalog.gd")
const LogisticsMarker = preload("res://src/rendering/logistics_marker.gd")
const CartMarker = preload("res://src/rendering/cart_marker.gd")
const SettlementGenerator = preload("res://src/world/settlement_generator.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")

const CHUNK_SIZE := EarthChunkManager.CHUNK_SIZE

var manager: EarthChunkManager
var tile_map_layer: TileMapLayer
var entities_parent: Node2D
var creatures_parent: Node2D
var _chunk_coord: Vector2i
var _store_origin: Vector2i
var _mill_origin: Vector2i
var _settlement_generator := SettlementGenerator.new()


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


func _scrub(coord := _chunk_coord) -> void:
	for path in [
		manager._modifications_path(coord), manager._buildings_path(coord),
		manager._roof_modifications_path(coord), manager._furniture_modifications_path(coord),
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


## Every wagon still alive, queued for deletion or not -- the count the
## node-growth probe watched climb. Both parents, because a village's own
## nodes are spawned under the creatures parent while a placeable's worker
## goes under the entities parent, and a leak in either is a leak.
func _carts() -> Array:
	var out: Array = []
	for parent in [entities_parent, creatures_parent]:
		for node in parent.get_children():
			if node is CartMarker:
				out.append(node)
	return out


func _global(local: Vector2i) -> Vector2i:
	return _chunk_coord * CHUNK_SIZE + local


# -- the manager staffs nobody ----------------------------------------------

func test_a_warehouse_beside_a_producer_spawns_no_porter():
	assert_true(manager.place_building(_chunk_coord, _store_origin, "warehouse"))
	assert_true(manager.place_building(_chunk_coord, _mill_origin, "sawmill"))

	assert_eq(_porters().size(), 0, "a village's round is walked by a villager, not a spawned walker")
	assert_eq(_carts().size(), 0, "and the wagon comes with the carter, not with the building")


## Either order, and a removal too: there is no hidden pairing left that a
## later placement could still trip.
func test_no_order_of_raising_or_removing_conjures_a_porter():
	assert_true(manager.place_building(_chunk_coord, _mill_origin, "sawmill"))
	assert_eq(_porters().size(), 0)
	assert_true(manager.place_building(_chunk_coord, _store_origin, "warehouse"))
	assert_eq(_porters().size(), 0)
	assert_true(manager.remove_building(_chunk_coord, _store_origin))

	assert_eq(_porters().size(), 0)
	assert_eq(_carts().size(), 0)


## And a reload does not either -- the old mechanism bound its porter on
## every restore, so this is where a leftover would show up first.
func test_a_restored_village_still_spawns_no_porter():
	manager.place_building(_chunk_coord, _store_origin, "warehouse")
	manager.place_building(_chunk_coord, _mill_origin, "sawmill")

	manager._unload_chunk(_chunk_coord)
	manager._load_chunk(_chunk_coord)

	assert_eq(_porters().size(), 0)
	assert_eq(_carts().size(), 0)


# -- and a village leaves nothing behind ------------------------------------
# Measured with tools/probe_node_growth.gd after the framerate was reported
# falling from 60-100 to 20: loading and unloading the same three real chunks
# over and over left one more walker and one more cart alive on every single
# cycle, while every other class returned to where it started. A village the
# player walks in and out of was leaving a person and a wagon behind each
# time, each of them still running _process.
#
# The carter's own wagon is spawned WITH the village (VillageRenderer puts it
# in the array _unload_chunk frees), so these drive a REAL settlement chunk
# rather than the two hand-placed buildings above.

## A real chunk whose village really put a carter and a wagon on the ground.
##
## Measured, not assumed: has_settlement_at rolls off the chunk coordinate
## alone, and a village whose site turns out to be water or forest founds
## nothing at all (honest, and tested in test_village_renderer.gd). So every
## hash-confirmed candidate is LOADED and checked, and the ones that founded
## nothing are unloaded and scrubbed again.
func _village_chunk() -> Vector2i:
	var geo := GeoCoordinates.new()
	var center := Vector2i(
		floori(float(geo.tile_for_longitude(13.405, EarthChunkGenerator.WORLD_WIDTH_TILES)) / float(CHUNK_SIZE)),
		floori(float(geo.tile_for_latitude(52.52, EarthChunkGenerator.WORLD_HEIGHT_TILES)) / float(CHUNK_SIZE)),
	)
	var tried := 0
	for dy in range(-12, 13):
		for dx in range(-12, 13):
			var coord := center + Vector2i(dx, dy)
			if coord == _chunk_coord:
				continue
			if not _settlement_generator.has_settlement_at(coord, "grassland"):
				continue
			tried += 1
			_scrub(coord)
			manager._load_chunk(coord)
			var carts := _carts().size()
			manager._unload_chunk(coord)
			_scrub(coord)
			if carts > 0:
				return coord
			if tried >= 8:
				break
	fail_test("no settlement chunk near the sampled region founded a village with a carter")
	return Vector2i.ZERO


func test_a_village_leaves_no_wagon_behind_when_its_chunk_goes():
	var coord := _village_chunk()
	manager._load_chunk(coord)
	var standing := _carts().size()
	manager._unload_chunk(coord)

	assert_eq(_carts().size(), 0, "nothing is left rolling in a chunk that is gone")
	assert_gt(standing, 0, "precondition: this village really had a carter with a wagon")


## And the same across the whole round of load/unload the probe measured: a
## village visited again and again leaves nothing behind.
func test_visiting_a_village_again_and_again_leaves_nothing_behind():
	var coord := _village_chunk()
	manager._load_chunk(coord)
	var standing := _carts().size()
	assert_gt(standing, 0, "precondition: this village really had a carter with a wagon")

	for i in 4:
		manager._unload_chunk(coord)
		manager._load_chunk(coord)

	assert_eq(_carts().size(), standing, "the same wagons, however many times it is visited")
	manager._unload_chunk(coord)


# -- a village founded under an older, smaller roster catches up ------------
# Reported live after the founding roster grew from five to ten: "the village
# still doesn't have 10 people". A village's household count is read back out
# of the persisted event graph, so one recorded as founded with five keeps
# five for ever however big a village is founded today -- the change is
# invisible in a world that already has villages in it.

const NpcIdentity = preload("res://src/world/npc_identity.gd")
const EntityRef = preload("res://src/emergence/entity_ref.gd")


func test_a_village_founded_smaller_grows_to_todays_founding_roster():
	var settlement_id := EntityRef.for_settlement(_chunk_coord)
	var founders: Array = []
	for i in 5:
		founders.append(NpcIdentity.new(hash("%d_%d_villager_%d" % [_chunk_coord.x, _chunk_coord.y, i])))
	manager.record_settlement_founded_if_new(_chunk_coord, founders)
	assert_eq(
		manager.household_count_for_settlement(settlement_id), 5,
		"precondition: an older save's village really was founded with five"
	)

	manager.settle_up_to_founding_roster(_chunk_coord)

	assert_eq(
		manager.household_count_for_settlement(settlement_id), SettlementGenerator.POPULATION,
		"a village founded under an older rule catches up to today's"
	)


## Once, not every visit -- and never DOWN: a village that has grown past the
## founding roster is not culled back to it.
func test_catching_up_never_shrinks_a_village_that_grew():
	var settlement_id := EntityRef.for_settlement(_chunk_coord)
	var founders: Array = []
	for i in 5:
		founders.append(NpcIdentity.new(hash("%d_%d_villager_%d" % [_chunk_coord.x, _chunk_coord.y, i])))
	manager.record_settlement_founded_if_new(_chunk_coord, founders)
	for i in SettlementGenerator.POPULATION + 3:
		manager.admit_household(_chunk_coord)
	var grown: int = manager.household_count_for_settlement(settlement_id)
	assert_gt(grown, SettlementGenerator.POPULATION, "precondition: it really outgrew the roster")

	manager.settle_up_to_founding_roster(_chunk_coord)

	assert_eq(manager.household_count_for_settlement(settlement_id), grown, "nobody is sent away")


func test_catching_up_a_chunk_with_no_village_settles_nobody():
	manager.settle_up_to_founding_roster(_chunk_coord)
	assert_eq(manager.household_count_for_settlement(EntityRef.for_settlement(_chunk_coord)), 0)


## And it happens on the visit, not only when something asks for it: a
## village the player walks back into is the village it would be founded as
## today.
func test_a_village_catches_up_on_the_visit():
	var settlement_id := EntityRef.for_settlement(_chunk_coord)
	var founders: Array = []
	for i in 5:
		founders.append(NpcIdentity.new(hash("%d_%d_villager_%d" % [_chunk_coord.x, _chunk_coord.y, i])))
	manager.record_settlement_founded_if_new(_chunk_coord, founders)
	assert_eq(manager.household_count_for_settlement(settlement_id), 5, "precondition")

	manager._unload_chunk(_chunk_coord)
	manager._load_chunk(_chunk_coord)

	assert_eq(manager.household_count_for_settlement(settlement_id), SettlementGenerator.POPULATION)
