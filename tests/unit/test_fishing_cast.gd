extends GutTest

## FishingCast: pure geometry for where a cast line lands -- the visual
## bobber and the fish-attraction radius (see EarthChunkManager.
## set_attraction_point) both need to agree on this same point.

const FishingCast = preload("res://src/gameplay/fishing_cast.gd")

var cast := FishingCast.new()


func test_cast_point_is_offset_along_the_facing_direction():
	var point := cast.cast_point(Vector2(100, 100), Vector2.DOWN)
	assert_eq(point.x, 100.0)
	assert_gt(point.y, 100.0)


func test_cast_point_is_a_fixed_distance_from_the_player():
	var point := cast.cast_point(Vector2(100, 100), Vector2.RIGHT)
	assert_almost_eq(Vector2(100, 100).distance_to(point), FishingCast.CAST_DISTANCE_PX, 0.01)


func test_cast_point_follows_facing_direction():
	var down := cast.cast_point(Vector2.ZERO, Vector2.DOWN)
	var up := cast.cast_point(Vector2.ZERO, Vector2.UP)
	var left := cast.cast_point(Vector2.ZERO, Vector2.LEFT)
	var right := cast.cast_point(Vector2.ZERO, Vector2.RIGHT)
	assert_gt(down.y, 0.0)
	assert_lt(up.y, 0.0)
	assert_lt(left.x, 0.0)
	assert_gt(right.x, 0.0)


## A zero-length facing (shouldn't normally happen, but the player's own
## facing vector defaults meaningfully) must not divide by zero.
func test_cast_point_with_a_zero_facing_falls_back_to_a_default_direction():
	var point := cast.cast_point(Vector2(50, 50), Vector2.ZERO)
	assert_almost_eq(Vector2(50, 50).distance_to(point), FishingCast.CAST_DISTANCE_PX, 0.01)


func test_cast_point_normalizes_a_non_unit_facing():
	var point_a := cast.cast_point(Vector2.ZERO, Vector2.DOWN)
	var point_b := cast.cast_point(Vector2.ZERO, Vector2(0, 5))
	assert_almost_eq(point_a.x, point_b.x, 0.01)
	assert_almost_eq(point_a.y, point_b.y, 0.01)
