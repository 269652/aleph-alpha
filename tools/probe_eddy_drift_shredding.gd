extends SceneTree

## GPU-side confirmation of the eddy/bend drift half of the far-time
## shredding fix (`RiverFlowShader`'s `bend_drift`, wrapped modulo
## `drift_period` in EDDY units since commit 830f4ba "fix(rivers): bound
## both drifts") -- the fix `test_a_long_session_does_not_shred_the_field_
## on_a_bend` already pins on the CPU mirror, and `docs/concept/rivers.md`'s
## "Bounded drift: the far-time shredding" section already documents. This
## tool exists because neither the original smear-only fix (79b8c5a) nor
## the both-drifts fix (830f4ba) committed a reusable probe -- their GPU
## numbers were measured and thrown away. This one stays.
##
## The FIXED variant below targets the shader as it stood after 8678d83
## ("the reach's own drift speed"), which renamed the single shared
## `drift_speed_m_s` uniform to a per-fragment `drift_speed` read from a
## new nearest-filtered `flow_drift_map` -- but left the eddy-bounding
## technique this probe actually exercises (`bend_drift`'s modulo wrap,
## `eddy_p`, `value_noise_tiled`) untouched. If a future commit changes
## those specific lines again, `_initialize()`'s own guard will refuse to
## run rather than silently measuring the wrong shader -- update the
## FIXED_*/LEGACY_* constants below to match.
##
## Renders the REAL shared material's SHADER_CODE over a synthetic BENDING
## reach (flow direction rotates gently across the painted tiles, so
## neighbouring fragments genuinely see different flow_dir, the precondition
## for this whole bug class) at two pinned TIMEs -- "fresh" and a "long
## session" -- and reports what fraction of pixels read as an isolated
## bright speck (a pixel measurably brighter than its own 8 neighbours,
## which is what decorrelated per-pixel noise looks like next to a healthy
## smooth field).
##
## TIME is PINNED to an exact literal via whole-word text substitution on a
## COPY of SHADER_CODE, not driven by the engine clock -- deterministic and
## reproducible, unlike accumulating real frames under Engine.time_scale.
##
## Also builds a "legacy" shader variant with the eddy path patched back to
## its exact pre-830f4ba form (bend_drift unbounded, eddy_p unwrapped,
## value_noise instead of value_noise_tiled -- lifted verbatim from `git show
## 830f4ba`), purely as an in-memory string patch. This is what makes the
## comparison meaningful: if this probe's own speckle metric can't tell the
## legacy shader apart from the fixed one, the metric proves nothing either
## way. The shipped file is never touched.
##
## Run (no --headless -- it needs a GPU target to read back):
##   <godot> --path . --rendering-driver opengl3 -s tools/probe_eddy_drift_shredding.gd

const RiverFlowShader = preload("res://src/rendering/river_flow_shader.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")

const VIEW := 512
const ZOOM := 4.0
# Matches test_a_long_session_does_not_shred_the_field_on_a_bend's own
# speed_mps=2.2 and base bend angle (231 deg), so this GPU check exercises
# the same regime the CPU-mirror test pins.
const SPEED_M_S := 2.2
const BASE_BEARING_DEG := 231.0
const BEND_DEG_PER_TILE := 1.0
const FRESH_TIME := 0.05
const LONG_SESSION_TIME := 2000.0
const SPECK_THRESHOLDS: Array[float] = [0.05, 0.10, 0.15, 0.20, 0.25]

