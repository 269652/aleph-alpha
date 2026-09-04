extends SceneTree

## Dev tool: tests the standing zigzag hypothesis WITHOUT touching the
## shader.
##
## RiverFlowShader smears its noise field along a STRAIGHT line: it takes
## SMEAR_TAPS samples spaced SMEAR_SPACING apart in noise units, all along
## one fixed `flow_dir` read at the fragment. If the real flow rotates
## appreciably over that span, then two neighbouring fragments smear along
## lines that diverge, and the strokes they draw tear apart instead of
## lining up -- which is what a zigzag is.
##
## So the question is quantitative: how many degrees does the course turn
## across ONE smear length? This walks the real baked field, follows each
## wet tile's own flow direction out to each tap position, reads the
## bearing there, and reports the total angular spread across the taps.
##
## A large spread at bends supports the hypothesis and justifies paying
## for streamline smearing. A small one kills it, for the price of a
## headless run instead of 18 extra texture samples per fragment.
##
## Usage: godot --headless --path . -s tools/probe_smear.gd -- lat lon radius

const HydrologyData = preload("res://src/world/hydrology_data.gd")
const HydrologyField = preload("res://src/world/hydrology_field.gd")
const EarthChunkGenerator = preload("res://src/world/earth_chunk_generator.gd")
const GeoCoordinates = preload("res://src/world/geo_coordinates.gd")
const RiverFlowShader = preload("res://src/rendering/river_flow_shader.gd")


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var lat := float(args[0]) if args.size() > 0 else 47.2031
	var lon := float(args[1]) if args.size() > 1 else -1.5469
	var radius := int(args[2]) if args.size() > 2 else 120

	# One tap step, in TILES: the shader spaces taps by SMEAR_SPACING in
	# noise units, and noise units are world pixels times NOISE_SCALE.
	var taps: int = RiverFlowShader.SMEAR_TAPS
	var step_tiles: float = (
		RiverFlowShader.SMEAR_SPACING / RiverFlowShader.NOISE_SCALE / RiverFlowShader.TILE_PX
	)
	var half_taps := (taps - 1) / 2
	var span_tiles := step_tiles * float(taps - 1)
	print("smear geometry: %d taps, %.3f tiles apart, total span %.2f tiles" % [
		taps, step_tiles, span_tiles
	])

	var data := HydrologyData.new()
	if not data.load_from(HydrologyData.DEFAULT_DIRECTORY):
		print("probe_smear: no bake at %s" % HydrologyData.DEFAULT_DIRECTORY)
		quit()
		return
	var field := HydrologyField.new(
		data, EarthChunkGenerator.WORLD_WIDTH_TILES, EarthChunkGenerator.WORLD_HEIGHT_TILES
	)
	var geo := GeoCoordinates.new()
	var center := geo.tile_for_coordinate(
		lat, lon, EarthChunkGenerator.WORLD_WIDTH_TILES, EarthChunkGenerator.WORLD_HEIGHT_TILES
	)
	print("scan around %s, radius %d\n" % [center, radius])

	var spreads: Array[float] = []
	# The residual a CHEAP fix would leave. Instead of re-sampling the
	# flow at all nine taps, sample it at the two ENDS and interpolate
	# the direction linearly along the smear. Over a circular arc the
	# tangent rotates linearly with arc length, so for a bend of roughly
	# constant curvature that model is nearly exact -- and it costs two
	# extra texture samples rather than eight.
	var residuals: Array[float] = []
	var worst: Array = []
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var x := center.x + dx
			var y := center.y + dy
			var here: Dictionary = field.nearest_channel_geometry(x, y)
			if here.is_empty():
				continue
			var half: float = here["half_width_tiles"]
			if absf(here["signed_across_tiles"]) / maxf(half, 0.01) >= 1.0:
				continue  # dry: the shader draws no stroke here
			var bearing: float = here["course_bearing_deg"]
			var radians := deg_to_rad(bearing)
			var flow := Vector2(sin(radians), -cos(radians))
			var lowest := 0.0
			var highest := 0.0
			var sampled := 0
			# Each tap's own bearing relative to the centre, indexed by k,
			# so the endpoint-interpolation residual can be computed from
			# the same samples rather than a second walk.
			var deltas := {}
			for k in range(-half_taps, half_taps + 1):
				if k == 0:
					continue
				var at := Vector2(float(x), float(y)) + flow * (float(k) * step_tiles)
				var tap: Dictionary = field.nearest_channel_geometry(
					int(round(at.x)), int(round(at.y))
				)
				if tap.is_empty():
					continue
				var delta := _angle_delta(bearing, tap["course_bearing_deg"])
				deltas[k] = delta
				lowest = minf(lowest, delta)
				highest = maxf(highest, delta)
				sampled += 1
			if sampled < 2:
				continue
			var spread := highest - lowest
			spreads.append(spread)
			# What linear interpolation between the two END taps leaves.
			if deltas.has(-half_taps) and deltas.has(half_taps):
				var start: float = deltas[-half_taps]
				var end: float = deltas[half_taps]
				var residual := 0.0
				for k in deltas:
					var t := (float(k) + float(half_taps)) / float(2 * half_taps)
					residual = maxf(residual, absf(float(deltas[k]) - lerp(start, end, t)))
				residuals.append(residual)
			worst.append({"tile": Vector2i(x, y), "spread": spread, "bearing": bearing})

	if spreads.is_empty():
		print("no wet tiles found in the window")
		quit()
		return
	spreads.sort()
	print("wet tiles measured: %d" % spreads.size())
	print("rotation across ONE smear length, degrees:")
	for q in [0.5, 0.75, 0.9, 0.99, 1.0]:
		var index := mini(spreads.size() - 1, int(float(spreads.size() - 1) * q))
		print("   %5.0f%% of tiles at or under %7.2f deg" % [q * 100.0, spreads[index]])
	var over := 0
	for spread in spreads:
		if spread >= 30.0:
			over += 1
	print("tiles turning 30 deg or more across one smear: %d (%.1f%%)" % [
		over, 100.0 * float(over) / float(spreads.size())
	])
	if not residuals.is_empty():
		residuals.sort()
		print("\nresidual AFTER interpolating direction between the two end taps:")
		for q in [0.5, 0.75, 0.9, 0.99, 1.0]:
			var index := mini(residuals.size() - 1, int(float(residuals.size() - 1) * q))
			print("   %5.0f%% of tiles at or under %7.2f deg" % [q * 100.0, residuals[index]])
		var still_over := 0
		for residual in residuals:
			if residual >= 30.0:
				still_over += 1
		print("tiles still 30 deg or more off: %d of %d (%.1f%%)" % [
			still_over, residuals.size(), 100.0 * float(still_over) / float(residuals.size())
		])
	worst.sort_custom(func(a, b): return a["spread"] > b["spread"])
	print("\nworst tiles:")
	for i in mini(12, worst.size()):
		var w: Dictionary = worst[i]
		print("   %s  spread=%7.2f deg  bearing=%6.1f" % [w["tile"], w["spread"], w["bearing"]])
	quit()


## Signed smallest difference between two compass bearings, in degrees.
static func _angle_delta(a: float, b: float) -> float:
	return fposmod(b - a + 180.0, 360.0) - 180.0
