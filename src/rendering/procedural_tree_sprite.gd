extends RefCounted

## Deterministic offline pixel-art for trees, matching the same shaded/
## outlined technique ProceduralSpriteGenerator (creatures), ProceduralItemSprite
## (items), and ProceduralCharacterSprite (player) already use. A tree's
## canopy hue leans toward `species_bias` -- TreeGenome's 0 (nut) .. 1 (fruit)
## trait -- so a fruit-leaning tree visibly reads differently from a
## nut-leaning one, not just in what it drops. `seed_value` (typically the
## tree's own genome seed) adds a small deterministic leaf-speckle pattern so
## same-species trees aren't all pixel-identical clones.

const PixelPalette = preload("res://src/rendering/pixel_palette.gd")

## Bumped from 16x20: fuller canopies that overlap between adjacent forest
## tiles, so a forest reads as a connected leafy mass instead of spaced
## lollipops. Collision stays proportional (TreeRenderer.COLLISION_SCALE).
const SIZE := Vector2i(20, 26)
const OUTLINE_DARKEN := 0.5
const SHADE_DARKEN := 0.2
const HIGHLIGHT_LIGHTEN := 0.2
const SPECKLE_COUNT := 5

## Push canopy toward a saturated Zelda-canopy green before shading.
const CANOPY_SATURATE := 0.16

const NUT_CANOPY_COLOR := Color(0.15, 0.52, 0.12)
const FRUIT_CANOPY_COLOR := Color(0.2, 0.64, 0.16)
const TRUNK_COLOR := Color(0.38, 0.25, 0.13)

var _palette := PixelPalette.new()

const CANOPY_HEIGHT_FRAC := 0.7  # fraction of SIZE.y the canopy occupies, from the top


## How many individual ripe fruits can be shown as pixel dots on a canopy at
## once -- a real crop of dozens is visually summarized by up to this many
## dots (see FruitingModel/ecosystem_dynamics.md's phenology).
const MAX_FRUIT_DOTS := 8
## Ripe fruit dot color -- a warm red that reads clearly against the green
## canopy (test_ripe_fruit_adds_warm_fruit_dots_to_the_canopy pins the hue).
const RIPE_FRUIT_COLOR := Color(0.9, 0.22, 0.18)


func generate_texture(species_bias: float, seed_value: int) -> ImageTexture:
	return ImageTexture.create_from_image(generate_image(species_bias, seed_value))


func generate_texture_with_fruit(species_bias: float, seed_value: int, ripe_count: int) -> ImageTexture:
	return ImageTexture.create_from_image(generate_image_with_fruit(species_bias, seed_value, ripe_count))


func generate_image(species_bias: float, seed_value: int) -> Image:
	return generate_image_with_fruit(species_bias, seed_value, 0)


## The tree, with `ripe_count` ripe fruits drawn as individual warm pixel dots
## on the canopy (capped at MAX_FRUIT_DOTS). ripe_count 0 is exactly the plain
## tree. Dot positions are deterministic per seed_value so a tree's fruit
## doesn't teleport around as its crop count changes -- the Nth dot is always
## in the same spot; more ripe fruit just lights up more of them.
func generate_image_with_fruit(species_bias: float, seed_value: int, ripe_count: int) -> Image:
	var image := Image.create(SIZE.x, SIZE.y, false, Image.FORMAT_RGBA8)
	var canopy_color: Color = _palette.saturate(
		NUT_CANOPY_COLOR.lerp(FRUIT_CANOPY_COLOR, clampf(species_bias, 0.0, 1.0)), CANOPY_SATURATE
	)

	_paint_trunk(image)
	_paint_canopy(image, canopy_color, seed_value)
	if ripe_count > 0:
		_paint_fruit_dots(image, seed_value, ripe_count)
	return image


