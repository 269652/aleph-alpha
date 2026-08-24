extends RefCounted

## Deterministic pixel-art for a settlement's shared landmarks (see
## SettlementGenerator's well/stall/gate) and per-occupation workspot props
## (see VillageRenderer, NpcPlanner.FakeNpcPlanner._WORK_LOCATION_BY_
## OCCUPATION) -- previously these were invisible positions NPCs walked to,
## which read as villagers milling around empty grass. A stone well with
## posts and a pitched cap, a market stall with a striped awning over a
## counter, a wooden gate arch, a farmer's tilled field, a blacksmith's
## forge, a fisher's dock, and an herbalist's garden. Same PixelPalette
## outline/shading house style as every other generator; deterministic, no
## RandomNumberGenerator.

const PixelPalette = preload("res://src/rendering/pixel_palette.gd")

const LANDMARK_IDS: Array[String] = ["well", "stall", "gate", "field", "forge", "dock", "garden"]

const SIZES := {
	"well": Vector2i(40, 44),
	"stall": Vector2i(52, 44),
	"gate": Vector2i(48, 52),
	"field": Vector2i(48, 40),
	"forge": Vector2i(44, 44),
	"dock": Vector2i(48, 48),
	"garden": Vector2i(44, 36),
}

const STONE_COLOR := Color(0.58, 0.58, 0.62)
const WATER_COLOR := Color(0.10, 0.28, 0.5)
const WOOD_COLOR := Color(0.48, 0.34, 0.18)
const AWNING_A := Color(0.78, 0.24, 0.2)
const AWNING_B := Color(0.9, 0.86, 0.78)
const COUNTER_COLOR := Color(0.6, 0.44, 0.24)
const SOIL_COLOR := Color(0.32, 0.22, 0.13)
const CROP_COLOR := Color(0.42, 0.68, 0.18)
const EMBER_COLOR := Color(0.95, 0.42, 0.08)
const HERB_COLOR := Color(0.55, 0.32, 0.62)

var _palette := PixelPalette.new()


func generate_texture(landmark_id: String) -> ImageTexture:
	return ImageTexture.create_from_image(generate_image(landmark_id))


## Renders one landmark. Unknown ids fall back to the well (fail-safe
## default, matching this codebase's `.get(x, default)` convention).
func generate_image(landmark_id: String) -> Image:
	match landmark_id:
		"stall":
			return _stall_image()
		"gate":
			return _gate_image()
		"field":
			return _field_image()
		"forge":
			return _forge_image()
		"dock":
			return _dock_image()
		"garden":
			return _garden_image()
		_:
			return _well_image()


## A stone ring around dark water, two posts carrying a small pitched cap.
func _well_image() -> Image:
	var size: Vector2i = SIZES["well"]
	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	var center := Vector2(size.x / 2.0, size.y * 0.68)

	# Cap: a small triangle up top between the posts.
	for y in range(1, 6):
		var half := (y - 1) * 1.6 + 1.0
		for x in size.x:
			if absf(x + 0.5 - size.x / 2.0) <= half:
				image.set_pixel(x, y, _palette.shade(WOOD_COLOR))
	# Posts either side, cap down to the ring.
	for y in range(5, int(center.y)):
		for x in [3, 4, size.x - 5, size.x - 4]:
			image.set_pixel(x, y, WOOD_COLOR)
	# Stone ring with a water core.
	for y in size.y:
		for x in size.x:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(center)
			if d <= 3.5:
				image.set_pixel(x, y, WATER_COLOR)
			elif d <= 6.5:
				image.set_pixel(x, y, STONE_COLOR if (x + y) % 3 != 0 else _palette.shade(STONE_COLOR))
	_outline_against_transparent(image, size)
	return image


## A striped awning over corner posts and a goods counter.
func _stall_image() -> Image:
	var size: Vector2i = SIZES["stall"]
	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)

	# Awning: alternating vertical stripes, slightly overhanging the posts.
	for y in range(1, 7):
		for x in range(1, size.x - 1):
			image.set_pixel(x, y, AWNING_A if (x / 3) % 2 == 0 else AWNING_B)
	# Corner posts.
	for y in range(7, size.y - 1):
		for x in [2, 3, size.x - 4, size.x - 3]:
			image.set_pixel(x, y, WOOD_COLOR)
	# Counter across the lower half.
	var counter_top := int(size.y * 0.62)
	for y in range(counter_top, size.y - 1):
		for x in range(2, size.x - 2):
			image.set_pixel(x, y, COUNTER_COLOR if y > counter_top else _palette.highlight(COUNTER_COLOR))
	_outline_against_transparent(image, size)
	return image


