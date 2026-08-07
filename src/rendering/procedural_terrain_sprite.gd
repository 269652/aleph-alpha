extends RefCounted

## Deterministic offline pixel-art for terrain tiles, matching the same
## technique used elsewhere (ProceduralItemSprite/ProceduralSpriteGenerator/
## ProceduralTreeSprite): a base color speckled with texture, seeded so the
## same (biome, variant_seed) always produces the same tile but different
## variant_seeds give visibly different-looking tiles of the same biome --
## TerrainRenderer picks a variant per tile position so the ground doesn't
## read as one obviously-repeating texture.

const SIZE := 16

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
## as an all-over speckled fill, with per-biome tuning of how coarse/bright
## the speckle is. Water instead gets horizontal wave streaks.
const SPECKLE_DENSITY := 0.35
const SPECKLE_DARKEN := 0.18
const SPECKLE_LIGHTEN := 0.12


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
			# twice). They freeze as varied windswept ground detail; all real
			# blade motion lives in the GPU field (see GrassBladeField).
			_paint_grass_blades(image, base_color, variant_seed, 0)
			_paint_flowers(image, variant_seed)
		"forest", "rainforest":
			_paint_speckled(image, base_color, variant_seed)
			_paint_moss(image, base_color, variant_seed)
		"desert":
			_paint_speckled(image, base_color, variant_seed)
			_paint_dune_ripples(image, base_color, variant_seed)
		"tundra":
			_paint_speckled(image, base_color, variant_seed)
			_paint_scatter(image, base_color.darkened(0.28), variant_seed, "stones", 3)
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
			var roll := _fraction(variant_seed, x, y, "speckle")
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
## TerrainRenderer.build_water_overlay_tile_set).
const WIND_GLINT_COUNT := 5


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
		var length := 2 + (h / 211) % 3
		for k in length:
			image.set_pixel((gx + k) % SIZE, clampi(gy - (k / 2), 0, SIZE - 1), glint_color)
		image.set_pixel(gx, clampi(gy + 1, 0, SIZE - 1), glint_soft)
	var trough_color := base_color.darkened(0.22)
	for i in 4:
		var h := absi(hash("%d_trough_%d" % [variant_seed, i]))
		var ty := h % SIZE
		var tx := posmod(h / 41 - wrapped, SIZE)
		for k in 3:
			image.set_pixel((tx + k) % SIZE, ty, trough_color)


## Individual grass blades: BLADE_COUNT per tile, each with its own
## hash-derived position, height (2-4px), color (3 green tones), and sway
## phase (see blade_spec -- the pure, tested core). Blades bend progressively
## in the wind: the root stays planted, the tip carries the full [0,1,0,-1]
## lean cycle, mid pixels bend halfway -- so grass reads as living blades
## rather than stamped tufts.
const BLADE_COUNT := 4
## Tip lean per animation frame, in px. Was [0,1,0,-1] -- a 1px shuffle that
## read as static at screen scale; the wider asymmetric cycle is an obvious,
## organic whip (and still wraps seamlessly over FRAME_COUNT).
const _TUFT_SWAY := [0, 2, 1, -2]


func blade_spec(variant_seed: int, index: int) -> Dictionary:
	var h := absi(hash("%d_blade_%d" % [variant_seed, index]))
	return {
		"x": 1 + h % (SIZE - 2),
		"base_y": 5 + (h / 53) % (SIZE - 7),
		"height": 2 + (h / 349) % 3,
		"color_index": (h / 1117) % 3,
		"phase": (h / 4111) % FRAME_COUNT,
	}


