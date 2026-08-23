extends RefCounted

const PixelNoise = preload("res://src/rendering/pixel_noise.gd")

## Deterministic offline pixel-art for a tuft of tall grass -- a few green
## blades on a transparent background, using the same shaded technique as
## ProceduralTreeSprite (trees) and the other procedural sprite generators.
## `seed_value` (typically hashed from the patch's cell) varies blade count,
## lean, and height so neighbouring tufts aren't pixel-identical clones.

## DETAIL_MULTIPLIER times the world footprint (see
## docs/concept/art_resolution.md) -- drawn at ArtResolution.SPRITE_SCALE
## so it gains pixel detail without growing in the world.
## Doubled again beyond the shared art resolution: a tuft is small on
## screen, so its blades need the extra pixels to stay thin and separate
## rather than fusing (see docs/concept/art_resolution.md).
const SIZE := Vector2i(64, 64)
## A blade is this wide at its root, tapering to a single pixel at the
## tip. A uniform 1px stroke reads as a scratch, not a blade.
const BLADE_ROOT_WIDTH := 2

## The seven tuft variants: how many blades each has, how tall they grow as
## a fraction of the CANVAS (blade detail within the sprite), and how tall
## the whole clump stands in the WORLD, in tiles (see world_scale_for_seed).
## Ranges from a sparse short clump to a dense tall one, so a meadow reads as
## uneven growth rather than a uniform lawn -- real tall grass varies between
## roughly 0.75 and 1.5 tiles tall (reported: "make them roughly 1 square
## high" / "varied height between 0.75 and 1.5 squares").
const VARIANTS := [
	{"blades": 6, "height": 0.30, "world_tiles": 0.75},
	{"blades": 9, "height": 0.40, "world_tiles": 0.875},
	{"blades": 12, "height": 0.52, "world_tiles": 1.0},
	{"blades": 15, "height": 0.62, "world_tiles": 1.125},
	{"blades": 19, "height": 0.72, "world_tiles": 1.25},
	{"blades": 23, "height": 0.84, "world_tiles": 1.375},
	{"blades": 28, "height": 0.95, "world_tiles": 1.5},
]
const BASE_COLOR := Color(0.3, 0.55, 0.18)
const SHADE_DARKEN := 0.25
const HIGHLIGHT_LIGHTEN := 0.25

## The mature tuft's target WORLD-space width, in world units -- kept
## independent of SIZE deliberately. Doubling SIZE for finer blade detail
## regressed this once already: EarthChunkManager derived the tuft's world
## scale from a fixed multiplier of the CANVAS size, so doubling the canvas
## silently doubled the tuft's on-screen footprint too. Callers should scale
## by world_scale(), not re-derive a factor from SIZE themselves.
## Roughly one tile (TerrainRenderer.TILE_SIZE == 16) tall/wide -- tall grass
## should read as tall grass, not an ankle-high tuft (reported: "grass
## blades which are now tiny ... make them roughly 1 square high").
const WORLD_WIDTH := 16.0


## The scale factor that renders this tuft at WORLD_WIDTH regardless of how
## many art pixels SIZE currently is. Callers that don't have a specific
## seed (e.g. sizing a whole layer up front) should prefer
## world_scale_for_seed(), which additionally varies with the tuft's own
## height variant.
static func world_scale() -> float:
	return WORLD_WIDTH / float(SIZE.x)


## Which of VARIANTS a given seed rolls -- pulled out of generate_image so
## callers (EarthChunkManager sizing the world-space sprite) and the image
## painter always agree on the same variant for the same seed.
static func variant_for_seed(seed_value: int) -> int:
	return PixelNoise.range_index(seed_value, 0, 0, VARIANTS.size())


## The world-space scale for a specific tuft, varying with its rolled
## variant's "world_tiles" height (0.75..1.5 tiles) so a meadow shows real
## height variety, not identically-sized clumps with only their internal
## blade detail differing.
static func world_scale_for_seed(seed_value: int) -> float:
	var variant := variant_for_seed(seed_value)
	var target_world_height: float = WORLD_WIDTH * float(VARIANTS[variant].world_tiles)
	return target_world_height / float(SIZE.x)


func generate_texture(seed_value: int) -> ImageTexture:
	return ImageTexture.create_from_image(generate_image(seed_value))


func generate_image(seed_value: int) -> Image:
	var image := Image.create(SIZE.x, SIZE.y, false, Image.FORMAT_RGBA8)
	# Seven hand-picked variants rather than one shape with jitter: a
	# meadow wants visibly different clumps -- sparse and short through
	# dense and tall -- not seven rolls of the same tuft.
	var variant := variant_for_seed(seed_value)
	var blade_count: int = VARIANTS[variant].blades
	for i in blade_count:
		_paint_blade(image, seed_value, i, variant)
	return image


## One blade: a 1px-wide column rising from the bottom edge, leaning left or
## right as it climbs. Blades near the tuft's center get the highlight tint,
## outer blades the shade tint, so the tuft reads as lit from above.
func _paint_blade(image: Image, seed_value: int, index: int, variant: int) -> void:
	# Placement comes from PixelNoise, not Godot's string hash: hashing
	# "..._0", "..._1", "..._2" correlates, so consecutive blades landed
	# beside each other at the same height and merged into solid slabs
	# instead of reading as separate blades. Same clustering this project
	# hit with village house sizes and tree leaves.
	var h := PixelNoise.value(seed_value, index, 0)
	var base_x := 2 + h % (SIZE.x - 4)
	var max_height: float = float(SIZE.y) * float(VARIANTS[variant].height)
	var height := int(max_height * (0.55 + float(h % 45) / 100.0))
	var lean: int = [-2, -1, 0, 1, 2][(h / 977) % 5]

	# Five tones so overlapping blades read as a clump with depth rather
	# than one flat green mass.
	var tones := [
		BASE_COLOR.darkened(SHADE_DARKEN),
		BASE_COLOR,
		BASE_COLOR.lightened(HIGHLIGHT_LIGHTEN),
		BASE_COLOR.darkened(SHADE_DARKEN * 0.5),
		Color(BASE_COLOR.r * 1.05, BASE_COLOR.g * 0.9, BASE_COLOR.b * 0.55),  # dry
	]
	var color: Color = tones[(h / 613) % tones.size()]

	for step in height:
		var y := SIZE.y - 1 - step
		if y < 0:
			break
		var t := float(step) / maxf(float(height - 1), 1.0)
		# Blades CURVE: the root stays planted and the lean accelerates
		# toward the tip, so a tuft bends instead of leaning like a stick.
		var x: int = base_x + int(round(float(lean) * pow(t, 2.0)))
		# ...and TAPER: wide at the root, a single pixel at the tip.
		var width := BLADE_ROOT_WIDTH if t < 0.15 else 1
		var stroke: Color = color.lightened(0.2) if step >= height - 2 else color
		for w in width:
			var px := x + w
			if px >= 0 and px < SIZE.x:
				image.set_pixel(px, y, stroke)
