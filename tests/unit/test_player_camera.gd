extends GutTest

## Player's Camera2D zoom -- a tuned value (CLAUDE.md: tuned values/thresholds
## must be tested/pinned constants, never eyeballed comments), so it lives as
## Player.CAMERA_ZOOM and is applied in _ready() rather than sitting as a bare
## number buried in player.tscn.
##
## CAMERA_ZOOM is DERIVED from Player.TARGET_TILE_SCREEN_PX (the actual
## tuned/eyeballed value) divided by TerrainRenderer.TILE_SIZE, not a bare
## zoom number -- a source art resolution bump (see docs/concept/
## art_resolution.md) changes TILE_SIZE, and a fixed zoom number would then
## silently show more/less of each tile than intended (exactly what
## happened when TILE_SIZE went 16->64 with zoom left at a now-stale 4:
## tiles rendered 4x too big on screen, "everything is zoomed in 4x too
## much" -- see the regression test below).

const PlayerScene = preload("res://scenes/player.tscn")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")

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


## Pins the actual eyeballed value (TARGET_TILE_SCREEN_PX), not zoom itself --
## zoom is a derived quantity, see the file header comment. This is the
## original, always-correct framing (a 16-world-unit tile at 4x zoom): the
## art-resolution pass does NOT change how much world fits on screen, only
## how many art pixels are painted per tile (see
## TerrainRenderer.ART_TILE_SIZE / LAYER_SCALE).
func test_target_tile_screen_size_keeps_the_original_framing():
	assert_almost_eq(Player.TARGET_TILE_SCREEN_PX, 64.0, 0.001)


## Regression: TILE_SIZE going 16->64 (see docs/concept/art_resolution.md)
## must NOT change how big a tile looks on screen -- only how much real
## pixel detail is packed into that same footprint. A bare zoom number left
## over from before the resolution bump made every tile render 4x too big
## ("everything is zoomed in 4x too much, water tiles are huge").
func test_camera_zoom_keeps_the_on_screen_tile_size_constant_across_a_resolution_bump():
	var on_screen_tile_px: float = TerrainRenderer.TILE_SIZE * Player.CAMERA_ZOOM.x
	assert_almost_eq(on_screen_tile_px, Player.TARGET_TILE_SCREEN_PX, 0.01)
