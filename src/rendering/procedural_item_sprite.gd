extends RefCounted

## Deterministic in-engine pixel-art for items, matching the creature
## generator's offline/zero-dependency approach. Each known item id maps to a
## base color and a silhouette shape (round fruit/meat, oval nut/hide, pointed
## fang, sword blade+hilt); unknown ids fall back to a generic pebble so new
## items always render something valid rather than crashing.

const PixelPalette = preload("res://src/rendering/pixel_palette.gd")

const SIZE := 16
const OUTLINE_DARKEN := 0.55
const SHADE_DARKEN := 0.25
const HIGHLIGHT_LIGHTEN := 0.25

## Push base item colors toward a brighter, more saturated look before shading.
const BASE_SATURATE := 0.16

var _palette := PixelPalette.new()

## id -> {color, shape}. shape is one of: round, oval, fang, sword, axe.
const _ITEM_LOOKS := {
	"hide": {"color": Color(0.55, 0.4, 0.25), "shape": "oval"},
	"meat": {"color": Color(0.72, 0.28, 0.3), "shape": "round"},
	"fang": {"color": Color(0.9, 0.9, 0.85), "shape": "fang"},
	"fruit": {"color": Color(0.85, 0.2, 0.2), "shape": "round"},
	"nut": {"color": Color(0.5, 0.35, 0.18), "shape": "oval"},
	"wooden_club": {"color": Color(0.5, 0.35, 0.2), "shape": "sword"},
	"iron_sword": {"color": Color(0.75, 0.78, 0.82), "shape": "sword"},
	"iron_axe": {"color": Color(0.7, 0.73, 0.78), "shape": "axe"},
	"torch": {"color": Color(0.65, 0.4, 0.15), "shape": "sword"},
	"campfire": {"color": Color(0.85, 0.45, 0.1), "shape": "campfire"},
	"cooked_meat": {"color": Color(0.45, 0.22, 0.12), "shape": "round"},
	"rock": {"color": Color(0.55, 0.55, 0.58), "shape": "round"},
	"stick": {"color": Color(0.45, 0.32, 0.18), "shape": "sword"},
	"sharp_shard": {"color": Color(0.7, 0.7, 0.74), "shape": "fang"},
	"plant_fibre": {"color": Color(0.55, 0.7, 0.3), "shape": "oval"},
	"crude_blade": {"color": Color(0.6, 0.55, 0.5), "shape": "sword"},
	"stone": {"color": Color(0.5, 0.5, 0.53), "shape": "round"},
	"stone_pickaxe": {"color": Color(0.55, 0.5, 0.45), "shape": "axe"},
	"iron_ore": {"color": Color(0.72, 0.5, 0.32), "shape": "round"},
	"copper_ore": {"color": Color(0.3, 0.68, 0.6), "shape": "round"},
	"coal": {"color": Color(0.18, 0.17, 0.2), "shape": "round"},
	"fish": {"color": Color(0.5, 0.65, 0.8), "shape": "oval"},
	"cooked_fish": {"color": Color(0.72, 0.55, 0.35), "shape": "oval"},
	# Rare/legendary catches (see FishingMinigame.fish_rarity) get a
	# visibly special color -- a cool blue-violet vs. a vivid gold -- so
	# they read as valuable at a glance in the inventory grid, distinct
	# from the plain blue-gray common "fish".
	"rare_fish": {"color": Color(0.55, 0.4, 0.85), "shape": "oval"},
	"legendary_fish": {"color": Color(0.95, 0.72, 0.15), "shape": "oval"},
	"leather_helm": {"color": Color(0.55, 0.38, 0.22), "shape": "helm"},
	"leather_chest": {"color": Color(0.5, 0.34, 0.2), "shape": "armor"},
	"leather_legs": {"color": Color(0.46, 0.31, 0.18), "shape": "legs"},
	"leather_boots": {"color": Color(0.4, 0.27, 0.16), "shape": "boots"},
	"iron_ingot": {"color": Color(0.72, 0.74, 0.8), "shape": "oval"},
	"copper_ingot": {"color": Color(0.8, 0.5, 0.32), "shape": "oval"},
	"furnace": {"color": Color(0.42, 0.4, 0.42), "shape": "furnace"},
	"iron_helm": {"color": Color(0.72, 0.74, 0.8), "shape": "helm"},
	"iron_chest": {"color": Color(0.68, 0.7, 0.77), "shape": "armor"},
	"iron_legs": {"color": Color(0.64, 0.66, 0.73), "shape": "legs"},
	"iron_boots": {"color": Color(0.6, 0.62, 0.69), "shape": "boots"},
	"fishing_rod": {"color": Color(0.5, 0.36, 0.2), "shape": "sword"},
}
const _FALLBACK := {"color": Color(0.6, 0.6, 0.6), "shape": "round"}


