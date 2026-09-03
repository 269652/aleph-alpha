extends RefCounted

## Deterministic offline pixel-art for trees, matching the same shaded/
## outlined technique ProceduralSpriteGenerator (creatures), ProceduralItemSprite
## (items), and ProceduralCharacterSprite (player) already use. A tree's
## canopy/fruit colour comes from its NAMED species (see TreeSpecies --
## Walnut/Cherry/Apple), resolved from `species_bias` -- TreeGenome's 0
## (nut) .. 1 (fruit) trait -- so each of the three reads visibly differently,
## not just in what it drops. `seed_value` (typically the tree's own genome
## seed) adds a small deterministic leaf-speckle pattern so same-species
## trees aren't all pixel-identical clones.

const PixelPalette = preload("res://src/rendering/pixel_palette.gd")
const TreeSpecies = preload("res://src/world/tree_species.gd")
const IllustratedTree = preload("res://src/rendering/illustrated_tree.gd")
const PixelNoise = preload("res://src/rendering/pixel_noise.gd")
# SnowLayer used to be preloaded here for SNOW_LEVELS below; see that
# constant's own doc comment -- the file it pointed to no longer exists.

const ArtResolution = preload("res://src/rendering/art_resolution.gd")

## The tree's WORLD footprint, in world units. Bumped from 16x20 (before the
## resolution pass) so canopies overlap between adjacent forest tiles and a
## forest reads as a connected leafy mass instead of spaced lollipops.
## Collision stays proportional (TreeRenderer.COLLISION_SCALE).
## A tree's WORLD footprint. Briefly grown to 40x56 to tower over the hero,
## then reverted: at that size forests crowded and read worse than they had
## at this one. Height relative to the hero is better solved by draw order
## (a tree now occludes someone walking behind it) than by sheer bulk.
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

## Canopy/fruit colour comes from TreeSpecies (Walnut/Cherry/Apple),
## resolved from species_bias -- three NAMED looks (see _species_id_for),
## not one continuous nut->fruit lerp between two anonymous endpoints.
const TRUNK_COLOR := Color(0.38, 0.25, 0.13)

var _palette := PixelPalette.new()

const CANOPY_HEIGHT_FRAC := 0.7  # fraction of SIZE.y the canopy occupies, from the top


## Test seam: forces the plain PROCEDURAL painter below even for a species
## with illustrated art. TreeSpecies.IDS and IllustratedTree.SPECIES_WITH_ART
## now list the exact same six species, so every real species_bias --
## TreeGenome.species_bias, continuous over 0..1 -- resolves to a species
## that HAS art, and no real caller (TreeRenderer, ChoppableTree) can reach
## the procedural branch any more. It stays as the deliberate fallback for a
## species added to IDS before its art exists (see "Everything else is
## procedural" in illustrated_tree.gd), matching the procedural-baseline
## pattern every other renderer here (creature/item/character) already
## follows -- so tests exercising the painter itself set this rather than
## hunting for a bias that happens to have no art.
var force_procedural := false


## Whether `species_id` should be drawn from its illustrated art rather than
## painted procedurally. The one place both generate_image_with_fruit and
## generate_bare_trunk_image decide that, so they can't drift apart.
func _uses_illustrated_art(species_id: String) -> bool:
	return not force_procedural and IllustratedTree.has_art_for(species_id)


## How many individual ripe fruits can be shown as pixel dots on a canopy at
## once -- a real crop of dozens is visually summarized by up to this many
## dots (see FruitingModel/ecosystem_dynamics.md's phenology).
const MAX_FRUIT_DOTS := 8


## The named species (see TreeSpecies) this species_bias resolves to. Kept as
## its own function rather than inlined so callers only ever go through one
## bias->species mapping.
func _species_id_for(species_bias: float) -> String:
	return TreeSpecies.species_for_bias(species_bias)


func generate_texture(species_bias: float, seed_value: int) -> ImageTexture:
	return ImageTexture.create_from_image(generate_image(species_bias, seed_value))


## Finished trees, keyed by everything that can change one.
##
## Bounded because a tree's variance comes from TREE_VARIANTS rather than from
## its seed: a hundred cherry trees in summer bearing three fruit are the same
## sixteen pictures, so the hundred-and-first is a dictionary lookup rather
## than a composite. This is what makes a fast-forward affordable -- rebuilding
## every tree from scratch each time its crop changed cost seconds a frame.
static var _tree_texture_cache := {}


func generate_texture_with_fruit(
	species_bias: float,
	seed_value: int,
	ripe_count: int,
	season: String = "",
	turning_into: String = "",
	turn_progress: float = 0.0,
	growth: float = 1.0,
	snow_coverage: float = 0.0
) -> ImageTexture:
	# The turn is part of the key: a half-turned tree is its own picture.
	# Quantised upstream (SeasonTransition.TURN_STEPS) precisely so this stays
	# a small, affordable set rather than one image per frame. Snow coverage
	# is quantised HERE instead (see snow_level's own doc comment), since --
	# unlike the turn -- nothing upstream already coarsens it: live snow
	# depth changes by fractions of a percent every tick.
	var key := "%s/%s/%s/%.2f/%d/%d/%.2f/%.2f" % [
		_species_id_for(species_bias),
		season,
		turning_into,
		turn_progress,
		crop_level_for(ripe_count),
		tree_variant_for(seed_value),
		growth_level(growth),
		snow_level(snow_coverage),
	]
	if _tree_texture_cache.has(key):
		return _tree_texture_cache[key]
	var texture := ImageTexture.create_from_image(
		generate_image_with_fruit(
			species_bias, seed_value, ripe_count, season, turning_into, turn_progress, growth,
			snow_coverage
		)
	)
	_tree_texture_cache[key] = texture
	return texture


func generate_image(species_bias: float, seed_value: int) -> Image:
	return generate_image_with_fruit(species_bias, seed_value, 0)


## The trunk alone, no canopy at all -- what a felled tree looks like once
## its crown has been limbed off (see ChoppableTree._remove_canopy,
## docs/concept/woodworking.md). `season` only matters for a species with
## illustrated art (the trunk piece is fetched per-season the same way the
## canopy is, even though the trunk itself doesn't visibly change with it);
## empty falls back the same way generate_image's own empty season does.
func generate_bare_trunk_texture(species_bias: float, seed_value: int, season: String = "") -> ImageTexture:
	return ImageTexture.create_from_image(generate_bare_trunk_image(species_bias, seed_value, season))


