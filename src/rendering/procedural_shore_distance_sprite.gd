extends RefCounted

## Per-pixel land-proximity DATA, not art: a 16x16 image whose red channel
## encodes normalized distance to the nearest land-facing edge (0 right at
## the edge touching land, 1 at the tile's far side). Consumed by
## water_shader.gd as a texture sample (never rendered directly) to drive a
## smooth, continuous alpha fade and shore-wave band on the GPU -- replacing
## the old baked foam/dash shore tiles, whose fixed 16px tile boundaries read
## as a jagged staircase around every lake.

const SIZE := 16


func generate_texture(land_directions: Array) -> ImageTexture:
	return ImageTexture.create_from_image(generate_image(land_directions))


## `land_directions`: cardinal Vector2i directions (TerrainRenderer's
## _DIRECTIONS convention) toward this cell's land neighbors. Multiple
## directions combine with min() -- a pixel near two land edges reads as
## close to shore from whichever edge is actually nearer, so corners fade
## correctly toward both sides at once instead of favoring one arbitrarily.
func generate_image(land_directions: Array) -> Image:
	var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	for y in SIZE:
		for x in SIZE:
			var value := 1.0
			for direction in land_directions:
				value = minf(value, _distance_along(x, y, direction))
			image.set_pixel(x, y, Color(value, value, value, 1.0))
	return image


## A uniform "far from any shore" tile, for open-water cells with no land
## neighbor at all.
func generate_deep_water_image() -> Image:
	var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	image.fill(Color(1.0, 1.0, 1.0, 1.0))
	return image


## Normalized [0, 1] distance from (x, y) to the tile edge facing
## `direction` -- 0 right at that edge, 1 at the opposite edge. Unknown/non-
## cardinal directions fail safe to "far" (1.0) rather than crashing.
func _distance_along(x: int, y: int, direction: Vector2i) -> float:
	var last := float(SIZE - 1)
	if direction == Vector2i(0, -1):
		return y / last
	if direction == Vector2i(0, 1):
		return (last - y) / last
	if direction == Vector2i(-1, 0):
		return x / last
	if direction == Vector2i(1, 0):
		return (last - x) / last
	return 1.0
