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

const ArtResolution = preload("res://src/rendering/art_resolution.gd")

## The tree's WORLD footprint, in world units. Bumped from 16x20 (before the
## resolution pass) so canopies overlap between adjacent forest tiles and a
## forest reads as a connected leafy mass instead of spaced lollipops.
## Collision stays proportional (TreeRenderer.COLLISION_SCALE).
const WORLD_SIZE := Vector2i(20, 26)

## The ART canvas, DETAIL_MULTIPLIER times the world footprint (see
## docs/concept/art_resolution.md) -- TreeRenderer draws it at
## ArtResolution.SPRITE_SCALE so the tree gains real pixel detail without
## growing in the world.
const SIZE := Vector2i(40, 52)
const OUTLINE_DARKEN := 0.5
const SHADE_DARKEN := 0.2
const HIGHLIGHT_LIGHTEN := 0.2
## Scaled with the canvas area so leaf speckle density per drawn area is
## unchanged -- a fixed count would read as a nearly-bare canopy at 16x the
## pixels.
const SPECKLE_COUNT := 80

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

	_paint_trunk(image, seed_value)
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


## How many bark striations run down a trunk -- vertical grain lines that
## only became legible once the trunk was wider than a few pixels (see
## docs/concept/art_resolution.md); at the old resolution the trunk was
## barely wider than its own outline.
const _BARK_STRIATIONS := 14


func _paint_trunk(image: Image, seed_value: int = 0) -> void:
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
			elif x <= trunk_left + trunk_width / 4:
				# Rim light down the lit side, widened with the trunk so it
				# reads as a rounded column rather than a single bright line.
				color = _palette.highlight(TRUNK_COLOR)
			elif x >= trunk_left + trunk_width - trunk_width / 4:
				color = _palette.shade(TRUNK_COLOR)
			image.set_pixel(x, y, color)

	_paint_bark(image, trunk_left, trunk_width, trunk_top, seed_value)


## Short vertical bark grain: broken dark striations down the trunk's
## interior, so it reads as textured bark instead of a flat brown column.
func _paint_bark(image: Image, trunk_left: int, trunk_width: int, trunk_top: int, seed_value: int) -> void:
	var bark_color := TRUNK_COLOR.darkened(0.28)
	var trunk_height := SIZE.y - trunk_top
	if trunk_width <= 3 or trunk_height <= 3:
		return  # too narrow for interior texture -- leave the plain column
	for i in _BARK_STRIATIONS:
		var h := absi(hash("%d_bark_%d" % [seed_value, i]))
		# Interior only: never overwrite the trunk's own edge columns.
		var x := trunk_left + 1 + h % (trunk_width - 2)
		var y := trunk_top + 1 + (h / 53) % maxi(trunk_height - 2, 1)
		var length := 2 + (h / 197) % 4
		for k in length:
			var py := y + k
			if py < SIZE.y - 1:
				image.set_pixel(x, py, bark_color)


func _paint_canopy(image: Image, canopy_color: Color, seed_value: int) -> void:
	var outline_color := _palette.outline_color()
	var shade_color := _palette.shade(canopy_color)
	var highlight_color := _palette.highlight(canopy_color)
	var speckle_color := canopy_color.darkened(0.35)
	# The gaps between leaves: only slightly darker than the leaves
	# themselves, so foliage reads as a mass with depth rather than bright
	# flecks floating on a dark background.
	var base_fill := canopy_color.darkened(0.14)

	var canopy_height := SIZE.y * CANOPY_HEIGHT_FRAC
	var center := Vector2(SIZE.x / 2.0, canopy_height / 2.0)
	var radius_x := SIZE.x / 2.0 - 1.0
	var radius_y := canopy_height / 2.0 - 1.0

	# The crown is ONE ROUND mass -- a clean rounded silhouette reads better
	# than a lumpy cluster-of-blobs outline. All of its texture comes from
	# individually drawn leaves (see _paint_leaves) painted over this base,
	# NOT from hard horizontal shade bands: banding at this canvas size read
	# as flat stripes across the crown rather than as a lit sphere.
	for y in int(canopy_height) + 1:
		for x in SIZE.x:
			var dx := (x + 0.5 - center.x) / radius_x
			var dy := (y + 0.5 - center.y) / radius_y
			var dist_sq := dx * dx + dy * dy
			if dist_sq > 1.0:
				continue  # outside the canopy silhouette -- left transparent
			image.set_pixel(x, y, outline_color if dist_sq > _CANOPY_RIM_START else base_fill)

	_paint_leaves(image, center, radius_x, radius_y, canopy_color, seed_value)
	_paint_speckles(image, center, radius_x, radius_y, speckle_color, seed_value)


