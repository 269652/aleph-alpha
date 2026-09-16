extends GutTest

## Real terrain buildability for houses (docs/concept/building.md) --
## reported directly: "houses / buildings cannot be built on river / water;
## also not in the forest... the NPCs / Player must first fell all trees to
## make space for the building." Before this, can_build_house_from_blueprint
## only checked that a cell had no existing MODIFICATION -- water, forest,
## and standing trees were never checked at all, and BuilderMarker's own
## `_buildable_ground` was a named, honest permissive stand-in ("no live
## caller anywhere in this codebase checks real water/cliff buildability").
##
## tree_at_global/is_buildable_terrain_at close that gap. is_buildable_
## terrain_at is a thin, real aggregator over FOUR already-real, already-
## tested primitives (biome_at_global, is_river_at_global, is_lake_at_global,
## tree_at_global) -- the risk here is wiring the boolean logic correctly,
## not the primitives themselves, so this suite finds one REAL example of
## each blocking condition rather than mocking terrain.
##
## Shared, expensive real-world fixture (manager.update(_berlin_tile), the
## SAME real Berlin tile every other test in this file's sibling
## (test_earth_chunk_manager.gd) already anchors on -- "Berlin sits on the
## Spree's own curated course", reliably giving real river/ocean/forest
## cells within one real update() call) -- built ONCE in before_all and
## reused read-only across every test below, since a single real update()
## costs ~100s (see CONTRIBUTING.md) and none of these tests mutate biome/
## river/lake state (the one tree injected below is added to its OWN
## dedicated chunk, never queried by any other test in this file).

const EarthChunkManager = preload("res://src/world/earth_chunk_manager.gd")
const GeoCoordinates = preload("res://src/world/geo_coordinates.gd")
const EarthChunkGenerator = preload("res://src/world/earth_chunk_generator.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")

var manager: EarthChunkManager
var tile_map_layer: TileMapLayer
var entities_parent: Node2D
var creatures_parent: Node2D
var _berlin_tile: Vector2i


func before_all():
	tile_map_layer = TileMapLayer.new()
	entities_parent = Node2D.new()
	creatures_parent = Node2D.new()
	manager = EarthChunkManager.new(tile_map_layer, entities_parent, creatures_parent)
	var geo_coordinates := GeoCoordinates.new()
	_berlin_tile = Vector2i(
		geo_coordinates.tile_for_longitude(13.405, EarthChunkGenerator.WORLD_WIDTH_TILES),
		geo_coordinates.tile_for_latitude(52.52, EarthChunkGenerator.WORLD_HEIGHT_TILES)
	)
	manager.update(_berlin_tile)


func after_all():
	tile_map_layer.free()
	entities_parent.free()
	creatures_parent.free()


## Every loaded cell, so a test can scan for one real example of whatever
## condition it needs (mirrors test_earth_chunk_manager.gd's own established
## "scan the loaded radius for a real example" convention).
func _each_loaded_cell() -> Array:
	var cells: Array = []
	var center_chunk := Vector2i(
		floori(float(_berlin_tile.x) / EarthChunkManager.CHUNK_SIZE),
		floori(float(_berlin_tile.y) / EarthChunkManager.CHUNK_SIZE)
	)
	for chunk_coord in manager.chunks_in_radius(center_chunk, EarthChunkManager.LOAD_RADIUS):
		for y in EarthChunkManager.CHUNK_SIZE:
			for x in EarthChunkManager.CHUNK_SIZE:
				cells.append(Vector2i(chunk_coord.x * EarthChunkManager.CHUNK_SIZE + x, chunk_coord.y * EarthChunkManager.CHUNK_SIZE + y))
	return cells


# -- tree_at_global -----------------------------------------------------------

func test_tree_at_global_is_false_with_no_tree():
	# A tile far outside anything spawn_trees could ever have touched.
	assert_false(manager.tree_at_global(_berlin_tile.x + 9000, _berlin_tile.y + 9000))


func test_tree_at_global_is_true_where_a_real_tree_node_stands():
	var chunk_coord := Vector2i(500, 500)  # a dedicated, unused chunk -- no other test touches this one
	var tree_tile := chunk_coord * EarthChunkManager.CHUNK_SIZE + Vector2i(4, 4)
	var fake_tree := Node2D.new()
	fake_tree.position = Vector2(
		(tree_tile.x + 0.5) * TerrainRenderer.TILE_SIZE, (tree_tile.y + 0.5) * TerrainRenderer.TILE_SIZE
	)
	manager._loaded_trees[chunk_coord] = [fake_tree]

	assert_true(manager.tree_at_global(tree_tile.x, tree_tile.y))
	assert_false(
		manager.tree_at_global(tree_tile.x + 1, tree_tile.y), "a neighboring EMPTY cell must not read as tree-blocked"
	)
	fake_tree.free()


