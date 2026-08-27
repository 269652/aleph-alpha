extends RefCounted

## A killed animal's remains lying on the ground (see Carcass,
## docs/concept/carrion.md) -- one shared silhouette regardless of species,
## the same "dirt looks the same regardless of what's growing in it"
## reasoning ProceduralSoilSprite already gives for the soil mound under a
## wild crop. No AI art exists for this yet, so a hand-drawn procedural
## fallback in the same offline-art style as ProceduralBobberSprite.
##
## Two states: INTACT (a rounded reddish-brown mass, still holding its
## parts) and STRIPPED (paler, flatter -- what's left once hide/meat/guts
## have all been taken; what a decomposer actually works on).

const PixelPalette = preload("res://src/rendering/pixel_palette.gd")

const SIZE := 26

const INTACT_COLOR := Color(0.38, 0.16, 0.13)
## Paler and greyer -- bone/connective tissue rather than a fresh kill.
const STRIPPED_COLOR := Color(0.55, 0.5, 0.42)

var _palette := PixelPalette.new()


func generate_texture(stripped: bool) -> ImageTexture:
	return ImageTexture.create_from_image(generate_image(stripped))


func generate_image(stripped: bool) -> Image:
	var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var center := Vector2(SIZE / 2.0, SIZE / 2.0)
	# Not a perfect circle -- a carcass lies flatter/wider than it is tall,
	# unlike the round mounds/blobs everything else in this file this
	# mirrors is drawn as.
	var radius_x := SIZE / 2.0
	var radius_y := SIZE / 3.0
	var base_color := STRIPPED_COLOR if stripped else INTACT_COLOR

	for y in SIZE:
		for x in SIZE:
			var point := Vector2(x + 0.5, y + 0.5)
			var normalized := Vector2((point.x - center.x) / radius_x, (point.y - center.y) / radius_y)
			var d := normalized.length()
			if d > 1.0:
				continue
			if d > 1.0 - (1.0 / radius_y):
				image.set_pixel(x, y, _palette.outline_color())
				continue
			var lit := normalized.x < 0.0 and normalized.y < 0.0
			image.set_pixel(x, y, _palette.highlight(base_color) if lit else _palette.shade(base_color))
	return image
