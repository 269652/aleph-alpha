extends RefCounted

## Deterministic offline pixel art for a real aquatic invertebrate patch (see
## docs/concept/aquatic_foraging.md's "Revised (2026-09-07)") -- what the
## player sees clustered in a river or lake, and what a foraging fish
## arrives at and grazes.
##
## A small cluster of curved, comma-shaped larvae/nymphs, deliberately NOT
## ProceduralAquaticVegetationSprite's own tall tapered blades -- real
## aquatic insect larvae (mayfly/caddisfly/midge nymphs) read as short,
## curled, tan/brown grubs low in the water, nothing like a rooted plant's
## own upright silhouette. Same "hand-drawn procedural style, real
## illustrated art later" convention every other patch sim in this project
## follows. `seed_value` (hashed from the patch's own cell) varies grub
## count, size, and curl, so a cluster isn't a row of identical commas.
##
## Pure logic, no RandomNumberGenerator, and no Godot string hash either --
## all variation comes from PixelNoise, the same decorrelation
## ProceduralAquaticVegetationSprite already relies on.

const PixelNoise = preload("res://src/rendering/pixel_noise.gd")
const PixelPalette = preload("res://src/rendering/pixel_palette.gd")

## Same art-canvas-independent-of-world-size caution
## ProceduralAquaticVegetationSprite's own doc comment already names.
const SIZE := Vector2i(16, 20)

## Slightly smaller than vegetation's own WORLD_WIDTH (4.0) -- a cluster of
## small grubs is a genuinely smaller thing on the ground than a clump of
## rising blades.
const WORLD_WIDTH := 3.0
const TILE_SIZE := 16.0

## Real aquatic-insect-larva colouring: a muted tan/olive-brown, nothing
## like vegetation's own cool green (BLADE_COLOR) -- the direct visual
## differentiator between the two food layers (see this file's own class
## doc comment).
const GRUB_COLOR := Color(0.52, 0.40, 0.24)
const HIGHLIGHT_COLOR := Color(0.68, 0.54, 0.34)

## How many grubs a patch has, and how long each one is, in art pixels.
const _MIN_GRUBS := 3
const _MAX_GRUBS := 6
const _MIN_LENGTH := 4.0
const _MAX_LENGTH := 7.0

## How far a grub curls from a straight line, in art pixels of perpendicular
## drift at its own midpoint -- a real larva's own segmented, curled-up
## resting posture, not a straight blade.
const _MAX_CURL := 2.0

const _GRUB_HALF_WIDTH := 0.9

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
	# x = grub index, y = attribute channel below -- decorrelates every
	# grub from its siblings AND every attribute of one grub from its own
	# others, the same two-channel spread PixelNoise's own doc comment
	# describes.
	var grub_count := _MIN_GRUBS + PixelNoise.range_index(seed_value, 0, 0, _MAX_GRUBS - _MIN_GRUBS + 1)
	for i in grub_count:
		var center_x := PixelNoise.range_value(seed_value, i, 1, 2.0, float(SIZE.x) - 2.0)
		var center_y := PixelNoise.range_value(seed_value, i, 2, 3.0, float(SIZE.y) - 3.0)
		var length := PixelNoise.range_value(seed_value, i, 3, _MIN_LENGTH, _MAX_LENGTH)
		var curl := PixelNoise.range_value(seed_value, i, 4, -_MAX_CURL, _MAX_CURL)
		var angle := PixelNoise.range_value(seed_value, i, 5, 0.0, TAU)
		var lit := PixelNoise.unit(seed_value, i, 6) > 0.5
		_paint_grub(image, Vector2(center_x, center_y), length, curl, angle, lit)
	_outline_silhouette(image)
	return image


## One grub: a short, curled arc centred on `center`, `length` pixels long,
## drifted `curl` pixels perpendicular at its own midpoint (a real larva's
## curled-up resting posture), rotated by `angle` so the cluster doesn't
## all lie the same way.
func _paint_grub(image: Image, center: Vector2, length: float, curl: float, angle: float, lit: bool) -> void:
	var samples := int(length * 3.0)
	var color := HIGHLIGHT_COLOR if lit else GRUB_COLOR
	var direction := Vector2.RIGHT.rotated(angle)
	var perpendicular := direction.orthogonal()
	for i in samples:
		var t := float(i) / float(maxi(samples - 1, 1))
		var along := (t - 0.5) * length
		# A parabolic curl -- zero drift at both ends, maximum at the
		# midpoint, the same simple "start and end pinched, middle bowed"
		# shape a real curled-up grub's own body reads as.
		var bow := curl * (1.0 - pow(2.0 * t - 1.0, 2.0))
		var point := center + direction * along + perpendicular * bow
		# Tapered: fullest at the middle, pinched at both ends.
		var half_width := maxf(_GRUB_HALF_WIDTH * (1.0 - absf(2.0 * t - 1.0) * 0.6), 0.35)
		_paint_column(image, point.x, point.y, half_width, color)


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


## Rings the invertebrates so they separate from the water they live in --
## the identical technique ProceduralAquaticVegetationSprite already uses.
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
