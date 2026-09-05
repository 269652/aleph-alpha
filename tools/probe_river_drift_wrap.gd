extends SceneTree

## GPU-side confirmation of the drift-wrap-instant fix (RiverFlowShader's
## wrap_crossfade_weight, added alongside the far-time-shredding fix this
## reuses the exact harness from -- tools/probe_eddy_drift_shredding.gd).
##
## Renders the REAL shared material's SHADER_CODE at pairs of TIMEs one
## frame (1/60s) apart, straddling the smear drift's own wrap instant at a
## generic (non-axis-aligned) bearing, and reports the mean per-pixel
## luminance change against the SAME one-frame step taken half a cycle
## away (ordinary flow evolution, not a wrap) -- the same comparison
## test_the_drift_wrap_does_not_pop_the_field_at_a_generic_bearing makes
## on the CPU mirror, done here against the actual compiled shader so a
## GDScript-double-vs-GLSL-float32 divergence would still show up.
##
## Also builds a "legacy" variant with wrap_crossfade_weight patched to
## always return 0 (the crossfade disabled, i.e. the shader as it stood
## right after the far-time-shredding fix but before this one) purely as
## an in-memory string patch, to prove the metric would have caught the
## original bug. The shipped file is never touched.
##
## Run (no --headless -- it needs a GPU target to read back):
##   <godot> --path . --rendering-driver opengl3 -s tools/probe_river_drift_wrap.gd

const RiverFlowShader = preload("res://src/rendering/river_flow_shader.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")

const VIEW := 256
const ZOOM := 4.0
const SPEED_M_S := 2.2
const BASE_BEARING_DEG := 135.0  # generic: neither axis-aligned nor 3-4-5
const EPS := 1.0 / 60.0

const FIXED_WEIGHT_LINE := "float wrap_crossfade_weight(float distance_to_wrap) {"
const LEGACY_WEIGHT_LINE := "float wrap_crossfade_weight(float distance_to_wrap) { if (true) return 0.0;"

var _real_material: ShaderMaterial


func _initialize() -> void:
	_real_material = RiverFlowShader.new().make_material()
	if not RiverFlowShader.SHADER_CODE.contains(FIXED_WEIGHT_LINE):
		push_error("probe_river_drift_wrap: shader source no longer contains:\n  %s\nUpdate this probe's FIXED/LEGACY constants to match." % FIXED_WEIGHT_LINE)
		quit(1)
		return
	var legacy_code: String = RiverFlowShader.SHADER_CODE.replace(FIXED_WEIGHT_LINE, LEGACY_WEIGHT_LINE)

	var period_seconds: float = RiverFlowShader.DRIFT_PERIOD_CELLS / (
		RiverFlowShader.DRIFT_PX_PER_MPS * SPEED_M_S * RiverFlowShader.NOISE_SCALE
	)
	var baseline_t := period_seconds * 0.5

	print("Reach: bearing %.1f deg, speed %.1f m/s, smear-drift period %.3f s\n" % [
		BASE_BEARING_DEG, SPEED_M_S, period_seconds
	])

	for variant in [
		{"name": "fixed (current shipped)", "code": RiverFlowShader.SHADER_CODE},
		{"name": "legacy (crossfade disabled)", "code": legacy_code},
	]:
		var code: String = variant["code"]
		var baseline_before: Image = await _render(_pin_time(code, baseline_t - EPS))
		var baseline_after: Image = await _render(_pin_time(code, baseline_t + EPS))
		var wrap_before: Image = await _render(_pin_time(code, period_seconds - EPS))
		var wrap_after: Image = await _render(_pin_time(code, period_seconds + EPS))
		if baseline_before == null or baseline_after == null or wrap_before == null or wrap_after == null:
			return

		var baseline_diff := _mean_abs_diff(baseline_before, baseline_after)
		var wrap_diff := _mean_abs_diff(wrap_before, wrap_after)
		print("%-28s ordinary step=%.5f  wrap step=%.5f  ratio=%.2fx" % [
			variant["name"], baseline_diff, wrap_diff, wrap_diff / maxf(baseline_diff, 0.00001)
		])

	print("\nExpected: 'fixed' ratio close to 1x (the wrap is hidden, indistinguishable")
	print("from ordinary flow evolution); 'legacy' ratio an order of magnitude or more")
	print("higher, mean-over-the-whole-frame though this is (proving the metric would")
	print("have caught the bug -- a worst-PIXEL comparison, not this mean, is what the")
	print("CPU-mirror unit tests pin exactly).")
	quit()


