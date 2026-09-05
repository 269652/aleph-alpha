extends SceneTree

## Dev tool: hunts for CREASES in the across field -- the geometric
## signature behind "zigzags at almost every bend".
##
## The strokes, the waterline, the ink line and the shore highlight are all
## contours of `across`, which is a signed DISTANCE to the channel's
## centreline curve. A distance field around a CURVED line is smooth
## except on its medial axis -- the locus, on the inside of a bend, where
## the nearest point on the curve jumps from one part of it to another.
## Across that locus the field has a genuine crease (a gradient
## discontinuity), and every contour through it comes out as a sharp V.
##
## The nearest point is not returned directly, but its TANGENT is (the
## course bearing). So a large bearing jump between ADJACENT tiles means
## the nearest point jumped: a crease. This scans a window and reports
## the worst jumps, with the local curvature for context.
##
## Usage: godot --headless --path . -s tools/probe_crease.gd
##        -- lat lon radius [jump_threshold_deg]

const EarthChunkGenerator = preload("res://src/world/earth_chunk_generator.gd")
const GeoCoordinates = preload("res://src/world/geo_coordinates.gd")


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var lat := float(args[0])
	var lon := float(args[1])
	var radius := int(args[2])
	var threshold := float(args[3]) if args.size() > 3 else 20.0
	var generator := EarthChunkGenerator.new()
	var geo := GeoCoordinates.new()
	var center := geo.tile_for_coordinate(
		lat, lon, EarthChunkGenerator.WORLD_WIDTH_TILES, EarthChunkGenerator.WORLD_HEIGHT_TILES
	)
	print("crease scan around %s, radius %d, threshold %.1f deg" % [center, radius, threshold])

	# Cache one row at a time so each tile is queried once, not four times.
	var wet_tiles := 0
	var creases: Array = []
	var worst_jump := 0.0
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var here := _read(generator, center.x + dx, center.y + dy)
			if not here["wet"]:
				continue
			wet_tiles += 1
			# Compare against the east and south neighbours only, so each
			# adjacent pair is examined exactly once.
			for offset in [Vector2i(1, 0), Vector2i(0, 1)]:
				var there := _read(generator, center.x + dx + offset.x, center.y + dy + offset.y)
				if not there["wet"]:
					continue
				var jump: float = absf(_angle_delta(here["bearing"], there["bearing"]))
				worst_jump = maxf(worst_jump, jump)
				if jump >= threshold:
					creases.append({
						"tile": Vector2i(center.x + dx, center.y + dy),
						"offset": offset,
						"jump": jump,
						"across_here": here["across"],
						"across_there": there["across"],
					})

	print("wet tiles scanned: %d, worst adjacent bearing jump: %.2f deg" % [wet_tiles, worst_jump])
	print("adjacent pairs jumping >= %.1f deg: %d" % [threshold, creases.size()])
	creases.sort_custom(func(a, b): return a["jump"] > b["jump"])
	for i in mini(25, creases.size()):
		var c: Dictionary = creases[i]
		print("  %s %s jump=%7.2f deg  across %6.3f -> %6.3f" % [
			c["tile"], c["offset"], c["jump"], c["across_here"], c["across_there"]
		])
	quit()


## The tile's across/bearing, plus whether it is WET (inside the channel,
## |across| < 1) -- a crease only matters where the water is actually drawn.
func _read(generator: EarthChunkGenerator, x: int, y: int) -> Dictionary:
	var hit: Dictionary = generator.nearest_river_at(x, y)
	if hit.is_empty():
		return {"wet": false, "across": 0.0, "bearing": 0.0}
	var half: float = hit.get("half_width_tiles", 2.0)
	var across: float = hit.signed_across_tiles / maxf(half, 0.01)
	return {"wet": absf(across) < 1.0, "across": across, "bearing": hit.course_bearing_deg}


## Signed smallest difference between two compass bearings, in degrees.
static func _angle_delta(a: float, b: float) -> float:
	return fposmod(b - a + 180.0, 360.0) - 180.0