func generate_bare_trunk_image(species_bias: float, seed_value: int, season: String = "") -> Image:
	var species_id := _species_id_for(species_bias)
	var image := Image.create(SIZE.x, SIZE.y, false, Image.FORMAT_RGBA8)
	if _uses_illustrated_art(species_id):
		var trunk_box := illustrated_trunk_box(seed_value)
		var trunk_image := _scaled_piece(species_id, season, "trunk", trunk_box.size)
		if trunk_image != null:
			_blend_at(image, trunk_image, trunk_box.position.x, trunk_box.position.y)
		return image
	_paint_trunk(image, seed_value)
	return image


## The tree, with `ripe_count` ripe fruits drawn as individual warm pixel dots
## on the canopy (capped at MAX_FRUIT_DOTS). ripe_count 0 is exactly the plain
## tree. Dot positions are deterministic per seed_value so a tree's fruit
## doesn't teleport around as its crop count changes -- the Nth dot is always
## in the same spot; more ripe fruit just lights up more of them.
## `season` selects the canopy for species that have illustrated art (see
## IllustratedTree). Empty means "no opinion", which draws the tree in leaf --
## that is what every caller got before the canopy could change, so leaving it
## off keeps the old behaviour exactly.
## `turning_into` and `turn_progress` blend the canopy toward the next season
## (see SeasonTransition). Progress 0 is simply `season`, 1 is simply
## `turning_into`, and in between the canopy turns BRANCH BY BRANCH.
## `snow_coverage` layers a live-weather snow blend ON TOP of whatever the
## above already drew (see the "Snow" section below and _composite_
## illustrated) -- 0.0, the default, is a no-op for every call site that
## predates this parameter, and for every species without a snow frame
## regardless of value (see IllustratedTree.has_snow_frame_for).
func generate_image_with_fruit(
	species_bias: float,
	seed_value: int,
	ripe_count: int,
	season: String = "",
	turning_into: String = "",
	turn_progress: float = 0.0,
	growth: float = 1.0,
	snow_coverage: float = 0.0
) -> Image:
	var species_id := _species_id_for(species_bias)
	if _uses_illustrated_art(species_id):
		return _composite_illustrated(
			species_id, seed_value, ripe_count, season, turning_into, turn_progress, growth,
			snow_coverage
		)

	var image := Image.create(SIZE.x, SIZE.y, false, Image.FORMAT_RGBA8)
	var canopy_color: Color = _palette.saturate(
		TreeSpecies.canopy_color_for(species_id), CANOPY_SATURATE
	)
	_paint_trunk(image, seed_value)
	_paint_canopy(image, canopy_color, seed_value)
	if ripe_count > 0:
		_paint_fruit_dots(image, seed_value, ripe_count, TreeSpecies.fruit_color_for(species_id))
	return image


## Draws up to MAX_FRUIT_DOTS ripe-fruit pixels at deterministic canopy
## positions, in `fruit_color` (this tree's own named species -- see
## TreeSpecies.fruit_color_for). Each dot sits inside the canopy silhouette
## (same ellipse as _paint_canopy) so fruit never floats off the leaves.
func _paint_fruit_dots(image: Image, seed_value: int, ripe_count: int, fruit_color: Color) -> void:
	var canopy_height := SIZE.y * CANOPY_HEIGHT_FRAC
	var center := Vector2(SIZE.x / 2.0, canopy_height / 2.0)
	var radius_x := SIZE.x / 2.0 - 1.0
	var radius_y := canopy_height / 2.0 - 1.0
	var shown := mini(ripe_count, MAX_FRUIT_DOTS)
	for i in shown:
		# PixelNoise rather than hash("..._fruit_N"): Godot's string hash is
		# near-linear across inputs differing only in a trailing number, so
		# consecutive dots came out at consecutive angles and piled up in one
		# spot instead of spreading round the canopy (see the illustrated
		# scatter, which had the same bug).
		var angle := float(PixelNoise.range_index(seed_value, 100 + i * 2, 0, 360)) 			* PI / 180.0
		var radius_fraction := 0.25 + float(
			PixelNoise.range_index(seed_value, 101 + i * 2, 0, 100)
		) / 100.0 * 0.55
		var px := int(center.x + cos(angle) * radius_x * radius_fraction)
		var py := int(center.y + sin(angle) * radius_y * radius_fraction)
		if px < 0 or px >= SIZE.x or py < 0 or py >= SIZE.y:
			continue
		var dx := (px + 0.5 - center.x) / radius_x
		var dy := (py + 0.5 - center.y) / radius_y
		if dx * dx + dy * dy <= 0.8:  # keep dots off the outline ring
			image.set_pixel(px, py, fruit_color)


## How many bark striations run down a trunk -- vertical grain lines that
## only became legible once the trunk was wider than a few pixels (see
## docs/concept/art_resolution.md); at the old resolution the trunk was
## barely wider than its own outline.
## How wide the trunk is as a fraction of the canvas -- tuned so the trunk
## lands close to a full tile in the world (see
## test_the_trunk_is_close_to_a_tile_wide).
const TRUNK_WIDTH_FRACTION := 0.22

const _BARK_STRIATIONS := 14


func _paint_trunk(image: Image, seed_value: int = 0) -> void:
	var trunk_width := maxi(2, int(SIZE.x * TRUNK_WIDTH_FRACTION))
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


## The trunk's width in WORLD units -- what a collision box or a "can I walk
## past this" question actually cares about.
static func trunk_world_width() -> float:
	return float(SIZE.x) * TRUNK_WIDTH_FRACTION * ArtResolution.SPRITE_SCALE


## ## Compositing an illustrated tree
##
## Trunk, canopy and fruit are three separate sheets (see IllustratedTree and
## docs/concept/flora.md#illustrated-trees) assembled onto the same canvas the
## procedural painter uses, so nothing downstream has to know which of the two
## drew a given tree.

