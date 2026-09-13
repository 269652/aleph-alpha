extends GutTest

## Nothing built stands in water (docs/concept/building.md "Terrain
## buildability"). Two halves: the pure still-water rule the water surface
## and buildability now share (is_still_water_probe), and what happens to a
## house piece that is ALREADY persisted on a water cell -- reported with a
## screenshot of a stone house standing in a pond, from a save made before
## the water rule existed: the water reclaims it on the next load, the way
## nothing anyone builds in a pond survives the pond. A dam is the one piece
## that belongs in water and is left alone.
##
## Berlin's real chunk (land plus the Spree, so both a wet and a dry cell
## exist) loaded directly via _load_chunk -- see test_earth_chunk_manager.gd's
## own known-slow-file note -- with its persisted files scrubbed before and
## after, since tests share one real user:// dir.

const EarthChunkManager = preload("res://src/world/earth_chunk_manager.gd")
const GeoCoordinates = preload("res://src/world/geo_coordinates.gd")
const EarthChunkGenerator = preload("res://src/world/earth_chunk_generator.gd")

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


func _a_cell_where(predicate: Callable):
	for y in EarthChunkManager.CHUNK_SIZE:
		for x in EarthChunkManager.CHUNK_SIZE:
			var cell: Vector2i = _chunk_coord * EarthChunkManager.CHUNK_SIZE + Vector2i(x, y)
			if predicate.call(cell):
				return cell
	return null


func _water_cell():
	return _a_cell_where(func(c: Vector2i) -> bool: return manager.is_water_at_global(c.x, c.y))


func _dry_cell():
	return _a_cell_where(func(c: Vector2i) -> bool: return manager.is_buildable_terrain_at(c.x, c.y))


# -- the still-water rule, as data --------------------------------------------

func test_is_still_water_probe_reads_exactly_what_the_water_surface_paints():
	assert_true(EarthChunkManager.is_still_water_probe({"kind": "lake", "sea": false, "lake_across": 99.0}), "a lake")
	assert_true(EarthChunkManager.is_still_water_probe({"kind": "", "sea": true, "lake_across": 99.0}), "a sea pocket")
	assert_true(
		EarthChunkManager.is_still_water_probe({"kind": "", "sea": false, "lake_across": EarthChunkManager.LAKE_PAINT_ACROSS - 0.1}),
		"a gentle shore's own feather cell"
	)
	assert_false(EarthChunkManager.is_still_water_probe({"kind": "", "sea": false, "lake_across": 99.0}), "dry land")
	assert_false(EarthChunkManager.is_still_water_probe({"kind": "river", "sea": true, "lake_across": 0.0}), "a river cell is flowing water, painted by the river branch instead")


# -- the water reclaims what should never have stood in it -------------------

func test_a_house_piece_persisted_on_water_is_washed_away_on_load():
	var wet = _water_cell()
	assert_not_null(wet, "precondition: Berlin's chunk has water (the Spree)")
	if wet == null:
		return
	manager.build_at_global(wet.x, wet.y, "wood_floor")  # the raw write never checked terrain; an old save could hold this
	var local: Vector2i = manager._local_coord(wet.x, wet.y)
	manager._loaded_chunks[_chunk_coord].roof_modifications[local] = "wood_roof"
	manager._loaded_chunks[_chunk_coord].furniture_modifications[local] = "wood_bed"
	manager._unload_chunk(_chunk_coord)

	manager._load_chunk(_chunk_coord)

	assert_eq(manager.modification_at_global(wet.x, wet.y), "", "the floor is gone")
	assert_eq(manager.roof_at_global(wet.x, wet.y), "", "...its roof with it")
	assert_eq(manager.furniture_at_global(wet.x, wet.y), "", "...and the bed")


func test_a_dam_persisted_in_water_is_left_alone():
	var wet = _water_cell()
	if wet == null:
		return
	manager.build_at_global(wet.x, wet.y, "stone_dam")
	manager._unload_chunk(_chunk_coord)
	manager._load_chunk(_chunk_coord)
	assert_eq(manager.modification_at_global(wet.x, wet.y), "stone_dam", "a dam belongs in water")


func test_a_house_piece_on_dry_ground_survives_a_reload():
	var dry = _dry_cell()
	assert_not_null(dry, "precondition: Berlin's chunk has dry ground")
	if dry == null:
		return
	manager.build_at_global(dry.x, dry.y, "wood_floor")
	manager._unload_chunk(_chunk_coord)
	manager._load_chunk(_chunk_coord)
	assert_eq(manager.modification_at_global(dry.x, dry.y), "wood_floor")


func test_the_wash_is_written_back_so_the_save_does_not_carry_the_wet_piece_forever():
	var wet = _water_cell()
	if wet == null:
		return
	manager.build_at_global(wet.x, wet.y, "wood_floor")
	manager._unload_chunk(_chunk_coord)
	manager._load_chunk(_chunk_coord)
	var on_disk: Dictionary = manager._chunk_serializer.load_modifications(manager._modifications_path(_chunk_coord))
	assert_false(on_disk.has(manager._local_coord(wet.x, wet.y)), "the reclaimed cell is gone from the save too")
