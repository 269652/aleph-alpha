extends RefCounted

## Elevation removed from each cell a droplet passes through.
const EROSION_AMOUNT := 0.02

const NEIGHBOR_OFFSETS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]


## Carves the heightmap by simulating `iterations` droplets: each spawns at a
## seeded-random cell and flows to strictly-lower neighbors, eroding a fixed
## amount from every cell it leaves, until it reaches a local minimum.
## Returns a new heightmap; the input is not modified.
func erode(heights: PackedFloat32Array, width: int, height: int, iterations: int, seed_value: int) -> PackedFloat32Array:
	var eroded := heights.duplicate()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value

	for i in iterations:
		var start_x := rng.randi_range(0, width - 1)
		var start_y := rng.randi_range(0, height - 1)
		_flow_downhill(eroded, width, height, start_x, start_y)

	return eroded


func _flow_downhill(heights: PackedFloat32Array, width: int, height: int, start_x: int, start_y: int) -> void:
	var x := start_x
	var y := start_y

	while true:
		var current_index := y * width + x
		var current_height := heights[current_index]
		var next_x := x
		var next_y := y
		var lowest := current_height

		for offset in NEIGHBOR_OFFSETS:
			var nx := x + offset.x
			var ny := y + offset.y
			if nx < 0 or nx >= width or ny < 0 or ny >= height:
				continue
			var neighbor_height := heights[ny * width + nx]
			if neighbor_height < lowest:
				lowest = neighbor_height
				next_x = nx
				next_y = ny

		if next_x == x and next_y == y:
			return  # local minimum: nothing lower to flow to

		heights[current_index] = clampf(current_height - EROSION_AMOUNT, 0.0, 1.0)
		x = next_x
		y = next_y
