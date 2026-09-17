extends GutTest

## A village pond is REAL water (docs/concept/village_ponds.md). Asked for
## directly: "filled with water and a pond with river water physics".
##
## Two world queries are the whole of it. Everything else in the game that
## cares about water already asks one of them, so a pond needs no case of its
## own anywhere else: creatures refuse it, the surface paints it, and what
## floats in it drifts.
##
## Uses _load_chunk directly rather than the slow real update(), the same way
## test_earth_chunk_manager_bees.gd and its siblings do.

const EarthChunkManager = preload("res://src/world/earth_chunk_manager.gd")
const EarthChunkGenerator = preload("res://src/world/earth_chunk_generator.gd")
const GeoCoordinates = preload("res://src/world/geo_coordinates.gd")
const VillagePond = preload("res://src/gameplay/village_pond.gd")
const VillageFarm = preload("res://src/gameplay/village_farm.gd")

var tile_map_layer: TileMapLayer
var entities_parent: Node2D
var creatures_parent: Node2D
var manager: EarthChunkManager
var _tile: Vector2i


func before_each():
	tile_map_layer = TileMapLayer.new()
	entities_parent = Node2D.new()
	creatures_parent = Node2D.new()
	manager = EarthChunkManager.new(tile_map_layer, entities_parent, creatures_parent)
	add_child(entities_parent)
	var geo := GeoCoordinates.new()
	# Deliberately inland: a tile that is already river or ocean could not
	# tell a pond's own answer from the ground's.
	_tile = Vector2i(
		geo.tile_for_longitude(13.405, EarthChunkGenerator.WORLD_WIDTH_TILES),
		geo.tile_for_latitude(52.52, EarthChunkGenerator.WORLD_HEIGHT_TILES)
	)
	manager.update(_tile)


func after_each():
	remove_child(entities_parent)
	entities_parent.free()
	creatures_parent.free()
	tile_map_layer.free()


func test_dry_ground_is_not_water_before_anybody_digs():
	assert_false(manager.is_water_at_global(_tile.x, _tile.y), "precondition: dry inland ground")
	assert_false(manager.is_river_at_global(_tile.x, _tile.y))


func test_a_dug_pond_cell_reads_as_real_water():
	manager.build_at_global(_tile.x, _tile.y, VillagePond.POND_TILE_ID)
	assert_true(
		manager.is_water_at_global(_tile.x, _tile.y),
		"a pond nothing reads as water is a brown square with fish drawn on it"
	)


## "River water physics": the flow overlay and FishMarker's own current both
## key on is_river_at_global, so a pond that answers it moves what floats in
## it without either of them learning about ponds.
func test_a_dug_pond_carries_river_flow():
	manager.build_at_global(_tile.x, _tile.y, VillagePond.POND_TILE_ID)
	assert_true(manager.is_river_at_global(_tile.x, _tile.y))


## Filling one in gives the ground back -- a pond is a thing somebody dug,
## not a permanent change to the world.
func test_filling_a_pond_in_leaves_dry_ground_again():
	manager.build_at_global(_tile.x, _tile.y, VillagePond.POND_TILE_ID)
	manager.destroy_at_global(_tile.x, _tile.y)
	assert_false(manager.is_water_at_global(_tile.x, _tile.y))
	assert_false(manager.is_river_at_global(_tile.x, _tile.y))


## And nothing ELSE built becomes water by accident.
func test_no_other_built_tile_reads_as_water():
	manager.build_at_global(_tile.x, _tile.y, VillageFarm.fence_tile_for("north"))
	assert_false(manager.is_water_at_global(_tile.x, _tile.y))
	assert_false(manager.is_river_at_global(_tile.x, _tile.y))


## Nobody may build on open water, so nobody may build on a pond either --
## otherwise a village would site a house in the fisher's own water.
func test_a_pond_is_not_ground_anybody_may_build_on():
	manager.build_at_global(_tile.x, _tile.y, VillagePond.POND_TILE_ID)
	assert_false(manager.is_buildable_ground_at(_tile.x, _tile.y))
