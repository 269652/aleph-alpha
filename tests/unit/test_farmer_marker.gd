extends GutTest

## The Farm's Farmer -- a small, purpose-built walker Node2D (mirrors
## LumberjackMarker's own doc comment on why this is NOT the full
## NpcMarker stack). Owns a fixed set of real FarmPlotMarker children (the
## SAME plant/water/harvest logic and art a player's own hand-tilled plot
## already uses) and cycles: harvest a ready plot, else plant an empty one,
## else water a growing one at real risk of withering -- crediting the
## Farm's own real StructureStock on harvest (see docs/concept/
## npc_farm_production.md). Instantiates a real EarthChunkManager the same
## way test_lumberjack_marker.gd does, since harvested wheat credits its
## real StructureStock via a late-bound `earth` reference.

const FarmerMarker = preload("res://src/rendering/farmer_marker.gd")
const FarmerBehavior = preload("res://src/gameplay/farmer_behavior.gd")
const FarmPlotMarker = preload("res://src/rendering/farm_plot_marker.gd")
const EarthChunkManager = preload("res://src/world/earth_chunk_manager.gd")
const EarthChunkGenerator = preload("res://src/world/earth_chunk_generator.gd")
const GeoCoordinates = preload("res://src/world/geo_coordinates.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")

var marker: FarmerMarker
var manager: EarthChunkManager
var _tile_map_layer: TileMapLayer
var _entities_parent: Node2D
var _creatures_parent: Node2D
var _berlin_tile: Vector2i
var _geo_coordinates := GeoCoordinates.new()


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

	marker = FarmerMarker.new()
	marker.earth = manager
	var home := Vector2(_berlin_tile) * TerrainRenderer.TILE_SIZE
	marker.home = home
	marker.position = home
	add_child_autofree(marker)


func after_each():
	_tile_map_layer.free()
	_entities_parent.free()
	_creatures_parent.free()


func test_joins_the_farmer_group():
	assert_true(marker.is_in_group(FarmerMarker.GROUP_NAME))


func test_owns_the_real_plot_count():
	assert_eq(marker._plots.size(), FarmerMarker.PLOT_COUNT)
	for plot_marker in marker._plots:
		assert_true(plot_marker is FarmPlotMarker)


## Every owned plot starts empty and gets planted with wheat almost
## immediately -- the Farmer's very first priority once there is nothing
## else to do.
func test_plants_an_empty_plot_soon_after_starting():
	for i in 40:
		marker._process(0.5)
	var any_planted := false
	for plot_marker in marker._plots:
		if plot_marker.plot.state != "empty":
			any_planted = true
	assert_true(any_planted, "at least one plot should be planted after 20 simulated seconds")


func _has_wheat_stock() -> bool:
	return manager.structure_stock_at(_berlin_tile.x, _berlin_tile.y, "wheat") > 0


## The full loop, end to end: plant, tend (water before withering), harvest
## once ready, credit the Farm's own real StructureStock -- repeatable
## since a harvested plot gets re-planted.
func test_the_full_loop_eventually_yields_wheat_at_home():
	for i in 4000:
		marker._process(0.25)
		if _has_wheat_stock():
			break
	assert_true(_has_wheat_stock(), "a full plant/tend/harvest loop should eventually yield real wheat")


## Plots must not be left to wither for lack of tending -- given the
## Farmer's own real priority order (harvest, then plant, then water), no
## owned plot should ever actually reach "withered" over a long run.
func test_no_owned_plot_withers_over_a_long_run():
	for i in 4000:
		marker._process(0.25)
	for plot_marker in marker._plots:
		assert_ne(plot_marker.plot.state, "withered", "a tended plot should never be left to wither")


func test_get_display_name_reports_farmer():
	assert_eq(marker.get_display_name(), "Farmer")


func test_get_hover_actions_is_empty():
	assert_eq(marker.get_hover_actions(), [])
