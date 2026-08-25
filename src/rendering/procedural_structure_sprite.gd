extends RefCounted

## Deterministic offline pixel-art for placed world structures (campfire,
## furnace -- see item_catalog.gd's "placeable" kind and
## TerrainRenderer.atlas_coords_for_modification). These render as full
## TerrainRenderer.ART_TILE_SIZE ground tiles (the modification a built cell
## paints instead of its biome tile), not as a creature/item sprite layered
## over ground, so -- unlike ProceduralAnimalSprite -- every pixel is opaque,
## matching ProceduralTerrainSprite's all-over-textured tile technique. Same
## house style otherwise: PixelPalette shading/outline, deterministic
## hash-seeded jitter, no RandomNumberGenerator. Structure ids are dict-keyed
## (see generate_image), mirroring ProceduralAnimalSprite's
## SPECIES_BITMAPS/SPECIES_SHAPE_FAMILY split -- one dict per hand-authored
## look, keyed by id, rather than one script per structure.

const PixelPalette = preload("res://src/rendering/pixel_palette.gd")

## DETAIL_MULTIPLIER times the original 16px tile (see
## docs/concept/art_resolution.md), matched to
## TerrainRenderer.ART_TILE_SIZE. Every hand-placed pixel constant below (log
## endpoints, flame span, brick spacing, firebox bounds) is scaled by the
## same 4x factor so each structure's composition stays identical, just at
## higher fidelity -- except mortar/outline LINE width, which deliberately
## stays 1px: a thin line against 4x-bigger bricks reads as finer masonry,
## not coarser (scaling the line's width too would have made it chunkier).
const SIZE := 32

## Every structure id this generator knows how to draw, in the fixed order
## TerrainRenderer reserves their atlas slots (see
## TerrainRenderer._structure_linear) -- adding a new placeable structure's
## art means adding its id here and a case in generate_image.
const STRUCTURE_IDS: Array[String] = ["campfire", "furnace", "sagewerk"]

# -- campfire: warm ember ground, crossed logs, a licking flame -------------

## Dark ember/ash ground the campfire sits on -- distinctly warmer and darker
## than TerrainRenderer.EARTH_COLOR's flat dirt brown, and nothing like
## furnace's cool stone grey.
const _EMBER_GROUND := Color(0.22, 0.07, 0.04)
const _LOG_COLOR := Color(0.33, 0.21, 0.11)
const _FLAME_OUTER := Color(0.85, 0.22, 0.05)
const _FLAME_INNER := Color(0.98, 0.68, 0.18)

## Logs cross near the tile's base; each is a shallow staircase diagonal this
## many pixels thick.
const _LOG_THICKNESS := 4
const _LOG_JITTER_RANGE := 0.2

## The flame silhouette spans these rows (1-indexed from the top), narrow at
## the tip and wide at its base where it meets the logs.
const _FLAME_TOP_ROW := 2
const _FLAME_BASE_ROW := 18
const _FLAME_TIP_HALF_WIDTH := 1.0
const _FLAME_BASE_HALF_WIDTH := 8.0
const _FLAME_INNER_CORE_FRACTION := 0.45
const _FLAME_CENTER_JITTER_PX := 3.0
const _FLAME_SWAY_PX := 1.6

# -- furnace: cool stone/brick block with a glowing firebox ------------------

const _STONE_COLOR := Color(0.52, 0.52, 0.57)
const _MORTAR_COLOR := Color(0.36, 0.36, 0.4)
const _FIREBOX_COLOR := Color(0.55, 0.18, 0.05)
const _BRICK_ROW_HEIGHT := 8
const _BRICK_JOINT_SPACING := 12
const _BRICK_JOINT_OFFSET := 6

## The firebox opening's bounds (exclusive end), where fuel burns -- the
## detail that reads "furnace" rather than "brick wall".
const _FIREBOX_LEFT := 10
const _FIREBOX_RIGHT := 22
const _FIREBOX_TOP := 18
const _FIREBOX_BOTTOM := 28

var _palette := PixelPalette.new()


func generate_texture(structure_id: String, variant_seed: int = 0) -> ImageTexture:
	return ImageTexture.create_from_image(generate_image(structure_id, variant_seed))


## Renders one structure id's tile. Unknown ids fall back to campfire's art
## (fail-safe default, matching this codebase's `.get(x, default)`
## convention -- TerrainRenderer.atlas_coords_for_modification is the one
## that actually decides whether an id gets a dedicated atlas slot at all;
## this only guards generate_image itself against ever crashing on an odd id).
func generate_image(structure_id: String, variant_seed: int = 0) -> Image:
	if structure_id == "furnace":
		return _furnace_image(variant_seed)
	if structure_id == "sagewerk":
		return _sagewerk_image(variant_seed)
	return _campfire_image(variant_seed)


func _campfire_image(variant_seed: int) -> Image:
	var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	image.fill(_EMBER_GROUND)

	_paint_log(image, 4, 26, 26, 20, variant_seed, 0)
	_paint_log(image, 4, 20, 26, 26, variant_seed, 1)
	_paint_flame(image, variant_seed)
	_outline_against_background(image, _EMBER_GROUND)
	return image


