extends SceneTree

## Dev tool: walks the same row through the synthetic confluence that
## test_the_across_field_is_continuous_through_a_confluence walks, but
## prints what the blend is actually made of at each step -- which
## channels were hit, their discharges, their half widths and their own
## across values -- so a jump in the blended field can be attributed
## instead of guessed at.
##
## Usage: godot --headless --path . -s tools/probe_confluence.gd

const DrainageNetwork = preload("res://src/world/drainage_network.gd")
const HydrologyData = preload("res://src/world/hydrology_data.gd")
const HydrologyField = preload("res://src/world/hydrology_field.gd")

const SEA_LEVEL := 0.25
const WORLD_TILES := 70


func _initialize() -> void:
	var heights := PackedFloat32Array()
	heights.resize(49)
	heights.fill(0.8)
	for x in 7:
		heights[x] = 0.2
	for y in range(1, 7):
		heights[y * 7 + 3] = 0.6
	for x in range(0, 3):
		heights[3 * 7 + x] = 0.7

	var network = DrainageNetwork.new().build(heights, 7, 7, SEA_LEVEL)
	var weights := PackedFloat32Array()
	weights.resize(49)
	weights.fill(1.0)
	for y in range(1, 7):
		weights[y * 7 + 3] = 2.0
	var data := HydrologyData.new()
	data.build_from_network(network, network.accumulate_weighted(weights))
	var field := HydrologyField.new(data, WORLD_TILES, WORLD_TILES)
	field.river_min_discharge = 3.0

	print("cell discharges (7x7), tile size = %d" % (WORLD_TILES / 7))
	for y in 7:
		var row := ""
		for x in 7:
			row += "%8.2f" % data.discharge_at(y * 7 + x)
		print("  ", row)

	print("\n  x  across  |across|/hw   Q      hw   bearing   hits")
	var previous := INF
	for x in range(26, 40):
		var geometry: Dictionary = field.nearest_channel_geometry(x, 33)
		if geometry.is_empty():
			print("%3d  (dry)" % x)
			previous = INF
			continue
		var half: float = geometry["half_width_tiles"]
		var across: float = absf(geometry["signed_across_tiles"]) / half
		var jump := 0.0 if previous == INF else absf(across - previous)
		var hits: Array = field._channel_hits(x, 33)
		var detail := ""
		for hit in hits:
			detail += "[cell %d Q=%.1f hw=%.2f a=%+.2f] " % [
				int(hit.get("cell", -1)), float(hit.get("discharge", 0.0)),
				float(hit.get("half_width_tiles", 0.0)),
				float(hit.get("signed_across_tiles", 0.0)),
			]
		print("%3d  %+6.2f  %6.2f  %s %7.2f %6.2f %7.1f   %s" % [
			x, float(geometry["signed_across_tiles"]), across,
			"JUMP" if jump >= 0.4 else "    ",
			float(geometry["discharge"]), half,
			float(geometry["course_bearing_deg"]), detail,
		])
		previous = across
	quit()
