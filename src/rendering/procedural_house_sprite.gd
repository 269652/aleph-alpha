extends RefCounted

## Deterministic pixel-art for a village house (see SettlementGenerator,
## VillageRenderer) -- a pitched-roof home in one of 3 real sizes (every one
## clearly bigger than a villager, see test_every_house_size_is_clearly_
## bigger_than_a_villager), with a seeded wall palette (plaster/timber/stone/
## clay), roof palette (fired tile/thatch/slate), scaled door, 1-2 windows,
## faint plank/masonry coursing, and a chimney on about half of them -- so a
## village reads as a settlement of individual homes, not a ring of
## identical toy huts (the original was one 20x20 cottage, smaller than the
## villager standing beside it).
##
## Single-sprite simplification (not a multi-tile BuildingBlueprint
## footprint) -- see docs/progress.md's NPC section for the scope note. Same
## PixelPalette shading/outline house style as every other generator; no
## RandomNumberGenerator, hash-seeded only.

const PixelPalette = preload("res://src/rendering/pixel_palette.gd")

## The 3 house sizes a seed can roll -- cottage, house, homestead. All wider
## and taller than a full villager sprite (body + head).
## DETAIL_MULTIPLIER times the world footprint (see
## docs/concept/art_resolution.md) -- drawn at ArtResolution.SPRITE_SCALE
## so it gains pixel detail without growing in the world.
const SIZES: Array[Vector2i] = [Vector2i(72, 64), Vector2i(92, 80), Vector2i(112, 92)]

## Seeded wall palettes: cream plaster, timber brown, field-stone grey,
## warm clay.
const WALL_PALETTES: Array[Color] = [
	Color(0.82, 0.76, 0.62),
	Color(0.62, 0.45, 0.28),
	Color(0.63, 0.63, 0.66),
	Color(0.75, 0.62, 0.45),
]

## Seeded roof palettes: fired-clay red, thatch gold, slate blue-grey.
const ROOF_PALETTES: Array[Color] = [
	Color(0.55, 0.24, 0.16),
	Color(0.78, 0.62, 0.28),
	Color(0.36, 0.42, 0.52),
]

const DOOR_COLOR := Color(0.30, 0.19, 0.10)
const WINDOW_FRAME_COLOR := Color(0.32, 0.22, 0.12)
const WINDOW_GLASS_COLOR := Color(0.55, 0.78, 0.85)
const CHIMNEY_COLOR := Color(0.46, 0.45, 0.47)

## Fraction of the sprite's height the roof occupies before walls begin.
const _ROOF_FRACTION := 0.42
## Faint horizontal coursing every this many wall rows (planks/masonry), so
## big walls don't read as one flat fill.
const _COURSE_SPACING := 4
const _COURSE_DARKEN := 0.12
## Small per-house lighten/darken so two same-palette houses still differ.
const _WALL_JITTER_RANGE := 0.12

## Windows are a 4x4 frame with a 2x2 glass core; houses at least this wide
## get a second window.
const _WINDOW_SIZE := 4
const _TWO_WINDOW_MIN_WIDTH := 46

var _palette := PixelPalette.new()


func generate_texture(variant_seed: int) -> ImageTexture:
	return ImageTexture.create_from_image(generate_image(variant_seed))


## The size this seed's house rolls -- exposed (and test-pinned) so callers
## like VillageRenderer can size shadows/spacing from it without rendering.
func size_for(variant_seed: int) -> Vector2i:
	return SIZES[_index(variant_seed, "size", SIZES.size())]


func wall_color_for(variant_seed: int) -> Color:
	return WALL_PALETTES[_index(variant_seed, "wall", WALL_PALETTES.size())]


func roof_color_for(variant_seed: int) -> Color:
	return ROOF_PALETTES[_index(variant_seed, "roof", ROOF_PALETTES.size())]


## About half of all houses get a chimney.
func has_chimney(variant_seed: int) -> bool:
	return _index(variant_seed, "chimney", 2) == 0


func generate_image(variant_seed: int) -> Image:
	var size := size_for(variant_seed)
	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	var roof_base := int(size.y * _ROOF_FRACTION)

	_paint_roof(image, size, roof_base, roof_color_for(variant_seed))
	if has_chimney(variant_seed):
		_paint_chimney(image, size, roof_base)
	_paint_walls(image, size, roof_base, variant_seed)
	_paint_door(image, size, variant_seed)
	_paint_windows(image, size, roof_base)
	_outline_against_transparent(image, size)
	return image


## A symmetric triangular roof from an apex row down to the full wall width,
## with the lower rows shaded slightly for depth.
func _paint_roof(image: Image, size: Vector2i, roof_base: int, roof_color: Color) -> void:
	var span := roof_base - 1
	for y in range(1, roof_base):
		var t := float(y - 1) / float(span)
		var half_width := t * (size.x / 2.0)
		var color := roof_color if t < 0.7 else _palette.shade(roof_color)
		for x in size.x:
			if absf(x + 0.5 - size.x / 2.0) <= half_width:
				image.set_pixel(x, y, color)


