extends RefCounted

## A small fishing bobber (red top, white bottom, dark outline -- the classic
## cork-float look) marking where a cast line has landed (see
## Player._fishing_step / FishingCast). Deterministic, no variants needed --
## same offline-art philosophy as every other procedural generator here.

const PixelPalette = preload("res://src/rendering/pixel_palette.gd")

## DETAIL_MULTIPLIER times the world footprint (see
## docs/concept/art_resolution.md) -- drawn at ArtResolution.SPRITE_SCALE
## so it gains pixel detail without growing in the world.
const SIZE := 20

const TOP_COLOR := Color(0.85, 0.15, 0.1)
const BOTTOM_COLOR := Color(0.95, 0.95, 0.92)

var _palette := PixelPalette.new()


func generate_texture() -> ImageTexture:
	return ImageTexture.create_from_image(generate_image())


func generate_image() -> Image:
	var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var center := Vector2(SIZE / 2.0, SIZE / 2.0)
	var r := SIZE / 2.0

	for y in SIZE:
		for x in SIZE:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(center)
			if d > r:
				continue
			var color := TOP_COLOR if y < SIZE / 2 else BOTTOM_COLOR
			if d > r - 1.0:
				color = _palette.outline_color()
			image.set_pixel(x, y, color)
	return image