## Draws up to MAX_FRUIT_DOTS ripe-fruit pixels at deterministic canopy
## positions. Each dot sits inside the canopy silhouette (same ellipse as
## _paint_canopy) so fruit never floats off the leaves.
func _paint_fruit_dots(image: Image, seed_value: int, ripe_count: int) -> void:
	var canopy_height := SIZE.y * CANOPY_HEIGHT_FRAC
	var center := Vector2(SIZE.x / 2.0, canopy_height / 2.0)
	var radius_x := SIZE.x / 2.0 - 1.0
	var radius_y := canopy_height / 2.0 - 1.0
	var shown := mini(ripe_count, MAX_FRUIT_DOTS)
	for i in shown:
		var dot_seed := hash("%d_fruit_%d" % [seed_value, i])
		var angle := float(absi(dot_seed) % 360) * PI / 180.0
		var radius_fraction := 0.25 + float((absi(dot_seed) / 360) % 100) / 100.0 * 0.55
		var px := int(center.x + cos(angle) * radius_x * radius_fraction)
		var py := int(center.y + sin(angle) * radius_y * radius_fraction)
		if px < 0 or px >= SIZE.x or py < 0 or py >= SIZE.y:
			continue
		var dx := (px + 0.5 - center.x) / radius_x
		var dy := (py + 0.5 - center.y) / radius_y
		if dx * dx + dy * dy <= 0.8:  # keep dots off the outline ring
			image.set_pixel(px, py, RIPE_FRUIT_COLOR)


func _paint_trunk(image: Image) -> void:
	var trunk_width := maxi(2, SIZE.x / 5)
	var trunk_left := (SIZE.x - trunk_width) / 2
	var trunk_top := int(SIZE.y * CANOPY_HEIGHT_FRAC) - 1

	for y in range(trunk_top, SIZE.y):
		for x in range(trunk_left, trunk_left + trunk_width):
			var is_edge := x == trunk_left or x == trunk_left + trunk_width - 1 or y == SIZE.y - 1
			var color := TRUNK_COLOR
			if is_edge:
				# Warm-dark trunk edge (keeps the narrow trunk reading brown);
				# the shared cool outline rings the canopy silhouette above.
				color = TRUNK_COLOR.darkened(OUTLINE_DARKEN)
			elif x == trunk_left + 1:
				color = _palette.highlight(TRUNK_COLOR)
			image.set_pixel(x, y, color)


func _paint_canopy(image: Image, canopy_color: Color, seed_value: int) -> void:
	var outline_color := _palette.outline_color()
	var shade_color := _palette.shade(canopy_color)
	var highlight_color := _palette.highlight(canopy_color)
	var speckle_color := canopy_color.darkened(0.35)

	var canopy_height := SIZE.y * CANOPY_HEIGHT_FRAC
	var center := Vector2(SIZE.x / 2.0, canopy_height / 2.0)
	var radius_x := SIZE.x / 2.0 - 1.0
	var radius_y := canopy_height / 2.0 - 1.0

	for y in int(canopy_height) + 1:
		for x in SIZE.x:
			var dx := (x + 0.5 - center.x) / radius_x
			var dy := (y + 0.5 - center.y) / radius_y
			var dist_sq := dx * dx + dy * dy
			if dist_sq > 1.0:
				continue  # outside the canopy silhouette -- left transparent

			var color := canopy_color
			if dist_sq > 0.8:
				color = outline_color
			elif dy < -0.3:
				color = highlight_color
			elif dy > 0.4:
				color = shade_color
			image.set_pixel(x, y, color)

	_paint_speckles(image, center, radius_x, radius_y, speckle_color, seed_value)


## A handful of deterministic darker leaf-cluster pixels within the canopy,
## seeded from `seed_value` -- same idea as the creature generator's spots,
## so trees sharing a species_bias bucket still look like distinct individuals.
func _paint_speckles(
	image: Image, center: Vector2, radius_x: float, radius_y: float, speckle_color: Color, seed_value: int
) -> void:
	for i in SPECKLE_COUNT:
		var speckle_seed := hash("%d_speckle_%d" % [seed_value, i])
		var angle := float(absi(speckle_seed) % 360) * PI / 180.0
		var radius_fraction := 0.2 + float((absi(speckle_seed) / 360) % 100) / 100.0 * 0.5
		var speckle_x := int(center.x + cos(angle) * radius_x * radius_fraction)
		var speckle_y := int(center.y + sin(angle) * radius_y * radius_fraction)
		if speckle_x < 0 or speckle_x >= image.get_width() or speckle_y < 0 or speckle_y >= image.get_height():
			continue
		var dx := (speckle_x + 0.5 - center.x) / radius_x
		var dy := (speckle_y + 0.5 - center.y) / radius_y
		if dx * dx + dy * dy <= 0.8:  # keep speckles off the outline ring
			image.set_pixel(speckle_x, speckle_y, speckle_color)
