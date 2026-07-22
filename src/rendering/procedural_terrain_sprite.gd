extends RefCounted

## Deterministic offline pixel-art for terrain tiles, matching the same
## technique used elsewhere (ProceduralItemSprite/ProceduralSpriteGenerator/
## ProceduralTreeSprite): a base color speckled with texture, seeded so the
## same (biome, variant_seed) always produces the same tile but different
## variant_seeds give visibly different-looking tiles of the same biome --
## TerrainRenderer picks a variant per tile position so the ground doesn't
## read as one obviously-repeating texture.

const SIZE := 16

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
	var base_color: Color = BASE_COLORS.get(biome_name, _FALLBACK_COLOR)
	var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)

	if biome_name == "ocean":
		_paint_water(image, base_color, variant_seed)
	else:
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


## Water gets horizontal wave streaks (a lighter band every few rows, phase
## offset by variant_seed) layered over a light speckle, instead of the
## grainy land texture -- reads as light glinting on a surface.
func _paint_water(image: Image, base_color: Color, variant_seed: int) -> void:
	var phase := absi(hash("%d_wave_phase" % variant_seed)) % SIZE
	for y in SIZE:
		for x in SIZE:
			var roll := _fraction(variant_seed, x, y, "ripple")
			var color := base_color
			if roll < SPECKLE_DENSITY * 0.3:
				color = base_color.darkened(SPECKLE_DARKEN * 0.6)
			if (y + phase) % 4 == 0:
				color = color.lightened(SPECKLE_LIGHTEN)
			image.set_pixel(x, y, color)


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
