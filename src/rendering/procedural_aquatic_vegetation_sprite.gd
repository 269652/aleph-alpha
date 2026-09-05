extends RefCounted

## Deterministic offline pixel art for a real aquatic vegetation patch (see
## docs/concept/aquatic_foraging.md) -- what the player sees growing in a
## river or lake, and what a foraging fish arrives at and grazes.
##
## A small cluster of tapered blades rising from one base point, the same
## "hand-drawn procedural style, real illustrated art later" convention
## ProceduralWormSprite/ProceduralAntMoundSprite already follow. `seed_value`
## (hashed from the patch's own cell) varies blade count, height, and lean,
## so a bed of weed isn't a row of identical clumps.
##
## Pure logic, no RandomNumberGenerator, and no Godot string hash either --
## all variation comes from PixelNoise, which decorrelates neighbouring
## cells (see its own doc comment).

const PixelNoise = preload("res://src/rendering/pixel_noise.gd")
const PixelPalette = preload("res://src/rendering/pixel_palette.gd")

## The ART canvas -- kept independent of the world size below, the same
## "a world scale derived from canvas dimensions has twice shipped a sprite
## that changed size on screen" caution ProceduralWormSprite's own doc
## comment already names.
const SIZE := Vector2i(16, 20)

## How wide a patch reads ON THE GROUND, in world pixels -- close to
## ProceduralWormSprite's own real "about ten centimetres" reference (a
## patch of pondweed is a similarly small, ground-level thing), a touch
## wider since a clump of several blades naturally spans more than one
## worm's own body width.
const WORLD_WIDTH := 4.0
const TILE_SIZE := 16.0

## Real aquatic-plant colouring: a cooler, more saturated green than land
## grass (see docs/concept/long_grass.md's own grass palette) -- submerged
## vegetation reads distinctly from the terrestrial grass at the shore it
## borders, the same "distinguishable from its neighbour" requirement
## ProceduralAntMoundSprite's own entrance-vs-body contrast already holds
## itself to.
const BLADE_COLOR := Color(0.18, 0.42, 0.30)
const HIGHLIGHT_COLOR := Color(0.28, 0.58, 0.40)

## How many blades a patch has, and how tall each one grows, in art pixels.
const _MIN_BLADES := 3
const _MAX_BLADES := 6
const _MIN_HEIGHT := 8.0
const _MAX_HEIGHT := 17.0

## How far a blade may lean from vertical, in art pixels of horizontal
## drift from base to tip.
const _MAX_LEAN := 3.5

const _BLADE_HALF_WIDTH := 0.8

var _palette := PixelPalette.new()


## The scale that renders a patch at its intended world width regardless of
## the art canvas's pixel resolution.
static func world_scale() -> float:
	return WORLD_WIDTH / float(SIZE.x)


static var _texture_cache := {}


func generate_texture(seed_value: int) -> ImageTexture:
	if _texture_cache.has(seed_value):
		return _texture_cache[seed_value]
	var texture := ImageTexture.create_from_image(generate_image(seed_value))
	_texture_cache[seed_value] = texture
	return texture


func generate_image(seed_value: int) -> Image:
	var image := Image.create(SIZE.x, SIZE.y, false, Image.FORMAT_RGBA8)
	# x = blade index, y = attribute channel below -- decorrelates every
	# blade from its siblings AND every attribute of one blade from its
	# own others, the same two-channel spread PixelNoise's own doc
	# comment describes.
	var blade_count := _MIN_BLADES + PixelNoise.range_index(seed_value, 0, 0, _MAX_BLADES - _MIN_BLADES + 1)
	var base_y := float(SIZE.y) - 1.0
	for i in blade_count:
		var base_x := PixelNoise.range_value(seed_value, i, 1, 1.5, float(SIZE.x) - 1.5)
		var height := PixelNoise.range_value(seed_value, i, 2, _MIN_HEIGHT, _MAX_HEIGHT)
		var lean := PixelNoise.range_value(seed_value, i, 3, -_MAX_LEAN, _MAX_LEAN)
		var lit := PixelNoise.unit(seed_value, i, 4) > 0.5
		_paint_blade(image, Vector2(base_x, base_y), height, lean, lit)
	_outline_silhouette(image)
	return image


## One blade: a straight taper from `base` up to a tip drifted `lean` art
## pixels sideways, `height` pixels tall.
func _paint_blade(image: Image, base: Vector2, height: float, lean: float, lit: bool) -> void:
	var samples := int(height * 3.0)
	var color := HIGHLIGHT_COLOR if lit else BLADE_COLOR
	for i in samples:
		var t := float(i) / float(maxi(samples - 1, 1))
		var x := base.x + lean * t
		var y := base.y - height * t
		# Tapered: full width at the base, a near-point at the tip.
		var half_width := maxf(_BLADE_HALF_WIDTH * (1.0 - t), 0.4)
		_paint_column(image, x, y, half_width, color)


func _paint_column(image: Image, x: float, y: float, half_width: float, color: Color) -> void:
	var left := int(floor(x - half_width))
	var right := int(ceil(x + half_width))
	var row := int(round(y))
	if row < 0 or row >= SIZE.y:
		return
	for col in range(left, right + 1):
		if col < 0 or col >= SIZE.x:
			continue
		if absf(float(col) + 0.5 - x) > half_width:
			continue
		image.set_pixel(col, row, color)


## Rings the vegetation so it separates from the water it grows in -- the
## identical technique ProceduralWormSprite/ProceduralAntMoundSprite
## already use.
func _outline_silhouette(image: Image) -> void:
	var outline := _palette.outline_color()
	var to_outline: Array[Vector2i] = []
	var offsets := [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]
	for y in SIZE.y:
		for x in SIZE.x:
			if image.get_pixel(x, y).a > 0.0:
				continue
			for offset in offsets:
				var nx: int = x + offset.x
				var ny: int = y + offset.y
				if nx < 0 or nx >= SIZE.x or ny < 0 or ny >= SIZE.y:
					continue
				if image.get_pixel(nx, ny).a > 0.0:
					to_outline.append(Vector2i(x, y))
					break
	for cell in to_outline:
		image.set_pixel(cell.x, cell.y, outline)