# The exact lines 830f4ba changed, lifted verbatim from `git show 830f4ba`
# (confirmed against the current file before use below) -- the "legacy"
# variant patches FIXED -> LEGACY on a copy of SHADER_CODE, reproducing the
# real pre-fix shader byte for byte rather than an approximation.
const FIXED_BEND_DRIFT_LINE := "float bend_drift = mod(TIME * surface_px_per_s(drift_speed, moving) * noise_scale * bend_drift_fraction * eddy_scale, drift_period);"
const LEGACY_BEND_DRIFT_LINE := "float bend_drift = TIME * surface_px_per_s(speed_mps, moving) * noise_scale * bend_drift_fraction;"
const FIXED_EDDY_P_LINE := "vec2 eddy_p = p * eddy_scale - flow_dir * bend_drift;"
const LEGACY_EDDY_P_LINE := "vec2 eddy_p = (p - flow_dir * bend_drift) * eddy_scale;"
const FIXED_BEND_NOISE_COARSE := "value_noise_tiled(eddy_p, drift_period)"
const LEGACY_BEND_NOISE_COARSE := "value_noise(eddy_p)"
const FIXED_BEND_NOISE_FINE := "value_noise_tiled(eddy_p * eddy_detail_frequency + vec2(19.7, 7.3), drift_period * eddy_detail_frequency)"
const LEGACY_BEND_NOISE_FINE := "value_noise(eddy_p * eddy_detail_frequency + vec2(19.7, 7.3))"

var _real_material: ShaderMaterial


func _initialize() -> void:
	_real_material = RiverFlowShader.new().make_material()

	for needle in [FIXED_BEND_DRIFT_LINE, FIXED_EDDY_P_LINE, FIXED_BEND_NOISE_COARSE, FIXED_BEND_NOISE_FINE]:
		if not RiverFlowShader.SHADER_CODE.contains(needle):
			push_error("probe_eddy_drift_shredding: shader source no longer contains:\n  %s\nUpdate this probe's FIXED_*/LEGACY_* constants to match." % needle)
			quit(1)
			return

	var legacy_code := RiverFlowShader.SHADER_CODE
	legacy_code = legacy_code.replace(FIXED_BEND_DRIFT_LINE, LEGACY_BEND_DRIFT_LINE)
	legacy_code = legacy_code.replace(FIXED_EDDY_P_LINE, LEGACY_EDDY_P_LINE)
	legacy_code = legacy_code.replace(FIXED_BEND_NOISE_COARSE, LEGACY_BEND_NOISE_COARSE)
	legacy_code = legacy_code.replace(FIXED_BEND_NOISE_FINE, LEGACY_BEND_NOISE_FINE)
	if legacy_code == RiverFlowShader.SHADER_CODE:
		push_error("probe_eddy_drift_shredding: legacy patch was a no-op")
		quit(1)
		return

	print("Reach: bearing %.1f deg +/- drift, %.1f deg/tile, speed %.1f m/s\n" % [BASE_BEARING_DEG, BEND_DEG_PER_TILE, SPEED_M_S])

	var variants := [
		{"name": "fixed (current shipped)", "code": RiverFlowShader.SHADER_CODE},
		{"name": "legacy (pre-830f4ba)", "code": legacy_code},
	]
	var times := [
		{"label": "fresh", "seconds": FRESH_TIME},
		{"label": "long session (2000s)", "seconds": LONG_SESSION_TIME},
	]
	for variant in variants:
		for t in times:
			var img: Image = await _render(_pin_time(variant["code"], t["seconds"]))
			if img == null:
				return
			var fractions := _measure_speckle(img)
			print("%-24s @ %-22s: %s" % [variant["name"], t["label"], _format_speckle(fractions)])
		print("")

	print("Expected: 'fixed' stays roughly flat fresh -> long session (830f4ba holds);")
	print("'legacy' rises sharply at the tightest thresholds (proving this metric")
	print("would have caught the original bug, and that it is genuinely fixed now).")
	quit()


func _pin_time(code: String, seconds: float) -> String:
	var re := RegEx.new()
	re.compile("\\bTIME\\b")
	return re.sub(code, "(%.4f)" % seconds, true)


