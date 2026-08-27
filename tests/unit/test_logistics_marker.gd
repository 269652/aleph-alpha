extends GutTest

## LogisticsMarker: the engine glue for a Logistics worker (see
## docs/concept/timber_construction.md's "Storage, logistics, and the
## autonomous dependency chain" section) -- walks to a source structure
## carrying real waiting stock, collects it, carries it to the nearest
## Storage, and deposits it. Mirrors DecomposerMarker's own
## match-on-behavior-phase engine-glue split exactly.
##
## Honesty note: no real production building accumulates output on its own
## in this codebase yet (see this doc section's own gap note) -- these tests
## seed a source structure's stock directly via
## EarthChunkManager.deposit_to_structure_at, standing in for "a producer
## already piled up real output here", exactly the way test_earth_chunk_
## manager.gd's own has_structure_near tests place a bare structure tile
## without a real building process behind it. The collect/carry/deposit loop
## itself, and the stock it moves, are both real.

const LogisticsMarker = preload("res://src/rendering/logistics_marker.gd")
const LogisticsBehavior = preload("res://src/gameplay/logistics_behavior.gd")
const EarthChunkManager = preload("res://src/world/earth_chunk_manager.gd")
const EarthChunkGenerator = preload("res://src/world/earth_chunk_generator.gd")
const GeoCoordinates = preload("res://src/world/geo_coordinates.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")

var manager: EarthChunkManager
var marker: LogisticsMarker
var _berlin_tile: Vector2i
var _geo_coordinates := GeoCoordinates.new()
var _tile_map_layer: TileMapLayer
var _entities_parent: Node2D
var _creatures_parent: Node2D


func before_each():
	_tile_map_layer = TileMapLayer.new()
	_entities_parent = Node2D.new()
	_creatures_parent = Node2D.new()
	manager = EarthChunkManager.new(_tile_map_layer, _entities_parent, _creatures_parent)
	_berlin_tile = Vector2i(
		_geo_coordinates.tile_for_longitude(13.405, EarthChunkGenerator.WORLD_WIDTH_TILES),
		_geo_coordinates.tile_for_latitude(52.52, EarthChunkGenerator.WORLD_HEIGHT_TILES)
	)
	manager.update(_berlin_tile)

	marker = LogisticsMarker.new()
	marker.earth = manager
	marker.item_id = "plank"
	marker.source_structure_id = "furnace"  # stand-in producer id -- see class doc
	marker.storage_structure_id = "storage"
	marker.position = Vector2(_berlin_tile) * TerrainRenderer.TILE_SIZE
	add_child_autofree(marker)


func after_each():
	_tile_map_layer.free()
	_entities_parent.free()
	_creatures_parent.free()


func test_joins_the_logistics_worker_group():
	assert_true(marker.is_in_group(LogisticsMarker.GROUP_NAME))


func test_stays_seeking_when_no_source_structure_exists():
	for i in 10:
		marker._process(1.0)
	assert_eq(marker._behavior.phase, LogisticsBehavior.Phase.SEEKING)


## The full loop, end to end: a source with real waiting stock is found,
## walked to, collected, carried to storage, and deposited -- storage's own
## real stock increases.
func test_collects_from_a_source_and_deposits_into_storage():
	var source_tile := _berlin_tile + Vector2i(2, 0)
	var storage_tile := _berlin_tile + Vector2i(-2, 0)
	manager.build_at_global(source_tile.x, source_tile.y, "furnace")
	manager.build_at_global(storage_tile.x, storage_tile.y, "storage")
	manager.deposit_to_structure_at(source_tile.x, source_tile.y, "plank", 4)

	for i in 400:
		marker._process(0.25)
		if manager.structure_stock_at(storage_tile.x, storage_tile.y, "plank") > 0:
			break

	assert_gt(manager.structure_stock_at(storage_tile.x, storage_tile.y, "plank"), 0)


## What's picked up leaves the source's own stock -- this is a real transfer,
## not a duplication.
func test_collecting_withdraws_from_the_source_stock():
	var source_tile := _berlin_tile + Vector2i(2, 0)
	var storage_tile := _berlin_tile + Vector2i(-2, 0)
	manager.build_at_global(source_tile.x, source_tile.y, "furnace")
	manager.build_at_global(storage_tile.x, storage_tile.y, "storage")
	manager.deposit_to_structure_at(source_tile.x, source_tile.y, "plank", 4)

	for i in 400:
		marker._process(0.25)
		if manager.structure_stock_at(storage_tile.x, storage_tile.y, "plank") > 0:
			break

	assert_eq(manager.structure_stock_at(source_tile.x, source_tile.y, "plank"), 0)


