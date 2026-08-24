extends RefCounted

## Deterministic offline pixel-art for terrain tiles, matching the same
## technique used elsewhere (ProceduralItemSprite/ProceduralSpriteGenerator/
## ProceduralTreeSprite): a base color speckled with texture, seeded so the
## same (biome, variant_seed) always produces the same tile but different
## variant_seeds give visibly different-looking tiles of the same biome --
## TerrainRenderer picks a variant per tile position so the ground doesn't
## read as one obviously-repeating texture.

## 4x the original 16px tile (see docs/concept/art_resolution.md) -- every
## feature-level constant below (blade height, moss blob size, foam band
## width, ...) scales in step so the tile's composition stays the same,
## just genuinely more detailed: independent per-pixel speckle noise across
## 4x the pixels, not the old 16x16 art stretched larger (pinned by
## test_speckled_texture_has_genuine_per_pixel_detail_not_upscaled_blocks).
const PixelNoise = preload("res://src/rendering/pixel_noise.gd")

const SIZE := 64

## Frames per animated tile (see generate_frame_image and TerrainRenderer's
## animated atlas blocks). Every animated pattern is designed to loop
## seamlessly with exactly this period: water streaks scroll one row per frame
## against their 4-row spacing, and grass tuft sway cycles [0, 1, 0, -1].
## Static biomes return identical frames -- same pipeline, no visible churn.
const FRAME_COUNT := 4

## Brighter, more saturated Zelda/Pokemon-overworld palette. Relationships are
## preserved -- grassland vivid green, forest a deeper green, ocean vivid blue,
## desert sandy, mountain/tundra neutral -- just pushed toward higher HSV
## saturation and a touch more value so the ground reads like a bright route
## rather than a muddy field.
const BASE_COLORS := {
	"grassland": Color(0.36, 0.74, 0.22),
	"forest": Color(0.11, 0.5, 0.15),
	"ocean": Color(0.1, 0.42, 0.85),
	"mountain": Color(0.52, 0.52, 0.56),
	"tundra": Color(0.85, 0.9, 0.93),
	"rainforest": Color(0.05, 0.42, 0.12),
	"desert": Color(0.92, 0.78, 0.38),
}
const _FALLBACK_COLOR := Color(0.5, 0.5, 0.5)

## Terrain has no "shape" family the way items do -- every biome is textured
## as an all-over marked fill, with per-biome detail layered on top. Water
## instead gets horizontal wave streaks.
##
## ## Marks, not static
##
## This was INDEPENDENT per-pixel noise at 35% density: a third of every
## tile's pixels randomly darkened or lightened, each one rolled on its own.
## Measured, the tile changed appearance at 65% of neighbouring pixel pairs --
## worse than a coin flip, i.e. the tile was mostly high-frequency noise. That
## is precisely what "coarse and grainy" is, and the old non-pixel-perfect
## fullscreen upscale (see DisplayScaling) made it shimmer on top.
##
## Real pixel-art ground is made of deliberate MARKS -- small clumps and
## dashes -- with clean ground showing between them. So the roll is taken
## from a COARSER grid than the pixel: SPECKLE_CLUSTER-sized cells decide
## most of the value, and a per-pixel roll contributes the rest, which ragged
## the edges of each mark so nothing reads as painted in blocks. Density
## drops too, because the point of texture is the clean ground it sits on.
##
## Pinned from three sides: the transition rate must stay low
## (test_ground_marks_clump_together_instead_of_speckling_at_random), clean
## ground must stay in the majority (test_clean_ground_shows_between_the_marks),
## and mark edges must still land on odd pixels
## (test_marks_still_have_per_pixel_ragged_edges).
const SPECKLE_DENSITY := 0.24
const SPECKLE_DARKEN := 0.18
const SPECKLE_LIGHTEN := 0.12
## How many pixels across one mark's cell is, and how much of the roll that
## cell decides versus the per-pixel roll that frays its edge.
const SPECKLE_CLUSTER := 2
const SPECKLE_CLUSTER_WEIGHT := 0.8


func generate_texture(biome_name: String, variant_seed: int) -> ImageTexture:
	return ImageTexture.create_from_image(generate_image(biome_name, variant_seed))


func generate_image(biome_name: String, variant_seed: int) -> Image:
	return generate_frame_image(biome_name, variant_seed, 0)


