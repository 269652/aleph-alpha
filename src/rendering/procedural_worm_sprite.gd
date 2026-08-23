extends RefCounted

## Deterministic offline pixel art for a surfaced earthworm (see
## docs/concept/soil_fauna.md) -- what the player sees lying on wet ground,
## and what a robin lands on and takes.
##
## A tapered, segmented body lying in a shallow curve. `seed_value` (hashed
## from the worm's cell) varies how much it curls, how tightly, and which way,
## so a lawn after rain isn't a row of identical squiggles.
##
## Pure logic, no RandomNumberGenerator, and no Godot string hash either: all
## variation comes from PixelNoise, which decorrelates neighbouring cells (see
## its doc comment).

const PixelNoise = preload("res://src/rendering/pixel_noise.gd")
const PixelPalette = preload("res://src/rendering/pixel_palette.gd")

## The ART canvas. Kept independent of the world size below on purpose: this
## project has twice shipped sprites that changed size on screen because a
## world scale was derived from canvas dimensions (see
## ProceduralFlowerSprite), so raising this for more detail must never change
## how big a worm looks.
const SIZE := Vector2i(20, 10)

## How long a worm lies in the WORLD, in tiles. Comfortably under one tile --
## a worm lies within its own square of ground -- and well under a flower's
## height (see ProceduralFlowerSprite.WORLD_HEIGHT_TILES), because it is a
## small thing on the floor of the meadow rather than part of its canopy.
## An earthworm is about ten centimetres, the same as a crocus is tall, and
## is drawn at the size that makes true (see ProceduralFlowerSprite, where
## every plant is pinned to the player's own height).
##
## It was 0.55 tiles, set by eye back when every flower shared one invented
## height. Once flowers were pinned to real scale the worm was suddenly longer
## than several of them and read as a snake lying in the grass.
const WORLD_LENGTH_TILES := 0.32
const TILE_SIZE := 16.0

## Live earthworm colouring: a desaturated pink-brown, with a darker band
## colour for the segment rings and a paler underside so the body reads as
## round rather than as a flat stroke.
const BODY_COLOR := Color(0.72, 0.46, 0.45)
const SEGMENT_COLOR := Color(0.58, 0.34, 0.35)
const UNDERSIDE_COLOR := Color(0.82, 0.58, 0.56)

## Body thickness at the worm's thickest point, in art pixels. Tapers toward
## both ends (a real earthworm is pointed at the head and tail).
const THICKNESS := 3.0

## How many visible segment rings run down the body.
const SEGMENTS := 7

## How far the body may wander from the canvas centre line, as a fraction of
## the canvas half-height. Bounded so the taper and the outline both stay on
## the canvas.
const _MAX_CURL := 0.55

## Samples taken along the body when painting. Several per pixel of length, so
## a steeply-curving stretch can't leave a gap between columns (pinned by
## test_the_body_is_continuous_along_its_length).
const _SAMPLES_PER_PIXEL := 6

## Blank border kept clear at each end, so the outline pass has somewhere to
## draw and the worm doesn't butt against the canvas edge.
const _END_MARGIN := 1.0

var _palette := PixelPalette.new()


## The scale that renders a worm at its intended world length regardless of
## the art canvas's pixel resolution. Callers scale by this rather than
## re-deriving a factor from SIZE themselves.
static func world_scale() -> float:
	return (WORLD_LENGTH_TILES * TILE_SIZE) / float(SIZE.x)


func generate_texture(seed_value: int) -> ImageTexture:
	return ImageTexture.create_from_image(generate_image(seed_value))


func generate_image(seed_value: int) -> Image:
	var image := Image.create(SIZE.x, SIZE.y, false, Image.FORMAT_RGBA8)
	_paint_worm(image, seed_value)
	_outline_silhouette(image)
	return image


func _paint_worm(image: Image, seed_value: int) -> void:
	var half_height := float(SIZE.y) * 0.5
	# How far it curls, how many bends fit along the body, and where in the
	# wave it starts -- three independently salted samples, so a worm that
	# curls a lot isn't also always bent the same way.
	var curl := PixelNoise.range_value(seed_value, 0, 0, 0.25, 1.0) * _MAX_CURL * half_height
	var bends := PixelNoise.range_value(seed_value + 4703, 1, 0, 0.6, 1.4)
	var phase := PixelNoise.unit(seed_value + 9161, 2, 0) * TAU

	var length := float(SIZE.x) - _END_MARGIN * 2.0
	var samples := int(length * float(_SAMPLES_PER_PIXEL))
	for i in samples:
		var t := float(i) / float(samples - 1)
		var x := _END_MARGIN + t * length
		var y := half_height + sin(phase + t * TAU * bends) * curl
		# Tapered at both ends: a sine over the body's length is 0 at the head
		# and tail and full in the middle.
		var thickness := THICKNESS * (0.3 + 0.7 * sin(t * PI))
		var band := int(t * float(SEGMENTS)) % 2 == 1
		_paint_column(image, x, y, thickness, band)


## One vertical slice of the body at `x`, centred on `y`.
func _paint_column(image: Image, x: float, y: float, thickness: float, band: bool) -> void:
	var column := int(x)
	if column < 0 or column >= SIZE.x:
		return
	var half := maxf(thickness * 0.5, 0.5)
	var top := int(floor(y - half))
	var bottom := int(ceil(y + half))
	for row in range(top, bottom + 1):
		if row < 0 or row >= SIZE.y:
			continue
		if absf(float(row) + 0.5 - y) > half:
			continue
		# Lowest row of the slice catches the light from below -- the standard
		# one-shade-side convention this project's other sprites use.
		var color := UNDERSIDE_COLOR if float(row) + 0.5 > y + half * 0.35 else (
			SEGMENT_COLOR if band else BODY_COLOR
		)
		image.set_pixel(column, row, color)


## Rings the body so a worm separates from the grass it is lying on -- at this
## size the silhouette is most of what the player actually reads.
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
