extends GutTest

## Regression precedent: test_world_ecology_batch_wild_crops.gd caught
## EarthChunkManager.step_wild_crops existing and being tested while World's
## own per-frame ecology step never actually called it -- a real session
## never grew a single wild crop past its seeded starting growth. This is
## the same check for the farming loop's own tick hook
## (EarthChunkManager.step_farm_plots, docs/concept/farming.md): a planted
## farm plot must actually grow across a real World._step_ecology_batch
## call, not just when a test/manager calls step_farm_plots directly.
##
## World itself has no direct unit tests (see test_world_persistence.gd's
## own framing: its _ready() assumes the real scene tree, so a bare
## World.new() is deliberately never add_child()'d). Same "call the private
## step directly on an un-added instance" pattern as
## test_world_ecology_batch_wild_crops.gd, wiring up only the one dependency
## (_chunk_manager) _step_ecology_batch actually reads.

const World = preload("res://scenes/world.gd")
const EarthChunkManager = preload("res://src/world/earth_chunk_manager.gd")
const EarthChunkGenerator = preload("res://src/world/earth_chunk_generator.gd")
const GeoCoordinates = preload("res://src/world/geo_coordinates.gd")

class TestWorld extends World:
	func _step_reproduction(_delta: float) -> void:
		pass

	func _step_herbivore_food_consumption(_delta: float) -> void:
		pass


var world: TestWorld
var manager: EarthChunkManager
var tile_map_layer: TileMapLayer
var entities_parent: Node2D
var creatures_parent: Node2D
var _berlin_tile: Vector2i


func before_each():
	# Deliberately NOT add_child()'d -- see test_world_persistence.gd.
	world = TestWorld.new()
	tile_map_layer = TileMapLayer.new()
	entities_parent = Node2D.new()
	creatures_parent = Node2D.new()
	manager = EarthChunkManager.new(tile_map_layer, entities_parent, creatures_parent)
	# step_ground_food (one of _step_ecology_batch's own steps) reads
	# _entities_parent.get_tree() -- real for the test node itself (GUT adds
	# it to the running tree), so parenting entities_parent under it gives
	# the manager a real tree to find, exactly like
	# test_world_ecology_batch_wild_crops.gd does.
	add_child(entities_parent)
	var geo_coordinates := GeoCoordinates.new()
	_berlin_tile = Vector2i(
		geo_coordinates.tile_for_longitude(13.405, EarthChunkGenerator.WORLD_WIDTH_TILES),
		geo_coordinates.tile_for_latitude(52.52, EarthChunkGenerator.WORLD_HEIGHT_TILES)
	)
	manager.update(_berlin_tile)
	world._chunk_manager = manager


func after_each():
	world.free()
	tile_map_layer.free()
	entities_parent.free()
	creatures_parent.free()


## The case that was broken for wild crops and must not be broken here
## either: a real per-frame World ecology batch step must actually grow a
## planted farm plot over simulated time.
func test_ecology_batch_advances_a_real_farm_plots_growth():
	manager.till_and_plant_farm_plot_at_global(_berlin_tile.x, _berlin_tile.y, "carrot")
	var marker = manager._farm_plots[_berlin_tile]
	var before: float = marker.plot.time_growing

	world._step_ecology_batch(1.0, null)

	assert_gt(marker.plot.time_growing, before)