## One frame of a biome tile's real-time animation cycle (see FRAME_COUNT).
## Every biome layers detail over its base speckle -- grass tufts + flowers on
## grassland, moss on forest floors, dune ripples on desert, stones on tundra,
## cracks on mountain -- and the living biomes animate: water streaks scroll,
## grass tufts sway. `frame` wraps, so frame FRAME_COUNT == frame 0 exactly
## (seamless loop, pinned by test_ocean_frames_differ_and_loop_seamlessly).
func generate_frame_image(biome_name: String, variant_seed: int, frame: int) -> Image:
	var wrapped_frame := posmod(frame, FRAME_COUNT)
	var base_color: Color = BASE_COLORS.get(biome_name, _FALLBACK_COLOR)
	var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)

	match biome_name:
		"ocean":
			_paint_water(image, base_color, variant_seed, wrapped_frame)
		"grassland":
			_paint_speckled(image, base_color, variant_seed)
			# Baked blades are STATIC by design: 4 tile frames can only make a
			# 1px tip jump, which reads as flicker, never as wind (reported
			# twice). They freeze as varied windswept ground detail. The GPU
			# blade field that used to carry the real swaying motion was
			# removed (flat, non-interactive 1px rectangles, no real shape) --
			# a real, illustrated decorative grass layer is expected to
			# replace it.
			_paint_grass_blades(image, base_color, variant_seed, 0)
			# No baked flower dots: real flowers are entities now (see
			# FlowerPatch/ProceduralFlowerSprite). The old painted specks read
			# as flowers you could never pick or smell.
		"forest", "rainforest":
			_paint_speckled(image, base_color, variant_seed)
			_paint_moss(image, base_color, variant_seed)
		"desert":
			_paint_speckled(image, base_color, variant_seed)
			_paint_dune_ripples(image, base_color, variant_seed)
		"tundra":
			_paint_speckled(image, base_color, variant_seed)
			_paint_scatter(image, base_color.darkened(0.28), variant_seed, "stones", 5)
		"mountain":
			_paint_speckled(image, base_color, variant_seed)
			_paint_cracks(image, base_color, variant_seed)
		_:
			_paint_speckled(image, base_color, variant_seed)

	return image


## An all-over speckled fill: each pixel independently rolls slightly
## lighter/darker/unchanged from the base color, seeded by (variant_seed, x,
## y) so it's fully deterministic but different variant_seeds look distinct.
func _paint_speckled(image: Image, base_color: Color, variant_seed: int) -> void:
	for y in SIZE:
		for x in SIZE:
			var roll := _speckle_roll(variant_seed, x, y)
			var color := base_color
			if roll < SPECKLE_DENSITY * 0.5:
				color = base_color.darkened(SPECKLE_DARKEN)
			elif roll < SPECKLE_DENSITY:
				color = base_color.lightened(SPECKLE_LIGHTEN)
			image.set_pixel(x, y, color)


## Base (baked-tile) water: a noisy two-tone surface with short diagonal wind
## glints that DRIFT sideways one pixel per frame -- choppy, wind-blown water,
## not raindrops. Glint drift wraps modulo SIZE, so the cycle loops
## seamlessly. This is only the STATIC layer now: the GPU WaterFx overlay
## (water_shader.gd) draws the continuous waves, shore reflection, and
## raindrop ripples on top at partial alpha, so this tile's job is just to
## give the water a believable base tint/texture underneath -- shore
## blending and rain both moved entirely to the overlay (see
## TerrainRenderer.build_water_overlay_tile_set). Scaled 4x in step with
## SIZE (see docs/concept/art_resolution.md) so glint density per visible
## tile area stays the same as before the resolution pass.
const WIND_GLINT_COUNT := 20


func _paint_water(image: Image, base_color: Color, variant_seed: int, frame: int = 0) -> void:
	for y in SIZE:
		for x in SIZE:
			var roll := _fraction(variant_seed, x, y, "chop")
			var color := base_color
			if roll < SPECKLE_DENSITY * 0.55:
				color = base_color.darkened(SPECKLE_DARKEN * 0.8)
			elif roll > 1.0 - SPECKLE_DENSITY * 0.25:
				color = base_color.lightened(SPECKLE_LIGHTEN * 0.7)
			image.set_pixel(x, y, color)

	# Wind-on-water reads as three layered motions, all seamless over the
	# wrapped frame cycle: bright wave crests drifting with the wind (varied
	# lengths, occasionally twinkling out as a crest collapses), each with a
	# dimmer trailing pixel so it reads as a crescent rather than a bar, and
	# dark troughs counter-drifting beneath -- the surface shears instead of
	# sliding as one sheet.
	var wrapped := posmod(frame, FRAME_COUNT)
	var glint_color := base_color.lightened(0.3)
	var glint_soft := base_color.lightened(0.15)
	for i in WIND_GLINT_COUNT:
		var h := absi(hash("%d_glint_%d" % [variant_seed, i]))
		if (h / 501 + wrapped) % 5 == 0:
			continue  # this crest collapses for one frame -- twinkle
		var gy := h % SIZE
		var gx := (h / 37 + wrapped) % SIZE
		var length := 8 + (h / 211) % 9
		for k in length:
			image.set_pixel((gx + k) % SIZE, clampi(gy - (k / 2), 0, SIZE - 1), glint_color)
		image.set_pixel(gx, clampi(gy + 1, 0, SIZE - 1), glint_soft)
	var trough_color := base_color.darkened(0.22)
	for i in 16:
		var h := absi(hash("%d_trough_%d" % [variant_seed, i]))
		var ty := h % SIZE
		var tx := posmod(h / 41 - wrapped, SIZE)
		for k in 12:
			image.set_pixel((tx + k) % SIZE, ty, trough_color)


