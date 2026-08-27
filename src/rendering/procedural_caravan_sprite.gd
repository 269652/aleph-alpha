extends RefCounted

## A single porter carrying regional-trade goods (see CaravanMarker,
## docs/concept/trade.md). Tiny, deterministic, one silhouette -- same
## offline-art style as ProceduralDecomposerSprite: a pack-laden body plus a
## small head, no walk-cycle articulation at this scale.

const SIZE := 12

const BODY_COLOR := Color(0.32, 0.22, 0.12)
const PACK_COLOR := Color(0.48, 0.34, 0.16)


func generate_texture() -> ImageTexture:
	return ImageTexture.create_from_image(generate_image())


func generate_image() -> Image:
	var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var center := Vector2(SIZE / 2.0, SIZE / 2.0)
	_draw_oval(image, center + Vector2(0.0, 1.0), 2.0, 3.6, BODY_COLOR)
	_draw_circle(image, center + Vector2(0.0, -3.2), 1.6, BODY_COLOR)
	# The carried pack -- a broad bundle riding higher and wider than the
	# body, reading as "laden" even at this tiny scale.
	_draw_oval(image, center + Vector2(2.6, -0.5), 2.4, 2.8, PACK_COLOR)
	return image


func _draw_circle(image: Image, center: Vector2, radius: float, color: Color) -> void:
	var from_x := maxi(0, int(center.x - radius - 1))
	var to_x := mini(SIZE, int(center.x + radius + 1))
	var from_y := maxi(0, int(center.y - radius - 1))
	var to_y := mini(SIZE, int(center.y + radius + 1))
	for y in range(from_y, to_y):
		for x in range(from_x, to_x):
			if Vector2(x + 0.5, y + 0.5).distance_to(center) <= radius:
				image.set_pixel(x, y, color)


func _draw_oval(image: Image, center: Vector2, radius_x: float, radius_y: float, color: Color) -> void:
	for y in SIZE:
		for x in SIZE:
			var point := Vector2(x + 0.5, y + 0.5)
			var normalized := Vector2((point.x - center.x) / radius_x, (point.y - center.y) / radius_y)
			if normalized.length() <= 1.0:
				image.set_pixel(x, y, color)
