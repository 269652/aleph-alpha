extends SceneTree

## Renders a block of mid-channel river with the REAL shared material on the
## real GPU, saves frames at successive times plus amplified difference
## images between them, so what actually MOVES on the surface (and what
## stays put) can be looked at rather than argued from the algebra.
##
## Run (no --headless -- it needs a GPU target to read back):
##   <godot> --path . --rendering-driver opengl3 -s tools/probe_river_motion.gd
## Writes to user://river_motion/ (printed as an absolute path).

const RiverFlowShader = preload("res://src/rendering/river_flow_shader.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")

const SPEED_M_S := 0.9
const TIMES := [0.0, 0.5, 1.0, 2.0, 3.0, 4.0]
const VIEW := 512
const ZOOM := 4.0

var _flow_shader: RiverFlowShader
var _viewport: SubViewport
var _ripple_at := Vector2(64.0, 40.0)
var _ripple_born := 0.5


func _initialize() -> void:
	var out_dir := "user://river_motion"
	DirAccess.make_dir_recursive_absolute(out_dir)
	print("writing to ", ProjectSettings.globalize_path(out_dir))
	_viewport = _build()
	root.add_child(_viewport)
	_run(out_dir)


func _run(out_dir: String) -> void:
	await process_frame
	await process_frame
	var t0 := Time.get_ticks_msec()
	var images: Array[Image] = []
	for target in TIMES:
		while Time.get_ticks_msec() - t0 < target * 1000.0:
			_age_ripple(float(Time.get_ticks_msec() - t0) / 1000.0)
			await process_frame
		_age_ripple(float(Time.get_ticks_msec() - t0) / 1000.0)
		await process_frame
		var img := _viewport.get_texture().get_image()
		if img == null:
			push_error("no readback -- run with a real rendering driver")
			quit(1)
			return
		img.save_png("%s/frame_t%03d.png" % [out_dir, int(target * 100.0)])
		images.append(img)
		print("frame at %.2f s" % target)
	for i in range(1, images.size()):
		_save_diff(images[i - 1], images[i], "%s/diff_t%03d_t%03d.png" % [out_dir, int(TIMES[i - 1] * 100.0), int(TIMES[i] * 100.0)])
	_save_diff(images[2], images[4], "%s/diff_t100_t300.png" % out_dir)
	print("done")
	quit()


func _age_ripple(now: float) -> void:
	var age := now - _ripple_born
	var positions := PackedVector2Array([_ripple_at])
	positions.resize(RiverFlowShader.DISTURBANCE_SLOTS)
	var ages := PackedFloat32Array([age if age >= 0.0 else -999.0])
	while ages.size() < RiverFlowShader.DISTURBANCE_SLOTS:
		ages.append(-999.0)
	_flow_shader.set_disturbances(positions, ages, 1)


## Pixels that did not change between two frames come out BLACK; anything
## that moved lights up, amplified so even a small shift is visible.
func _save_diff(a: Image, b: Image, path: String) -> void:
	var out := Image.create(a.get_width(), a.get_height(), false, Image.FORMAT_RGB8)
	var unchanged := 0
	var total := 0
	for y in a.get_height():
		for x in a.get_width():
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			var d := absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b)
			total += 1
			if d < 0.02:
				unchanged += 1
			var v := clampf(d * 3.0, 0.0, 1.0)
			out.set_pixel(x, y, Color(v, v, v))
	out.save_png(path)
	print("%s: %.1f%% of pixels unchanged" % [path.get_file(), 100.0 * float(unchanged) / float(total)])


func _build() -> SubViewport:
	var renderer := TerrainRenderer.new()
	_flow_shader = RiverFlowShader.new()

	var viewport := SubViewport.new()
	viewport.size = Vector2i(VIEW, VIEW)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS

	var layer := TileMapLayer.new()
	layer.tile_set = renderer.build_river_flow_tile_set()
	layer.material = _flow_shader.shared_material()
	layer.scale = Vector2.ONE * TerrainRenderer.LAYER_SCALE
	viewport.add_child(layer)

	var camera := Camera2D.new()
	camera.zoom = Vector2(ZOOM, ZOOM)
	camera.position = Vector2(64, 64)
	viewport.add_child(camera)
	camera.make_current()

	var side := RiverFlowShader.FLOW_MAP_TILES
	var map_image := Image.create(side, side, false, Image.FORMAT_RGBAF)
	for y in range(-2, 10):
		for x in range(-2, 10):
			# Flow south, so across runs with x: banks left and right.
			var across := (float(x) - 3.5) / 3.5 * 0.9
			map_image.set_pixel(posmod(x, side), posmod(y, side), Color(across, 0.0, 1.0, SPEED_M_S))
	_flow_shader.shared_material().set_shader_parameter("flow_across_map", ImageTexture.create_from_image(map_image))
	# A real half width too (the curated rivers' 2 tiles), so the wobble and
	# the obstacle pushes scale the way they do in the game.
	var scale_image := Image.create(side, side, false, Image.FORMAT_RF)
	scale_image.fill(Color(2.0, 0.0, 0.0))
	_flow_shader.shared_material().set_shader_parameter("flow_scale_map", ImageTexture.create_from_image(scale_image))

	# One reference-sized rock mid-channel, a little downstream of centre,
	# so its shoal, its foam and its wake are all in frame.
	var boulders := PackedVector2Array([Vector2(64.0, 72.0)])
	boulders.resize(24)
	var radii := PackedFloat32Array([RiverFlowShader.BOULDER_RADIUS_PX])
	radii.resize(24)
	_flow_shader.shared_material().set_shader_parameter("boulder_count", 1)
	_flow_shader.shared_material().set_shader_parameter("boulders", boulders)
	_flow_shader.shared_material().set_shader_parameter("boulder_radius", radii)

	var atlas_coords := renderer.atlas_coords_for_river_flow(180.0, true)
	for y in range(8):
		for x in range(8):
			layer.set_cell(Vector2i(x, y), 0, atlas_coords)
	return viewport