## Individual grass blades: BLADE_COUNT per tile, each with its own
## hash-derived position, height (8-16px -- 4x the original 2-4px, see
## docs/concept/art_resolution.md), color (3 green tones), and sway phase
## (see blade_spec -- the pure, tested core). Blades bend progressively in
## the wind: the root stays planted, the tip carries the full lean cycle,
## mid pixels bend halfway -- so grass reads as living blades rather than
## stamped tufts. BLADE_COUNT scales with the tile's linear resolution (4x),
## not its area, so blades stay individually legible instead of crowding.
## Enough blades that a tile reads as a dense meadow rather than a few
## strokes on a flat field (reported: "the grass tiles don't look nice
## anymore... make it look more like real grass blades"). A 64px tile has
## the room for a real population -- pinned by
## test_grassland_is_densely_covered_in_blades.
const BLADE_COUNT := 52
## Tip lean per animation frame, in px -- 4x the original [0,2,1,-2] so the
## sway stays proportional to the taller blade (still wraps seamlessly over
## FRAME_COUNT).
const _TUFT_SWAY := [0, 8, 4, -8]
## A blade's width at its root, tapering to 1px at the tip (see
## blade_width_at). A uniform-width stroke reads as a painted stripe; real
## grass is widest where it leaves the ground.
const BLADE_ROOT_WIDTH := 3
## How sharply a blade curves: the lean grows with this power of the
## root->tip fraction, so the root stays planted and the bend accelerates
## toward the tip (a curve, not a straight diagonal -- see
## blade_curve_fraction).
const BLADE_CURVE_POWER := 2.0


## How many pixels wide a blade is at `t` along its length (0 = root,
## 1 = tip) -- linear taper from BLADE_ROOT_WIDTH down to a 1px tip.
func blade_width_at(t: float) -> int:
	return maxi(1, int(round(lerp(float(BLADE_ROOT_WIDTH), 1.0, clampf(t, 0.0, 1.0)))))


## How much of a blade's full tip-lean applies at `t` along its length
## (0 = root, 1 = tip). Non-linear so the blade curves out of the ground
## instead of leaning as a straight line.
func blade_curve_fraction(t: float) -> float:
	return pow(clampf(t, 0.0, 1.0), BLADE_CURVE_POWER)


func blade_spec(variant_seed: int, index: int) -> Dictionary:
	# PixelNoise, not Godot's string hash: hashing "..._0", "..._1", "..._2"
	# correlates badly, so consecutive blades landed beside each other at the
	# same height and their (up to BLADE_ROOT_WIDTH wide, and darkly tinted)
	# strokes merged into solid slabs -- a litter of flat dark-green blocks
	# lying on the grass (reported repeatedly as "green square patches which
	# look horrible"). This is the FIFTH site of that same clustering bug in
	# this project, after village house sizes, tree leaf angles, grass tuft
	# blades and the GPU blade field.
	var h := PixelNoise.value(variant_seed, index, 0)
	return {
		"x": 1 + h % (SIZE - 2),
		# Roots spread over the whole tile (not just its lower band) so the
		# meadow covers the ground evenly rather than banding.
		"base_y": 10 + (h / 53) % (SIZE - 12),
		"height": 8 + (h / 349) % 19,
		"color_index": (h / 1117) % 5,
		"phase": (h / 4111) % FRAME_COUNT,
	}


func _paint_grass_blades(image: Image, base_color: Color, variant_seed: int, frame: int) -> void:
	# Five tones rather than three: deep shade through sunlit highlight plus
	# a dry yellow-green, so overlapping blades read as depth in a meadow
	# instead of one flat green mass.
	var blade_colors := [
		base_color.darkened(0.34),
		base_color.darkened(0.22),
		base_color.darkened(0.1),
		base_color.lightened(0.1),
		Color(base_color.r * 1.06, base_color.g * 0.92, base_color.b * 0.55),  # dry yellow-green
	]
	for i in BLADE_COUNT:
		var spec := blade_spec(variant_seed, i)
		# Frozen per-blade lean (frame is ignored -- see the grassland branch
		# comment): each blade holds its own windswept posture.
		var lean: int = _TUFT_SWAY[spec.phase % _TUFT_SWAY.size()]
		var color: Color = blade_colors[spec.color_index]
		var height: int = spec.height
		for k in height:
			var y: int = spec.base_y - k
			if y < 0:
				break
			var t := float(k) / maxf(height - 1, 1.0)
			var x := clampi(spec.x + int(round(lean * blade_curve_fraction(t))), 0, SIZE - 1)
			# Sun-lit tip so each blade ends crisply, and a tapered width so
			# it reads as a blade rather than a stripe.
			var stroke_color := color.lightened(0.24) if k >= height - 2 else color
			for w in blade_width_at(t):
				var px := clampi(x + w, 0, SIZE - 1)
				image.set_pixel(px, y, stroke_color)


