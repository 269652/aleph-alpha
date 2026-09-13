extends GutTest

## RiverFlowPass (src/rendering/river_flow_pass.gd): the river-flow layer
## rendered once into a SubViewport at ONE TEXEL PER SHADER SNAP CELL and
## composited back into the world canvas as a single sprite -- FPS
## regression round 15 (docs/concept/soil_fauna.md). RiverFlowShader
## quantises every fragment's world position to PIXEL_SNAP (half a world
## pixel, one art pixel) before doing anything, so at the game's fixed
## 4x camera every 2x2 block of screen fragments computed the identical
## answer four times over. Measured live (within-run A/B, river on
## screen): the layer alone was ~21 ms of GPU per frame; a texel grid
## aligned to the snap grid reproduces the image exactly with a quarter of
## the fragments, and more than that on larger windows.

const RiverFlowPass = preload("res://src/rendering/river_flow_pass.gd")
const RiverFlowShader = preload("res://src/rendering/river_flow_shader.gd")
const Player = preload("res://scenes/player.gd")

var parent: Node2D
var river_layer: TileMapLayer


func before_each():
	parent = Node2D.new()
	add_child(parent)
	# The world.tscn shape: ground-effect siblings at z_index -1, the river
	# layer LATER than the rest so its streaks draw over them.
	var earlier := Node2D.new()
	earlier.name = "HillshadeFx"
	earlier.z_index = -1
	parent.add_child(earlier)
	river_layer = TileMapLayer.new()
	river_layer.name = "RiverFlowFx"
	river_layer.z_index = -1
	river_layer.scale = Vector2(0.5, 0.5)
	parent.add_child(river_layer)
	var later := Node2D.new()
	later.name = "Entities"
	parent.add_child(later)


func after_each():
	parent.queue_free()


# -- the texel grid IS the shader's snap grid ---------------------------------

func test_one_texel_is_exactly_one_shader_snap_cell():
	assert_eq(RiverFlowPass.TEXEL_WORLD_PX, RiverFlowShader.PIXEL_SNAP,
		"the pass may only ever be exact if its texel is the shader's own snap cell")


func test_at_the_games_camera_zoom_a_texel_is_a_whole_number_of_screen_pixels():
	var screen_px_per_texel: float = RiverFlowPass.TEXEL_WORLD_PX * Player.CAMERA_ZOOM.x
	assert_eq(screen_px_per_texel, 2.0, "2x2 screen pixels per texel at the fixed 4x zoom -- an exact upscale, not a resample")


func test_the_sub_camera_zoom_puts_one_texel_per_snap_cell():
	assert_eq(RiverFlowPass.camera_zoom(), Vector2.ONE / RiverFlowShader.PIXEL_SNAP)


func test_target_size_covers_the_visible_world_plus_a_margin_texel_each_side():
	# 320x180 world px visible (1280x720 at 4x): 640x360 texels plus margin.
	var size: Vector2i = RiverFlowPass.target_size(Vector2(320.0, 180.0))
	assert_eq(size, Vector2i(640 + RiverFlowPass.MARGIN_TEXELS, 360 + RiverFlowPass.MARGIN_TEXELS))
	assert_gt(RiverFlowPass.MARGIN_TEXELS, 0, "the snapped origin floors, so the far edge needs at least one spare texel")


func test_target_size_rounds_a_fractional_world_span_up_never_down():
	var size: Vector2i = RiverFlowPass.target_size(Vector2(320.3, 179.9))
	assert_eq(size.x, 641 + RiverFlowPass.MARGIN_TEXELS)
	assert_eq(size.y, 360 + RiverFlowPass.MARGIN_TEXELS)


func test_the_origin_snaps_down_onto_the_texel_grid():
	assert_eq(RiverFlowPass.snapped_origin(Vector2(10.7, -3.2)), Vector2(10.5, -3.5))
	assert_eq(RiverFlowPass.snapped_origin(Vector2(8.0, 4.5)), Vector2(8.0, 4.5), "already on the grid: untouched")


# -- adopting the layer: same draw order, same transform, own viewport -------

