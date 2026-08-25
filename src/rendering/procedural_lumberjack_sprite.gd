extends RefCounted

## The Sägewerk's Lumberjack NPC (see LumberjackMarker,
## docs/concept/timber_construction.md). Deliberately NOT CharacterView's
## full character-composite rig -- LumberjackMarker is a small, purpose-
## built walker (mirrors DecomposerMarker's own doc comment on why), so its
## art is the same tiny offline-generated silhouette style as
## ProceduralDecomposerSprite: a body, a head, and a held axe -- reads as a
## woodsman at a glance, not a fully-dressed villager.

const SIZE := 14

const TUNIC_COLOR := Color(0.36, 0.24, 0.12)
const SKIN_COLOR := Color(0.75, 0.58, 0.44)
const AXE_HANDLE_COLOR := Color(0.42, 0.28, 0.14)
const AXE_HEAD_COLOR := Color(0.55, 0.55, 0.58)


func generate_texture() -> ImageTexture:
	return ImageTexture.create_from_image(generate_image())


func generate_image() -> Image:
	var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var center := Vector2(SIZE / 2.0, SIZE / 2.0)

	# Body: a squat tunic-colored oval, standing on the tile's lower half.
	_draw_oval(image, center + Vector2(0.0, 1.5), 3.0, 4.0, TUNIC_COLOR)
	# Head: a small round patch of skin above the body.
	_draw_circle(image, center + Vector2(0.0, -3.5), 2.0, SKIN_COLOR)
	# A slung axe: a haft with a head at its top, held to one side --
	# reads distinctly different from the decomposer's legs/segments.
	_draw_line(image, center + Vector2(3.0, 2.0), center + Vector2(3.0, -3.0), AXE_HANDLE_COLOR)
	_draw_oval(image, center + Vector2(3.0, -3.5), 1.4, 1.0, AXE_HEAD_COLOR)

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


func _draw_line(image: Image, from: Vector2, to: Vector2, color: Color) -> void:
	var steps := int(from.distance_to(to) * 2.0) + 1
	for i in steps + 1:
		var point := from.lerp(to, float(i) / float(steps))
		var x := int(point.x)
		var y := int(point.y)
		if x >= 0 and x < SIZE and y >= 0 and y < SIZE:
			image.set_pixel(x, y, color)
