extends GutTest

## A piece occupies its tile against vegetation, in both directions (docs/
## concept/building.md "Placement rules"; reported directly: "grass must be
## cut before and can't grow back inside a house"). Trees already had this
## rule at all three seams (stamp / spawn_trees / spread). The ground cover
## -- tall grass, flowers, desert scrub, tundra lichen -- did not: their
## sims never looked at chunk.modifications, so grass and flowers stood
## inside every house and grew back through the floor. These pin the
## manager-side wiring of the sims' own block_cells: on build, on a village
## stamp, on reload of a persisted piece, and released again on destroy;
## plus the one thing trees still lacked -- a house's doorstep and the
## one-cell apron around it stay clear of trees, so no tree ever stands in
## front of a door.
##
## Berlin's real chunk (grassland, so the grass and flower sims have
## something to grow) loaded via _load_chunk -- see test_earth_chunk_
## manager.gd's own known-slow-file note -- persisted files scrubbed before
## and after.

const EarthChunkManager = preload("res://src/world/earth_chunk_manager.gd")
const GeoCoordinates = preload("res://src/world/geo_coordinates.gd")
const EarthChunkGenerator = preload("res://src/world/earth_chunk_generator.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")
const BuildingPiece = preload("res://src/gameplay/building_piece.gd")

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
	for path in [
		manager._modifications_path(_chunk_coord), manager._roof_modifications_path(_chunk_coord),
		manager._furniture_modifications_path(_chunk_coord), manager._upper_floor_modifications_path(_chunk_coord),
		manager._upper_floor_furniture_modifications_path(_chunk_coord),
	]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func _grass():
	return manager._grass_sims[_chunk_coord]


func _flowers():
	return manager._flower_patches[_chunk_coord]


## A real grass cell that is also dry, buildable ground -- what a player or
## a village would actually build on.
func _a_buildable_grass_cell():
	for local in _grass().get_patch_cells():
		var g: Vector2i = _chunk_coord * EarthChunkManager.CHUNK_SIZE + local
		if manager.is_buildable_terrain_at(g.x, g.y):
			return local
	return null


func _global(local: Vector2i) -> Vector2i:
	return _chunk_coord * EarthChunkManager.CHUNK_SIZE + local


# -- one piece, built and destroyed -------------------------------------------

func test_building_a_piece_on_grass_clears_it_and_grass_never_regrows_there():
	var local = _a_buildable_grass_cell()
	assert_not_null(local, "precondition: Berlin's chunk has grass on buildable ground")
	if local == null:
		return
	var g := _global(local)
	manager.build_at_global(g.x, g.y, "wood_floor")
	assert_false(_grass().has_grass(local), "the floor took the grass")
	assert_false(_grass().plant(local), "...and nothing plants through a floor")
	assert_false(_flowers().plant(local, "poppy"))


func test_destroying_the_piece_gives_the_ground_back():
	var local = _a_buildable_grass_cell()
	if local == null:
		return
	var g := _global(local)
	manager.build_at_global(g.x, g.y, "wood_floor")
	manager.destroy_at_global(g.x, g.y)
	assert_true(_grass().plant(local), "bare ground again: grass may take it back")


func test_an_earth_path_is_not_a_piece_and_blocks_nothing():
	var local = _a_buildable_grass_cell()
	if local == null:
		return
	var g := _global(local)
	manager.build_at_global(g.x, g.y, TerrainRenderer.EARTH_TILE_ID)
	assert_true(_grass().has_grass(local), "only a real BuildingPiece occupies a tile against vegetation")


# -- a whole house, stamped -----------------------------------------------------

func test_a_stamped_house_clears_every_grass_and_flower_cell_under_it():
	var local = _a_buildable_grass_cell()
	if local == null:
		return
	var origin := _global(local)
	var pieces := {}
	for x in 4:
		for y in 4:
			pieces[Vector2i(x, y)] = "wood_wall" if (x == 0 or y == 0 or x == 3 or y == 3) else "wood_floor"
	manager.stamp_structure_at_global(_chunk_coord, origin, pieces, {})
	for cell in pieces:
		var l: Vector2i = local + cell
		assert_false(_grass().has_grass(l), "grass left standing inside the house at %s" % str(l))
		assert_false(_flowers().has_flower(l), "a flower left standing inside the house at %s" % str(l))


# -- a persisted piece, reloaded ---------------------------------------------

func test_a_persisted_piece_blocks_ground_cover_again_on_reload():
	var local = _a_buildable_grass_cell()
	if local == null:
		return
	var g := _global(local)
	manager.build_at_global(g.x, g.y, "wood_floor")
	manager._unload_chunk(_chunk_coord)
	manager._load_chunk(_chunk_coord)
	assert_false(_grass().has_grass(local), "the reloaded chunk's fresh grass sim must not regrow through the persisted floor")
	assert_false(_grass().plant(local))


# -- trees: the doorstep and apron stay clear -------------------------------

func test_a_stamped_house_fells_the_tree_on_its_doorstep_apron():
	var local = _a_buildable_grass_cell()
	if local == null:
		return
	var origin := _global(local)
	# A "tree" standing one cell south of the house's bottom wall -- where a
	# door would open. _clear_vegetation_on_cells reads only position and
	# validity, so a bare Node2D stands in for a ChoppableTree here.
	var doorstep := origin + Vector2i(1, 4)
	var tree := Node2D.new()
	tree.position = (Vector2(doorstep) + Vector2(0.5, 0.5)) * TerrainRenderer.TILE_SIZE
	entities_parent.add_child(tree)
	manager._loaded_trees[_chunk_coord].append(tree)
	assert_true(manager.tree_at_global(doorstep.x, doorstep.y), "precondition: the tree stands on the doorstep")

	var pieces := {}
	for x in 4:
		for y in 4:
			pieces[Vector2i(x, y)] = "wood_wall" if (x == 0 or y == 0 or x == 3 or y == 3) else "wood_floor"
	manager.stamp_structure_at_global(_chunk_coord, origin, pieces, {})

	assert_false(manager.tree_at_global(doorstep.x, doorstep.y), "a village clears the ground around a house, doorstep included")


func test_no_tree_respawns_on_a_houses_apron_after_reload():
	var local = _a_buildable_grass_cell()
	if local == null:
		return
	var g := _global(local)
	manager.build_at_global(g.x, g.y, "wood_wall")
	manager._unload_chunk(_chunk_coord)
	manager._load_chunk(_chunk_coord)
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var cell := g + Vector2i(dx, dy)
			assert_false(
				manager.tree_at_global(cell.x, cell.y),
				"a map tree respawned within a cell of a persisted piece at %s" % str(cell)
			)


func test_touches_building_piece_reads_the_eight_neighbours_and_the_cell_itself():
	var modifications := {Vector2i(5, 5): "wood_wall", Vector2i(9, 9): TerrainRenderer.EARTH_TILE_ID}
	assert_true(BuildingPiece.touches_piece(modifications, Vector2i(5, 5)), "the cell itself")
	assert_true(BuildingPiece.touches_piece(modifications, Vector2i(6, 6)), "diagonal neighbour")
	assert_true(BuildingPiece.touches_piece(modifications, Vector2i(5, 4)), "cardinal neighbour")
	assert_false(BuildingPiece.touches_piece(modifications, Vector2i(7, 5)), "two cells away")
	assert_false(BuildingPiece.touches_piece(modifications, Vector2i(9, 9)), "an earth path is not a piece")
