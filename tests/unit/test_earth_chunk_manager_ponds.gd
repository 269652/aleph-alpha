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


# -- fish that live there and breed ----------------------------------------
#
# "...and fish swimming in it which reproduce". A pond holds its own small
# stock, grown on the world's own ecology tick toward what its water can
# feed (docs/concept/village_ponds.md).


func _dig_pond(cells: Array) -> void:
	for cell in cells:
		manager.build_at_global((cell as Vector2i).x, (cell as Vector2i).y, VillagePond.POND_TILE_ID)


func _a_pond() -> Array:
	var cells: Array = []
	for y in 2:
		for x in 3:
			cells.append(_tile + Vector2i(x, y))
	return cells


func test_water_nobody_stocked_holds_no_fish():
	var cells := _a_pond()
	_dig_pond(cells)
	assert_almost_eq(manager.pond_fish_at(_tile.x, _tile.y), 0.0, 0.0001)


func test_stocking_a_pond_puts_real_fish_in_it():
	var cells := _a_pond()
	_dig_pond(cells)
	manager.stock_pond_at(_tile.x, _tile.y)
	assert_almost_eq(
		manager.pond_fish_at(_tile.x, _tile.y), float(VillagePond.STOCKING_FISH), 0.0001
	)


## Every cell of the same water is the same stock -- a pond is one body of
## water, not six buckets.
func test_every_cell_of_one_pond_reports_the_same_stock():
	var cells := _a_pond()
	_dig_pond(cells)
	manager.stock_pond_at(_tile.x, _tile.y)
	for cell in cells:
		assert_almost_eq(
			manager.pond_fish_at((cell as Vector2i).x, (cell as Vector2i).y),
			float(VillagePond.STOCKING_FISH), 0.0001, str(cell)
		)


func test_a_stocked_pond_breeds_on_the_worlds_own_tick():
	var cells := _a_pond()
	_dig_pond(cells)
	manager.stock_pond_at(_tile.x, _tile.y)
	var before: float = manager.pond_fish_at(_tile.x, _tile.y)

	for _day in 30:
		manager.step_ponds(3600.0)  # ChunkEcologyCatchup.SECONDS_PER_DAY

	var after: float = manager.pond_fish_at(_tile.x, _tile.y)
	assert_gt(after, before, "the stock never bred")
	assert_lte(
		after, VillagePond.carrying_capacity(cells.size(), 0.55) + 1.0,
		"a pond fed more fish than its water can"
	)


## Stocking is not spontaneous, and neither is breeding from nothing.
func test_an_unstocked_pond_stays_empty_however_long_it_ticks():
	_dig_pond(_a_pond())
	for _day in 30:
		manager.step_ponds(3600.0)
	assert_almost_eq(manager.pond_fish_at(_tile.x, _tile.y), 0.0, 0.0001)


## Stocking twice does not double the stock -- a fisher stocks a pond, they
## do not keep stocking it.
func test_stocking_an_already_stocked_pond_changes_nothing():
	_dig_pond(_a_pond())
	manager.stock_pond_at(_tile.x, _tile.y)
	manager.stock_pond_at(_tile.x, _tile.y)
	assert_almost_eq(
		manager.pond_fish_at(_tile.x, _tile.y), float(VillagePond.STOCKING_FISH), 0.0001
	)


func test_dry_ground_can_neither_be_stocked_nor_report_fish():
	manager.stock_pond_at(_tile.x, _tile.y)
	assert_almost_eq(manager.pond_fish_at(_tile.x, _tile.y), 0.0, 0.0001)