## ## Trunk and canopy proportions
##
## A trunk is TALL and NARROW, and much narrower than the crown above it.
##
## Scaled to preserve the source art's aspect it came out squat and wide: the
## trunk drawings are nearly square, because they include the flare of the
## roots, so a tree read as a canopy sitting on a stump. The art is stretched
## to reach real proportions instead -- deliberately, and only so far. Bark
## grain runs vertically, which is why it takes a vertical stretch without
## looking wrong; past MAX_TRUNK_STRETCH it reads as rubber rather than wood.
const ILLUSTRATED_TRUNK_WIDTH_FRAC := 0.26
const ILLUSTRATED_TRUNK_HEIGHT_FRAC := 0.52
## The trunk box's height-to-width ratio. The source art is roughly square --
## it includes the flare of the roots -- so reaching this squeezes it to about
## a third of its drawn width. Bark grain runs vertically, which is what lets
## it take that; past this it reads as rubber rather than wood.
const MAX_TRUNK_STRETCH := 3.6

## How wide a trunk may be relative to the crown it holds up. A trunk as wide
## as its canopy is a mushroom.
const MAX_TRUNK_SHARE_OF_CANOPY := 0.45

## How far DOWN the trunk the canopy reaches, as a fraction of the trunk's
## height.
##
## The two overlap rather than meet, and by a lot. A real tree's branches begin
## inside its crown, so a canopy resting on top of a trunk reads as a lollipop
## -- but more than that, these canopies are NOTCHED along the bottom, exactly
## where the trunk is, because the artist left room for one. At a small overlap
## the trunk stops in that notch and the crown visibly floats above it.
##
## Pinned from below by test_the_trunk_runs_up_into_the_foliage, which measures
## the sky between crown and trunk in the trunk's own columns rather than
## across whole rows -- the notch is invisible to a row-wise check.
const TRUNK_OVERLAP_FRAC := 0.62

## ## Every tree is its own tree
##
## A wood where every trunk is the same height reads as one tree stamped out
## repeatedly. Trunk height and canopy width vary per tree from its own seed --
## the canopy less than the trunk, because a crown that changed as much would
## stop reading as the same species.
##
## They vary TOGETHER rather than independently: the canopy is placed against
## the trunk's actual top, so a taller trunk lifts its crown with it instead of
## leaving a gap or burying it.
const TRUNK_HEIGHT_VARIANCE := 0.18
const CANOPY_SIZE_VARIANCE := 0.10

## How many DIFFERENT trees a species can have, per season.
##
## Compositing costs real time, and a tree is rebuilt every time its crop or
## its season changes -- which while the world runs fast (/ecotest) is
## constantly. Keyed by raw seed every tree is unique and nothing can be
## reused: measured, one fast-forward frame spent 3.3 seconds rebuilding about
## 190 trees and the game locked up.
##
## So a tree's own variance -- trunk height, canopy size, where its fruit hangs
## -- is drawn from a bounded VARIANT rather than from its seed directly. A
## wood still looks varied, and the renderer only ever builds a fixed number of
## images however many trees are standing in it.
const TREE_VARIANTS := 6

## How many levels of crop a tree is drawn in.
##
## Not one picture per fruit. At this size nobody can tell seven cherries from
## eight, and a picture per exact count multiplied the set of images a wood
## needs into the thousands -- measured, about a minute of solid compositing,
## which a fast-forward spent building pictures instead of showing a year.
##
## None, a few, a good crop, laden.
const CROP_LEVELS := 4


## Which level this crop is drawn at. Nothing is nothing -- a bare tree must
## never show a berry.
static func crop_level_for(ripe_count: int) -> int:
	if ripe_count <= 0:
		return 0
	var span := float(ILLUSTRATED_MAX_FRUIT) / float(CROP_LEVELS - 1)
	return clampi(1 + int(float(ripe_count - 1) / span), 1, CROP_LEVELS - 1)


## How many fruit to actually draw for a crop of this size: the level's own
## representative count.
static func drawn_fruit_for(ripe_count: int) -> int:
	var level := crop_level_for(ripe_count)
	if level <= 0:
		return 0
	return int(round(float(level) * float(ILLUSTRATED_MAX_FRUIT) / float(CROP_LEVELS - 1)))


## Which of the bounded looks this tree has.
static func tree_variant_for(seed_value: int) -> int:
	return absi(seed_value) % TREE_VARIANTS

## How wide a fruit is drawn, as a fraction of the canvas width.
##
## Raised from 0.12, which was chosen against the frame's WIDTH and forgot that
## the cherry art is mostly stem: the fruit itself came out about three pixels
## and vanished into the leaf texture. It was there, and no player would ever
## have seen it. Pinned from below by test_a_crop_is_actually_visible_on_the_
## tree so it cannot quietly shrink again.
const ILLUSTRATED_FRUIT_WIDTH_FRAC := 0.22

## How many pixels of the tree one fruit must cover to count as visible. Small,
## because at this canvas a fruit IS a few pixels -- but not so few that a crop
## is invisible.
const MIN_PIXELS_PER_FRUIT := 3

## Where in the canopy box the crop hangs, and how far it spreads. The centre
## sits high because the lower part of the box is the trunk overlap.
const FRUIT_CENTER_FRAC := 0.42
const FRUIT_SPREAD_FRAC := 0.3

## The most fruit drawn on one tree. A heavy crop reads as heavy well before
## every cherry is individually visible, and past this they merge into a red
## mass anyway.
const ILLUSTRATED_MAX_FRUIT := 10


## How much this tree is stretched vertically to reach trunk proportions.
func illustrated_trunk_stretch(seed_value: int) -> float:
	var box := illustrated_trunk_box(seed_value)
	# The stretch is height-per-width against the source art's own square-ish
	# shape; expressed as a ratio so the bound means the same for any sheet.
	return float(box.size.y) / float(maxi(box.size.x, 1))


## Where this tree's trunk sits on the canvas. Always standing on the bottom
## edge; height varies with the tree's own seed.
func illustrated_trunk_box(seed_value: int) -> Rect2i:
	var variant := tree_variant_for(seed_value)
	var roll := float(PixelNoise.range_index(variant, 11, 0, 101)) / 100.0
	var scale := 1.0 + (roll * 2.0 - 1.0) * TRUNK_HEIGHT_VARIANCE
	var height := maxi(2, int(round(float(SIZE.y) * ILLUSTRATED_TRUNK_HEIGHT_FRAC * scale)))
	var width := maxi(2, int(round(float(SIZE.x) * ILLUSTRATED_TRUNK_WIDTH_FRAC)))
	return Rect2i((SIZE.x - width) / 2, SIZE.y - height, width, height)