func _pin_time(code: String, seconds: float) -> String:
	var re := RegEx.new()
	re.compile("\\bTIME\\b")
	return re.sub(code, "(%.6f)" % seconds, true)


func _render(shader_code: String) -> Image:
	var shader := Shader.new()
	shader.code = shader_code
	var uniforms := shader.get_shader_uniform_list()
	if uniforms.is_empty():
		push_error("probe_river_drift_wrap: patched shader failed to parse (0 uniforms) -- check the console above for a SHADER ERROR")
		quit(1)
		return null

	var material := ShaderMaterial.new()
	material.shader = shader
	var painted_maps := ["flow_across_map", "flow_scale_map", "flow_drift_map"]
	for u in uniforms:
		var uname: String = u["name"]
		if uname in painted_maps:
			continue
		var v = _real_material.get_shader_parameter(uname)
		if v != null:
			material.set_shader_parameter(uname, v)
	material.set_shader_parameter("flow_across_map", _build_bend_map())
	material.set_shader_parameter("flow_scale_map", _build_scale_map())
	if uniforms.any(func(u): return u["name"] == "flow_drift_map"):
		material.set_shader_parameter("flow_drift_map", _build_drift_map())

	var renderer := TerrainRenderer.new()
	var viewport := SubViewport.new()
	viewport.size = Vector2i(VIEW, VIEW)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	await process_frame

	var layer := TileMapLayer.new()
	layer.tile_set = renderer.build_river_flow_tile_set()
	layer.material = material
	layer.scale = Vector2.ONE * TerrainRenderer.LAYER_SCALE
	viewport.add_child(layer)

	var camera := Camera2D.new()
	camera.zoom = Vector2(ZOOM, ZOOM)
	camera.position = Vector2(64, 64)
	viewport.add_child(camera)
	camera.make_current()

	var atlas_coords := renderer.atlas_coords_for_river_flow(BASE_BEARING_DEG, true)
	for y in range(-8, 24):
		for x in range(-8, 24):
			layer.set_cell(Vector2i(x, y), 0, atlas_coords)

	await process_frame
	await process_frame
	var img := viewport.get_texture().get_image()
	viewport.queue_free()
	if img == null:
		push_error("probe_river_drift_wrap: no readback -- run with a real rendering driver (--rendering-driver opengl3, no --headless)")
		quit(1)
		return null
	return img


## Mid-channel everywhere, one FIXED bearing (no bend) -- the wrap-instant
## bug reproduces at a single generic bearing with no curvature needed
## (unlike the far-time SHREDDING bug, which needs neighbouring fragments
## to disagree on bearing).
func _build_bend_map() -> ImageTexture:
	var side: int = RiverFlowShader.FLOW_MAP_TILES
	var img := Image.create(side, side, false, Image.FORMAT_RGBAF)
	var rad := deg_to_rad(BASE_BEARING_DEG)
	for y in range(-8, 24):
		for x in range(-8, 24):
			img.set_pixel(posmod(x, side), posmod(y, side), Color(0.0, sin(rad), -cos(rad), SPEED_M_S))
	return ImageTexture.create_from_image(img)


func _build_scale_map() -> ImageTexture:
	var side: int = RiverFlowShader.FLOW_MAP_TILES
	var img := Image.create(side, side, false, Image.FORMAT_RGBAF)
	img.fill(Color(2.0, 0.0, 0.0))
	return ImageTexture.create_from_image(img)


func _build_drift_map() -> ImageTexture:
	var side: int = RiverFlowShader.FLOW_MAP_TILES
	var img := Image.create(side, side, false, Image.FORMAT_RGBAF)
	img.fill(Color(0.0, SPEED_M_S, 0.0, 0.0))
	return ImageTexture.create_from_image(img)


func _mean_abs_diff(a: Image, b: Image) -> float:
	var total := 0.0
	var w := a.get_width()
	var h := a.get_height()
	for y in range(h):
		for x in range(w):
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			total += (absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b)) / 3.0
	return total / float(w * h)
