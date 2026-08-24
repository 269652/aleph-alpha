extends RefCounted

## Deterministic offline pixel-art for a cave-mouth marker -- a dark,
## slightly-irregular opening so it reads as a hole in the ground rather
## than a flat prop. No illustrated sheet exists yet for this (a documented
## gap, see docs/concept/geology.md's Status), so this flat procedural
## fallback is the only art today, same honestly-scoped situation
## ProceduralStoneSprite/ProceduralOreSprite are already in for any stone
## class with no sheet registered.

const PixelNoise = preload("res://src/rendering/pixel_noise.gd")

const SIZE := Vector2i(16, 16)
const _OPENING_COLOR := Color(0.06, 0.05, 0.05, 1.0)
const _RIM_COLOR := Color(0.24, 0.20, 0.17, 1.0)


func generate_texture(seed_value: int) -> ImageTexture:
	return ImageTexture.create_from_image(generate_image(seed_value))


func generate_image(seed_value: int) -> Image:
	var image := Image.create(SIZE.x, SIZE.y, false, Image.FORMAT_RGBA8)
	var center := Vector2(SIZE) * 0.5
	var base_radius := float(SIZE.x) * 0.4
	for y in SIZE.y:
		for x in SIZE.x:
			var offset := Vector2(x, y) + Vector2(0.5, 0.5) - center
			var angle := offset.angle()
			var wobble := PixelNoise.range_value(seed_value, int(angle * 100.0), 0, -0.15, 0.15)
			var radius := base_radius * (1.0 + wobble)
			var distance := offset.length()
			if distance <= radius * 0.75:
				image.set_pixel(x, y, _OPENING_COLOR)
			elif distance <= radius:
				image.set_pixel(x, y, _RIM_COLOR)
			else:
				image.set_pixel(x, y, Color(0, 0, 0, 0))
	return image