## Where this tree's canopy sits. Anchored to the TRUNK rather than to the
## canvas, so however the trunk varies the two still meet.
func illustrated_canopy_box(species_id: String, seed_value: int, season: String) -> Rect2i:
	var trunk := illustrated_trunk_box(seed_value)
	var variant := tree_variant_for(seed_value)
	var roll := float(PixelNoise.range_index(variant, 13, 0, 101)) / 100.0
	var scale := 1.0 + (roll * 2.0 - 1.0) * CANOPY_SIZE_VARIANCE
	var width := maxi(4, int(round(float(SIZE.x) * scale)))

	var height := width
	var trimmed := _piece_image(species_id, season, "canopy")
	if trimmed != null:
		height = maxi(
			2,
			int(round(float(trimmed.get_height()) * float(width) / float(trimmed.get_width())))
		)

	# The crown swallows the top of the trunk, because a tree's branches begin
	# inside it.
	var bottom := trunk.position.y + int(round(float(trunk.size.y) * TRUNK_OVERLAP_FRAC))
	var top := maxi(0, bottom - height)
	return Rect2i((SIZE.x - width) / 2, top, width, bottom - top)


## ## Why these caches exist
##
## Compositing a tree measured at 160ms, and a chunk of forest asks for one per
## tree. The cost was not the drawing -- it was `Texture2D.get_image()`, which
## copies back from the GPU, called two or three times per tree for pieces that
## never change.
##
## So the pieces are kept as IMAGES, trimmed once per species and season, and
## the scaled versions are kept too: trunk heights vary per tree but land on
## whole pixels, so a wood of a hundred trees only ever needs a handful of
## distinct sizes.
static var _piece_cache := {}
static var _scaled_cache := {}


## A pseudo-"season" key for `_piece_image`/`_scaled_piece`, standing in for
## the snow canopy frame rather than any real SeasonCycle.SEASONS name (it
## collides with none of them). Reusing the trunk's own "fetch per season
## even though it never changes" shape rather than a parallel cache is what
## lets the snow frame share _piece_cache/_scaled_cache with every other
## piece -- a wood asking for the same handful of scaled snow crowns is
## exactly the case those caches already exist for.
const SNOW_CANOPY_KEY := "snow"


## A sliced piece as a trimmed Image, fetched from the GPU once and kept.
func _piece_image(species_id: String, season: String, role: String) -> Image:
	var key := "%s/%s/%s" % [species_id, season, role]
	if _piece_cache.has(key):
		return _piece_cache[key]
	var art := IllustratedTree.new()
	var texture: Texture2D
	if role == "trunk":
		texture = art.trunk_for(species_id)
	elif season == SNOW_CANOPY_KEY:
		texture = art.snow_canopy_for(species_id)
	else:
		texture = art.canopy_for(species_id, season)
	var image: Image = null
	if texture != null:
		image = _trimmed(texture.get_image())
	_piece_cache[key] = image
	return image


## The same piece scaled to a given box, kept because neighbouring trees keep
## asking for the same handful of sizes.
func _scaled_piece(species_id: String, season: String, role: String, size: Vector2i) -> Image:
	var key := "%s/%s/%s/%dx%d" % [species_id, season, role, size.x, size.y]
	if _scaled_cache.has(key):
		return _scaled_cache[key]
	var source := _piece_image(species_id, season, role)
	var scaled: Image = null
	if source != null and size.x > 0 and size.y > 0:
		scaled = scale_piece(source, size)
		if role == "trunk":
			# Only the trunk gets root-flare art squeezed sideways into a box
			# far narrower than the source drawing -- the canopy and fruit
			# pieces are scaled close to their own aspect and have no
			# equivalent gap to close.
			scaled = close_enclosed_gaps(scaled)
	_scaled_cache[key] = scaled
	return scaled


## A piece of tree art scaled to `size`, NEAREST-NEIGHBOUR.
##
## Nearest can only copy pixels, so the result's palette is a subset of the
## source's and every pixel is opaque or absent. Lanczos, which this used, blends
## neighbours -- inventing in-between colours and part-transparent edges. On a
## dense summer canopy that hides; on BARE WINTER BRANCHES, thin high-contrast
## strokes on transparency, it reads as smeared and haloed twigs (reported: the
## winter trees look blurry).
##
## The rest of the game is nearest-neighbour pixel art -- the project sets
## default_texture_filter to nearest -- so resampling the source art smoothly
## was contradicting the house style everywhere else honours.
static func scale_piece(source: Image, size: Vector2i) -> Image:
	var scaled := source.duplicate()
	scaled.resize(size.x, size.y, Image.INTERPOLATE_NEAREST)
	return scaled


## A trunk reads as one solid piece of wood, not two objects with a sliver of
## background showing between them.
##
## Squeezing a wide root-flare drawing sideways into the trunk's own narrow
## box (see illustrated_trunk_box) can land a real gap between two separate
## root "toes" of the source art on the box's own centre column. For the
## walnut sheet specifically that centre column IS a genuine gap in the art,
## so every walnut tree sampled there came out fully transparent (reported as
## a missing trunk).
##
## Any transparent run flanked by opaque pixels on BOTH sides in the same row
## is enclosed by the trunk itself rather than open to the background, so it
## is filled -- the same "petals are not windows" reasoning flora.md already
## applies to line-art holes, just row-wise instead of a full flood fill: a
## trunk's gaps run sideways between root legs, not as pockets needing 2D
## reachability.
static func close_enclosed_gaps(image: Image) -> Image:
	# Image.duplicate() returns an untyped Variant, not Image -- ":=" would
	# infer `result` as Variant and every downstream ":=" off it (width,
	# fill_color, pixel) then fails to infer a type at all. Annotated
	# explicitly instead (see the project's other typed-Variant gotchas).
	var result: Image = image.duplicate()
	var width := result.get_width()
	for y in result.get_height():
		var left := -1
		var right := -1
		for x in width:
			if result.get_pixel(x, y).a > 0.05:
				if left < 0:
					left = x
				right = x
		if left < 0:
			continue  # an entirely empty row -- nothing to close
		var fill_color := result.get_pixel(left, y)
		for x in range(left, right + 1):
			var pixel := result.get_pixel(x, y)
			if pixel.a > 0.05:
				fill_color = pixel
			else:
				result.set_pixel(x, y, fill_color)
	return result


