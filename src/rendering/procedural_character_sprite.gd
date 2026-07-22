extends RefCounted

## Deterministic offline pixel-art for the player/NPC body (torso, limbs,
## head) -- shaded and outlined rather than the old single flat-color fills,
## matching the same technique ProceduralSpriteGenerator (creatures) and
## ProceduralItemSprite (items) already use, for a consistent look across the
## whole game.

const PixelPalette = preload("res://src/rendering/pixel_palette.gd")

const OUTLINE_DARKEN := 0.5
const SHADE_DARKEN := 0.2
const HIGHLIGHT_LIGHTEN := 0.2

var _palette := PixelPalette.new()


## A rectangular body part (torso/limb): outlined edge, lighter top, darker
## bottom -- reads as a small rounded block instead of a flat rectangle.
func generate_body_part_texture(size: Vector2i, base_color: Color) -> ImageTexture:
	return ImageTexture.create_from_image(generate_body_part_image(size, base_color))


func generate_body_part_image(size: Vector2i, base_color: Color) -> Image:
	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	for y in size.y:
		for x in size.x:
			var is_edge := x == 0 or y == 0 or x == size.x - 1 or y == size.y - 1
			var color := base_color
			if is_edge:
				color = _palette.outline_color()
			elif y < size.y * 0.35:
				color = _palette.highlight(base_color)
			elif y > size.y * 0.7:
				color = _palette.shade(base_color)
			image.set_pixel(x, y, color)
	return image


## A round, shaded head with two simple eye pixels.
func generate_head_texture(size: Vector2i, skin_color: Color, eye_color: Color) -> ImageTexture:
	return ImageTexture.create_from_image(generate_head_image(size, skin_color, eye_color))


func generate_head_image(size: Vector2i, skin_color: Color, eye_color: Color) -> Image:
	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	var center := Vector2(size.x / 2.0, size.y / 2.0)
	var rx := size.x / 2.0
	var ry := size.y / 2.0

	for y in size.y:
		for x in size.x:
			var dx := (x + 0.5 - center.x) / rx
			var dy := (y + 0.5 - center.y) / ry
			var d := dx * dx + dy * dy
			if d > 1.0:
				continue
			var color := skin_color
			if d > 0.75:
				color = _palette.outline_color()
			elif dy < -0.3:
				color = _palette.highlight(skin_color)
			elif dy > 0.3:
				color = _palette.shade(skin_color)
			image.set_pixel(x, y, color)

	var eye_y := int(size.y / 3.0)
	image.set_pixel(int(size.x * 0.3), eye_y, eye_color)
	image.set_pixel(int(size.x * 0.7), eye_y, eye_color)
	return image
