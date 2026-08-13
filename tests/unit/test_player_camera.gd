extends GutTest

## Player's Camera2D zoom -- a tuned value (CLAUDE.md: tuned values/thresholds
## must be tested/pinned constants, never eyeballed comments), so it lives as
## Player.CAMERA_ZOOM and is applied in _ready() rather than sitting as a bare
## number buried in player.tscn.

const PlayerScene = preload("res://scenes/player.tscn")

var player: Player


func before_each():
	player = PlayerScene.instantiate()
	add_child(player)


func after_each():
	remove_child(player)
	player.free()


func test_camera_zoom_is_wired_from_the_tuned_constant():
	var camera := player.get_node("Camera2D") as Camera2D
	assert_eq(camera.zoom, Player.CAMERA_ZOOM)


## Regression: bumped from the original 3x so pixel art reads clearly across
## a full 1280x720+ window instead of only a small slice of it.
func test_camera_zoom_is_the_bumped_4x_scale():
	assert_eq(Player.CAMERA_ZOOM, Vector2(4, 4))
