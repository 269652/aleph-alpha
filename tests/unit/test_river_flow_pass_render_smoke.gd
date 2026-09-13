extends GutTest

## RiverFlowPass on a real GPU: does what the adopted layer draws actually
## reach the world canvas, where it was, at the size it was? The unit tests
## in test_river_flow_pass.gd pin the arithmetic; only a readback can prove
## the sub camera is current, the viewport texture is live and the
## composite lands on the right screen pixels. A solid-colour sprite stands
## in for the river layer so the assertion is a plain colour check.
##
## Skips under --headless (get_image() returns null there, and the engine
## error that produces fails the test on its own -- the same reason
## test_river_flow_render_smoke.gd skips). Run for real with:
##   <godot> --rendering-driver opengl3 --path . -s addons/gut/gut_cmdln.gd \
##     -gconfig=res://.gutconfig.json -gselect=test_river_flow_pass_render_smoke -gexit

const RiverFlowPass = preload("res://src/rendering/river_flow_pass.gd")

## The stand-in world: a 256x256 "screen" at the game's 4x zoom frames a
## 64x64 world-px window whose top-left is WORLD_TOP_LEFT.
const SCREEN := Vector2i(256, 256)
const ZOOM := 4.0
const WORLD_TOP_LEFT := Vector2(100.0, 100.0)
const RIVER_COLOR := Color(1.0, 0.0, 1.0, 1.0)


func _no_real_gpu() -> bool:
	if DisplayServer.get_name() != "headless":
		return false
	pending("no GPU readback under --headless; run with --rendering-driver opengl3")
	return true


func _solid(size: int) -> ImageTexture:
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	image.fill(RIVER_COLOR)
	return ImageTexture.create_from_image(image)


func test_the_adopted_layer_is_drawn_into_the_world_canvas_where_it_stood():
	if _no_real_gpu():
		return
	var screen := SubViewport.new()
	screen.size = SCREEN
	screen.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	screen.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	add_child_autofree(screen)
	var world := Node2D.new()
	screen.add_child(world)
	var camera := Camera2D.new()
	camera.zoom = Vector2.ONE * ZOOM
	camera.position = WORLD_TOP_LEFT + Vector2(SCREEN) / ZOOM * 0.5
	world.add_child(camera)
	# The "river": 16 world px square at the window's top-left corner, so it
	# should fill the top-left 64x64 screen pixels and nothing else.
	var river := Sprite2D.new()
	river.centered = false
	river.texture = _solid(16)
	river.position = WORLD_TOP_LEFT
	river.z_index = -1
	world.add_child(river)

	var pass_node := RiverFlowPass.new()
	pass_node.adopt(river)
	pass_node.sync(WORLD_TOP_LEFT, Vector2(SCREEN) / ZOOM)
	for _i in 3:
		await get_tree().process_frame
	var image := screen.get_texture().get_image()
	assert_not_null(image)
	if image == null:
		return
	var inside := image.get_pixel(10, 10)
	var edge := image.get_pixel(62, 62)
	var outside := image.get_pixel(70, 70)
	var far := image.get_pixel(200, 200)
	assert_true(inside.is_equal_approx(RIVER_COLOR), "top-left of the screen is river, exactly the colour drawn: %s" % inside)
	assert_true(edge.is_equal_approx(RIVER_COLOR), "still river one screen pixel inside the 64 px edge: %s" % edge)
	assert_false(outside.is_equal_approx(RIVER_COLOR), "just past the 16-world-px square there is no river: %s" % outside)
	assert_false(far.is_equal_approx(RIVER_COLOR), "far away there is no river: %s" % far)