## Occasional flower accents (static -- flowers don't sway): roughly every
## third variant gets 1-2 bright petal clusters, so walking a meadow passes
## little bursts of white/yellow/red among the green. Each petal is a
## _FLOWER_SIZE px square (was a single hairline pixel) so it reads as an
## actual bloom at the new tile resolution instead of a stray fleck.
const _FLOWER_COLORS := [Color(0.95, 0.95, 0.9), Color(0.98, 0.85, 0.25), Color(0.9, 0.3, 0.3)]
const _FLOWER_SIZE := 3


func _paint_flowers(image: Image, variant_seed: int) -> void:
	var h := absi(hash("%d_flowers" % variant_seed))
	if h % 3 != 0:
		return
	var flower_count := 1 + (h / 7) % 2
	for i in flower_count:
		var fh := absi(hash("%d_flower_%d" % [variant_seed, i]))
		var fx := 1 + fh % (SIZE - 2 - _FLOWER_SIZE)
		var fy := 1 + (fh / 61) % (SIZE - 2 - _FLOWER_SIZE)
		var color: Color = _FLOWER_COLORS[(fh / 397) % _FLOWER_COLORS.size()]
		for dy in _FLOWER_SIZE:
			for dx in _FLOWER_SIZE:
				image.set_pixel(fx + dx, fy + dy, color)


## Dark moss/undergrowth patches on forest-floor tiles, so the floor reads as
## layered undergrowth rather than one flat speckle field.
##
## These used to be perfect axis-aligned filled squares, three per tile.
## Across a whole forest that read as a litter of hard green rectangles lying
## on the ground (reported: "there are these green square patches which look
## horrible"). A patch is now a ragged blob: a disc whose rim distance
## wanders per DIRECTION, so the outline is coherently irregular rather than
## either a clean circle or per-pixel static.
const MOSS_PATCH_RADIUS := 5
## How many rim sectors the wobble is sampled over. Few enough that the
## outline reads as a handful of lobes rather than noise.
const MOSS_RIM_SECTORS := 12
## How much of the radius the rim can lose at its narrowest, as a fraction --
## the remainder is the guaranteed solid core.
const MOSS_RIM_JITTER := 0.45


## The pixel offsets, relative to a patch's center, that one moss patch
## covers. Pulled out of the painter so the SHAPE can be tested directly --
## the thing that was wrong was never the colour, it was that the shape was a
## rectangle.
static func moss_patch_offsets(seed_value: int, index: int) -> Array[Vector2i]:
	var offsets: Array[Vector2i] = []
	var radius := float(MOSS_PATCH_RADIUS)
	for dy in range(-MOSS_PATCH_RADIUS, MOSS_PATCH_RADIUS + 1):
		for dx in range(-MOSS_PATCH_RADIUS, MOSS_PATCH_RADIUS + 1):
			if dx == 0 and dy == 0:
				offsets.append(Vector2i.ZERO)
				continue
			var distance := sqrt(float(dx * dx + dy * dy))
			# Which rim sector this direction falls in. Sampling the wobble
			# by angle (not per pixel) keeps neighbouring pixels agreeing, so
			# the edge is a ragged outline instead of a dissolve.
			var sector := int((atan2(float(dy), float(dx)) + PI) / TAU * float(MOSS_RIM_SECTORS))
			# PixelNoise, not Godot's string hash: hashing near-identical
			# inputs correlates, which this project has been bitten by four
			# times (village house sizes, tree leaf angles, tuft blades,
			# blade fields).
			var wobble := PixelNoise.unit(seed_value + index * 7919, sector, 0)
			var limit := radius * (1.0 - MOSS_RIM_JITTER + MOSS_RIM_JITTER * wobble)
			if distance <= limit:
				offsets.append(Vector2i(dx, dy))
	return offsets


func _paint_moss(image: Image, base_color: Color, variant_seed: int) -> void:
	var moss_color := base_color.darkened(0.3)
	for i in 3:
		var h := absi(hash("%d_moss_%d" % [variant_seed, i]))
		var center_x := MOSS_PATCH_RADIUS + h % (SIZE - MOSS_PATCH_RADIUS * 2)
		var center_y := MOSS_PATCH_RADIUS + (h / 47) % (SIZE - MOSS_PATCH_RADIUS * 2)
		for offset in moss_patch_offsets(variant_seed, i):
			var px := center_x + offset.x
			var py := center_y + offset.y
			if px >= 0 and px < SIZE and py >= 0 and py < SIZE:
				image.set_pixel(px, py, moss_color)


