extends GutTest

## EarthChunkManager's wiring for the farming loop (docs/concept/farming.md,
## FarmPlot, FarmPlotMarker) -- till/plant, water (tend), harvest, and the
## world-clock tick hook (step_farm_plots). Mirrors test_player_fruit_harvest.gd's
## own "separate, focused test file" precedent rather than growing the
## already-9000-line test_earth_chunk_manager.gd, and test_earth_chunk_manager.gd's
## own before_each/_berlin_tile setup for a real, loaded chunk.
##
## The central case this file exists to prove (see the task's own "Minimum
## bar"): a planted plot reaches "ready" after the right amount of simulated
## time, tended through the SAME entry points a real play session uses --
## not just FarmPlot's own already-tested pure state machine in isolation.

const EarthChunkManager = preload("res://src/world/earth_chunk_manager.gd")
const EarthChunkGenerator = preload("res://src/world/earth_chunk_generator.gd")
const GeoCoordinates = preload("res://src/world/geo_coordinates.gd")
const FarmPlot = preload("res://src/gameplay/farm_plot.gd")

var tile_map_layer: TileMapLayer
var entities_parent: Node2D
var creatures_parent: Node2D
var manager: EarthChunkManager
var _berlin_tile: Vector2i


func before_each():
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


func after_each():
	tile_map_layer.free()
	entities_parent.free()
	creatures_parent.free()


func _plot_at(tile: Vector2i) -> FarmPlot:
	var marker = manager._farm_plots.get(tile)
	return marker.plot if marker != null else null


func test_till_and_plant_creates_a_growing_plot_in_a_loaded_chunk():
	var planted := manager.till_and_plant_farm_plot_at_global(_berlin_tile.x, _berlin_tile.y, "carrot")
	assert_true(planted)
	var plot := _plot_at(_berlin_tile)
	assert_not_null(plot)
	assert_eq(plot.state, "growing")
	assert_eq(plot.crop_id, "carrot")


## Same "farming far outside the streamed area isn't meaningful" reasoning
## build_at_global already applies to building.
func test_till_and_plant_outside_any_loaded_chunk_is_a_noop():
	var far_away_tile := Vector2i(500 * EarthChunkManager.CHUNK_SIZE, 500 * EarthChunkManager.CHUNK_SIZE)
	var planted := manager.till_and_plant_farm_plot_at_global(far_away_tile.x, far_away_tile.y, "carrot")
	assert_false(planted)


func test_till_and_plant_refuses_to_disturb_a_growing_plot():
	manager.till_and_plant_farm_plot_at_global(_berlin_tile.x, _berlin_tile.y, "carrot")
	var replanted := manager.till_and_plant_farm_plot_at_global(_berlin_tile.x, _berlin_tile.y, "potato")
	assert_false(replanted)
	assert_eq(_plot_at(_berlin_tile).crop_id, "carrot")


func test_water_farm_plot_resets_the_neglect_clock():
	manager.till_and_plant_farm_plot_at_global(_berlin_tile.x, _berlin_tile.y, "carrot")
	var plot := _plot_at(_berlin_tile)
	manager.step_farm_plots(plot.growth_time * FarmPlot.WATER_GRACE_FRACTION - 0.1)
	var watered := manager.water_farm_plot_at_global(_berlin_tile.x, _berlin_tile.y)
	assert_true(watered)
	assert_eq(plot.time_since_watered, 0.0)


func test_water_farm_plot_with_nothing_planted_is_a_noop():
	assert_false(manager.water_farm_plot_at_global(_berlin_tile.x, _berlin_tile.y))


func test_harvest_before_ready_is_a_noop():
	manager.till_and_plant_farm_plot_at_global(_berlin_tile.x, _berlin_tile.y, "carrot")
	var result: Dictionary = manager.harvest_farm_plot_at_global(_berlin_tile.x, _berlin_tile.y)
	assert_eq(result["crop_id"], "")
	assert_eq(result["count"], 0)


func test_harvest_with_nothing_planted_is_a_noop():
	var result: Dictionary = manager.harvest_farm_plot_at_global(_berlin_tile.x, _berlin_tile.y)
	assert_eq(result["crop_id"], "")
	assert_eq(result["count"], 0)


## The world-clock tick hook itself (see World._step_ecology_batch, which
## calls this) -- mirrors step_worms/step_tall_grass's identical
## "for x in _sims.values(): x.advance(delta)" shape.
func test_step_farm_plots_advances_growth():
	manager.till_and_plant_farm_plot_at_global(_berlin_tile.x, _berlin_tile.y, "carrot")
	manager.step_farm_plots(1.0)
	assert_eq(_plot_at(_berlin_tile).time_growing, 1.0)


## THE central case (see this file's own header comment / the task's
## "Minimum bar"): tended through the real entry points -- till_and_plant,
## repeated water + step_farm_plots -- a plot reaches "ready" after the
## right amount of simulated time, and can then be harvested for a real,
## positive yield. Mirrors test_farm_plot.gd's own _grow_to_ready idiom
## (water, then advance in steps that never exceed the grace window) but
## driven through EarthChunkManager's wiring instead of FarmPlot directly.
func test_a_tended_plot_reaches_harvestable_state_after_simulated_time_and_harvests_for_real():
	manager.till_and_plant_farm_plot_at_global(_berlin_tile.x, _berlin_tile.y, "carrot")
	var plot := _plot_at(_berlin_tile)
	var step: float = plot.growth_time / 10.0
	for i in 12:
		manager.water_farm_plot_at_global(_berlin_tile.x, _berlin_tile.y)
		manager.step_farm_plots(step)

	assert_eq(plot.state, "ready")

	var result: Dictionary = manager.harvest_farm_plot_at_global(_berlin_tile.x, _berlin_tile.y)
	assert_eq(result["crop_id"], "carrot")
	assert_gt(result["count"], 0)


## Neglecting the plot (never watering across the same simulated span) must
## NOT reach "ready" -- the tending loop above only proves growth works,
## this is what proves the neglect/grace-window rule is actually reachable
## through the same entry points, not bypassed by them.
func test_an_unwatered_plot_withers_instead_of_reaching_ready():
	manager.till_and_plant_farm_plot_at_global(_berlin_tile.x, _berlin_tile.y, "carrot")
	var plot := _plot_at(_berlin_tile)
	manager.step_farm_plots(plot.growth_time * FarmPlot.WATER_GRACE_FRACTION + 0.01)
	assert_eq(plot.state, "withered")


## A harvested plot's own tilled soil persists (see FarmPlotMarker/FarmPlot's
## "empty" state) so the SAME marker can be planted again without re-tilling.
func test_a_harvested_plot_can_be_planted_again():
	manager.till_and_plant_farm_plot_at_global(_berlin_tile.x, _berlin_tile.y, "carrot")
	var plot := _plot_at(_berlin_tile)
	var step: float = plot.growth_time / 10.0
	for i in 12:
		manager.water_farm_plot_at_global(_berlin_tile.x, _berlin_tile.y)
		manager.step_farm_plots(step)
	manager.harvest_farm_plot_at_global(_berlin_tile.x, _berlin_tile.y)

	var replanted := manager.till_and_plant_farm_plot_at_global(_berlin_tile.x, _berlin_tile.y, "potato")

	assert_true(replanted)
	assert_eq(plot.crop_id, "potato")
