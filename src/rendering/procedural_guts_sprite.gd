extends RefCounted

## Offal spilled from a butchered carcass (see CarcassGuts,
## docs/concept/carrion.md) -- a small dark-red glistening mass. No AI art
## exists for this yet, so a hand-drawn procedural fallback in the same
## offline-art style as ProceduralBobberSprite and friends. Deterministic,
## no variants needed -- guts don't need to look different creature to
## creature at this scale, the same reasoning ProceduralSoilSprite already
## gives for sharing one mound across every crop.

const PixelPalette = preload("res://src/rendering/pixel_palette.gd")

const SIZE := 18

const GUTS_COLOR := Color(0.42, 0.05, 0.08)
## A wet sheen highlight, not the usual upper-left rim light -- this is a
## slick organic mass, not a solid shaded object.
const SHEEN_COLOR := Color(0.62, 0.15, 0.18)

var _palette := PixelPalette.new()


func generate_texture() -> ImageTexture:
	return ImageTexture.create_from_image(generate_image())


func generate_image() -> Image:
	var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var center := Vector2(SIZE / 2.0, SIZE / 2.0)
	var radius := SIZE / 2.0

	for y in SIZE:
		for x in SIZE:
			var point := Vector2(x + 0.5, y + 0.5)
			var d := point.distance_to(center)
			if d > radius:
				continue
			if d > radius - 1.0:
				image.set_pixel(x, y, _palette.outline_color())
				continue
			var to_point := point - center
			var sheen := to_point.x < 0.0 and to_point.y < 0.0
			image.set_pixel(x, y, SHEEN_COLOR if sheen else GUTS_COLOR)
	return image
