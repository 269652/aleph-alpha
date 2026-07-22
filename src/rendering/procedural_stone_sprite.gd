extends RefCounted

## Deterministic offline pixel-art for boulders, matching the shaded/outlined
## technique ProceduralTreeSprite and the other procedural sprite generators
## use. The boulder is a squashed grey ellipse with a darker outline ring, a
## top-left highlight, a bottom shade band, and a few seeded darker crack/
## speckle pixels plus a seeded radius wobble so no two boulders are
## pixel-identical clones.

const PixelPalette = preload("res://src/rendering/pixel_palette.gd")

const SIZE := Vector2i(16, 16)
const OUTLINE_DARKEN := 0.5
const SHADE_DARKEN := 0.25
const HIGHLIGHT_LIGHTEN := 0.2
const SPECKLE_COUNT := 6

const STONE_COLOR := Color(0.56, 0.56, 0.59)

var _palette := PixelPalette.new()

## Fraction of SIZE.y the boulder occupies (squashed, sitting on the ground).
const BOULDER_HEIGHT_FRAC := 0.75


func generate_texture(seed_value: int) -> ImageTexture:
	return ImageTexture.create_from_image(generate_image(seed_value))


func generate_image(seed_value: int) -> Image:
	var image := Image.create(SIZE.x, SIZE.y, false, Image.FORMAT_RGBA8)

	var outline_color := _palette.outline_color()
	var shade_color := _palette.shade(STONE_COLOR)
	var highlight_color := _palette.highlight(STONE_COLOR)

	var boulder_height := SIZE.y * BOULDER_HEIGHT_FRAC
	var boulder_top := SIZE.y - boulder_height
	var center := Vector2(SIZE.x / 2.0, boulder_top + boulder_height / 2.0)
	var radius_x := SIZE.x / 2.0 - 1.0
	var radius_y := boulder_height / 2.0 - 0.5

	# Seeded shape wobble: shrink the horizontal radius slightly per seed so
	# boulders differ in silhouette, not just surface detail.
	var wobble := float(absi(hash("%d_shape" % seed_value)) % 10000) / 10000.0
	radius_x -= wobble * 1.5

	for y in SIZE.y:
		for x in SIZE.x:
			var dx := (x + 0.5 - center.x) / radius_x
			var dy := (y + 0.5 - center.y) / radius_y
			var dist_sq := dx * dx + dy * dy
			if dist_sq > 1.0:
				continue  # outside the boulder silhouette -- left transparent

			var color := STONE_COLOR
			if dist_sq > 0.78:
				color = outline_color
			elif dx < -0.15 and dy < -0.2:
				color = highlight_color
			elif dy > 0.35:
				color = shade_color
			image.set_pixel(x, y, color)

	_paint_speckles(image, center, radius_x, radius_y, outline_color, seed_value)
	return image


## A handful of deterministic darker crack/pit pixels inside the boulder,
## seeded from `seed_value` -- same idea as the tree canopy speckles.
func _paint_speckles(
	image: Image, center: Vector2, radius_x: float, radius_y: float, speckle_color: Color, seed_value: int
) -> void:
	for i in SPECKLE_COUNT:
		var speckle_seed := hash("%d_stone_speckle_%d" % [seed_value, i])
		var angle := float(absi(speckle_seed) % 360) * PI / 180.0
		var radius_fraction := 0.15 + float((absi(speckle_seed) / 360) % 100) / 100.0 * 0.55
		var speckle_x := int(center.x + cos(angle) * radius_x * radius_fraction)
		var speckle_y := int(center.y + sin(angle) * radius_y * radius_fraction)
		if speckle_x < 0 or speckle_x >= image.get_width() or speckle_y < 0 or speckle_y >= image.get_height():
			continue
		var dx := (speckle_x + 0.5 - center.x) / radius_x
		var dy := (speckle_y + 0.5 - center.y) / radius_y
		if dx * dx + dy * dy <= 0.78:  # keep speckles off the outline ring
			image.set_pixel(speckle_x, speckle_y, speckle_color)