## Wind-blown dune ripples: two shallow diagonal shade lines across the sand,
## evenly spaced (SIZE / 2 apart) regardless of tile resolution.
func _paint_dune_ripples(image: Image, base_color: Color, variant_seed: int) -> void:
	var ripple_color := base_color.darkened(0.12)
	var offset := absi(hash("%d_dune" % variant_seed)) % SIZE
	var half := SIZE / 2
	for x in SIZE:
		var y1 := (x / 2 + offset) % SIZE
		var y2 := (x / 2 + offset + half) % SIZE
		image.set_pixel(x, y1, ripple_color)
		image.set_pixel(x, y2, ripple_color)


## A few scattered small stone accents (tundra etc.): _SCATTER_SIZE px
## squares (was a single hairline pixel, see docs/concept/art_resolution.md)
## so each reads as an actual stone rather than a stray fleck.
const _SCATTER_SIZE := 3


func _paint_scatter(image: Image, color: Color, variant_seed: int, salt: String, count: int) -> void:
	for i in count:
		var h := absi(hash("%d_%s_%d" % [variant_seed, salt, i]))
		var sx := h % (SIZE - _SCATTER_SIZE)
		var sy := (h / 43) % (SIZE - _SCATTER_SIZE)
		for dy in _SCATTER_SIZE:
			for dx in _SCATTER_SIZE:
				image.set_pixel(sx + dx, sy + dy, color)


## Foam color for shoreline water (near-white; test_procedural_terrain_sprite
## detects foam as r/g/b all > 0.85).
const FOAM_COLOR := Color(0.55, 0.74, 0.97)


## A water tile that borders land on `land_directions` (Array of cardinal
## Vector2i, matching the blend functions' convention): the ordinary animated
## water base, plus a shimmering band of foam pixels along each land-facing
## edge and a lightened lapping row just inside it. Foam pattern re-rolls per
## frame (hash-salted with the wrapped frame), so the shoreline visibly
## fizzes; the cycle loops seamlessly because the frame index wraps.
func generate_shore_water_image(land_directions: Array, variant_seed: int, frame: int) -> Image:
	var wrapped_frame := posmod(frame, FRAME_COUNT)
	var base_color: Color = BASE_COLORS["ocean"]
	var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	_paint_water(image, base_color, variant_seed, wrapped_frame)
	for direction in land_directions:
		_paint_foam_edge(image, base_color, direction, variant_seed, wrapped_frame)
	return image


func _paint_foam_edge(
	image: Image, base_color: Color, direction: Vector2i, variant_seed: int, frame: int
) -> void:
	var lap_color := base_color.lightened(0.3)
	for i in SIZE:
		# Outer edge pixel and the pixel just inside it, along this direction.
		var outer := Vector2i(i, 0)
		var inner := Vector2i(i, 1)
		if direction == Vector2i(0, 1):
			outer = Vector2i(i, SIZE - 1)
			inner = Vector2i(i, SIZE - 2)
		elif direction == Vector2i(-1, 0):
			outer = Vector2i(0, i)
			inner = Vector2i(1, i)
		elif direction == Vector2i(1, 0):
			outer = Vector2i(SIZE - 1, i)
			inner = Vector2i(SIZE - 2, i)

		var salt := "foam_%d_%d_%d" % [direction.x, direction.y, frame]
		if _fraction(variant_seed, i, 0, salt) < 0.92:
			image.set_pixel(outer.x, outer.y, FOAM_COLOR)
		if _fraction(variant_seed, i, 1, salt) < 0.35:
			image.set_pixel(inner.x, inner.y, lap_color)


## A jagged rock-face crack: a dark 1px line wandering down the tile, plus a
## shorter branch fork partway down -- real branching detail that only
## became legible once a mountain tile got real vertical room (64px vs the
## original 16px, see docs/concept/art_resolution.md); a fork at 16px would
## have had nowhere to go.
func _paint_cracks(image: Image, base_color: Color, variant_seed: int) -> void:
	var crack_color := base_color.darkened(0.4)
	var h := absi(hash("%d_crack" % variant_seed))
	var x := 2 + h % (SIZE - 4)
	var branch_start_y := SIZE / 2 + (h / 17) % maxi(SIZE / 4, 1)
	var branch_x := x
	for y in range(2, SIZE - 2):
		x = clampi(x + [-1, 0, 0, 1][(h / (y + 3)) % 4], 1, SIZE - 2)
		image.set_pixel(x, y, crack_color)
		if y == branch_start_y:
			branch_x = x

	var branch_dir := 1 if (h / 29) % 2 == 0 else -1
	var branch_length := SIZE / 4
	for k in branch_length:
		var y := branch_start_y + k
		if y >= SIZE - 2:
			break
		branch_x = clampi(branch_x + branch_dir * ([0, 0, 1][(h / (y + 11)) % 3]), 1, SIZE - 2)
		image.set_pixel(branch_x, y, crack_color)