func _composite_illustrated(
	species_id: String,
	seed_value: int,
	ripe_count: int,
	season: String,
	turning_into: String = "",
	turn_progress: float = 0.0,
	growth: float = 1.0,
	snow_coverage: float = 0.0
) -> Image:
	var image := Image.create(SIZE.x, SIZE.y, false, Image.FORMAT_RGBA8)
	var art := IllustratedTree.new()

	# Trunk: stretched to real proportions rather than kept square, and
	# standing on the bottom edge of the canvas.
	var trunk_box := illustrated_trunk_box(seed_value)
	var trunk_image := _scaled_piece(species_id, season, "trunk", trunk_box.size)
	if trunk_image != null:
		_blend_at(image, trunk_image, trunk_box.position.x, trunk_box.position.y)

	# Canopy: anchored to the trunk, overlapping its top.
	var canopy_box := illustrated_canopy_box(species_id, seed_value, season)
	var turning: bool = (
		turning_into != "" and turning_into != season and turn_progress > 0.0
	)
	if turning:
		# The CROWN ITSELF changes size across a turn -- a bare winter crown is
		# smaller than a summer one -- so the box is interpolated too. Without
		# it a finished turn is the new art in the old season's box, which is
		# not the same picture as that season's tree: the crown would pop at
		# the moment the season arrived, which is exactly the jump this whole
		# feature exists to remove.
		canopy_box = _blend_boxes(
			canopy_box,
			illustrated_canopy_box(species_id, seed_value, turning_into),
			turn_progress
		)
	var canopy_image := _scaled_piece(species_id, season, "canopy", canopy_box.size)
	if turning:
		var into_image := _scaled_piece(species_id, turning_into, "canopy", canopy_box.size)
		if into_image != null and canopy_image != null:
			canopy_image = _turned_canopy(
				canopy_image, into_image, turn_progress, tree_variant_for(seed_value)
			)
		elif into_image != null:
			canopy_image = into_image
	# A young tree has FEWER BRANCHES, not a smaller picture.
	#
	# Growth used to scale the whole node down, so a sapling was a full-grown
	# tree in miniature -- crown, boughs and every twig. A real young tree puts
	# out its inner branches first and its twigs later, which is the same trace
	# the season turn already walks.
	if canopy_image != null and growth < 1.0:
		canopy_image = _grown_canopy(canopy_image, growth, tree_variant_for(seed_value))

	# Snow: layered ON TOP of whatever season/turn/growth already drew, not
	# instead of it -- a live-weather fact, not another phenology stage (see
	# IllustratedTree.CANOPY_SNOW's own doc comment). Reuses the SAME
	# branch-order blend the season turn uses (_turned_canopy): this is a
	# reuse of the existing per-tree branch-order variance, not a new blend
	# mechanism, which is why two trees show snow on different boughs at the
	# same coverage. Gated on has_snow_frame_for so a species without this
	# frame renders identically whatever snow_coverage is -- the fallback
	# contract for every species that has not gained one yet.
	if canopy_image != null and snow_coverage > 0.0 and art.has_snow_frame_for(species_id):
		var snow_image := _scaled_piece(species_id, SNOW_CANOPY_KEY, "canopy", canopy_box.size)
		if snow_image != null:
			canopy_image = _turned_canopy(
				canopy_image, snow_image, snow_level(snow_coverage), tree_variant_for(seed_value)
			)
	if canopy_image != null:
		_blend_at(image, canopy_image, canopy_box.position.x, canopy_box.position.y)

	if ripe_count > 0:
		_blend_illustrated_fruit(image, art, species_id, seed_value, ripe_count, canopy_box)
	return image


## Scatters fruit across the canopy's actual painted area.
##
## Positions come from the tree's own seed and are the SAME for every crop
## size, so the Nth fruit is always in the same place: a growing crop lights up
## more fruit rather than rearranging what is already there.
##
## Scattered within the canopy's rect rather than an invented ellipse -- placed
## against the frame rectangle instead, most of a crop fell outside the foliage.
func _blend_illustrated_fruit(
	image: Image, art, species_id: String, seed_value: int, ripe_count: int, canopy: Rect2i
) -> void:
	var variant := tree_variant_for(seed_value)
	var fruit_width := maxi(2, int(float(SIZE.x) * ILLUSTRATED_FRUIT_WIDTH_FRAC))
	var fruit_image := _scaled_fruit(art, species_id, fruit_width)
	if fruit_image == null:
		return
	# Placed in the FOLIAGE, not across the canopy box. The box reaches well
	# down over the trunk so the two overlap (see TRUNK_OVERLAP_FRAC), and
	# scattering across all of it dropped most of the crop onto the trunk.
	var center := Vector2(
		float(canopy.position.x) + float(canopy.size.x) * 0.5,
		float(canopy.position.y) + float(canopy.size.y) * FRUIT_CENTER_FRAC
	)
	var radius_x := float(canopy.size.x) * FRUIT_SPREAD_FRAC
	var radius_y := float(canopy.size.y) * FRUIT_SPREAD_FRAC
	for index in mini(ripe_count, ILLUSTRATED_MAX_FRUIT):
		# PixelNoise, not hash("..._fruit_N").
		#
		# Godot's string hash is near-LINEAR across inputs that differ only in
		# a trailing number, so consecutive fruit came out at consecutive
		# angles and distances: measured, all eight of a crop landed within a
		# tenth of a pixel of each other and read as one berry stuck to the
		# tree. This project has hit the same banding before, in terrain, which
		# is what PixelNoise exists for.
		# Shared with fruit_ground_offset, so where a fruit is DRAWN and where
		# it LANDS cannot drift apart.
		var polar := fruit_polar(variant, index)
		var at := Vector2(
			center.x + cos(polar.x) * radius_x * polar.y,
			center.y + sin(polar.x) * radius_y * polar.y
		)
		_blend_at(
			image,
			fruit_image,
			int(at.x) - fruit_image.get_width() / 2,
			int(at.y) - fruit_image.get_height() / 2
		)