func test_adopt_moves_the_layer_into_a_sub_viewport_and_takes_its_place_in_the_tree():
	var pass_node := RiverFlowPass.new()
	var old_index := river_layer.get_index()
	pass_node.adopt(river_layer)
	assert_eq(pass_node.get_parent(), parent, "the pass stands where the layer stood")
	assert_eq(pass_node.get_index(), old_index, "at the layer's exact old sibling index -- world.tscn's ground draw order is a tested contract")
	assert_true(river_layer.get_parent() is SubViewport, "the layer itself now renders inside the pass's own viewport")
	assert_eq(river_layer.get_parent().get_parent(), pass_node)
	assert_eq(river_layer.scale, Vector2(0.5, 0.5), "the layer keeps its own transform: the shader's world_pos must not change")
	assert_eq(river_layer.z_index, -1)


func test_the_sub_viewport_is_transparent_and_re_rendered_every_frame():
	var pass_node := RiverFlowPass.new()
	pass_node.adopt(river_layer)
	var sub: SubViewport = river_layer.get_parent()
	assert_true(sub.transparent_bg, "only the river is drawn; everything else stays the world canvas's")
	assert_eq(sub.render_target_update_mode, SubViewport.UPDATE_ALWAYS, "the surface advects every frame")
	assert_true(sub.disable_3d)
	assert_eq(sub.canvas_item_default_texture_filter, Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST,
		"the layer's own tiles must not get bilinear-blurred inside the pass either")


func test_the_sub_camera_is_top_left_anchored_at_the_texel_zoom():
	var pass_node := RiverFlowPass.new()
	pass_node.adopt(river_layer)
	var camera: Camera2D = pass_node.sub_camera()
	assert_not_null(camera)
	assert_eq(camera.get_parent(), river_layer.get_parent(), "inside the same viewport as the layer")
	assert_eq(camera.anchor_mode, Camera2D.ANCHOR_MODE_FIXED_TOP_LEFT)
	assert_eq(camera.zoom, RiverFlowPass.camera_zoom())


func test_the_composite_sprite_draws_the_viewport_texture_at_the_layers_own_z_index_unfiltered():
	var pass_node := RiverFlowPass.new()
	pass_node.adopt(river_layer)
	var sprite: Sprite2D = pass_node.composite()
	assert_not_null(sprite)
	assert_true(sprite.texture is ViewportTexture)
	assert_eq(sprite.z_index, -1, "the ground-effects tier, exactly where the layer drew")
	assert_false(sprite.centered, "positioned by its top-left, like the sub camera")
	assert_eq(sprite.texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST, "an exact 2x2 upscale, never a resample")
	assert_eq(sprite.scale, Vector2.ONE * RiverFlowPass.TEXEL_WORLD_PX, "one texel covers one snap cell of world")


# -- syncing every frame --------------------------------------------------------

func test_sync_places_camera_and_composite_on_the_same_snapped_origin_and_sizes_the_viewport():
	var pass_node := RiverFlowPass.new()
	pass_node.adopt(river_layer)
	pass_node.sync(Vector2(1000.3, 500.8), Vector2(320.0, 180.0))
	var origin := RiverFlowPass.snapped_origin(Vector2(1000.3, 500.8))
	assert_eq(pass_node.sub_camera().position, origin)
	assert_eq(pass_node.composite().position, origin, "camera and composite agree to the texel, so the upscale lands on the snap grid")
	var sub: SubViewport = river_layer.get_parent()
	assert_eq(sub.size, RiverFlowPass.target_size(Vector2(320.0, 180.0)))


func test_sync_only_resizes_the_viewport_when_the_visible_world_changes():
	var pass_node := RiverFlowPass.new()
	pass_node.adopt(river_layer)
	pass_node.sync(Vector2.ZERO, Vector2(320.0, 180.0))
	var sub: SubViewport = river_layer.get_parent()
	var size_before := sub.size
	pass_node.sync(Vector2(5.0, 5.0), Vector2(320.0, 180.0))
	assert_eq(sub.size, size_before)
	pass_node.sync(Vector2(5.0, 5.0), Vector2(480.0, 270.0))
	assert_eq(sub.size, RiverFlowPass.target_size(Vector2(480.0, 270.0)), "a bigger window frames more world: more texels, same texel")