# -- is_buildable_terrain_at: one real example of each blocking condition ----

func test_is_buildable_terrain_at_is_false_on_a_real_ocean_cell():
	for cell in _each_loaded_cell():
		if manager.biome_at_global(cell.x, cell.y) == "ocean":
			assert_false(manager.is_buildable_terrain_at(cell.x, cell.y))
			return
	pass_test("precondition unmet (no ocean cell in this run's loaded radius) -- nothing to check")


func test_is_buildable_terrain_at_is_false_on_a_real_forest_cell():
	for cell in _each_loaded_cell():
		if manager.biome_at_global(cell.x, cell.y) == "forest":
			assert_false(manager.is_buildable_terrain_at(cell.x, cell.y))
			return
	pass_test("precondition unmet (no forest cell in this run's loaded radius) -- nothing to check")


func test_is_buildable_terrain_at_is_false_on_a_real_river_cell():
	for cell in _each_loaded_cell():
		if manager.is_river_at_global(cell.x, cell.y):
			assert_false(manager.is_buildable_terrain_at(cell.x, cell.y))
			return
	pass_test("precondition unmet (no river cell in this run's loaded radius) -- nothing to check")


func test_is_buildable_terrain_at_is_false_on_a_real_lake_cell():
	for cell in _each_loaded_cell():
		if manager.is_lake_at_global(cell.x, cell.y):
			assert_false(manager.is_buildable_terrain_at(cell.x, cell.y))
			return
	pass_test("precondition unmet (no lake cell in this run's loaded radius) -- nothing to check")


func test_is_buildable_terrain_at_is_false_where_a_real_tree_stands():
	var chunk_coord := Vector2i(501, 500)  # a second dedicated, unused chunk
	var tree_tile := chunk_coord * EarthChunkManager.CHUNK_SIZE + Vector2i(4, 4)
	var fake_tree := Node2D.new()
	fake_tree.position = Vector2(
		(tree_tile.x + 0.5) * TerrainRenderer.TILE_SIZE, (tree_tile.y + 0.5) * TerrainRenderer.TILE_SIZE
	)
	manager._loaded_trees[chunk_coord] = [fake_tree]

	assert_false(manager.is_buildable_terrain_at(tree_tile.x, tree_tile.y))
	fake_tree.free()


## The village's own siting rule (docs/concept/building.md "Village
## layout"): a village fells what stands on its plots and square (placing
## a building or paving a road clears the vegetation there), so a standing
## tree is not what stops a village -- only ground that can never carry a
## building (water, the forest biome) is. The player's own rule
## (is_buildable_terrain_at: fell the trees first) is unchanged.
func test_is_buildable_ground_at_ignores_a_standing_tree_but_not_water_or_forest():
	# A real dry, plain cell of the loaded radius, with a tree planted on it
	# by hand -- the tree is the ONLY thing that could refuse it.
	var tree_tile := Vector2i.ZERO
	var found_open := false
	for cell in _each_loaded_cell():
		if manager.is_buildable_terrain_at(cell.x, cell.y):
			tree_tile = cell
			found_open = true
			break
	assert_true(found_open, "precondition: some plain buildable cell in the loaded radius")
	var chunk_coord := Vector2i(
		floori(float(tree_tile.x) / EarthChunkManager.CHUNK_SIZE), floori(float(tree_tile.y) / EarthChunkManager.CHUNK_SIZE)
	)
	var fake_tree := Node2D.new()
	fake_tree.position = Vector2(
		(tree_tile.x + 0.5) * TerrainRenderer.TILE_SIZE, (tree_tile.y + 0.5) * TerrainRenderer.TILE_SIZE
	)
	var trees_before = manager._loaded_trees.get(chunk_coord, [])
	var with_tree: Array[Node2D] = []
	with_tree.assign(trees_before)
	with_tree.append(fake_tree)
	manager._loaded_trees[chunk_coord] = with_tree

	assert_true(manager.is_buildable_ground_at(tree_tile.x, tree_tile.y), "a tree is felled, not built around")
	assert_false(manager.is_buildable_terrain_at(tree_tile.x, tree_tile.y), "the player's own rule still refuses")
	manager._loaded_trees[chunk_coord] = trees_before
	fake_tree.free()

	for cell in _each_loaded_cell():
		if manager.is_water_at_global(cell.x, cell.y) or manager.biome_at_global(cell.x, cell.y) == "forest":
			assert_false(manager.is_buildable_ground_at(cell.x, cell.y), "water/forest can never carry a village building")
			return
	pass_test("precondition unmet (no water/forest cell in this run's loaded radius) -- nothing to check")