## Where the crown's dark rim starts, as squared normalized distance from
## its center -- outside this the pixel is drawn as outline, keeping the
## silhouette crisp against the ground.
const _CANOPY_RIM_START := 0.86

## Spacing of the jittered leaf grid, in art pixels -- roughly a leaf's own
## size, so leaves touch and overlap into full foliage. At the pre-pass
## 20x26 canvas a single leaf would have been a fifth of the whole tree,
## which is exactly why leaves could not be drawn before.
const _LEAF_GRID_STEP_X := 7
const _LEAF_GRID_STEP_Y := 6
## A leaf's half-extents in art pixels: a small oval, longer than it is wide.
const _LEAF_HALF_LENGTH := 3.1
const _LEAF_HALF_WIDTH := 1.9
## How much lighter/darker than the canopy a leaf's face and its shaded
## underside are drawn. The lighter face is what `is_leaf_highlight`
## detects, and what makes individual leaves legible against the crown.
const _LEAF_LIGHTEN := 0.34
const _LEAF_DARKEN := 0.26


## A well-distributed integer hash (xorshift-multiply). Godot's built-in
## string `hash()` correlates badly across near-identical inputs -- hashing
## "..._0", "..._1", "..._2" gave whole ROWS of leaves the same angle, the
## same clustering this project has hit before with seeded index lookups.
## Mixing the coordinates numerically instead decorrelates neighbours while
## staying fully deterministic.
static func _mix(a: int, b: int, c: int) -> int:
	var h := a * 374761393 + b * 668265263 + c * 2147483647
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return absi(h)


## `_mix` mapped into [0, 1).
static func _mix_unit(a: int, b: int, c: int) -> float:
	return float(_mix(a, b, c) % 100000) / 100000.0


## True if `color` is one of the lit leaf faces painted by _paint_leaves --
## used by tests to count individually drawn leaves, and kept next to the
## painter so the two can't drift apart.
func is_leaf_highlight(color: Color) -> bool:
	if color.a <= 0.0:
		return false
	# Compared with a tolerance, not by identity: the image is FORMAT_RGBA8,
	# so painting a float Color quantizes it to 8 bits per channel and the
	# value read back is never exactly the value written.
	for tone in _leaf_highlight_tones:
		if absf(color.r - tone.r) < _TONE_EPSILON 			and absf(color.g - tone.g) < _TONE_EPSILON 			and absf(color.b - tone.b) < _TONE_EPSILON:
			return true
	return false


## Half an 8-bit channel step -- enough to absorb FORMAT_RGBA8 quantization
## without matching a genuinely different tone.
const _TONE_EPSILON := 1.0 / 255.0


var _leaf_highlight_tones := {}