## A deterministic pseudo-random fraction in [0, 1] for a pixel, derived from
## the variant seed and its own coordinates.
## One pixel's texture roll: mostly decided by the mark-sized cell it sits in,
## with a per-pixel contribution that frays the mark's edge. Cell-first is what
## turns static into texture; the per-pixel part is what keeps it from reading
## as upscaled blocks.
func _speckle_roll(variant_seed: int, x: int, y: int) -> float:
	var coarse := _fraction(
		variant_seed, x / SPECKLE_CLUSTER, y / SPECKLE_CLUSTER, "clump"
	)
	var fine := _fraction(variant_seed, x, y, "speckle")
	return coarse * SPECKLE_CLUSTER_WEIGHT + fine * (1.0 - SPECKLE_CLUSTER_WEIGHT)


func _fraction(variant_seed: int, x: int, y: int, salt: String) -> float:
	return float(absi(hash("%d_%d_%d_%s" % [variant_seed, x, y, salt])) % 10000) / 10000.0


## A biome-border tile (see TerrainRenderer's blend-pair wiring): a gradient
## from near_biome's look to far_biome's look, oriented by `direction` (the
## direction, in tile-grid terms, that the far_biome neighbor lies in --
## e.g. Vector2i(0, -1) means far_biome is to the north, so the top edge of
## the tile reads mostly far_biome and the bottom edge mostly near_biome).
## Per-pixel speckle keeps it looking like patchy terrain, not a smooth
## color ramp, but the *bias* follows the gradient so the border genuinely
## reads as "this side leans toward that neighbor" rather than a uniform
## random 50/50 mix.
func generate_directional_blend_texture(
	near_biome: String, far_biome: String, direction: Vector2i, variant_seed: int
) -> ImageTexture:
	return ImageTexture.create_from_image(
		generate_directional_blend_image(near_biome, far_biome, direction, variant_seed)
	)


func generate_directional_blend_image(
	near_biome: String, far_biome: String, direction: Vector2i, variant_seed: int
) -> Image:
	return generate_multi_directional_blend_image(near_biome, far_biome, [direction], variant_seed)


## The four diagonal tile corners a corner-carve can be cut into, in a fixed
## order (NE, SE, SW, NW) -- TerrainRenderer's corner-detection and atlas
## layout both iterate this exact list so their indexing stays in sync.
const CORNER_DIRECTIONS: Array[Vector2i] = [
	Vector2i(1, -1), Vector2i(1, 1), Vector2i(-1, 1), Vector2i(-1, -1)
]

## How large a corner carve's radius is, in ART-PIXEL units at this
## generator's own SIZE (== TerrainRenderer.ART_TILE_SIZE) resolution -- the
## actual unit a human picks a border-radius in, so this is the one number
## that's tuned/tested, per CLAUDE.md's "no eyeballed tuning" rule. Small
## enough that it only eats the corner -- not the whole straight edge on
## either side of it. Pinned by
## test_corner_radius_is_exactly_8_pixels_at_art_tile_size_resolution and
## exercised by test_pixels_far_from_the_named_corner_are_untouched.
const CORNER_RADIUS_PIXELS := 8.0

## CORNER_RADIUS_PIXELS expressed as a fraction of SIZE -- what
## generate_corner_image's own math actually needs (independent of tile
## resolution, see docs/concept/art_resolution.md), derived from the tested
## pixel constant above rather than a bare literal fraction.
const CORNER_RADIUS_FRACTION := CORNER_RADIUS_PIXELS / SIZE


## A tile carved at one or more of its four corners at once (see
## CORNER_DIRECTIONS): `own_biome`'s own plain tile everywhere, except a
## quarter-circle wedge at EACH of `corner_directions`' corners (radius
## CORNER_RADIUS_FRACTION * SIZE, inset from that corner so the arc is
## tangent to both edges it touches) which is replaced pixel-for-pixel with
## `other_biome`'s own tile texture at the same coordinates. Multiple
## directions carve independently -- a pixel counts as carved if it falls in
## ANY of the requested wedges, so a cell that qualifies on more than one
## corner at once (a single-tile spit with water on three sides, or a lone
## one-tile pond surrounded on all four) gets every one of its real corners
## rounded, not just the first (measured directly against real generated
## chunks: 859 of 3355 real corner cells qualify on more than one corner
## simultaneously -- silently dropping the rest is exactly why some corners
## on a real coastline carved while others on the same tile stayed hard
## right angles, reported: "still not giving every corner a border radius").
## This is a real carved SHAPE in the opaque base tile -- not an alpha blend
## -- so it actually changes the tile's painted silhouette (unlike the GPU
## shore-distance overlay, which sits on top of this base tile and can never
## change its shape).
func generate_corner_image(
	own_biome: String, other_biome: String, corner_directions: Array, variant_seed: int
) -> Image:
	return generate_corner_image_from(
		generate_image(own_biome, variant_seed), generate_image(other_biome, variant_seed), corner_directions
	)


