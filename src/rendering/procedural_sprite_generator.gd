extends RefCounted

## Deterministic in-engine pixel-art generator: assembles a shaded, outlined
## creature silhouette (with eyes and a seeded marking pattern) from a base
## color, entirely offline -- no external image-gen API/network/cost. Given
## the same (base_color, seed_value) it always produces the same image, so a
## species/individual looks consistent across sessions; a different seed
## produces a visibly different individual.

const SIZE := 16
const SPOT_COUNT := 4
const EYE_COLOR := Color(0.05, 0.05, 0.05)


func generate_creature_texture(base_color: Color, seed_value: int) -> ImageTexture:
	return ImageTexture.create_from_image(generate_creature_image(base_color, seed_value))


func generate_creature_image(base_color: Color, seed_value: int) -> Image:
	var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)

	var outline_color := base_color.darkened(0.6)
	var shade_color := base_color.darkened(0.25)
	var highlight_color := base_color.lightened(0.2)
	var spot_color := base_color.darkened(0.45)

	var center := Vector2(SIZE / 2.0, SIZE / 2.0 + 1.0)
	var radius_x := SIZE / 2.0 - 2.0
	var radius_y := SIZE / 2.0 - 3.0

	for y in SIZE:
		for x in SIZE:
			var dx := (x + 0.5 - center.x) / radius_x
			var dy := (y + 0.5 - center.y) / radius_y
			var dist_sq := dx * dx + dy * dy
			if dist_sq > 1.0:
				continue  # outside the body silhouette -- left transparent

			var color := base_color
			if dist_sq > 0.8:
				color = outline_color
			elif dy < -0.3:
				color = highlight_color
			elif dy > 0.4:
				color = shade_color
			image.set_pixel(x, y, color)

	_paint_spots(image, center, radius_x, radius_y, spot_color, seed_value)
	_paint_eyes(image, center, radius_x, radius_y)

	return image


func _paint_spots(
	image: Image, center: Vector2, radius_x: float, radius_y: float, spot_color: Color, seed_value: int
) -> void:
	for i in SPOT_COUNT:
		var spot_seed := hash("%d_spot_%d" % [seed_value, i])
		var angle := float(spot_seed % 360) * PI / 180.0
		var radius_fraction := 0.3 + float((spot_seed / 360) % 100) / 100.0 * 0.5
		var spot_x := int(center.x + cos(angle) * radius_x * radius_fraction)
		var spot_y := int(center.y + sin(angle) * radius_y * radius_fraction)
		if spot_x < 0 or spot_x >= SIZE or spot_y < 0 or spot_y >= SIZE:
			continue
		var dx := (spot_x + 0.5 - center.x) / radius_x
		var dy := (spot_y + 0.5 - center.y) / radius_y
		if dx * dx + dy * dy <= 0.8:  # keep spots off the outline ring
			image.set_pixel(spot_x, spot_y, spot_color)


func _paint_eyes(image: Image, center: Vector2, radius_x: float, radius_y: float) -> void:
	var eye_y := int(center.y - radius_y * 0.3)
	var eye_offset_x := int(radius_x * 0.35)
	image.set_pixel(int(center.x - eye_offset_x), eye_y, EYE_COLOR)
	image.set_pixel(int(center.x + eye_offset_x), eye_y, EYE_COLOR)
