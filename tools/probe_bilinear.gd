extends SceneTree

## Dev tool: tests whether the zigzag is BILINEAR QUANTISATION of the
## across map.
##
## The flow map stores one texel per TILE (flow_map_tiles = 256 over 256
## tiles), holding `signed_across_tiles / half_width`. The shader samples
## it with filter_linear, and every stroke, the waterline, the ink line and
## the shore highlight are CONTOURS of that sampled field.
##
## Bilinear interpolation is continuous but its GRADIENT is not: it jumps
## at every texel boundary. A contour of such a field therefore kinks on a
## one-tile lattice -- which is exactly what "zigzags ... in regular steps
## at the edge" describes, and it would show at bends and behind boulders
## too, since those are where the field has the most structure.
##
## So this reconstructs the map on the CPU, samples the SAME bilinear
## filter at sub-tile resolution, and walks a line down the channel
## measuring the direction of the field's gradient -- the contour normal.
## A smooth field turns smoothly. A bilinear one oscillates with a period
## of exactly one tile, and this reports that period and its amplitude.
##
## Usage: godot --headless --path . -s tools/probe_bilinear.gd -- lat lon [steps_per_tile]

const HydrologyData = preload("res://src/world/hydrology_data.gd")
const HydrologyField = preload("res://src/world/hydrology_field.gd")
const EarthChunkGenerator = preload("res://src/world/earth_chunk_generator.gd")
const GeoCoordinates = preload("res://src/world/geo_coordinates.gd")