## Where fruit `index` hangs on a tree of this `variant`, as (angle, distance):
## a bearing in radians and a fraction of the crown's radius.
##
## ONE definition, used both to draw the fruit and to decide where it lands.
## Those used to be unrelated -- the canopy scattered fruit from this noise and
## the ground scattered windfall from a different hash entirely -- so a fallen
## cherry landed somewhere with no relation to where it had been hanging, which
## makes it a new cherry rather than the one that was on the tree (reported).
##
## PixelNoise, not hash("..._fruit_N"). Godot's string hash is near-LINEAR
## across inputs differing only in a trailing number, so consecutive fruit came
## out at consecutive angles and distances: measured, all eight of a crop landed
## within a tenth of a pixel of each other and read as one berry stuck to the
## tree. This project has hit the same banding in terrain, which is what
## PixelNoise exists for.
static func fruit_polar(variant: int, index: int) -> Vector2:
	var angle := float(PixelNoise.range_index(variant, 100 + index * 2, 0, 360)) * PI / 180.0
	# Square-rooted so fruit spreads evenly through the crown instead of
	# clustering at its middle.
	var distance := sqrt(float(PixelNoise.range_index(variant, 101 + index * 2, 0, 100)) / 100.0)
	return Vector2(angle, distance)


## How far a fruit hanging out at the crown's edge lands from the trunk, in
## world pixels. A fruit falls roughly straight down, so this is the reach of
## the crown rather than a throw.
const FRUIT_GROUND_REACH := 18.0


## Where fruit `index` lands when it leaves the tree, relative to the trunk.
##
## The same bearing it hung at, carried down to the ground -- so it lands under
## itself. The vertical part is small: fruit lies just in front of the trunk so
## it is not hidden behind it.
static func fruit_ground_offset(variant: int, index: int) -> Vector2:
	var polar := fruit_polar(variant, index)
	return Vector2(
		cos(polar.x) * polar.y * FRUIT_GROUND_REACH,
		absf(sin(polar.x)) * polar.y * FRUIT_GROUND_REACH * 0.35
	)


## The ripe fruit, trimmed and scaled once. Same reason as the other pieces:
## it never changes, and fetching it back from the GPU per tree is what made a
## forest freeze.
static var _fruit_cache := {}


func _scaled_fruit(art, species_id: String, width: int) -> Image:
	var key := "%s/%d" % [species_id, width]
	if _fruit_cache.has(key):
		return _fruit_cache[key]
	var fruit: Texture2D = art.fruit_for(species_id, true)
	var scaled: Image = null
	if fruit != null:
		scaled = _fit_width(_trimmed(fruit.get_image()), width)
	_fruit_cache[key] = scaled
	return scaled


## One box partway to another, so a crown changes size across a turn rather
## than popping at the end of it.
func _blend_boxes(from_box: Rect2i, into_box: Rect2i, progress: float) -> Rect2i:
	var t := clampf(progress, 0.0, 1.0)
	return Rect2i(
		int(round(lerpf(float(from_box.position.x), float(into_box.position.x), t))),
		int(round(lerpf(float(from_box.position.y), float(into_box.position.y), t))),
		maxi(1, int(round(lerpf(float(from_box.size.x), float(into_box.size.x), t)))),
		maxi(1, int(round(lerpf(float(from_box.size.y), float(into_box.size.y), t))))
	)


## How many distinct growth stages a canopy is drawn in.
##
## Quantised for exactly the reason the season turn is: every distinct value is
## a whole tree picture to composite and cache, and a continuous one would mean
## a new image per frame per sapling.
const GROWTH_LEVELS := 6


static func growth_level(growth: float) -> float:
	return ceilf(clampf(growth, 0.0, 1.0) * float(GROWTH_LEVELS)) / float(GROWTH_LEVELS)


## ## Snow: a live-weather overlay, not a season
##
## How much of a canopy is under snow is not one of the four season frames --
## it is a live fact about the weather (see IllustratedTree.CANOPY_SNOW's own
## doc comment), pushed in continuously as lying snow accumulates or thaws.
## Left unquantised it would mean a new tree picture every time snow depth
## ticked by a fraction of a percent -- exactly the "one image per frame"
## cost GROWTH_LEVELS/SeasonTransition.TURN_STEPS already exist to avoid.
##
## Quantised to the same granularity the GROUND's own lying snow steps
## through, so a canopy's snow response is exactly as coarse or fine as the
## snow already lying at its own foot and the two can never visibly disagree
## about how gradually a snowfall settles in.
##
## STOPGAP, unrelated to this file's own change history: this used to read
## `SnowLayer.DEPTH_BANDS`, but `src/rendering/snow_layer.gd` was deleted when
## the GPU texture-bombing shader replaced it (SnowBombShader/SnowStampAtlas,
## see docs/progress.md), which this file's own canopy-snow work never picked
## up -- confirmed broken on `origin/main` right now, not something this
## worktree caused (`git show origin/main:src/rendering/procedural_tree_
## sprite.gd` still preloads the deleted file), and it parse-errors every GUT
## run project-wide since GUT parses every script under tests/unit regardless
## of which test file is selected. Inlined at 10, `SnowLayer.DEPTH_BANDS`'s
## own last real value before deletion (`git show fc646e2^:src/rendering/
## snow_layer.gd`), rather than invented, so canopy snow keeps its exact
## existing granularity unchanged. The real fix -- wiring this to whatever
## depth signal the new GPU snow system exposes, if any -- is a separate,
## dedicated follow-up, not a one-line guess made in passing here.
const SNOW_LEVELS := 10


## The snow coverage LEVEL a tree draws at -- used both for the texture cache
## key (see generate_texture_with_fruit) and as the actual blend progress
## (see _composite_illustrated), so the two can never drift apart. Rounded UP
## like growth_level: a barely-dusted crown should show something rather than
## wait for a whole step to complete.
static func snow_level(coverage: float) -> float:
	return ceilf(clampf(coverage, 0.0, 1.0) * float(SNOW_LEVELS)) / float(SNOW_LEVELS)