## One log: a shallow staircase diagonal from (x0,y0) to (x1,y1),
## _LOG_THICKNESS px thick, with a small seeded lighten/darken so the two
## crossed logs don't read as one flat blob.
func _paint_log(image: Image, x0: int, y0: int, x1: int, y1: int, variant_seed: int, log_index: int) -> void:
	var jitter := _seeded_unit_float(variant_seed, "log_%d" % log_index) - 0.5
	var color := _LOG_COLOR.lightened(maxf(jitter * _LOG_JITTER_RANGE, 0.0)).darkened(
		maxf(-jitter * _LOG_JITTER_RANGE, 0.0)
	)
	var steps := x1 - x0
	for i in range(steps + 1):
		var x := x0 + i
		var y := y0 + int(round(float(y1 - y0) * i / steps))
		for t in _LOG_THICKNESS:
			var py := y + t
			if py >= 0 and py < SIZE:
				image.set_pixel(x, py, color)


## The flame: narrows from a wide base (where it meets the logs) to a
## flickering tip, with a brighter inner core -- half-width and a gentle
## sideways sway both driven by variant_seed so different seeds give visibly
## different flames.
func _paint_flame(image: Image, variant_seed: int) -> void:
	var center_jitter := _seeded_unit_float(variant_seed, "flame_center") - 0.5
	var center_x := SIZE / 2.0 + center_jitter * _FLAME_CENTER_JITTER_PX
	var span := _FLAME_BASE_ROW - _FLAME_TOP_ROW

	for y in range(_FLAME_TOP_ROW, _FLAME_BASE_ROW + 1):
		var t := float(y - _FLAME_TOP_ROW) / float(span)  # 0 at tip, 1 at base
		var half_width: float = lerp(_FLAME_TIP_HALF_WIDTH, _FLAME_BASE_HALF_WIDTH, t)
		var sway := sin(t * PI * 1.5 + center_jitter * 2.0) * _FLAME_SWAY_PX
		var row_center := center_x + sway

		for x in SIZE:
			var dist := absf(x + 0.5 - row_center)
			if dist > half_width:
				continue
			var color := _FLAME_INNER if dist < half_width * _FLAME_INNER_CORE_FRACTION else _FLAME_OUTER
			image.set_pixel(x, y, color)


## Post-process pass: any background-colored pixel touching a non-background
## pixel gets recolored to the shared dark outline -- gives the flame/log
## silhouette a crisp rim against the ember ground, same
## shaded-and-outlined house style as the other procedural generators.
func _outline_against_background(image: Image, background: Color) -> void:
	var outline := _palette.outline_color()
	var to_outline: Array[Vector2i] = []
	for y in SIZE:
		for x in SIZE:
			if image.get_pixel(x, y) != background:
				continue
			if _touches_non_background(image, x, y, background):
				to_outline.append(Vector2i(x, y))
	for cell in to_outline:
		image.set_pixel(cell.x, cell.y, outline)


## Cardinal offsets used to find whether a background pixel borders the
## structure's silhouette -- typed explicitly so `offset.x`/`offset.y` below
## resolve to int, not Variant (this project's strict-typing lint rejects
## Variant-inferred locals).
const _NEIGHBOR_OFFSETS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]


func _touches_non_background(image: Image, x: int, y: int, background: Color) -> bool:
	for offset in _NEIGHBOR_OFFSETS:
		var nx: int = x + offset.x
		var ny: int = y + offset.y
		if nx < 0 or nx >= SIZE or ny < 0 or ny >= SIZE:
			continue
		if image.get_pixel(nx, ny) != background:
			return true
	return false


func _furnace_image(variant_seed: int) -> Image:
	var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	image.fill(_STONE_COLOR)

	_paint_brick_pattern(image, variant_seed)
	_paint_firebox(image)
	_shade_top_left_highlight_bottom_right_shadow(image)
	return image


## Horizontal mortar lines every _BRICK_ROW_HEIGHT px, with vertical joints
## offset every other row (running-bond brick pattern), so the block reads
## as masonry rather than a flat grey fill.
func _paint_brick_pattern(image: Image, variant_seed: int) -> void:
	var jitter := _seeded_unit_float(variant_seed, "brick_shade") - 0.5
	var stone := _STONE_COLOR.lightened(maxf(jitter * 0.1, 0.0)).darkened(maxf(-jitter * 0.1, 0.0))
	for y in SIZE:
		if y % _BRICK_ROW_HEIGHT == 0:
			for x in SIZE:
				image.set_pixel(x, y, _MORTAR_COLOR)
			continue
		_fill_row(image, y, stone)
		var row_index := y / _BRICK_ROW_HEIGHT
		var offset := 0 if row_index % 2 == 0 else _BRICK_JOINT_OFFSET
		for x in SIZE:
			if (x + offset) % _BRICK_JOINT_SPACING == 0:
				image.set_pixel(x, y, _MORTAR_COLOR)