## A short stone stack poking through the upper roof slope, right of center.
func _paint_chimney(image: Image, size: Vector2i, roof_base: int) -> void:
	var chimney_x := int(size.x * 0.66)
	var chimney_top := 1
	var chimney_bottom := 1 + int((roof_base - 1) * 0.55)
	for y in range(chimney_top, chimney_bottom):
		for x in range(chimney_x, mini(chimney_x + 3, size.x)):
			image.set_pixel(x, y, CHIMNEY_COLOR)


func _paint_walls(image: Image, size: Vector2i, roof_base: int, variant_seed: int) -> void:
	var jitter := _seeded_unit_float(variant_seed, "wall_shade") - 0.5
	var wall := wall_color_for(variant_seed).lightened(maxf(jitter * _WALL_JITTER_RANGE, 0.0)).darkened(
		maxf(-jitter * _WALL_JITTER_RANGE, 0.0)
	)
	var course := wall.darkened(_COURSE_DARKEN)
	for y in range(roof_base, size.y - 1):
		var is_course := (y - roof_base) % _COURSE_SPACING == _COURSE_SPACING - 1
		for x in size.x:
			image.set_pixel(x, y, course if is_course else wall)


func _paint_door(image: Image, size: Vector2i, variant_seed: int) -> void:
	var offsets := [-size.x / 6, 0, size.x / 6]
	var offset: int = offsets[_index(variant_seed, "door_offset", offsets.size())]
	var door_width := maxi(4, size.x / 9)
	var door_height := int(size.y * 0.26)
	var left := size.x / 2 + offset - door_width / 2
	for y in range(size.y - 1 - door_height, size.y - 1):
		for x in range(left, left + door_width):
			if x >= 0 and x < size.x:
				image.set_pixel(x, y, DOOR_COLOR)


## 1 window on the small cottage, 2 on wider houses -- framed, with a glass
## core, sitting just below the roofline.
func _paint_windows(image: Image, size: Vector2i, roof_base: int) -> void:
	var window_y := roof_base + 3
	var positions: Array[int] = [int(size.x * 0.18)]
	if size.x >= _TWO_WINDOW_MIN_WIDTH:
		positions.append(int(size.x * 0.82) - _WINDOW_SIZE)
	for window_x in positions:
		for y in range(window_y, window_y + _WINDOW_SIZE):
			for x in range(window_x, window_x + _WINDOW_SIZE):
				var edge := (
					y == window_y or y == window_y + _WINDOW_SIZE - 1
					or x == window_x or x == window_x + _WINDOW_SIZE - 1
				)
				image.set_pixel(x, y, WINDOW_FRAME_COLOR if edge else WINDOW_GLASS_COLOR)


## Same rim-outline technique as ProceduralStructureSprite, against a
## transparent background (a house sprite sits over whatever ground is
## beneath it, not a full opaque tile).
func _outline_against_transparent(image: Image, size: Vector2i) -> void:
	var outline := _palette.outline_color()
	var to_outline: Array[Vector2i] = []
	for y in size.y:
		for x in size.x:
			if image.get_pixel(x, y).a > 0.0:
				continue
			if _touches_opaque(image, size, x, y):
				to_outline.append(Vector2i(x, y))
	for cell in to_outline:
		image.set_pixel(cell.x, cell.y, outline)


const _NEIGHBOR_OFFSETS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]


func _touches_opaque(image: Image, size: Vector2i, x: int, y: int) -> bool:
	for offset in _NEIGHBOR_OFFSETS:
		var nx: int = x + offset.x
		var ny: int = y + offset.y
		if nx < 0 or nx >= size.x or ny < 0 or ny >= size.y:
			continue
		if image.get_pixel(nx, ny).a > 0.0:
			return true
	return false


## Seeded pick, routed through a % 10000 reduction FIRST: Godot's String
## hash is djb2-style (multiplier 33, divisible by 3), so a raw
## `hash("<seed>_<salt>") % count` freezes to ONE bucket for counts
## divisible by 3 when every salted string shares the same short suffix --
## every seed rolled the identical size and roof before this (verified
## empirically; % 4 picks like the wall palette were unaffected). The
## % 10000 reduction re-mixes the higher characters (10000 is coprime to 3),
## matching the roll convention the rest of the codebase already uses.
func _index(seed_value: int, salt: String, count: int) -> int:
	return (absi(hash("%d_%s" % [seed_value, salt])) % 10000) % count


func _seeded_unit_float(seed_value: int, salt: String) -> float:
	return float(absi(hash("%d_%s" % [seed_value, salt])) % 10000) / 10000.0