## How much of a GROWING canopy's order comes from the branch trace rather than
## from clump noise.
##
## Much higher than the season turn's even split, and for a reason the turn does
## not share. A turn colours leaves individually all over a tree, so scattered
## clumps are what it should look like. Growth is not scattered: a sapling's
## crown is attached to its trunk and works outward. At the turn's 0.5 a young
## tree came out as confetti -- leaf specks strewn over the whole mature crown
## box, floating clear of the trunk with a gap beneath them.
##
## Kept below 1.0 so the crown is not purely a function of the shared art:
## the trace carries per-tree jitter, and this last slice of noise keeps two
## saplings of the same species visibly apart.
const GROWTH_BRANCH_WEIGHT := 0.85


## The least of a canopy a seedling shows. Something, rather than a bare stick:
## a shoot with a few leaves on it is a young tree, and nothing at all is a
## rendering fault.
const SEEDLING_CANOPY := 0.12


## `canopy` pruned back to the branches a tree of this growth has put out.
##
## Traced outward from where the crown meets the trunk, so the inner boughs
## come first and the twigs last -- and randomised per tree, so a nursery is
## not one sapling drawn many times.
func _grown_canopy(canopy: Image, growth: float, variant: int) -> Image:
	var reach := lerpf(SEEDLING_CANOPY, 1.0, clampf(growth_level(growth), 0.0, 1.0))
	var order := growth_order(canopy, variant)
	var width := canopy.get_width()
	var height := canopy.get_height()
	var result := Image.create(width, height, false, Image.FORMAT_RGBA8)
	for y in height:
		for x in width:
			var at := Vector2i(x, y)
			var along: float = order.get(at, 0.0)
			# The same clump draw the turn uses, so a growing tree fills out in
			# tufts rather than as a clean advancing front.
			var clump := float(PixelNoise.range_index(
				(x / CLUMP_PX) * 733 + (y / CLUMP_PX), 251 + variant * 17, 0, 1000
			)) / 1000.0
			var rank := (
				along * GROWTH_BRANCH_WEIGHT + clump * (1.0 - GROWTH_BRANCH_WEIGHT)
			)
			if rank <= reach:
				result.set_pixel(x, y, canopy.get_pixel(x, y))
	return result


## How ragged the boundary of a turn is.
##
## A clean contour sweeping across a canopy looks like a wipe, and leaves do
## not turn in a neat arc. Mixed into the ordering so the edge breaks up into
## individual twigs.
const TURN_JITTER := 0.18


## `from_image` with `progress` of it replaced by `into_image`, spreading
## outward from where the canopy meets the trunk.
##
## Outward, so the change runs along the branches to the twigs rather than
## speckling the crown at random -- that is what makes it read as a tree
## turning rather than as dissolve noise.
##
## Both images are the same size: they come from _scaled_piece at one box, so
## the crown cannot jump or slide partway through a turn.
func _turned_canopy(
	from_image: Image, into_image: Image, progress: float, variant: int = 0
) -> Image:
	var width := from_image.get_width()
	var height := from_image.get_height()
	if into_image.get_width() != width or into_image.get_height() != height:
		return from_image
	var order := _branch_order(into_image, variant)
	var result := Image.create(width, height, false, Image.FORMAT_RGBA8)
	for y in height:
		for x in width:
			var at := Vector2i(x, y)
			# Along the branches, plus this tree's own draw for the clump.
			var along: float = order.get(at, 0.0)
			var clump := float(PixelNoise.range_index(
				(x / CLUMP_PX) * 733 + (y / CLUMP_PX), 191 + variant * 13, 0, 1000
			)) / 1000.0
			var rank := (
				along * BRANCH_ORDER_WEIGHT + clump * (1.0 - BRANCH_ORDER_WEIGHT)
			)
			var turned: bool = rank <= progress
			result.set_pixel(x, y, (into_image if turned else from_image).get_pixel(x, y))
	return result


## How far along the BRANCHES each pixel of a canopy is, 0 at the trunk and 1
## at the outermost twig.
##
## Traced through the drawing itself rather than measured as a straight line:
## a flood spreading only through painted pixels, outward from where the crown
## meets the trunk. So the order follows the actual boughs -- a twig at the end
## of a long branch ranks late even if it hangs near the trunk in a straight
## line, which is what "along the branches" means and what a radial distance
## cannot express.
##
## Randomised per tree: the cost of reaching a pixel is nudged by the tree's
## own variant, so two trees of the same species turn in different orders and
## a wood does not change as one animation.
const BRANCH_STEP_JITTER := 0.15

## How wide a leaf CLUMP is, in pixels of the drawn crown.
##
## The turn flips clumps, not pixels: a whole tuft of leaves goes at once,
## which is how a real canopy turns and what stops the boundary looking like a
## gradient sweeping across the tree. Two pixels is a tuft at this size.
const CLUMP_PX := 2

## How much of a pixel's turn order comes from its place along the BRANCHES
## versus from its clump's own draw.
##
## Structure alone made every tree of a species turn identically -- the trace
## is a property of the crown art, so it is the same for every tree using it.
## Clump noise alone is a dissolve with no tree in it. Half and half keeps the
## turn moving broadly outward along the boughs while individual tufts go in an
## order that is this tree's own.
const BRANCH_ORDER_WEIGHT := 0.5


## The order the season turn walks a crown in: inward from the whole bottom
## edge, where the boughs leave the trunk.
func _branch_order(canopy: Image, variant: int) -> Dictionary:
	return _trace_order(canopy, variant, "turn", _rim_seeds(canopy))


## The order a crown GROWS in: outward from the single point where the trunk
## meets it.
##
## Not the same seeding as the turn, and the difference matters. The turn starts
## from the whole bottom EDGE of the crown, which for a spreading crown is the
## drooping outer rim -- so growth seeded that way drew a young cherry as an arch
## hanging in the air, with a gap between it and the trunk. A young tree is the
## opposite shape: a tuft at the trunk that spreads outward, tips last.
func growth_order(canopy: Image, variant: int) -> Dictionary:
	return _trace_order(canopy, variant, "growth", _trunk_seeds(canopy))


## Painted pixels along the bottom edge of the crown.
func _rim_seeds(canopy: Image) -> Array[Vector2i]:
	var seeds: Array[Vector2i] = []
	var height := canopy.get_height()
	for x in canopy.get_width():
		for y in range(height - 1, maxi(height - 3, 0) - 1, -1):
			if canopy.get_pixel(x, y).a > ALPHA_PAINTED:
				seeds.append(Vector2i(x, y))
	return seeds


