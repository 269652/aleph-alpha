extends SceneTree

## Dev tool: is the across field's own DATA jagged, tile to tile?
##
## Everything so far has asked how the map is RECONSTRUCTED. This asks
## whether the values being reconstructed are smooth in the first place.
## No filter, however continuous, can hide an input that oscillates from
## one tile to the next -- a C2 reconstruction of a sawtooth is a smooth
## sawtooth.
##
## Walks along the channel and, at each step, samples the across value at
## a FIXED lateral offset from the centreline. On a straight reach that
## series must be near-constant; on a bend it must drift slowly. Any
## tile-to-tile alternation in it is the artefact, in the data, before any
## shader is involved.
##
## Usage: godot --headless --path . -s tools/probe_across_series.gd -- x y [steps]

const HydrologyData = preload("res://src/world/hydrology_data.gd")
const HydrologyField = preload("res://src/world/hydrology_field.gd")
const EarthChunkGenerator = preload("res://src/world/earth_chunk_generator.gd")


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var start_x := int(args[0]) if args.size() > 0 else 19913
	var start_y := int(args[1]) if args.size() > 1 else 4742
	var steps := int(args[2]) if args.size() > 2 else 40

	var data := HydrologyData.new()
	if not data.load_from(HydrologyData.DEFAULT_DIRECTORY):
		print("probe_across_series: no bake at %s" % HydrologyData.DEFAULT_DIRECTORY)
		quit()
		return
	var field := HydrologyField.new(
		data, EarthChunkGenerator.WORLD_WIDTH_TILES, EarthChunkGenerator.WORLD_HEIGHT_TILES
	)

	print("across series from (%d, %d)\n" % [start_x, start_y])
	print(" step  tile           across    half   across/half   d(a/h)   bearing")

	var at := Vector2(float(start_x) + 0.5, float(start_y) + 0.5)
	var previous := INF
	var deltas: Array[float] = []
	var flips := 0
	var last_sign := 0
	for i in steps:
		var tile := Vector2i(int(at.x), int(at.y))
		var hit: Dictionary = field.nearest_channel_geometry(tile.x, tile.y)
		if hit.is_empty():
			print("%5d  %s  (no channel)" % [i, tile])
			break
		var half: float = hit["half_width_tiles"]
		var across: float = hit["signed_across_tiles"]
		var ratio := across / maxf(half, 0.01)
		var delta := 0.0 if previous == INF else ratio - previous
		if previous != INF:
			deltas.append(absf(delta))
			var sign_now := signi(int(signf(delta) * 1000.0))
			if last_sign != 0 and sign_now != 0 and sign_now != last_sign:
				flips += 1
			if sign_now != 0:
				last_sign = sign_now
		var hits: Array = field._channel_hits(tile.x, tile.y)
		var detail := ""
		for h in hits:
			var h_half: float = h["half_width_tiles"]
			detail += "[c%d a=%+.2f%s] " % [
				int(h.get("cell", -1)),
				float(h["distance_tiles"]) / maxf(h_half, 0.01),
				" IN" if float(h["distance_tiles"]) / maxf(h_half, 0.01) <= 1.0 else "",
			]
		print("%5d  %s  %+8.3f  %6.2f     %+8.3f  %+8.3f  %7.1f  %s" % [
			i, tile, across, half, ratio, delta, float(hit["course_bearing_deg"]), detail
		])
		previous = ratio
		var radians := deg_to_rad(float(hit["course_bearing_deg"]))
		at += Vector2(sin(radians), -cos(radians))

	if deltas.is_empty():
		quit()
		return
	deltas.sort()
	var total := 0.0
	for d in deltas:
		total += d
	print("\nstep-to-step change in across/half along the course:")
	print("   mean %.4f, median %.4f, worst %.4f" % [
		total / float(deltas.size()), deltas[deltas.size() / 2], deltas[-1]
	])
	print("   direction reversals: %d of %d steps (%.0f%%)" % [
		flips, deltas.size(), 100.0 * float(flips) / float(deltas.size())
	])
	print("   (walking ALONG a channel at a steady offset, the series should")
	print("    drift, not alternate -- reversals near half the steps are a")
	print("    tile-to-tile sawtooth in the DATA, which no filter can remove)")
	quit()
