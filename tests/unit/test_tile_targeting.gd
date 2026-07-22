extends GutTest

const TileTargeting = preload("res://src/gameplay/tile_targeting.gd")

var targeting: TileTargeting


func before_each():
	targeting = TileTargeting.new()


func test_facing_right_targets_the_tile_to_the_east():
	assert_eq(targeting.facing_tile(Vector2i(5, 5), Vector2(1, 0)), Vector2i(6, 5))


func test_facing_left_targets_the_tile_to_the_west():
	assert_eq(targeting.facing_tile(Vector2i(5, 5), Vector2(-1, 0)), Vector2i(4, 5))


func test_facing_down_targets_the_tile_to_the_south():
	assert_eq(targeting.facing_tile(Vector2i(5, 5), Vector2(0, 1)), Vector2i(5, 6))


func test_facing_up_targets_the_tile_to_the_north():
	assert_eq(targeting.facing_tile(Vector2i(5, 5), Vector2(0, -1)), Vector2i(5, 4))


func test_diagonal_facing_picks_the_dominant_axis():
	assert_eq(targeting.facing_tile(Vector2i(5, 5), Vector2(0.9, 0.1)), Vector2i(6, 5))


func test_zero_facing_targets_the_players_own_tile():
	assert_eq(targeting.facing_tile(Vector2i(5, 5), Vector2.ZERO), Vector2i(5, 5))
