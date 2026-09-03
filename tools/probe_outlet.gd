extends SceneTree

## Dev tool: dumps the filled surface, D8 downstream and accumulation for
## the drainage test's crater fixture, so "which cell is the outlet" is
## settled by measurement rather than by reading the ASCII art.
##
## Usage: godot --headless --path . -s tools/probe_outlet.gd

const DrainageNetwork = preload("res://src/world/drainage_network.gd")

const SEA_LEVEL := 0.25


func _initialize() -> void:
	var heights := PackedFloat32Array()
	heights.resize(49)
	heights.fill(0.8)
	for x in 7:
		heights[x] = 0.2
	for y in range(3, 6):
		for x in range(2, 5):
			heights[y * 7 + x] = 0.3
	heights[1 * 7 + 3] = 0.6
	heights[2 * 7 + 3] = 0.6

	var network = DrainageNetwork.new().build(heights, 7, 7, SEA_LEVEL)
	print("depressions: ", network.depressions.size())
	for d in network.depressions:
		print("  ", d)

	print("\nindex (x,y)  height filled  down  (dx,dy)  accum  member")
	for y in 7:
		for x in 7:
			var i := y * 7 + x
			if network.depression_id[i] == DrainageNetwork.NO_DEPRESSION and heights[i] > 0.55:
				continue
			var down: int = network.downstream_index(i)
			var dxy := "sea"
			if down >= 0:
				dxy = "(%+d,%+d)" % [down % 7 - x, down / 7 - y]
			print("%3d (%d,%d)  %.2f   %.2f  %4d  %-8s %5d  %s" % [
				i, x, y, heights[i], network.filled[i], down, dxy,
				network.accumulation[i],
				"yes" if network.depression_id[i] != DrainageNetwork.NO_DEPRESSION else "no",
			])
	quit()