## How far either side of the centre tile the CPU copy of the map runs.
const GRID_RADIUS := 40


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var lat := float(args[0]) if args.size() > 0 else 47.2031
	var lon := float(args[1]) if args.size() > 1 else -1.5469
	var per_tile := int(args[2]) if args.size() > 2 else 8

	var data := HydrologyData.new()
	if not data.load_from(HydrologyData.DEFAULT_DIRECTORY):
		print("probe_bilinear: no bake at %s" % HydrologyData.DEFAULT_DIRECTORY)
		quit()
		return
	var field := HydrologyField.new(
		data, EarthChunkGenerator.WORLD_WIDTH_TILES, EarthChunkGenerator.WORLD_HEIGHT_TILES
	)
	var geo := GeoCoordinates.new()
	# Two large numbers are TILE coordinates, so a bend found by another
	# probe can be re-examined here without a lat/lon round trip.
	var center := (
		Vector2i(int(lat), int(lon)) if absf(lat) > 1000.0
		else geo.tile_for_coordinate(
			lat, lon, EarthChunkGenerator.WORLD_WIDTH_TILES, EarthChunkGenerator.WORLD_HEIGHT_TILES
		)
	)

	# The CPU copy of what _write_flow_across_texel puts in the R channel.
	var span := GRID_RADIUS * 2 + 1
	var across := PackedFloat32Array()
	across.resize(span * span)
	for gy in span:
		for gx in span:
			var tile := Vector2i(center.x + gx - GRID_RADIUS, center.y + gy - GRID_RADIUS)
			var hit: Dictionary = field.nearest_channel_geometry(tile.x, tile.y)
			var value := 16.0
			if not hit.is_empty():
				value = float(hit["signed_across_tiles"]) / maxf(float(hit["half_width_tiles"]), 0.01)
			across[gy * span + gx] = clampf(value, -16.0, 16.0)

	print("bilinear across-field scan at %s, %d samples per tile" % [center, per_tile])

	# Walk DOWN the channel: start at the centre tile, step along the local
	# course, and at each sub-tile step measure the gradient direction of
	# the bilinearly-sampled field. That direction is the contour's normal.
	var start: Dictionary = field.nearest_channel_geometry(center.x, center.y)
	if start.is_empty():
		print("no channel at the centre tile -- pick another lat/lon")
		quit()
		return
	var bearing: float = start["course_bearing_deg"]
	var radians := deg_to_rad(bearing)
	var along := Vector2(sin(radians), -cos(radians))
	var step := 1.0 / float(per_tile)

	var angles: Array[float] = []
	# The same walk under a CUBIC B-SPLINE reconstruction, which is C2 --
	# its gradient is continuous everywhere, so if the lattice is the cause
	# these spikes must vanish. Measured here BEFORE any shader is touched.
	var smooth_angles: Array[float] = []
	var positions: Array[float] = []
	var at := Vector2(float(center.x) + 0.5, float(center.y) + 0.5)
	for i in range(per_tile * 24):
		var local := at - Vector2(float(center.x - GRID_RADIUS), float(center.y - GRID_RADIUS))
		if local.x < 2.0 or local.y < 2.0 or local.x > float(span - 3) or local.y > float(span - 3):
			break
		# Re-read the course EVERY step: holding the start tile's bearing
		# walks a straight line, which leaves the channel at exactly the
		# bends this is meant to measure.
		var here: Dictionary = field.nearest_channel_geometry(int(at.x), int(at.y))
		if not here.is_empty():
			var here_rad := deg_to_rad(float(here["course_bearing_deg"]))
			along = Vector2(sin(here_rad), -cos(here_rad))
		var gradient := _gradient(across, span, local)
		if gradient.length() < 1e-6:
			at += along * step
			continue
		angles.append(rad_to_deg(gradient.angle()))
		var smooth := _gradient_bspline(across, span, local)
		smooth_angles.append(rad_to_deg(smooth.angle()) if smooth.length() > 1e-6 else 0.0)
		positions.append(float(i) * step)
		at += along * step

	if angles.size() < 8:
		print("too few samples along the course (%d)" % angles.size())
		quit()
		return

	# The turn between consecutive sub-tile samples. A smooth field gives a
	# small, slowly-varying number; a bilinear one spikes once per tile.
	var turns: Array[float] = []
	for i in range(1, angles.size()):
		turns.append(absf(_angle_delta(angles[i - 1], angles[i])))
	var sorted_turns := turns.duplicate()
	sorted_turns.sort()
	var median: float = sorted_turns[sorted_turns.size() / 2]
	var peak: float = sorted_turns[-1]
	print("contour-normal turn per %.3f-tile step: median %.3f deg, peak %.3f deg" % [
		step, median, peak
	])
	print("peak / median ratio: %.1f  (a smooth field is near 1; a spike per texel is large)" % [
		peak / maxf(median, 1e-6)
	])

	var smooth_turns: Array[float] = []
	for i in range(1, smooth_angles.size()):
		smooth_turns.append(absf(_angle_delta(smooth_angles[i - 1], smooth_angles[i])))
	smooth_turns.sort()
	var smooth_median: float = smooth_turns[smooth_turns.size() / 2]
	var smooth_peak: float = smooth_turns[-1]
	print("\nsame walk, cubic B-spline reconstruction:")
	print("   median %.3f deg, peak %.3f deg, ratio %.1f" % [
		smooth_median, smooth_peak, smooth_peak / maxf(smooth_median, 1e-6)
	])
	print("   peak turn %.1fx smaller than bilinear's" % (peak / maxf(smooth_peak, 1e-6)))

	# Where the spikes land. If they sit on whole-tile boundaries, the
	# texel lattice is the cause and there is nothing else to look for.
	var threshold := median * 3.0 + 0.05
	var spikes: Array[float] = []
	for i in turns.size():
		if turns[i] >= threshold:
			spikes.append(positions[i + 1])
	print("\nsteps turning more than 3x the median: %d of %d" % [spikes.size(), turns.size()])
	if spikes.size() >= 2:
		var gaps: Array[float] = []
		for i in range(1, spikes.size()):
			gaps.append(spikes[i] - spikes[i - 1])
		var total := 0.0
		for gap in gaps:
			total += gap
		print("mean spacing between spikes: %.3f tiles" % (total / float(gaps.size())))
		print("(1.000 means one kink per texel -- the map's own lattice)")
	var shown := 0
	for spike in spikes:
		if shown >= 12:
			break
		# Distance from the nearest whole tile: 0 means dead on a boundary.
		print("   spike at %6.3f tiles along, %.3f from a tile boundary" % [
			spike, absf(spike - round(spike))
		])
		shown += 1
	quit()