## A cell with none of the four blocking conditions must read as buildable --
## the honest "not everything is blocked" counterpart to the five refusal
## tests above. Real dry, treeless, plain-biome ground is common, so this
## scans a bounded prefix rather than the whole loaded radius.
func test_is_buildable_terrain_at_is_true_on_plain_dry_treeless_ground():
	var cells := _each_loaded_cell()
	for i in mini(400, cells.size()):
		var cell: Vector2i = cells[i]
		var biome := manager.biome_at_global(cell.x, cell.y)
		if biome == "ocean" or biome == "forest":
			continue
		if manager.is_river_at_global(cell.x, cell.y) or manager.is_lake_at_global(cell.x, cell.y):
			continue
		if manager.tree_at_global(cell.x, cell.y):
			continue
		assert_true(manager.is_buildable_terrain_at(cell.x, cell.y))
		return
	pass_test("precondition unmet (no plain buildable cell found in the scanned prefix) -- nothing to check")


# -- water, by the one rule the water surface is drawn with ------------------
#
# Reported directly, with a screenshot of a stone house standing in a pond:
# "they shouldn't be able to build anything on water tiles." is_buildable_
# terrain_at asked is_river_at_global/is_lake_at_global/biome == ocean --
# but the live water surface (_paint_river_flow_overlay) paints MORE than
# that: a lake's gentle shoreline feather (lake_across < LAKE_PAINT_ACROSS),
# a sea pocket the biome array calls land (probe.sea), and a river's whole
# bank apron. A house could be sited on a cell painted blue. is_water_at_
# global is now the one rule both the overlay and buildability read, pinned
# here against the overlay's own decision, cell by cell, over the real
# Berlin radius.

const RiverCatalog = preload("res://src/world/river_catalog.gd")

var _painted_cache = null


## Exactly _paint_river_flow_overlay's own paint-or-erase decision.
func _painted_as_water(cell: Vector2i) -> bool:
	if manager.biome_at_global(cell.x, cell.y) == "ocean":
		return true  # the ocean biome's own terrain tile is water art
	var probe: Dictionary = manager.generator.hydrology_at_global(cell.x, cell.y)
	var still: bool = (
		probe["kind"] == "lake" or bool(probe.get("sea", false))
		or float(probe["lake_across"]) < EarthChunkManager.LAKE_PAINT_ACROSS
	)
	if probe["kind"] != "river" and still:
		return true
	var nearest: Dictionary = manager.generator.nearest_river_at(cell.x, cell.y)
	var half_width: float = float(nearest.get("half_width_tiles", RiverCatalog.RIVER_HALF_WIDTH_TILES))
	return float(nearest.get("distance_tiles", INF)) <= half_width + RiverCatalog.RIVER_BANK_APRON_TILES


func _painted_cells() -> Dictionary:
	if _painted_cache == null:
		_painted_cache = {}
		for cell in _each_loaded_cell():
			_painted_cache[cell] = _painted_as_water(cell)
	return _painted_cache


func test_a_painted_water_cell_the_old_checks_missed_is_no_longer_buildable():
	var gap = null
	for cell in _painted_cells():
		if not _painted_cells()[cell]:
			continue
		if (
			manager.is_river_at_global(cell.x, cell.y) or manager.is_lake_at_global(cell.x, cell.y)
			or manager.biome_at_global(cell.x, cell.y) == "ocean"
		):
			continue
		gap = cell
		break
	assert_not_null(gap, "precondition: the Berlin radius has a painted-water cell the old checks missed (a river bank, a shore feather)")
	if gap == null:
		return
	assert_true(manager.is_water_at_global(gap.x, gap.y), "%s is painted as water, so it IS water" % str(gap))
	assert_false(manager.is_buildable_terrain_at(gap.x, gap.y), "...and nothing may be built on it")


func test_every_cell_the_water_surface_paints_is_water_and_unbuildable():
	var checked := 0
	var wrong := 0
	for cell in _painted_cells():
		if not _painted_cells()[cell]:
			continue
		checked += 1
		if not manager.is_water_at_global(cell.x, cell.y) or manager.is_buildable_terrain_at(cell.x, cell.y):
			wrong += 1
	assert_gt(checked, 0, "precondition: real water in the radius")
	assert_eq(wrong, 0, "%d painted-water cells read as dry/buildable" % wrong)


func test_a_cell_the_water_surface_leaves_dry_is_not_water():
	var checked := 0
	var wrong := 0
	for cell in _painted_cells():
		if _painted_cells()[cell]:
			continue
		checked += 1
		if manager.is_water_at_global(cell.x, cell.y):
			wrong += 1
	assert_gt(checked, 0)
	assert_eq(wrong, 0, "%d dry cells read as water" % wrong)