## The painted pixel nearest where the trunk meets the crown -- the middle of
## the crown's bottom edge.
##
## A crown hollow in the middle (an arch) has nothing painted at the anchor
## itself, so the nearest paint to it is taken instead: for an arch that is the
## span directly above the trunk, which is exactly where a young tree's leaves
## belong.
func _trunk_seeds(canopy: Image) -> Array[Vector2i]:
	var width := canopy.get_width()
	var centre := width / 2
	# The trunk is narrow, so only the middle of the crown counts as "above the
	# trunk" -- and within that band the LOWEST paint is the join.
	var band := maxi(width / 8, 1)
	var best := Vector2i.ZERO
	var found := false
	for x in range(maxi(centre - band, 0), mini(centre + band + 1, width)):
		for y in range(canopy.get_height() - 1, -1, -1):
			if canopy.get_pixel(x, y).a <= ALPHA_PAINTED:
				continue
			if not found or y > best.y or (y == best.y and absi(x - centre) < absi(best.x - centre)):
				best = Vector2i(x, y)
				found = true
			break
	if not found:
		# Nothing above the trunk at all: fall back to whatever paint is nearest
		# the join, so the trace still starts somewhere sensible.
		var anchor := Vector2(float(width) * 0.5, float(canopy.get_height()) - 1.0)
		var best_distance := INF
		for y in canopy.get_height():
			for x in width:
				if canopy.get_pixel(x, y).a <= ALPHA_PAINTED:
					continue
				var distance := anchor.distance_to(Vector2(float(x), float(y)))
				if distance < best_distance:
					best_distance = distance
					best = Vector2i(x, y)
					found = true
	if not found:
		return []
	var seeds: Array[Vector2i] = [best]
	return seeds


## How opaque a canopy pixel has to be to count as branch rather than air.
const ALPHA_PAINTED := 0.4


## Geodesic distance through the crown's painted pixels from `seeds`,
## normalised to 0..1.
func _trace_order(
	canopy: Image, variant: int, purpose: String, seeds: Array[Vector2i]
) -> Dictionary:
	# Keyed by the crown's own bytes, so two seasons' crowns of the same size
	# do not share a trace -- a bare winter crown and a summer one are very
	# different shapes to walk along -- and by purpose, since growth and the
	# turn walk the same crown from different starts.
	var key := "%s/%d/%d/%d/%d" % [
		purpose, canopy.get_width(), canopy.get_height(), variant, hash(canopy.get_data())
	]
	if _order_cache.has(key):
		return _order_cache[key]

	var width := canopy.get_width()
	var height := canopy.get_height()
	var cost := {}
	var queue: Array[Vector2i] = []
	for at in seeds:
		cost[at] = 0.0
		queue.append(at)
	if queue.is_empty():
		# A crown that touches nothing: fall back to the topmost painted row so
		# the trace still has somewhere to start.
		for x in width:
			for y in height:
				if canopy.get_pixel(x, y).a > ALPHA_PAINTED:
					cost[Vector2i(x, y)] = 0.0
					queue.append(Vector2i(x, y))
					break

	var furthest := 0.0
	var head := 0
	while head < queue.size():
		var at: Vector2i = queue[head]
		head += 1
		var here: float = cost[at]
		furthest = maxf(furthest, here)
		for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var next: Vector2i = at + step
			if next.x < 0 or next.y < 0 or next.x >= width or next.y >= height:
				continue
			if cost.has(next) or canopy.get_pixel(next.x, next.y).a <= ALPHA_PAINTED:
				continue
			# Each step costs a little more or less depending on the tree, so
			# the same crown fills in a different order per variant.
			var jitter := (
				float(PixelNoise.range_index(next.x * 131 + next.y, 149 + variant, 0, 1000))
				/ 1000.0
			) * BRANCH_STEP_JITTER
			cost[next] = here + 1.0 + jitter
			queue.append(next)

	var order := {}
	for at in cost:
		order[at] = float(cost[at]) / maxf(furthest, 1.0)
	_order_cache[key] = order
	return order


## Branch orders, keyed by the crown they were traced from. A wood asks for the
## same handful of crowns over and over.
static var _order_cache := {}


## Crops a frame down to its painted content.
##
## The sheets carry transparent padding around the drawing, and the amount
## differs per frame -- the bare winter canopy is much smaller than the summer
## one. Positioning a frame by its RECTANGLE therefore positions the padding
## rather than the tree, which left the canopy hanging in the air above the
## trunk. Everything is placed by content instead.
func _trimmed(source: Image) -> Image:
	var used := source.get_used_rect()
	if used.size.x <= 0 or used.size.y <= 0:
		return source
	return source.get_region(used)


## Scales an image to a target HEIGHT, keeping its proportions.
func _fit(source: Image, target_height: int) -> Image:
	var scaled := source.duplicate()
	var width := maxi(1, int(round(
		float(source.get_width()) * float(target_height) / float(source.get_height())
	)))
	scaled.resize(width, maxi(1, target_height), Image.INTERPOLATE_LANCZOS)
	return scaled


## Scales an image to a target WIDTH, keeping its proportions.
func _fit_width(source: Image, target_width: int) -> Image:
	var scaled := source.duplicate()
	var height := maxi(1, int(round(
		float(source.get_height()) * float(target_width) / float(source.get_width())
	)))
	scaled.resize(maxi(1, target_width), height, Image.INTERPOLATE_LANCZOS)
	return scaled


func _blend_centered(image: Image, source: Image, top: int) -> void:
	_blend_at(image, source, (SIZE.x - source.get_width()) / 2, top)


## Blends `source` onto `image` at (left, top), clipped to the canvas.
##
## Clipped rather than assumed to fit: a canopy is deliberately drawn wider
## than the canvas in places, and a fruit near the edge of the crown hangs off
## it. blend_rect would silently skip a rect that does not fit entirely.
func _blend_at(image: Image, source: Image, left: int, top: int) -> void:
	for y in source.get_height():
		var target_y := top + y
		if target_y < 0 or target_y >= SIZE.y:
			continue
		for x in source.get_width():
			var target_x := left + x
			if target_x < 0 or target_x >= SIZE.x:
				continue
			var pixel := source.get_pixel(x, y)
			if pixel.a < 0.05:
				continue
			var under := image.get_pixel(target_x, target_y)
			image.set_pixel(target_x, target_y, under.blend(pixel))