## Like generate_corner_image, but sources real pixels from the given
## own_image/other_image instead of generating them from biome names --
## lets a caller (see TerrainRenderer._corner_image) hand in each side's
## REAL illustrated or procedural texture so a coastline corner carves
## actual ground art together, not a texture resynthesized from a bare
## biome name. Purely a compositing mask (wedge geometry): no variant_seed,
## since which pixel wins at each position depends only on position, and
## any real texture comes from the source images themselves. own_image and
## other_image must be the same size; the output matches that size.
func generate_corner_image_from(own_image: Image, other_image: Image, corner_directions: Array) -> Image:
	var size := own_image.get_width()
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var last := float(size - 1)
	var radius := CORNER_RADIUS_FRACTION * size

	# Precompute each requested corner's inset wedge-circle center once.
	var centers: Array[Vector2] = []
	for corner_direction in corner_directions:
		var corner := Vector2(last if corner_direction.x > 0 else 0.0, last if corner_direction.y > 0 else 0.0)
		centers.append(corner - Vector2(corner_direction.x, corner_direction.y) * radius)

	for y in size:
		for x in size:
			var point := Vector2(x, y)
			var carved := false
			for i in corner_directions.size():
				var corner_direction: Vector2i = corner_directions[i]
				var center: Vector2 = centers[i]
				var in_quadrant := (
					(point.x - center.x) * corner_direction.x >= 0
					and (point.y - center.y) * corner_direction.y >= 0
				)
				if in_quadrant and point.distance_to(center) > radius:
					carved = true
					break
			if carved:
				image.set_pixel(x, y, other_image.get_pixel(x, y))
			else:
				image.set_pixel(x, y, own_image.get_pixel(x, y))
	return image


## 4x4 Bayer ordered-dither threshold matrix (values 0..15, normalized on
## use). Ordered dithering makes the transition read as a coherent, gradually
## thinning pattern instead of per-pixel random static -- each row/column's
## far-pixel count changes monotonically along the gradient (pinned by
## test_directional_blend_far_fraction_grows_monotonically_toward_the_far_edge).
const _BAYER_4X4 := [
	[0, 8, 2, 10],
	[12, 4, 14, 6],
	[3, 11, 1, 9],
	[15, 7, 13, 5],
]

## The gradient is sharpened so only the middle band of the tile actually
## mixes: below this fraction of the way toward the far edge a pixel is pure
## near-biome, above (1 - it) pure far-biome -- the outer quarters stay
## essentially pure, so a blend tile connects seamlessly to the plain tiles
## on both of its sides (pinned by
## test_directional_blend_keeps_the_outer_quarters_essentially_pure).
const _BLEND_BAND_START := 0.3
const _BLEND_BAND_END := 0.7


## Like generate_directional_blend_image but blends toward the far biome on
## *every* direction in `directions` at once, so a cell bordering the same
## neighbor on two sides dithers into both edges (and their shared corner),
## instead of only one. Per pixel, the blend bias `t` is the strongest pull of
## any active edge (max over directions), so corners where two edges meet read
## most strongly toward the far biome while the opposite corner stays true to
## the near biome. A single-element `directions` reproduces the
## single-direction behavior exactly.
func generate_multi_directional_blend_image(
	near_biome: String, far_biome: String, directions: Array, variant_seed: int
) -> Image:
	return generate_multi_directional_blend_image_from(
		generate_image(near_biome, variant_seed), generate_image(far_biome, variant_seed), directions, variant_seed
	)


## How strongly a blend edge's seeded noise curve can perturb the
## transition, in edge-fraction units (matching _BLEND_BAND_START/
## _BLEND_BAND_END's own 0..1 scale). Enveloped by blend_wobble_envelope,
## which is exactly zero at and beyond the band edges, so however large
## this is, the wobble can only ever act strictly INSIDE the existing
## sharpening band and provably cannot perturb a pixel the un-wobbled
## design already resolves to pure near/far -- the outer-quarter-purity and
## far-fraction-monotonic guarantees hold unconditionally, not by tuning.
const BLEND_WOBBLE_AMPLITUDE := 0.5
## How many full noise waves span one tile edge -- few enough that the
## boundary reads as a handful of gentle curves, not high-frequency jitter
## (reported live: "improve the blended tiles so they include curves...
## individual per tile rather than straight half forest half grass tile").
const BLEND_WOBBLE_WAVES := 2.2


