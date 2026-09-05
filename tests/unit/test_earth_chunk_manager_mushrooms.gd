extends GutTest

## EarthChunkManager's wild-mushroom lifecycle (see docs/concept/
## mushrooms.md): a WildMushroomPatch per loaded chunk, visible
## MushroomMarkers kept in sync via step_wild_mushrooms, and the current
## player's identification state pushed in via set_mushroom_identification.
## Uses `_load_chunk` directly rather than `update()` (see CONTRIBUTING.md /
## test_earth_chunk_manager.gd's own known-slow-file note: a single
## `_load_chunk` costs a small fraction of a full `update()`'s radius of
## chunks).

const EarthChunkManager = preload("res://src/world/earth_chunk_manager.gd")
const EarthChunkGenerator = preload("res://src/world/earth_chunk_generator.gd")
const GeoCoordinates = preload("res://src/world/geo_coordinates.gd")
const WildMushroomPatch = preload("res://src/world/wild_mushroom_patch.gd")

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
	# Berlin -- same real-world spawn tile every other test file in this
	# project uses; reliably inland forest/grassland nearby.
	_berlin_tile = Vector2i(
		geo_coordinates.tile_for_longitude(13.405, EarthChunkGenerator.WORLD_WIDTH_TILES),
		geo_coordinates.tile_for_latitude(52.52, EarthChunkGenerator.WORLD_HEIGHT_TILES)
	)
	_berlin_chunk = Vector2i(
		floori(float(_berlin_tile.x) / EarthChunkManager.CHUNK_SIZE),
		floori(float(_berlin_tile.y) / EarthChunkManager.CHUNK_SIZE)
	)


func after_each():
	tile_map_layer.free()
	entities_parent.free()
	creatures_parent.free()


func test_loading_a_chunk_creates_a_wild_mushroom_patch():
	manager._load_chunk(_berlin_chunk)
	assert_true(manager._mushroom_sims.has(_berlin_chunk))
	assert_true(manager._mushroom_sims[_berlin_chunk] is WildMushroomPatch)


func test_loading_a_chunk_spawns_a_marker_per_fruiting_cell():
	manager._load_chunk(_berlin_chunk)
	var sim: WildMushroomPatch = manager._mushroom_sims[_berlin_chunk]
	assert_true(manager._mushroom_markers.has(_berlin_chunk))
	assert_eq(manager._mushroom_markers[_berlin_chunk].size(), sim.get_fruiting_cells().size())


func test_unloading_a_chunk_frees_its_mushroom_state():
	manager._load_chunk(_berlin_chunk)
	assert_true(manager._mushroom_sims.has(_berlin_chunk), "precondition: chunk actually loaded mushroom state")

	manager._unload_chunk(_berlin_chunk)

	assert_false(manager._mushroom_sims.has(_berlin_chunk))
	assert_false(manager._mushroom_markers.has(_berlin_chunk))


func test_step_wild_mushrooms_removes_a_marker_whose_mushroom_was_picked():
	manager._load_chunk(_berlin_chunk)
	var sim: WildMushroomPatch = manager._mushroom_sims[_berlin_chunk]
	var fruiting: Array = sim.get_fruiting_cells()
	if fruiting.is_empty():
		pass_test("precondition unmet (no fruiting site near Berlin this run) -- nothing to check")
		return
	var cell: Vector2i = fruiting[0]
	var marker = manager._mushroom_markers[_berlin_chunk][cell]

	sim.pick(cell)
	manager.step_wild_mushrooms(EarthChunkManager.CHUNK_SIZE)  # comfortably past the refresh interval

	assert_false(manager._mushroom_markers[_berlin_chunk].has(cell))
	assert_true(marker.is_queued_for_deletion())


func test_identification_reaches_every_live_marker_on_the_next_step():
	manager._load_chunk(_berlin_chunk)
	var sim: WildMushroomPatch = manager._mushroom_sims[_berlin_chunk]
	if sim.get_fruiting_cells().is_empty():
		pass_test("precondition unmet (no fruiting site near Berlin this run) -- nothing to check")
		return

	manager.set_mushroom_identification(true)
	manager.step_wild_mushrooms(EarthChunkManager.CHUNK_SIZE)

	for marker in manager._mushroom_markers[_berlin_chunk].values():
		assert_true(marker.identified)


func test_identification_defaults_to_false():
	manager._load_chunk(_berlin_chunk)
	var sim: WildMushroomPatch = manager._mushroom_sims[_berlin_chunk]
	if sim.get_fruiting_cells().is_empty():
		pass_test("precondition unmet (no fruiting site near Berlin this run) -- nothing to check")
		return
	for marker in manager._mushroom_markers[_berlin_chunk].values():
		assert_false(marker.identified)
