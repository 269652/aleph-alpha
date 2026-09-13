extends GutTest

## EarthChunkManager.step_farm_plots forwards the world's own current_season
## to every farm plot (see docs/concept/long_grass.md's "A second atlas
## family: farmed wheat") -- only a WHEAT crop's own art actually reads it
## (FarmPlotMarker._redraw_wheat), but step_farm_plots forwards it
## unconditionally to every plot's advance(), same shape as delta_seconds
## itself. Uses `_load_chunk` directly, never the slow real `update()` --
## see test_earth_chunk_manager_farm.gd's own header and docs/progress.md's
## "Godot tests share one real user:// dir across worktrees" note for why.

const EarthChunkManager = preload("res://src/world/earth_chunk_manager.gd")
const EarthChunkGenerator = preload("res://src/world/earth_chunk_generator.gd")
const GeoCoordinates = preload("res://src/world/geo_coordinates.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")
const IllustratedWheatPatch = preload("res://src/rendering/illustrated_wheat_patch.gd")

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
	_berlin_tile = Vector2i(
		geo_coordinates.tile_for_longitude(13.405, EarthChunkGenerator.WORLD_WIDTH_TILES),
		geo_coordinates.tile_for_latitude(52.52, EarthChunkGenerator.WORLD_HEIGHT_TILES)
	)
	_berlin_chunk = Vector2i(
		floori(float(_berlin_tile.x) / EarthChunkManager.CHUNK_SIZE),
		floori(float(_berlin_tile.y) / EarthChunkManager.CHUNK_SIZE)
	)
	manager._load_chunk(_berlin_chunk)


func after_each():
	tile_map_layer.free()
	entities_parent.free()
	creatures_parent.free()


func test_step_farm_plots_forwards_the_current_season_to_a_wheat_plot():
	manager.till_and_plant_farm_plot_at_global(_berlin_tile.x, _berlin_tile.y, "wheat")
	manager.step_farm_plots(0.0)
	assert_eq(manager._farm_plots[_berlin_tile].current_wheat_season(), manager.current_season())


func test_step_farm_plots_still_advances_growth_exactly_as_before():
	manager.till_and_plant_farm_plot_at_global(_berlin_tile.x, _berlin_tile.y, "wheat")
	manager.step_farm_plots(1.0)
	assert_eq(manager._farm_plots[_berlin_tile].plot.time_growing, 1.0)