## Two heavy posts under a crossbeam -- the village entrance.
func _gate_image() -> Image:
	var size: Vector2i = SIZES["gate"]
	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)

	# Crossbeam.
	for y in range(2, 6):
		for x in range(1, size.x - 1):
			image.set_pixel(x, y, _palette.shade(WOOD_COLOR) if y == 5 else WOOD_COLOR)
	# Posts, full height.
	for y in range(2, size.y - 1):
		for x in [1, 2, 3, size.x - 4, size.x - 3, size.x - 2]:
			image.set_pixel(x, y, WOOD_COLOR if x % 2 == 1 else _palette.shade(WOOD_COLOR))
	_outline_against_transparent(image, size)
	return image


## Tilled soil in horizontal furrow bands (alternating shade, so it reads as
## worked ground rather than a flat dirt rectangle), with a crop sprout atop
## every other band's crest -- a farmer's own plot.
func _field_image() -> Image:
	var size: Vector2i = SIZES["field"]
	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	var margin := 2
	for y in range(margin, size.y - margin):
		var band := (y - margin) / 4
		var soil := _palette.shade(SOIL_COLOR) if band % 2 == 0 else SOIL_COLOR
		for x in range(margin, size.x - margin):
			image.set_pixel(x, y, soil)
	var band_count := (size.y - margin * 2) / 4
	for band in range(0, band_count, 2):
		var crest_y := margin + band * 4 + 1
		if crest_y < margin or crest_y >= size.y - margin:
			continue
		for x in range(margin + 3, size.x - margin, 7):
			image.set_pixel(x, crest_y, CROP_COLOR)
			if crest_y - 1 >= margin:
				image.set_pixel(x, crest_y - 1, _palette.highlight(CROP_COLOR))
	_outline_against_transparent(image, size)
	return image


## A squat stone furnace block with a dark mouth full of glowing embers.
func _forge_image() -> Image:
	var size: Vector2i = SIZES["forge"]
	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	var body_top := int(size.y * 0.35)
	for y in range(body_top, size.y - 1):
		for x in range(2, size.x - 2):
			image.set_pixel(x, y, STONE_COLOR if (x + y) % 4 != 0 else _palette.shade(STONE_COLOR))
	var mouth_left := size.x / 2 - 6
	var mouth_right := size.x / 2 + 6
	var mouth_top := body_top + 4
	var mouth_bottom := size.y - 6
	for y in range(mouth_top, mouth_bottom):
		for x in range(mouth_left, mouth_right):
			image.set_pixel(x, y, EMBER_COLOR if (x + y) % 3 == 0 else _palette.shade(EMBER_COLOR))
	_outline_against_transparent(image, size)
	return image


## Wooden planking running from land out over open water.
func _dock_image() -> Image:
	var size: Vector2i = SIZES["dock"]
	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	var water_top := size.y / 2
	for y in range(water_top, size.y):
		for x in size.x:
			image.set_pixel(x, y, WATER_COLOR if (x + y) % 5 != 0 else _palette.highlight(WATER_COLOR))
	for x in range(4, size.x - 4):
		var plank := (x / 6) % 2 == 0
		for y in range(4, water_top + 12):
			image.set_pixel(x, y, WOOD_COLOR if plank else _palette.shade(WOOD_COLOR))
	_outline_against_transparent(image, size)
	return image


## Tilled soil with herb tufts scattered in a grid (not furrow rows -- a
## garden bed reads differently from a farmer's field) in HERB_COLOR, its
## own distinct purple-green, not the field's plain crop green.
func _garden_image() -> Image:
	var size: Vector2i = SIZES["garden"]
	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	var margin := 2
	for y in range(margin, size.y - margin):
		for x in range(margin, size.x - margin):
			image.set_pixel(x, y, SOIL_COLOR)
	for gy in range(margin + 2, size.y - margin, 6):
		for gx in range(margin + 2, size.x - margin, 6):
			image.set_pixel(gx, gy, HERB_COLOR)
			if gx + 1 < size.x - margin:
				image.set_pixel(gx + 1, gy, _palette.highlight(HERB_COLOR))
			if gy - 1 >= margin:
				image.set_pixel(gx, gy - 1, _palette.shade(HERB_COLOR))
	_outline_against_transparent(image, size)
	return image


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
