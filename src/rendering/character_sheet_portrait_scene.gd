extends RefCounted

## A small illustrated backdrop for the companion server's Character Sheet
## portrait (see docs/concept/companion_server.md and
## CompanionCharacterSheetView) -- a sky/ground vignette with the hero
## standing on it, not just a bare figure floating on transparency.
##
## Deliberately NOT the live CharacterPreviewDiorama scene: that is a real,
## continuously-animated Node2D (swaying grass, a pond, ambient creatures)
## built for the character creator's SubViewport, and reusing it here would
## mean instantiating live rendering nodes on every Character Sheet page
## load -- exactly what CompanionServer's own doc comment states this
## server deliberately never does ("reads only the save file, no live
## Player/scene-tree hook"). This class is a pure Image compositor instead,
## the same shape as ProceduralCharacterSprite.generate_hero_portrait_image,
## which it calls directly for the figure itself -- no Godot Node of any
## kind, safe to call from a plain HTTP request handler.

const ProceduralCharacterSprite = preload("res://src/rendering/procedural_character_sprite.gd")
const PixelPalette = preload("res://src/rendering/pixel_palette.gd")

## The whole scene, portrait included -- bigger than
## ProceduralCharacterSprite.PORTRAIT_SIZE (52x80) so there is real
## environment around the figure, not just a backdrop-colored margin.
const CANVAS_SIZE := Vector2i(140, 120)

## How tall the ground band is, in pixels from the bottom of the canvas --
## also where the figure's own feet land (see _ground_y).
const GROUND_MARGIN_PX := 28

## A simple two-stop vertical gradient, lighter near the horizon -- the same
## "one light source, posterized bands" convention PixelPalette's own
## shade/highlight helpers use elsewhere in this game's art, kept to two flat
## stops rather than a smooth blend so it reads as 16-bit pixel art next to
## the character's own flat-shaded portrait, not a modern smooth-shaded
## backdrop behind retro-shaded art.
const SKY_ZENITH := Color(0.38, 0.58, 0.82)
const SKY_HORIZON := Color(0.68, 0.82, 0.88)
const GROUND_COLOR := Color(0.36, 0.52, 0.26)
const GROUND_SHADE := Color(0.3, 0.44, 0.22)

## A few small hand-placed accents (grass tufts, a pebble) so the ground
## reads as a real patch of the game's own world, not a flat color fill --
## fixed positions/looks rather than seeded per-hero, since this backdrop is
## meant to read as "the same little clearing", not something that reshuffles
## every time a different hero is shown on it.
const _GRASS_TUFT_COLOR := Color(0.42, 0.58, 0.28)
const _GRASS_TUFT_POSITIONS := [Vector2i(14, 8), Vector2i(28, 4), Vector2i(112, 6), Vector2i(122, 10)]
const _PEBBLE_COLOR := Color(0.58, 0.56, 0.52)
const _PEBBLE_SHADE := Color(0.42, 0.4, 0.38)
const _PEBBLE_POSITION := Vector2i(100, 16)
const _PEBBLE_RADIUS := 4.0

var _character_sprite := ProceduralCharacterSprite.new()
var _palette := PixelPalette.new()


func generate_texture(appearance: Dictionary) -> ImageTexture:
	return ImageTexture.create_from_image(generate_image(appearance))


func generate_image(appearance: Dictionary) -> Image:
	var image := Image.create(CANVAS_SIZE.x, CANVAS_SIZE.y, false, Image.FORMAT_RGBA8)
	_paint_sky(image)
	_paint_ground(image)
	_paint_ground_accents(image)
	_blend_portrait(image, appearance)
	return image


## PNG-encoded bytes, ready to serve as `image/png` or embed as a
## `data:image/png;base64,...` URI -- see CompanionCharacterSheetView.
func generate_png_bytes(appearance: Dictionary) -> PackedByteArray:
	return generate_image(appearance).save_png_to_buffer()


func _ground_y() -> int:
	return CANVAS_SIZE.y - GROUND_MARGIN_PX


func _paint_sky(image: Image) -> void:
	var ground_y := _ground_y()
	for y in ground_y:
		var color := SKY_ZENITH if y < ground_y / 2 else SKY_HORIZON
		for x in CANVAS_SIZE.x:
			image.set_pixel(x, y, color)


func _paint_ground(image: Image) -> void:
	var ground_y := _ground_y()
	for y in range(ground_y, CANVAS_SIZE.y):
		# A single shaded band along the bottom edge, the same "one darker
		# strip along the unlit side" convention ProceduralCharacterSprite's
		# own body parts use -- reads as the ground's own far edge rather
		# than a perfectly flat fill.
		var color := GROUND_SHADE if y >= CANVAS_SIZE.y - 3 else GROUND_COLOR
		for x in CANVAS_SIZE.x:
			image.set_pixel(x, y, color)


func _paint_ground_accents(image: Image) -> void:
	for tuft in _GRASS_TUFT_POSITIONS:
		var at: Vector2i = tuft
		_paint_grass_tuft(image, Vector2i(at.x, _ground_y() + at.y))
	_paint_pebble(image, Vector2i(_PEBBLE_POSITION.x, _ground_y() + _PEBBLE_POSITION.y))


## Three short upward strokes -- the same minimal "reads as grass at this
## scale" shape this game's other small ground decorations use.
func _paint_grass_tuft(image: Image, base: Vector2i) -> void:
	for blade_x in [-2, 0, 2]:
		for h in range(4):
			var x: int = base.x + blade_x
			var y: int = base.y - h
			if x >= 0 and x < CANVAS_SIZE.x and y >= 0 and y < CANVAS_SIZE.y:
				image.set_pixel(x, y, _GRASS_TUFT_COLOR)


func _paint_pebble(image: Image, center: Vector2i) -> void:
	var from_x := maxi(0, int(center.x - _PEBBLE_RADIUS - 1))
	var to_x := mini(CANVAS_SIZE.x, int(center.x + _PEBBLE_RADIUS + 1))
	var from_y := maxi(0, int(center.y - _PEBBLE_RADIUS - 1))
	var to_y := mini(CANVAS_SIZE.y, int(center.y + _PEBBLE_RADIUS + 1))
	for y in range(from_y, to_y):
		for x in range(from_x, to_x):
			var point := Vector2(x + 0.5, y + 0.5)
			var offset := Vector2(center) - point
			if point.distance_to(Vector2(center)) > _PEBBLE_RADIUS:
				continue
			var lit := offset.x > 0 and offset.y > 0
			image.set_pixel(x, y, _PEBBLE_COLOR if lit else _PEBBLE_SHADE)


## Draws the hero portrait (ProceduralCharacterSprite's own hand/AI-
## illustrated-first, procedural-fallback figure) centered horizontally
## with its feet exactly on the ground line.
func _blend_portrait(image: Image, appearance: Dictionary) -> void:
	var portrait := _character_sprite.generate_hero_portrait_image(appearance)
	var portrait_size := Vector2i(portrait.get_width(), portrait.get_height())
	var at := Vector2i(
		(CANVAS_SIZE.x - portrait_size.x) / 2, _ground_y() - portrait_size.y
	)
	image.blend_rect(portrait, Rect2i(Vector2i.ZERO, portrait_size), at)
