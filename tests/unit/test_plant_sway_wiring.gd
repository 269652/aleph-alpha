extends GutTest

## Every plant sways on ONE eased walker point (docs/concept/long_grass.md,
## "A plant is not rubber"). Reported live: *"it bounces back too fast and
## also bending too fast"*, and then *"for all plants"*.
##
## The model is tested on its own. What is pinned here is that the manager
## eases at all rather than passing the raw position straight through, and
## that grass, ferns and wheat are all handed the SAME point -- two plants
## bending toward different places would be worse than both snapping.

const EarthChunkManager = preload("res://src/world/earth_chunk_manager.gd")
const PlantSway = preload("res://src/rendering/plant_sway.gd")

var manager: EarthChunkManager
var tile_map_layer: TileMapLayer
var entities_parent: Node2D
var creatures_parent: Node2D


func before_each():
	tile_map_layer = TileMapLayer.new()
	entities_parent = Node2D.new()
	creatures_parent = Node2D.new()
	manager = EarthChunkManager.new(tile_map_layer, entities_parent, creatures_parent)


func after_each():
	tile_map_layer.free()
	entities_parent.free()
	creatures_parent.free()


func _grass_point():
	return manager._illustrated_grass.material().get_shader_parameter("player_world_position")


func _fern_point():
	return manager._illustrated_ferns.material().get_shader_parameter("player_world_position")


## Once a walker is placed, moving them does not carry the bend with them
## in one frame. (The FIRST placement snaps -- there is nothing to ease
## from, and easing in from the sentinel would leave a fresh session with
## no parting at all for several seconds. PlantSway's own test pins that.)
func test_the_bend_does_not_jump_to_a_moved_walker_in_one_frame():
	manager.set_grass_walker_position(Vector2.ZERO, 1.0 / 60.0)
	manager.set_grass_walker_position(Vector2(100.0, 0.0), 1.0 / 60.0)
	var point: Vector2 = _grass_point()
	assert_lt(
		point.x, 60.0,
		"the plants were drawn against the walker's new position immediately"
	)
	assert_gt(point.x, 0.0, "...but they did move")


func test_it_arrives_if_the_walker_stays():
	for _frame in 240:
		manager.set_grass_walker_position(Vector2(500.0, 500.0), 1.0 / 60.0)
	var point: Vector2 = _grass_point()
	assert_almost_eq(point.x, 500.0, 2.0)
	assert_almost_eq(point.y, 500.0, 2.0)


## The whole report: the walker leaves and the plants are still leaning.
func test_the_plants_are_still_leaning_after_the_walker_has_gone():
	for _frame in 240:
		manager.set_grass_walker_position(Vector2.ZERO, 1.0 / 60.0)
	manager.set_grass_walker_position(Vector2(4000.0, 0.0), 1.0 / 60.0)
	var point: Vector2 = _grass_point()
	assert_lt(point.x, 2000.0, "the plants went with the walker instead of springing back")


## One point, every plant. A fern bending toward somewhere a blade is not
## is worse than either of them snapping.
func test_every_plant_is_handed_the_same_point():
	for _frame in 10:
		manager.set_grass_walker_position(Vector2(120.0, 80.0), 1.0 / 60.0)
	assert_eq(_grass_point(), _fern_point())


## A caller that hands over no delta still works and simply does not ease
## -- every existing call site keeps behaving exactly as it did.
func test_a_caller_with_no_delta_still_places_the_walker():
	manager.set_grass_walker_position(Vector2(7.0, 9.0))
	assert_eq(_grass_point(), Vector2(7.0, 9.0))
