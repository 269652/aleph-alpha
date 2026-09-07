extends RefCounted

## Procedural art for a solitary wild bee's nest hole -- see
## WildBeeNestMarker, docs/concept/bees.md's "Wild bee nests". No
## illustrated art was supplied for this (unlike the honeybee hive) -- a
## real, named gap for future art, not a blocker. A small twig stub with
## a dark entrance hole: the same "posterized circle + darker entrance
## dot" technique ProceduralAntMoundSprite already established for a
## structurally similar "small ground/branch feature with a hole" shape,
## recoloured to bark/wood rather than soil.
##
## Unlike ProceduralAntMoundSprite/ProceduralBeehiveSprite, this has NO
## growth-fraction sizing at all -- a hole is a fixed physical feature of
## existing deadwood; only its OCCUPANCY changes (see
## WildBeePatch.residents_at), never its own size. One fixed WORLD_WIDTH,
## the same "small, real, unremarkable" reading a hole in a twig should
## have regardless of how many residents currently work it.

const PixelPalette = preload("res://src/rendering/pixel_palette.gd")

const SIZE := 14

## A real, fixed physical feature -- a nest hole reads noticeably
## smaller than even a founding honeybee hive (a hole in a twig, not a
## hanging comb a colony actively builds out).
const WORLD_WIDTH := 2.5
const WORLD_SCALE := WORLD_WIDTH / float(SIZE)

const BARK_COLOR := Color(0.42, 0.30, 0.19)
## Distinctly darker than BARK_COLOR's own shade band, but not
## PixelPalette.OUTLINE-dark -- mirrors ProceduralAntMoundSprite.
## ENTRANCE_COLOR's own reasoning exactly.
const ENTRANCE_COLOR := Color(0.16, 0.10, 0.05)
const ENTRANCE_RADIUS := 2.0

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
			image.set_pixel(x, y, _color_at(point, center, radius, d))
	return image


func _color_at(point: Vector2, center: Vector2, radius: float, d: float) -> Color:
	if d > radius - 1.0:
		return _palette.outline_color()

	if point.distance_to(center) <= ENTRANCE_RADIUS:
		return ENTRANCE_COLOR

	# Posterized light/shadow banding from the upper-left, same
	# single-light-source convention every other generator here follows.
	var to_point := point - center
	var lit := to_point.x < 0 and to_point.y < 0
	return _palette.highlight(BARK_COLOR) if lit else _palette.shade(BARK_COLOR)