func _fill_row(image: Image, y: int, color: Color) -> void:
	for x in SIZE:
		image.set_pixel(x, y, color)


## The dark, glowing firebox opening in the lower-middle -- outlined, with a
## warm ember-colored interior, so the block reads "furnace" rather than
## "brick wall".
func _paint_firebox(image: Image) -> void:
	var outline := _palette.outline_color()
	for y in range(_FIREBOX_TOP, _FIREBOX_BOTTOM):
		for x in range(_FIREBOX_LEFT, _FIREBOX_RIGHT):
			var edge := y == _FIREBOX_TOP or y == _FIREBOX_BOTTOM - 1 or x == _FIREBOX_LEFT or x == _FIREBOX_RIGHT - 1
			image.set_pixel(x, y, outline if edge else _FIREBOX_COLOR)


## Lighten the top row and left column (rim light), darken the bottom row and
## right column (shadow) -- same top-left-lit convention
## PixelPalette.highlight/shade uses elsewhere, applied directly since this
## tile isn't a single flat base color like the other generators' shapes.
func _shade_top_left_highlight_bottom_right_shadow(image: Image) -> void:
	for x in SIZE:
		image.set_pixel(x, 0, _palette.highlight(image.get_pixel(x, 0)))
		image.set_pixel(x, SIZE - 1, _palette.shade(image.get_pixel(x, SIZE - 1)))
	for y in SIZE:
		image.set_pixel(0, y, _palette.highlight(image.get_pixel(0, y)))
		image.set_pixel(SIZE - 1, y, _palette.shade(image.get_pixel(SIZE - 1, y)))


# -- sagewerk: a sawdust-pale worksite, a trunk on trestles, a saw kerf ------
# (see docs/concept/timber_construction.md's Sägewerk worksite -- log ->
# beam/plank shaping, distinct from campfire's fire-warm and furnace's
# stone-cool reads: this one reads as raw, pale, worked wood.)

const _SAWDUST_GROUND := Color(0.62, 0.5, 0.32)
const _TRESTLE_COLOR := Color(0.3, 0.2, 0.1)
const _LOG_ON_TRESTLE_COLOR := Color(0.45, 0.32, 0.16)
const _SAWCUT_COLOR := Color(0.85, 0.8, 0.65)

## Two trestle uprights hold the trunk off the ground -- the same real
## "keep wood off bare earth" reasoning timber_construction.md's own
## grounding section gives for footings, applied to a worksite prop instead
## of a finished building.
const _TRESTLE_LEFT_X := 6
const _TRESTLE_RIGHT_X := 26
const _TRESTLE_TOP_ROW := 12
const _TRESTLE_BOTTOM_ROW := 28
const _TRESTLE_THICKNESS := 3

## The trunk lying across both trestles, spanning the full tile width.
const _LOG_ROW := 12
const _LOG_THICKNESS_SAGEWERK := 6


func _sagewerk_image(variant_seed: int) -> Image:
	var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	image.fill(_SAWDUST_GROUND)

	_paint_trestle(image, _TRESTLE_LEFT_X)
	_paint_trestle(image, _TRESTLE_RIGHT_X)
	_paint_log_on_trestle(image, variant_seed)
	_paint_sawcut(image, variant_seed)
	_outline_against_background(image, _SAWDUST_GROUND)
	return image


func _paint_trestle(image: Image, x: int) -> void:
	for y in range(_TRESTLE_TOP_ROW, _TRESTLE_BOTTOM_ROW):
		for t in _TRESTLE_THICKNESS:
			var px := x + t
			if px >= 0 and px < SIZE:
				image.set_pixel(px, y, _TRESTLE_COLOR)


## The trunk itself, with a small seeded lighten/darken so different seeds
## read as different individual logs, not one fixed texture.
func _paint_log_on_trestle(image: Image, variant_seed: int) -> void:
	var jitter := _seeded_unit_float(variant_seed, "sagewerk_log") - 0.5
	var color := _LOG_ON_TRESTLE_COLOR.lightened(maxf(jitter * 0.2, 0.0)).darkened(maxf(-jitter * 0.2, 0.0))
	for y in range(_LOG_ROW, _LOG_ROW + _LOG_THICKNESS_SAGEWERK):
		for x in SIZE:
			image.set_pixel(x, y, color)


## A pale saw kerf drawn straight through the trunk -- the detail that reads
## "sawmill worksite" rather than "log pile". A small seeded horizontal
## offset keeps different seeds visibly distinct.
func _paint_sawcut(image: Image, variant_seed: int) -> void:
	var offset := _seeded_unit_float(variant_seed, "sagewerk_saw") * 4.0
	var mid_row := _LOG_ROW + _LOG_THICKNESS_SAGEWERK / 2
	for x in SIZE:
		var y := mid_row + int(round(sin((float(x) + offset) * 0.4)))
		if y >= 0 and y < SIZE:
			image.set_pixel(x, y, _SAWCUT_COLOR)


func _seeded_unit_float(seed_value: int, salt: String) -> float:
	return float(absi(hash("%d_%s" % [seed_value, salt])) % 10000) / 10000.0
