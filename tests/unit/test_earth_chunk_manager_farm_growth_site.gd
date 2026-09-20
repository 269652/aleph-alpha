extends GutTest

## docs/concept/village_economy_balance.md mechanism 6: a farmstead the
## village raises through its own ledger is sited where its FIELD fits, on
## the outskirts if the streets are full -- the same rule the founding
## placement already keeps (VillageRenderer._place_farms_if_missing), so a
## growth farmhouse is never a farmhouse with nowhere to sow.
##
## Berlin's real chunk, loaded directly, exactly as
## test_earth_chunk_manager_buildings.gd does.

const EarthChunkManager = preload("res://src/world/earth_chunk_manager.gd")
const GeoCoordinates = preload("res://src/world/geo_coordinates.gd")
const EarthChunkGenerator = preload("res://src/world/earth_chunk_generator.gd")
const VillageFarm = preload("res://src/gameplay/village_farm.gd")

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
	for path in [manager._modifications_path(_chunk_coord), manager._buildings_path(_chunk_coord)]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func _fits_a_field(origin: Vector2i) -> bool:
	var renderer = manager._village_renderer
	var standing: Array = []
	for record in manager.buildings_in_chunk(_chunk_coord):
		if String(record["id"]) == VillageFarm.FARM_BUILDING_ID:
			standing.append(record["origin_local"])
	return renderer._field_fits_at(
		origin, standing + [origin], {}, _chunk_coord, EarthChunkManager.CHUNK_SIZE, manager,
		renderer._is_buildable_local(_chunk_coord, EarthChunkManager.CHUNK_SIZE, manager),
		renderer._is_occupied_local(_chunk_coord, EarthChunkManager.CHUNK_SIZE, manager)
	)


## The site the growth path picks for a farmhouse is one its field fits at.
func test_a_growth_farmhouse_is_sited_where_its_field_fits():
	var site = manager._growth_site_for(_chunk_coord, VillageFarm.FARM_BUILDING_ID)
	assert_not_null(site, "the premise: Berlin's chunk has room for a farm")
	assert_true(_fits_a_field(site), "a farmhouse at %s would have nowhere to sow" % str(site))


## And it is the founding placement's own search, not a second rule that
## agrees with it today.
func test_the_growth_site_is_the_founding_placements_own_field_aware_plot():
	var site = manager._growth_site_for(_chunk_coord, VillageFarm.FARM_BUILDING_ID)
	var plot: Dictionary = manager._village_renderer.farm_plot_with_field(
		_chunk_coord, EarthChunkManager.CHUNK_SIZE, manager
	)
	assert_false(plot.is_empty(), "the premise: the renderer finds a farm plot here")
	assert_eq(site, plot["origin"])


## A farmhouse already standing keeps its own field: the next site does
## not overlap the ground the first one owns.
func test_the_next_farm_keeps_off_the_first_ones_field():
	var first = manager._growth_site_for(_chunk_coord, VillageFarm.FARM_BUILDING_ID)
	assert_not_null(first)
	assert_true(manager.place_building(_chunk_coord, first, VillageFarm.FARM_BUILDING_ID, Vector2i(0, 1), 1, ""))
	var second = manager._growth_site_for(_chunk_coord, VillageFarm.FARM_BUILDING_ID)
	assert_not_null(second, "the premise: room for a second farm")
	assert_ne(second, first)
	assert_true(_fits_a_field(second), "the second farmhouse at %s would have nowhere to sow" % str(second))