## Individually drawn leaves filling the crown: each a small oval at its own
## angle, painted with a lit face and a shaded lower edge so it reads as an
## actual leaf rather than a speckle. Leaves are clipped to the crown's
## silhouette (minus its rim) so the round outline stays intact.
func _paint_leaves(
	image: Image, center: Vector2, radius_x: float, radius_y: float, canopy_color: Color, seed_value: int
) -> void:
	# Several tones so overlapping leaves read as depth, not one flat layer.
	# Ordered brightest to darkest: a leaf's tone is picked by how high it
	# sits on the crown, so the mass reads as lit from above.
	var faces := [
		canopy_color.lightened(_LEAF_LIGHTEN * 1.35),
		canopy_color.lightened(_LEAF_LIGHTEN),
		canopy_color.lightened(_LEAF_LIGHTEN * 0.5),
		canopy_color,
		canopy_color.darkened(_LEAF_DARKEN * 0.7),
	]
	for face in faces:
		_leaf_highlight_tones[face] = true

	# Leaves are placed on a JITTERED GRID rather than scattered at random:
	# random scatter leaves bald patches and clumps at this density, so the
	# crown read as a flat fill with a few specks on it. A jittered grid
	# covers the whole crown evenly while still looking unplanned.
	var y := int(center.y - radius_y) - _LEAF_GRID_STEP_Y
	while y <= int(center.y + radius_y) + _LEAF_GRID_STEP_Y:
		var x := int(center.x - radius_x) - _LEAF_GRID_STEP_X
		while x <= int(center.x + radius_x) + _LEAF_GRID_STEP_X:
			var leaf_center := Vector2(
				x + _mix_unit(seed_value, x, y) * _LEAF_GRID_STEP_X * 1.4,
				y + _mix_unit(seed_value + 7717, x, y) * _LEAF_GRID_STEP_Y * 1.4
			)
			var leaf_angle := _mix_unit(seed_value + 15413, x, y) * TAU
			# Light falls from above: leaves high on the crown take the
			# brighter faces, low ones the darker -- a soft gradient made of
			# leaves instead of hard bands.
			var vertical := clampf((leaf_center.y - (center.y - radius_y)) / (2.0 * radius_y), 0.0, 1.0)
			var jittered := clampf(vertical + (_mix_unit(seed_value + 33073, x, y) - 0.5) * 0.5, 0.0, 0.999)
			var face: Color = faces[int(jittered * faces.size())]
			_paint_one_leaf(
				image, leaf_center, leaf_angle, face, face.darkened(_LEAF_DARKEN),
				center, radius_x, radius_y
			)
			x += _LEAF_GRID_STEP_X
		y += _LEAF_GRID_STEP_Y


func _paint_one_leaf(
	image: Image, leaf_center: Vector2, leaf_angle: float, face: Color, underside: Color,
	crown_center: Vector2, radius_x: float, radius_y: float
) -> void:
	var cos_a := cos(leaf_angle)
	var sin_a := sin(leaf_angle)
	var extent := int(ceil(_LEAF_HALF_LENGTH)) + 1
	for oy in range(-extent, extent + 1):
		for ox in range(-extent, extent + 1):
			var px := int(leaf_center.x) + ox
			var py := int(leaf_center.y) + oy
			if px < 0 or px >= SIZE.x or py < 0 or py >= SIZE.y:
				continue
			# Stay inside the crown, off its dark rim, so the round
			# silhouette is never broken by a stray leaf.
			var cdx := (px + 0.5 - crown_center.x) / radius_x
			var cdy := (py + 0.5 - crown_center.y) / radius_y
			if cdx * cdx + cdy * cdy > _CANOPY_RIM_START:
				continue
			# The leaf's own rotated-oval test.
			var lx := float(ox) * cos_a + float(oy) * sin_a
			var ly := -float(ox) * sin_a + float(oy) * cos_a
			var nx := lx / _LEAF_HALF_LENGTH
			var ny := ly / _LEAF_HALF_WIDTH
			var d := nx * nx + ny * ny
			if d > 1.0:
				continue
			# Lower half of the leaf shades, so each one reads as a curved
			# surface catching light from above.
			image.set_pixel(px, py, underside if ly > 0.45 else face)


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
