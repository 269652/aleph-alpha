extends GutTest

const WorldCoordinates = preload("res://src/world/world_coordinates.gd")

var world_size := Vector2i(100, 100)
var coordinates: WorldCoordinates


func before_each():
	coordinates = WorldCoordinates.new()


func test_a_coordinate_within_bounds_is_unchanged():
	assert_eq(coordinates.wrap(Vector2i(5, 5), world_size), Vector2i(5, 5))


func test_a_coordinate_past_the_east_edge_wraps_to_the_west_side():
	assert_eq(coordinates.wrap(Vector2i(100, 5), world_size), Vector2i(0, 5))


func test_a_negative_x_coordinate_wraps_to_the_east_side():
	assert_eq(coordinates.wrap(Vector2i(-1, 5), world_size), Vector2i(99, 5))


func test_a_negative_y_coordinate_wraps_to_the_south_side():
	assert_eq(coordinates.wrap(Vector2i(5, -1), world_size), Vector2i(5, 99))


func test_walking_one_full_world_width_east_returns_to_the_start():
	var start := Vector2i(10, 5)
	var after_walking_around := coordinates.wrap(start + Vector2i(world_size.x, 0), world_size)
	assert_eq(after_walking_around, start)


func test_walking_one_full_world_height_south_returns_to_the_start():
	var start := Vector2i(10, 5)
	var after_walking_around := coordinates.wrap(start + Vector2i(0, world_size.y), world_size)
	assert_eq(after_walking_around, start)