func generate_texture(item_id: String) -> ImageTexture:
	return ImageTexture.create_from_image(generate_image(item_id))


func generate_image(item_id: String) -> Image:
	var look: Dictionary = _ITEM_LOOKS.get(item_id, _FALLBACK)
	var base: Color = _palette.saturate(look["color"], BASE_SATURATE)
	var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)

	match look["shape"]:
		"sword":
			_draw_sword(image, base)
		"axe":
			_draw_axe(image, base)
		"fang":
			_draw_fang(image, base)
		"oval":
			_draw_blob(image, base, 0.42, 0.30)
		"helm":
			_draw_plate(image, base, 3, 4, SIZE - 3, 10)  # a dome sitting up top
		"armor":
			_draw_plate(image, base, 3, 2, SIZE - 3, SIZE - 3)  # a broad chestplate
		"legs":
			_draw_plate(image, base, 4, 2, SIZE - 4, SIZE - 2)  # narrower greaves
		"boots":
			_draw_plate(image, base, 3, 8, SIZE - 3, SIZE - 2)  # short, low boots
		"campfire":
			_draw_campfire(image)
		"furnace":
			_draw_furnace(image, base)
		_:
			_draw_blob(image, base, 0.36, 0.36)

	return image


## A filled, outlined rectangular plate (armor pieces) spanning [x0,x1)x[y0,y1),
## with a dark outline ring and a top-left highlight so it reads as a metal/
## leather panel rather than a flat block.
func _draw_plate(image: Image, base: Color, x0: int, y0: int, x1: int, y1: int) -> void:
	var outline := base.darkened(OUTLINE_DARKEN)
	var highlight := _palette.highlight(base)
	var shade := base.darkened(SHADE_DARKEN)
	for y in range(y0, y1):
		for x in range(x0, x1):
			var edge := x == x0 or x == x1 - 1 or y == y0 or y == y1 - 1
			var color := base
			if edge:
				color = outline
			elif x <= x0 + 1 or y <= y0 + 1:
				color = highlight
			elif y >= y1 - 2:
				color = shade
			image.set_pixel(x, y, color)


const LOG_COLOR := Color(0.4, 0.26, 0.14)
const LOG_HIGHLIGHT := Color(0.52, 0.35, 0.2)
const EMBER_COLOR := Color(0.25, 0.12, 0.08)
const FLAME_BASE := Color(0.85, 0.15, 0.08)
const FLAME_TIP := Color(0.98, 0.78, 0.18)
const FURNACE_GLOW := Color(0.9, 0.35, 0.1)
const FURNACE_OPENING := Color(0.15, 0.08, 0.05)


## Two crossed logs on dark embers, with a tapering flame (color-graded red
## at its base to yellow at its tip -- a real gradient, not one shaded hue
## like the generic blob shapes) rising above them. The one item silhouette
## that needs to read as "fire" at a glance, not just "some orange thing".
func _draw_campfire(image: Image) -> void:
	var log_row_start := int(SIZE * 0.65)
	for y in range(log_row_start, SIZE - 1):
		var t := float(y - log_row_start) / maxf(float(SIZE - 1 - log_row_start), 1.0)
		var diag1_x := 2 + int(t * (SIZE - 5))
		var diag2_x := SIZE - 3 - int(t * (SIZE - 5))
		for x in SIZE:
			var on_diag1 := absi(x - diag1_x) <= 1
			var on_diag2 := absi(x - diag2_x) <= 1
			if on_diag1 or on_diag2:
				image.set_pixel(x, y, LOG_HIGHLIGHT if x <= diag1_x else LOG_COLOR)
	for x in range(3, SIZE - 3):
		image.set_pixel(x, SIZE - 1, EMBER_COLOR)

	var flame_top := 1
	var cx := SIZE / 2.0
	for y in range(flame_top, log_row_start):
		var t := float(y - flame_top) / maxf(float(log_row_start - flame_top), 1.0)  # 0 at tip, 1 at base
		var half_width := lerpf(0.5, SIZE * 0.22, t)
		var color := FLAME_TIP.lerp(FLAME_BASE, t)
		for x in SIZE:
			if absf(x + 0.5 - (cx + sin(t * PI) * 0.6)) <= half_width:
				image.set_pixel(x, y, color)