## Once its cargo is deposited, the worker returns to seeking and can start a
## fresh run rather than freezing after its first trip.
func test_returns_to_seeking_once_the_delivery_is_complete():
	var source_tile := _berlin_tile + Vector2i(2, 0)
	var storage_tile := _berlin_tile + Vector2i(-2, 0)
	manager.build_at_global(source_tile.x, source_tile.y, "furnace")
	manager.build_at_global(storage_tile.x, storage_tile.y, "storage")
	manager.deposit_to_structure_at(source_tile.x, source_tile.y, "plank", 4)

	for i in 400:
		marker._process(0.25)
		if manager.structure_stock_at(storage_tile.x, storage_tile.y, "plank") > 0:
			break
	marker._process(1.0)

	assert_eq(marker._behavior.phase, LogisticsBehavior.Phase.SEEKING)
	assert_eq(marker.carried_item_id, "")
	assert_eq(marker.carried_count, 0)


# -- preferred_storage_position (see docs/concept/timber_construction.md's --
# -- own named honest constraint this closes: a Sägewerk-paired worker must --
# -- deliver to ITS OWN paired Storage, not whichever Storage its own -------
# -- dynamic nearest_structure_position lookup would independently converge -
# -- on -- every worker doing that would defeat multi-storage pairing) ------

func test_preferred_storage_position_is_unset_by_default():
	assert_null(marker.preferred_storage_position, "existing single-storage callers never set this")


## Regression: with preferred_storage_position left unset, behavior is
## unchanged from before this field existed -- the worker still finds and
## delivers to a Storage via the existing dynamic nearest_structure_position
## lookup.
func test_falls_back_to_nearest_structure_position_when_preferred_storage_position_is_unset():
	var source_tile := _berlin_tile + Vector2i(2, 0)
	var storage_tile := _berlin_tile + Vector2i(-2, 0)
	manager.build_at_global(source_tile.x, source_tile.y, "furnace")
	manager.build_at_global(storage_tile.x, storage_tile.y, "storage")
	manager.deposit_to_structure_at(source_tile.x, source_tile.y, "plank", 4)

	for i in 400:
		marker._process(0.25)
		if manager.structure_stock_at(storage_tile.x, storage_tile.y, "plank") > 0:
			break

	assert_gt(manager.structure_stock_at(storage_tile.x, storage_tile.y, "plank"), 0)


## The actual fix: when preferred_storage_position IS set, the worker
## delivers there directly, ignoring a closer Storage that
## nearest_structure_position would otherwise have picked -- this is what
## makes pairing a Sägewerk with more than one Storage mean anything.
func test_delivers_to_the_preferred_storage_instead_of_the_nearer_one():
	var source_tile := _berlin_tile + Vector2i(2, 0)
	var near_storage_tile := _berlin_tile + Vector2i(-1, 0)  # closer to the source than far_storage
	var far_storage_tile := _berlin_tile + Vector2i(-10, 0)
	manager.build_at_global(source_tile.x, source_tile.y, "furnace")
	manager.build_at_global(near_storage_tile.x, near_storage_tile.y, "storage")
	manager.build_at_global(far_storage_tile.x, far_storage_tile.y, "storage")
	manager.deposit_to_structure_at(source_tile.x, source_tile.y, "plank", 4)

	marker.preferred_storage_position = Vector2(far_storage_tile) * TerrainRenderer.TILE_SIZE + (
		Vector2.ONE * (TerrainRenderer.TILE_SIZE * 0.5)
	)

	for i in 800:
		marker._process(0.25)
		if manager.structure_stock_at(far_storage_tile.x, far_storage_tile.y, "plank") > 0:
			break

	assert_gt(
		manager.structure_stock_at(far_storage_tile.x, far_storage_tile.y, "plank"), 0,
		"delivered to the preferred (farther) storage"
	)
	assert_eq(
		manager.structure_stock_at(near_storage_tile.x, near_storage_tile.y, "plank"), 0,
		"the nearer storage nearest_structure_position would have picked gets nothing"
	)