## The gradient under a cubic B-SPLINE reconstruction: C2, so its own
## gradient is continuous across texel boundaries instead of jumping.
static func _gradient_bspline(values: PackedFloat32Array, span: int, at: Vector2) -> Vector2:
	var h := 0.25
	var dx := (
		_bspline(values, span, at + Vector2(h, 0.0))
		- _bspline(values, span, at - Vector2(h, 0.0))
	)
	var dy := (
		_bspline(values, span, at + Vector2(0.0, h))
		- _bspline(values, span, at - Vector2(0.0, h))
	)
	return Vector2(dx, dy) / (2.0 * h)


## Cubic B-spline over the 4x4 neighbourhood. Approximating rather than
## interpolating -- it smooths the samples slightly, which for a distance
## field is a feature, and unlike warping the sample coordinate it does not
## bunch the contours toward texel centres.
static func _bspline(values: PackedFloat32Array, span: int, at: Vector2) -> float:
	var fx := at.x - 0.5
	var fy := at.y - 0.5
	var x0 := int(floor(fx))
	var y0 := int(floor(fy))
	var tx := fx - float(x0)
	var ty := fy - float(y0)
	var wx := _bspline_weights(tx)
	var wy := _bspline_weights(ty)
	var total := 0.0
	for j in 4:
		var sy := clampi(y0 - 1 + j, 0, span - 1)
		var row := 0.0
		for i in 4:
			var sx := clampi(x0 - 1 + i, 0, span - 1)
			row += values[sy * span + sx] * wx[i]
		total += row * wy[j]
	return total


static func _bspline_weights(t: float) -> Array[float]:
	var t2 := t * t
	var t3 := t2 * t
	return [
		(1.0 - 3.0 * t + 3.0 * t2 - t3) / 6.0,
		(4.0 - 6.0 * t2 + 3.0 * t3) / 6.0,
		(1.0 + 3.0 * t + 3.0 * t2 - 3.0 * t3) / 6.0,
		t3 / 6.0,
	]


## The bilinear-sampled field's gradient at a fractional grid position,
## by central difference at a quarter-texel -- small enough to sit inside
## one bilinear cell, so it reports that cell's own constant gradient.
static func _gradient(values: PackedFloat32Array, span: int, at: Vector2) -> Vector2:
	# Small enough to stay INSIDE one bilinear cell, so each sample
	# reports that cell's own gradient and a lattice kink shows up as a
	# jump BETWEEN samples rather than being averaged away.
	var h := 0.05
	var dx := _bilinear(values, span, at + Vector2(h, 0.0)) - _bilinear(values, span, at - Vector2(h, 0.0))
	var dy := _bilinear(values, span, at + Vector2(0.0, h)) - _bilinear(values, span, at - Vector2(0.0, h))
	return Vector2(dx, dy) / (2.0 * h)


## Exactly what filter_linear does: texel centres at +0.5, weights linear.
static func _bilinear(values: PackedFloat32Array, span: int, at: Vector2) -> float:
	var fx := at.x - 0.5
	var fy := at.y - 0.5
	var x0 := int(floor(fx))
	var y0 := int(floor(fy))
	var tx := fx - float(x0)
	var ty := fy - float(y0)
	var x1 := mini(x0 + 1, span - 1)
	var y1 := mini(y0 + 1, span - 1)
	x0 = clampi(x0, 0, span - 1)
	y0 = clampi(y0, 0, span - 1)
	var top: float = lerp(values[y0 * span + x0], values[y0 * span + x1], tx)
	var bottom: float = lerp(values[y1 * span + x0], values[y1 * span + x1], tx)
	return lerp(top, bottom, ty)


static func _angle_delta(a: float, b: float) -> float:
	return fposmod(b - a + 180.0, 360.0) - 180.0
