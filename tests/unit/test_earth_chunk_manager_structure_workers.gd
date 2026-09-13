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



# -- the Mill's Miller and the Bakery's Baker (docs/concept/milling_and_ ----
# -- baking.md): structure workers that convert the building's OWN stock ---
#
# Unlike the Sägewerk, whose logs live in its Lumberjack's private state,
# a Mill grinds whatever wheat has reached its real StructureStock (a
# hauler can feed it) and credits flour back to the same stock; a Bakery
# does the same with flour and bread. One worker per structure tile,
# spawned/despawned exactly like the Lumberjack and Farmer above.

const MillProduction = preload("res://src/world/mill_production.gd")
const BakeryProduction = preload("res://src/world/bakery_production.gd")


func test_building_a_mill_spawns_a_miller_wired_to_the_world():
	manager.build_at_global(_tile.x, _tile.y, "mill")
	var by_cell: Dictionary = manager._conversion_workers[_chunk_coord]
	assert_eq(by_cell.size(), 1)
	var marker = by_cell.values()[0]
	assert_eq(marker.earth, manager)
	assert_eq(marker.get_display_name(), "Miller")


func test_building_a_bakery_spawns_a_baker():
	manager.build_at_global(_tile.x, _tile.y, "bakery")
	var marker = manager._conversion_workers[_chunk_coord].values()[0]
	assert_eq(marker.get_display_name(), "Baker")


func test_rebuilding_the_same_mill_tile_never_double_spawns_and_destroying_despawns():
	manager.build_at_global(_tile.x, _tile.y, "mill")
	manager.build_at_global(_tile.x, _tile.y, "mill")
	assert_eq(manager._conversion_workers[_chunk_coord].size(), 1)
	manager.destroy_at_global(_tile.x, _tile.y)
	assert_eq(manager._conversion_workers[_chunk_coord].size(), 0)


func test_a_mill_grinds_the_wheat_in_its_own_stock_into_flour():
	manager.build_at_global(_tile.x, _tile.y, "mill")
	manager.deposit_to_structure_at(_tile.x, _tile.y, "wheat", 3)
	var miller = manager._conversion_workers[_chunk_coord].values()[0]

	miller._step_production(MillProduction.MILL_SECONDS_PER_FLOUR)

	assert_eq(manager.structure_stock_at(_tile.x, _tile.y, "flour"), 1)
	assert_eq(manager.structure_stock_at(_tile.x, _tile.y, "wheat"), 3 - int(MillProduction.WHEAT_PER_FLOUR))


func test_a_mill_with_no_wheat_grinds_nothing():
	manager.build_at_global(_tile.x, _tile.y, "mill")
	var miller = manager._conversion_workers[_chunk_coord].values()[0]
	miller._step_production(MillProduction.MILL_SECONDS_PER_FLOUR * 10.0)
	assert_eq(manager.structure_stock_at(_tile.x, _tile.y, "flour"), 0)


func test_a_bakery_bakes_the_flour_in_its_own_stock_into_bread():
	manager.build_at_global(_tile.x, _tile.y, "bakery")
	manager.deposit_to_structure_at(_tile.x, _tile.y, "flour", 2)
	var baker = manager._conversion_workers[_chunk_coord].values()[0]

	baker._step_production(BakeryProduction.BAKE_SECONDS_PER_BREAD)

	assert_eq(manager.structure_stock_at(_tile.x, _tile.y, "bread"), 1)
	assert_eq(manager.structure_stock_at(_tile.x, _tile.y, "flour"), 2 - int(BakeryProduction.FLOUR_PER_BREAD))


func test_a_persisted_mill_gets_its_miller_back_on_reload():
	manager.build_at_global(_tile.x, _tile.y, "mill")
	manager._unload_chunk(_chunk_coord)
	assert_false(manager._conversion_workers.has(_chunk_coord), "unload frees the worker")
	manager._load_chunk(_chunk_coord)
	assert_eq(manager._conversion_workers[_chunk_coord].size(), 1, "the persisted tile re-staffs on load")
	# Tests share one real user:// dir (see test_earth_chunk_manager.gd's
	# own scrub convention) -- never leave a persisted mill at (0, 0) behind
	# for every other _load_chunk(Vector2i(0, 0)) fixture to find.
	var path: String = manager._modifications_path(_chunk_coord)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
