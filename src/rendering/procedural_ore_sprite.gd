extends RefCounted

## Deterministic offline pixel-art for ore nodes: a grey boulder (same shaded/
## outlined silhouette as ProceduralStoneSprite) studded with bright, seeded
## flecks of the ore's signature colour so each ore type reads at a glance
## (iron = orange-brown, copper = teal-green, coal = near-black).

const SIZE := Vector2i(16, 16)
const OUTLINE_DARKEN := 0.5
const SHADE_DARKEN := 0.25
const HIGHLIGHT_LIGHTEN := 0.2
const FLECK_COUNT := 10

const STONE_COLOR := Color(0.52, 0.52, 0.55)

## Fraction of SIZE.y the boulder occupies (squashed, sitting on the ground).
const BOULDER_HEIGHT_FRAC := 0.75

## Signature fleck colour per ore type.
const FLECK_COLOR := {
	"iron": Color(0.78, 0.42, 0.18),   # orange-brown
	"copper": Color(0.15, 0.68, 0.55),  # teal-green
	"coal": Color(0.08, 0.08, 0.10),    # near-black
}


func generate_texture(ore_type: String, seed_value: int) -> ImageTexture:
	return ImageTexture.create_from_image(generate_image(ore_type, seed_value))


func generate_image(ore_type: String, seed_value: int) -> Image:
	var image := Image.create(SIZE.x, SIZE.y, false, Image.FORMAT_RGBA8)

	var outline_color := STONE_COLOR.darkened(OUTLINE_DARKEN)
	var shade_color := STONE_COLOR.darkened(SHADE_DARKEN)
	var highlight_color := STONE_COLOR.lightened(HIGHLIGHT_LIGHTEN)

	var boulder_height := SIZE.y * BOULDER_HEIGHT_FRAC
	var boulder_top := SIZE.y - boulder_height
	var center := Vector2(SIZE.x / 2.0, boulder_top + boulder_height / 2.0)
	var radius_x := SIZE.x / 2.0 - 1.0
	var radius_y := boulder_height / 2.0 - 0.5

	var wobble := float(absi(hash("%d_ore_shape" % seed_value)) % 10000) / 10000.0
	radius_x -= wobble * 1.5

	for y in SIZE.y:
		for x in SIZE.x:
			var dx := (x + 0.5 - center.x) / radius_x
			var dy := (y + 0.5 - center.y) / radius_y
			var dist_sq := dx * dx + dy * dy
			if dist_sq > 1.0:
				continue  # outside the boulder silhouette -- transparent

			var color := STONE_COLOR
			if dist_sq > 0.78:
				color = outline_color
			elif dx < -0.15 and dy < -0.2:
				color = highlight_color
			elif dy > 0.35:
				color = shade_color
			image.set_pixel(x, y, color)

	_paint_flecks(image, center, radius_x, radius_y, ore_type, seed_value)
	return image


## Seeded bright ore flecks embedded in the boulder face. Two tones (base and a
## brightened variant) give the flecks a bit of sparkle.
func _paint_flecks(
	image: Image, center: Vector2, radius_x: float, radius_y: float, ore_type: String, seed_value: int
) -> void:
	var base_color: Color = FLECK_COLOR.get(ore_type, FLECK_COLOR["iron"])
	var bright_color := base_color.lightened(0.25)
	for i in FLECK_COUNT:
		# Independent hashes for angle and radius so flecks scatter across the
		# whole face instead of correlating onto a couple of pixels.
		var angle_seed := hash("%d_%s_ore_fleck_a_%d" % [seed_value, ore_type, i])
		var radius_seed := hash("%d_%s_ore_fleck_r_%d" % [seed_value, ore_type, i])
		var angle := float(absi(angle_seed) % 360) * PI / 180.0
		var radius_fraction := 0.1 + float(absi(radius_seed) % 100) / 100.0 * 0.65
		var fx := int(center.x + cos(angle) * radius_x * radius_fraction)
		var fy := int(center.y + sin(angle) * radius_y * radius_fraction)
		if fx < 0 or fx >= image.get_width() or fy < 0 or fy >= image.get_height():
			continue
		var dx := (fx + 0.5 - center.x) / radius_x
		var dy := (fy + 0.5 - center.y) / radius_y
		if dx * dx + dy * dy > 0.78:
			continue  # keep flecks off the outline ring
		image.set_pixel(fx, fy, bright_color if (i % 3 == 0) else base_color)