func _paint_grass_blades(image: Image, base_color: Color, variant_seed: int, frame: int) -> void:
	var blade_colors := [
		base_color.darkened(0.2),
		base_color.darkened(0.1),
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
			var bend := float(k) / maxf(height - 1, 1.0)
			var x := clampi(spec.x + int(round(lean * bend)), 0, SIZE - 1)
			# Sun-lit tip so each blade ends crisply.
			image.set_pixel(x, y, color.lightened(0.22) if k == height - 1 else color)


## Occasional flower accents (static -- flowers don't sway at 16px): roughly
## every third variant gets 1-2 bright petal pixels, so walking a meadow
## passes little bursts of white/yellow/red among the green.
const _FLOWER_COLORS := [Color(0.95, 0.95, 0.9), Color(0.98, 0.85, 0.25), Color(0.9, 0.3, 0.3)]


func _paint_flowers(image: Image, variant_seed: int) -> void:
	var h := absi(hash("%d_flowers" % variant_seed))
	if h % 3 != 0:
		return
	var flower_count := 1 + (h / 7) % 2
	for i in flower_count:
		var fh := absi(hash("%d_flower_%d" % [variant_seed, i]))
		var fx := 1 + fh % (SIZE - 2)
		var fy := 1 + (fh / 61) % (SIZE - 2)
		var color: Color = _FLOWER_COLORS[(fh / 397) % _FLOWER_COLORS.size()]
		image.set_pixel(fx, fy, color)


## Dark moss/undergrowth patches on forest-floor tiles: 2-3 small 2x2 blobs of
## deepened green, so the floor reads as layered undergrowth rather than one
## flat speckle field.
func _paint_moss(image: Image, base_color: Color, variant_seed: int) -> void:
	var moss_color := base_color.darkened(0.3)
	for i in 3:
		var h := absi(hash("%d_moss_%d" % [variant_seed, i]))
		var mx := h % (SIZE - 1)
		var my := (h / 47) % (SIZE - 1)
		image.set_pixel(mx, my, moss_color)
		image.set_pixel(mx + 1, my, moss_color)
		image.set_pixel(mx, my + 1, moss_color)


## Wind-blown dune ripples: two shallow diagonal shade lines across the sand.
func _paint_dune_ripples(image: Image, base_color: Color, variant_seed: int) -> void:
	var ripple_color := base_color.darkened(0.12)
	var offset := absi(hash("%d_dune" % variant_seed)) % 8
	for x in SIZE:
		var y1 := (x / 2 + offset) % SIZE
		var y2 := (x / 2 + offset + 8) % SIZE
		image.set_pixel(x, y1, ripple_color)
		image.set_pixel(x, y2, ripple_color)


## A few scattered single-pixel accents (tundra stones etc.).
func _paint_scatter(image: Image, color: Color, variant_seed: int, salt: String, count: int) -> void:
	for i in count:
		var h := absi(hash("%d_%s_%d" % [variant_seed, salt, i]))
		image.set_pixel(h % SIZE, (h / 43) % SIZE, color)


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


## A jagged rock-face crack: a dark 1px line wandering down the tile.
func _paint_cracks(image: Image, base_color: Color, variant_seed: int) -> void:
	var crack_color := base_color.darkened(0.4)
	var h := absi(hash("%d_crack" % variant_seed))
	var x := 2 + h % (SIZE - 4)
	for y in range(2, SIZE - 2):
		x = clampi(x + [-1, 0, 0, 1][(h / (y + 3)) % 4], 1, SIZE - 2)
		image.set_pixel(x, y, crack_color)


## A deterministic pseudo-random fraction in [0, 1] for a pixel, derived from
## the variant seed and its own coordinates.
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
	var near_color: Color = BASE_COLORS.get(near_biome, _FALLBACK_COLOR)
	var far_color: Color = BASE_COLORS.get(far_biome, _FALLBACK_COLOR)
	var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var last := float(SIZE - 1)

	for y in SIZE:
		for x in SIZE:
			# Fraction toward far_biome (0 at a near edge, 1 at a far edge),
			# taken as the strongest pull among all active directions.
			var t := 0.0
			for direction in directions:
				var edge_t := 0.0
				if direction.y < 0:
					edge_t = 1.0 - y / last
				elif direction.y > 0:
					edge_t = y / last
				elif direction.x < 0:
					edge_t = 1.0 - x / last
				elif direction.x > 0:
					edge_t = x / last
				t = maxf(t, edge_t)

			var sharpened := smoothstep(_BLEND_BAND_START, _BLEND_BAND_END, t)
			var threshold := (float(_BAYER_4X4[y % 4][x % 4]) + 0.5) / 16.0
			var base_color := far_color if threshold < sharpened else near_color

			var speckle_roll := _fraction(variant_seed, x, y, "blend_speckle")
			var color := base_color
			if speckle_roll < SPECKLE_DENSITY * 0.5:
				color = base_color.darkened(SPECKLE_DARKEN)
			elif speckle_roll < SPECKLE_DENSITY:
				color = base_color.lightened(SPECKLE_LIGHTEN)
			image.set_pixel(x, y, color)

	return image