func _render(shader_code: String) -> Image:
	var shader := Shader.new()
	shader.code = shader_code
	var uniforms := shader.get_shader_uniform_list()
	if uniforms.is_empty():
		push_error("probe_eddy_drift_shredding: patched shader failed to parse (0 uniforms) -- check the console above for a SHADER ERROR")
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
	# Only meaningful post-8678d83 ("the reach's own drift speed") -- a
	# shader without this uniform just ignores the extra parameter.
	if uniforms.any(func(u): return u["name"] == "flow_drift_map"):
		material.set_shader_parameter("flow_drift_map", _build_drift_map())

	var renderer := TerrainRenderer.new()
	var viewport := SubViewport.new()
	viewport.size = Vector2i(VIEW, VIEW)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	# On the very first call this runs before the tree has ever processed a
	# frame, and camera.make_current() below needs the camera genuinely
	# inside a settled tree (its own "!is_inside_tree()" check fires
	# otherwise, harmlessly, but noisily).
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
		push_error("probe_eddy_drift_shredding: no readback -- run with a real rendering driver (--rendering-driver opengl3, no --headless)")
		quit(1)
		return null
	return img


## Mid-channel everywhere (across=0, always wet, no bank clipping to
## confound the metric) with the downstream bearing rotating gently across
## x -- a synthetic bend, the precondition for this bug class. Painted well
## past the visible window so bicubic reconstruction always has real
## neighbours to interpolate between, not the fallback direction.
func _build_bend_map() -> ImageTexture:
	var side: int = RiverFlowShader.FLOW_MAP_TILES
	var img := Image.create(side, side, false, Image.FORMAT_RGBAF)
	for y in range(-8, 24):
		for x in range(-8, 24):
			var bearing := BASE_BEARING_DEG + float(x) * BEND_DEG_PER_TILE
			var rad := deg_to_rad(bearing)
			img.set_pixel(posmod(x, side), posmod(y, side), Color(0.0, sin(rad), -cos(rad), SPEED_M_S))
	return ImageTexture.create_from_image(img)


func _build_scale_map() -> ImageTexture:
	var side: int = RiverFlowShader.FLOW_MAP_TILES
	var img := Image.create(side, side, false, Image.FORMAT_RF)
	img.fill(Color(2.0, 0.0, 0.0))
	return ImageTexture.create_from_image(img)


## Post-8678d83: the reach's own constant drift speed, read by the shader
## through a SEPARATE nearest-filtered sampler (its G channel) so no
## interpolation ramp between reaches can diverge under TIME. One constant
## value everywhere in this probe's single synthetic reach -- exactly the
## "constant along a whole reach" case that commit's own fix targets.
func _build_drift_map() -> ImageTexture:
	var side: int = RiverFlowShader.FLOW_MAP_TILES
	var img := Image.create(side, side, false, Image.FORMAT_RGBAF)
	img.fill(Color(0.0, SPEED_M_S, 0.0, 0.0))
	return ImageTexture.create_from_image(img)


## Fraction of interior pixels that read as an ISOLATED bright speck: a
## pixel measurably brighter than the average of its own 8 neighbours,
## which is what decorrelated per-pixel noise looks like sitting next to
## the smooth gradients a healthy advected/smeared field produces. Reported
## at several thresholds rather than one -- the absolute cutoff was never
## pinned by the original (uncommitted) probe this one replaces, so the
## CROSS-VARIANT comparison is the evidence, not any single number.
func _measure_speckle(img: Image) -> Dictionary:
	var counts := {}
	for th in SPECK_THRESHOLDS:
		counts[th] = 0
	var total := 0
	var w := img.get_width()
	var h := img.get_height()
	for y in range(1, h - 1):
		for x in range(1, w - 1):
			var lum := _luminance(img.get_pixel(x, y))
			var neighbor_sum := 0.0
			for oy in range(-1, 2):
				for ox in range(-1, 2):
					if ox == 0 and oy == 0:
						continue
					neighbor_sum += _luminance(img.get_pixel(x + ox, y + oy))
			var diff := lum - neighbor_sum / 8.0
			total += 1
			for th in SPECK_THRESHOLDS:
				if diff > th:
					counts[th] += 1
	var fractions := {}
	for th in SPECK_THRESHOLDS:
		fractions[th] = float(counts[th]) / float(total)
	return fractions


func _luminance(c: Color) -> float:
	return (c.r + c.g + c.b) / 3.0


func _format_speckle(fractions: Dictionary) -> String:
	var out := ""
	for th in SPECK_THRESHOLDS:
		out += "th>%.2f: %.4f  " % [th, fractions[th]]
	return out