## A grey stone block (reusing the shaded-plate technique) with a dark
## firebox opening glowing warm orange from within -- distinct in both
## silhouette and color from the flat single-hue armor-plate shape it used to
## share with leather/iron chest pieces.
func _draw_furnace(image: Image, base: Color) -> void:
	_draw_plate(image, base, 2, 3, SIZE - 2, SIZE - 1)
	var opening_x0 := SIZE / 2 - 3
	var opening_x1 := SIZE / 2 + 3
	var opening_y0 := SIZE - 7
	var opening_y1 := SIZE - 2
	for y in range(opening_y0, opening_y1):
		for x in range(opening_x0, opening_x1):
			image.set_pixel(x, y, FURNACE_OPENING)
	for y in range(opening_y0 + 1, opening_y1 - 1):
		for x in range(opening_x0 + 1, opening_x1 - 1):
			image.set_pixel(x, y, FURNACE_GLOW)


## A shaded, outlined ellipse centered in the sprite (round or oval).
func _draw_blob(image: Image, base: Color, radius_x_frac: float, radius_y_frac: float) -> void:
	var center := Vector2(SIZE / 2.0, SIZE / 2.0)
	var rx := SIZE * radius_x_frac
	var ry := SIZE * radius_y_frac
	for y in SIZE:
		for x in SIZE:
			var dx := (x + 0.5 - center.x) / rx
			var dy := (y + 0.5 - center.y) / ry
			var d := dx * dx + dy * dy
			if d > 1.0:
				continue
			image.set_pixel(x, y, _shade(base, d, dy))


func _draw_fang(image: Image, base: Color) -> void:
	# A downward-tapering tooth: width shrinks toward the bottom.
	for y in SIZE:
		var t := float(y) / (SIZE - 1)
		var half_width := (1.0 - t) * SIZE * 0.28
		var cx := SIZE / 2.0
		for x in SIZE:
			if absf(x + 0.5 - cx) > half_width:
				continue
			var edge := absf(x + 0.5 - cx) / maxf(half_width, 0.001)
			image.set_pixel(x, y, _shade(base, edge, -0.2))


func _draw_sword(image: Image, base: Color) -> void:
	var cx := SIZE / 2
	var hilt := base.darkened(0.3)
	# Blade: vertical bar down the middle, top ~75%.
	for y in range(1, int(SIZE * 0.75)):
		for x in range(cx - 1, cx + 2):
			var edge := absf(x - cx) / 1.5
			image.set_pixel(x, y, _shade(base, edge, -0.2))
	# Crossguard.
	var guard_y := int(SIZE * 0.75)
	for x in range(cx - 3, cx + 4):
		image.set_pixel(x, guard_y, hilt.darkened(OUTLINE_DARKEN))
	# Grip.
	for y in range(guard_y + 1, SIZE - 1):
		image.set_pixel(cx, y, hilt)


## An axe: an asymmetric wedge-shaped head bulging to one side of a straight
## haft, deliberately unlike the sword's thin symmetric blade + crossguard.
func _draw_axe(image: Image, base: Color) -> void:
	var cx := SIZE / 2 - 1
	var haft := base.darkened(0.55)

	# Haft: a plain vertical handle down the center-left, 2px wide.
	for y in range(3, SIZE - 1):
		image.set_pixel(cx, y, haft)
		image.set_pixel(cx + 1, y, haft)

	# Blade head: a wedge bulging to the right, widest partway down its arc
	# and tapering to a point at both ends -- an axe-head silhouette rather
	# than a symmetric blob or bar.
	var head_height := int(SIZE * 0.45)
	for y in range(0, head_height):
		var t := float(y) / float(head_height - 1)
		var width := int(round(sin(t * PI) * (SIZE * 0.35)))
		for dx in range(1, width + 1):
			var x := cx + dx
			if x >= SIZE:
				continue
			var edge := float(dx) / maxf(float(width), 1.0)
			image.set_pixel(x, y, _shade(base, edge, -0.2))


## Base color shaded by radial distance (outline near the rim) and vertical
## position (highlight up top, shadow at the bottom) for a rounded look.
func _shade(base: Color, edge: float, dy: float) -> Color:
	if edge > 0.75:
		return _palette.outline_color()
	if dy < -0.25:
		return _palette.highlight(base)
	if dy > 0.3:
		return _palette.shade(base)
	return base
