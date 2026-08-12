extends RefCounted

## Deterministic pixel-art for a village house (see SettlementGenerator,
## VillageRenderer) -- a simple pitched-roof cottage: a triangular roof over
## a rectangular wall, a door, and a window whose position varies per seed so
## a village's houses don't all look identically placed. Single-sprite
## simplification (not a multi-tile footprint via BuildingBlueprint) -- see
## docs/progress.md's NPC section for the scope note. Same PixelPalette
## shading/outline house style as every other procedural generator here; no
## RandomNumberGenerator, hash-seeded only.

const PixelPalette = preload("res://src/rendering/pixel_palette.gd")

const SIZE := Vector2i(20, 20)

const WALL_COLOR := Color(0.78, 0.7, 0.56)
const ROOF_COLOR := Color(0.55, 0.24, 0.16)
const DOOR_COLOR := Color(0.32, 0.2, 0.11)
const WINDOW_COLOR := Color(0.55, 0.78, 0.85)

const _ROOF_TOP_ROW := 2
const _ROOF_BASE_ROW := 9  # exclusive -- walls start here
const _WALL_BOTTOM_ROW := 18  # exclusive -- ground below

const _DOOR_WIDTH := 3
const _DOOR_HEIGHT := 4
## Door x-offset choices from center, picked per seed.
const _DOOR_OFFSETS := [-2, 0, 2]

const _WINDOW_SIZE := 2
## Window x positions (left wall / right wall), picked per seed.
const _WINDOW_X_OPTIONS := [3, SIZE.x - 3 - _WINDOW_SIZE]
const _WINDOW_Y := 11

var _palette := PixelPalette.new()


func generate_texture(variant_seed: int) -> ImageTexture:
	return ImageTexture.create_from_image(generate_image(variant_seed))


func generate_image(variant_seed: int) -> Image:
	var image := Image.create(SIZE.x, SIZE.y, false, Image.FORMAT_RGBA8)
	_paint_roof(image)
	_paint_walls(image)
	_paint_door(image, variant_seed)
	_paint_window(image, variant_seed)
	_outline_against_transparent(image)
	return image


## A symmetric triangular roof, apex at _ROOF_TOP_ROW widening to the full
## wall width by _ROOF_BASE_ROW.
func _paint_roof(image: Image) -> void:
	var span := _ROOF_BASE_ROW - _ROOF_TOP_ROW
	for y in range(_ROOF_TOP_ROW, _ROOF_BASE_ROW):
		var t := float(y - _ROOF_TOP_ROW) / float(span)
		var half_width := t * (SIZE.x / 2.0)
		var center := SIZE.x / 2.0
		for x in SIZE.x:
			if absf(x + 0.5 - center) <= half_width:
				image.set_pixel(x, y, ROOF_COLOR)


func _paint_walls(image: Image) -> void:
	for y in range(_ROOF_BASE_ROW, _WALL_BOTTOM_ROW):
		for x in SIZE.x:
			image.set_pixel(x, y, WALL_COLOR)


func _paint_door(image: Image, variant_seed: int) -> void:
	var offset: int = _DOOR_OFFSETS[_index(variant_seed, "door_offset", _DOOR_OFFSETS.size())]
	var center_x := SIZE.x / 2 + offset
	var left := center_x - _DOOR_WIDTH / 2
	for y in range(_WALL_BOTTOM_ROW - _DOOR_HEIGHT, _WALL_BOTTOM_ROW):
		for x in range(left, left + _DOOR_WIDTH):
			if x >= 0 and x < SIZE.x:
				image.set_pixel(x, y, DOOR_COLOR)


func _paint_window(image: Image, variant_seed: int) -> void:
	var window_x: int = _WINDOW_X_OPTIONS[_index(variant_seed, "window_side", _WINDOW_X_OPTIONS.size())]
	for y in range(_WINDOW_Y, _WINDOW_Y + _WINDOW_SIZE):
		for x in range(window_x, window_x + _WINDOW_SIZE):
			image.set_pixel(x, y, WINDOW_COLOR)


## Same rim-outline technique as ProceduralStructureSprite, against a
## transparent background instead of a filled ground tile (a house sprite
## sits over whatever grass/dirt is beneath it, not a full opaque tile).
func _outline_against_transparent(image: Image) -> void:
	var outline := _palette.outline_color()
	var to_outline: Array[Vector2i] = []
	for y in SIZE.y:
		for x in SIZE.x:
			if image.get_pixel(x, y).a > 0.0:
				continue
			if _touches_opaque(image, x, y):
				to_outline.append(Vector2i(x, y))
	for cell in to_outline:
		image.set_pixel(cell.x, cell.y, outline)


const _NEIGHBOR_OFFSETS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]


func _touches_opaque(image: Image, x: int, y: int) -> bool:
	for offset in _NEIGHBOR_OFFSETS:
		var nx: int = x + offset.x
		var ny: int = y + offset.y
		if nx < 0 or nx >= SIZE.x or ny < 0 or ny >= SIZE.y:
			continue
		if image.get_pixel(nx, ny).a > 0.0:
			return true
	return false


func _index(seed_value: int, salt: String, count: int) -> int:
	return absi(hash("%d_%s" % [seed_value, salt])) % count