## Tapers a blend edge's wobble to exactly zero at and beyond
## _BLEND_BAND_START/_BLEND_BAND_END (a triangular window peaking at 1 in
## the band's own center) -- see BLEND_WOBBLE_AMPLITUDE's doc comment for
## why this envelope is what makes the wobble provably safe regardless of
## amplitude.
static func blend_wobble_envelope(edge_t: float) -> float:
	# Explicit boundary check rather than trusting the linear formula below
	# to land on exactly 0.0 at the band edges: it does mathematically, but
	# float division can leave a tiny non-zero residue right at the
	# boundary, and the "provably zero outside the band" guarantee this
	# envelope exists for needs to be exact, not just numerically close.
	if edge_t <= _BLEND_BAND_START or edge_t >= _BLEND_BAND_END:
		return 0.0
	var half_band := (_BLEND_BAND_END - _BLEND_BAND_START) * 0.5
	var center := (_BLEND_BAND_START + _BLEND_BAND_END) * 0.5
	return clampf(1.0 - absf(edge_t - center) / half_band, 0.0, 1.0)


## A smooth, seeded curve offset (in edge-fraction units, before the
## envelope above is applied) at fraction `along` (0..1) across a blend
## edge -- gives the near/far boundary an organic wave instead of a
## straight line. A different variant_seed makes different variants of the
## same biome pair/direction curve differently rather than just re-speckle
## around one identical line; `direction` salts the seed so a tile blending
## on two edges at once (e.g. a corner cell bordering the same neighbor
## north AND east) doesn't wobble both edges in lockstep.
static func blend_edge_wobble(variant_seed: int, direction: Vector2i, along: float) -> float:
	var direction_salt := direction.x * 4001 + direction.y * 7919
	var n := PixelNoise.smooth(variant_seed + direction_salt, along * BLEND_WOBBLE_WAVES, 0.0)
	return (n * 2.0 - 1.0) * BLEND_WOBBLE_AMPLITUDE


## Like generate_multi_directional_blend_image, but sources real pixels from
## the given near_image/far_image instead of synthesizing flat BASE_COLORS
## plus a speckle roll -- lets a caller (see TerrainRenderer._blend_image)
## hand in each side's REAL illustrated or procedural texture, so a border
## dithers actual ground art together instead of a flat-color stand-in
## (reported: illustrated ground next to a flat/procedural-looking border
## read as visibly inconsistent). The dither MASK is computed here (which
## image's pixel wins at each position, via the directional gradient +
## seeded curve wobble + Bayer threshold): no extra speckle layered on top,
## since the source images already carry their own real texture (including,
## for the procedural wrapper above, generate_image's own speckle -- adding
## a second speckle pass on top of an already-textured image would just be
## noise on noise). variant_seed only shapes the curve (see
## blend_edge_wobble) -- it does not affect pixel sourcing. near_image and
## far_image must be the same size; the output matches that size.
func generate_multi_directional_blend_image_from(near_image: Image, far_image: Image, directions: Array, variant_seed: int = 0) -> Image:
	var size := near_image.get_width()
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var last := float(size - 1)

	# Precompute each active direction's wobble curve once: it only depends
	# on the coordinate running ALONG the edge (x for a N/S direction, y for
	# an E/W one), never on the coordinate ACROSS it, so recomputing
	# PixelNoise.smooth inside the pixel loop below recomputed the identical
	# value up to `size` times over. Measured: with this precompute missing,
	# a real atlas rebuild at BLEND_VARIANTS=7 didn't finish in several
	# minutes; with it, generation time is indistinguishable from the
	# unwobbled version's own cost.
	var wobble_curves: Array[PackedFloat32Array] = []
	for direction in directions:
		var curve := PackedFloat32Array()
		curve.resize(size)
		for i in size:
			curve[i] = blend_edge_wobble(variant_seed, direction, float(i) / last)
		wobble_curves.append(curve)

	for y in size:
		for x in size:
			# Fraction toward far_biome (0 at a near edge, 1 at a far edge),
			# taken as the strongest pull among all active directions, each
			# nudged by its own curved wobble before that max is taken.
			var t := 0.0
			for i in directions.size():
				var direction: Vector2i = directions[i]
				var edge_t := 0.0
				var wobble := 0.0
				if direction.y < 0:
					edge_t = 1.0 - y / last
					wobble = wobble_curves[i][x]
				elif direction.y > 0:
					edge_t = y / last
					wobble = wobble_curves[i][x]
				elif direction.x < 0:
					edge_t = 1.0 - x / last
					wobble = wobble_curves[i][y]
				elif direction.x > 0:
					edge_t = x / last
					wobble = wobble_curves[i][y]
				var envelope := blend_wobble_envelope(edge_t)
				t = maxf(t, clampf(edge_t + wobble * envelope, 0.0, 1.0))

			var sharpened := smoothstep(_BLEND_BAND_START, _BLEND_BAND_END, t)
			var threshold := (float(_BAYER_4X4[y % 4][x % 4]) + 0.5) / 16.0
			var source := far_image if threshold < sharpened else near_image
			image.set_pixel(x, y, source.get_pixel(x, y))

	return image
