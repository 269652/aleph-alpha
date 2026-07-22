extends RefCounted

## Generates a deterministic, seeded heightmap as a flat array of
## width * height values normalized to [0.0, 1.0], row-major (y * width + x).
func generate(width: int, height: int, seed_value: int) -> PackedFloat32Array:
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.frequency = 0.05

	var heights := PackedFloat32Array()
	heights.resize(width * height)

	for y in height:
		for x in width:
			var raw := noise.get_noise_2d(x, y)  # range [-1.0, 1.0]
			heights[y * width + x] = clampf((raw + 1.0) / 2.0, 0.0, 1.0)

	return heights
