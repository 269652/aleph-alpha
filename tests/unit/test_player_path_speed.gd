extends GutTest

## Walking a worn path is faster (docs/concept/infrastructure.md).
##
## The loop this closes: repeated movement wears a path, the path is quicker
## to walk, and being quicker to walk is what makes it worth using again.
## Until now the first half existed on its own -- a path was a texture change
## and nothing else, so wearing one in cost the player time and bought them
## nothing.

const PlayerScene = preload("res://scenes/player.tscn")
const Player = preload("res://scenes/player.gd")
const PathScarring = preload("res://src/world/path_scarring.gd")

var player: Player


func before_each():
	player = PlayerScene.instantiate()
	player.name = str(multiplayer.get_unique_id())
	add_child(player)


func after_each():
	remove_child(player)
	player.free()


func test_rough_ground_gives_no_advantage():
	assert_eq(player._path_speed_multiplier(), 1.0)


func test_standing_on_a_worn_path_is_faster():
	player.ground_wear = PathScarring.WORN_THRESHOLD
	assert_gt(player._path_speed_multiplier(), 1.0)


## The same number the world's own path model produces, not a second one --
## so the tile the world DREW as a path is exactly the tile that is faster.
func test_the_advantage_is_the_path_models_own():
	player.ground_wear = PathScarring.WORN_THRESHOLD * 0.6
	assert_eq(
		player._path_speed_multiplier(),
		PathScarring.speed_multiplier(PathScarring.WORN_THRESHOLD * 0.6)
	)
