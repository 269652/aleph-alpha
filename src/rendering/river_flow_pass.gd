extends Node2D

## The river-flow layer rendered once into its own SubViewport at ONE TEXEL
## PER SHADER SNAP CELL, then composited back into the world canvas as a
## single sprite -- FPS regression round 15 (docs/concept/soil_fauna.md,
## spec in docs/concept/rivers.md "The river surface at snap resolution").
##
## Why this is exact and not a quality trade: RiverFlowShader quantises
## every fragment's world position to PIXEL_SNAP (half a world pixel, one
## art pixel) before it reads a single map texel or noise value -- every
## term of the surface is a function of that snapped position alone. At the
## game's fixed 4x camera (Player.CAMERA_ZOOM) a snap cell is a 2x2 block of
## screen fragments, so the full-resolution pass computed the identical
## answer four times per cell; on a 1080p window, nine times. Measured live
## (within-run A/B with the layer hidden, river on screen): the layer alone
## was ~21 ms of GPU per frame on the reference machine's Intel iGPU, the
## single largest item in the whole frame and by itself above the 16.7 ms
## budget; a 640x360 window ran the same scene at ~8 ms, so the cost is
## fragment-bound and scales with pixels, not with the river.
##
## The mechanism, all engine-side: the TileMapLayer keeps its transform,
## its material and every cell the chunk manager paints -- it just lives
## inside a SubViewport of its own (own World2D, transparent, redrawn every
## frame) whose Camera2D is anchored top-left on the texel grid at a zoom of
## one texel per snap cell. A Sprite2D standing at the layer's exact old
## sibling index and z_index (world.tscn's ground draw order is a tested
## contract) draws that viewport texture with NEAREST filtering, scaled so
## one texel covers one snap cell of world: the main camera then upscales
## it by a whole number of screen pixels. The day/night CanvasModulate
## tints the composite once, in the world canvas, exactly as it tinted the
## layer; the sub viewport's own canvas has no modulate.
##
## Origin snapping is what keeps the texel grid ON the snap grid: camera
## and composite share one origin floored to a texel, so a texel's centre
## is always a snap cell's centre, whatever sub-texel position the player's
## camera is at this frame.

const RiverFlowShader = preload("res://src/rendering/river_flow_shader.gd")

## One texel is one shader snap cell, in world pixels. Pinned equal to
## RiverFlowShader.PIXEL_SNAP by test_one_texel_is_exactly_one_shader_snap_cell.
const TEXEL_WORLD_PX: float = RiverFlowShader.PIXEL_SNAP
## Spare texels past the visible world on each axis: the origin floors
## onto the grid (up to one texel short at the far edge), and the last
## texel row/column is where an off-by-one would show as a bare strip.
const MARGIN_TEXELS := 2

var _sub_viewport: SubViewport = null
var _sub_camera: Camera2D = null
var _composite: Sprite2D = null
var _visible_world_size := Vector2.ZERO


## The sub camera's zoom: one texel per snap cell.
static func camera_zoom() -> Vector2:
	return Vector2.ONE / TEXEL_WORLD_PX


## Viewport size in texels for a visible world span (world px), rounded
## up so a fractional span never drops a cell, plus the margin.
static func target_size(visible_world_size: Vector2) -> Vector2i:
	return Vector2i(
		ceili(visible_world_size.x / TEXEL_WORLD_PX) + MARGIN_TEXELS,
		ceili(visible_world_size.y / TEXEL_WORLD_PX) + MARGIN_TEXELS
	)


## The camera's top-left corner floored onto the texel grid.
static func snapped_origin(view_top_left_world: Vector2) -> Vector2:
	return Vector2(
		floorf(view_top_left_world.x / TEXEL_WORLD_PX) * TEXEL_WORLD_PX,
		floorf(view_top_left_world.y / TEXEL_WORLD_PX) * TEXEL_WORLD_PX
	)


## Takes `river_layer` out of its parent, stands this pass at its exact
## old sibling index, and re-homes the layer (transform untouched) inside
## the pass's own viewport with the sub camera beside it. Idempotent for
## nothing: call once, from World._ready.
func adopt(river_layer: CanvasItem) -> void:
	var old_parent := river_layer.get_parent()
	var old_index := river_layer.get_index()
	old_parent.remove_child(river_layer)
	old_parent.add_child(self)
	old_parent.move_child(self, old_index)

	_sub_viewport = SubViewport.new()
	_sub_viewport.name = "RiverFlowViewport"
	_sub_viewport.transparent_bg = true
	_sub_viewport.disable_3d = true
	_sub_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_sub_viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	_sub_viewport.size = target_size(Vector2.ONE)
	add_child(_sub_viewport)

	_sub_camera = Camera2D.new()
	_sub_camera.name = "RiverFlowCamera"
	_sub_camera.anchor_mode = Camera2D.ANCHOR_MODE_FIXED_TOP_LEFT
	_sub_camera.zoom = camera_zoom()
	_sub_viewport.add_child(_sub_camera)
	_sub_viewport.add_child(river_layer)

	_composite = Sprite2D.new()
	_composite.name = "RiverFlowComposite"
	_composite.centered = false
	_composite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_composite.z_index = river_layer.z_index
	_composite.scale = Vector2.ONE * TEXEL_WORLD_PX
	_composite.texture = _sub_viewport.get_texture()
	add_child(_composite)


## Once per frame, from World: `view_top_left_world` is the main camera's
## top-left corner in world px, `visible_world_size` how much world it
## frames. Camera and composite move together onto the snapped origin; the
## viewport is only resized when the framed world changes (a window
## resize), since resizing a render target reallocates it.
func sync(view_top_left_world: Vector2, visible_world_size: Vector2) -> void:
	if _sub_viewport == null:
		return
	if visible_world_size != _visible_world_size:
		_visible_world_size = visible_world_size
		_sub_viewport.size = target_size(visible_world_size)
	var origin := snapped_origin(view_top_left_world)
	_sub_camera.position = origin
	_composite.position = origin


func sub_camera() -> Camera2D:
	return _sub_camera


func composite() -> Sprite2D:
	return _composite
