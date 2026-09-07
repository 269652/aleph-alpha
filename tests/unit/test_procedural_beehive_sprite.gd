extends GutTest

## Procedural fallback for a honeybee hive (see IllustratedBeehiveSprite,
## docs/concept/bees.md) -- mirrors ProceduralAntMoundSprite's own shape
## and reasoning (a simple, offline-drawn silhouette with a darker
## entrance mark, world-width-for-growth-fraction using the identical
## pow-exponent-below-1 easing), recoloured to a honeycomb palette and
## drawn as a hanging teardrop rather than a squat ground dome -- a hive
## hangs from a branch, it is not dug into the earth.

const ProceduralBeehiveSprite = preload("res://src/rendering/procedural_beehive_sprite.gd")

var sprite: ProceduralBeehiveSprite


func before_each():
	sprite = ProceduralBeehiveSprite.new()


func test_generate_texture_returns_the_declared_size():
	var image: Image = sprite.generate_texture().get_image()
	assert_eq(image.get_width(), ProceduralBeehiveSprite.SIZE)
	assert_eq(image.get_height(), ProceduralBeehiveSprite.SIZE)


func test_generate_image_is_deterministic():
	var a := sprite.generate_image()
	var b := sprite.generate_image()
	for y in a.get_height():
		for x in a.get_width():
			assert_eq(a.get_pixel(x, y), b.get_pixel(x, y))


func test_draws_something_at_the_centre():
	var image := sprite.generate_image()
	var center := ProceduralBeehiveSprite.SIZE / 2
	assert_gt(image.get_pixel(center, center).a, 0.0)


## Mirrors ProceduralAntMoundSprite's own entrance-vs-outline distinction
## exactly -- a true near-black entrance would recreate the "fill colour
## lands on the outline ring" black-blob failure this project has already
## hit once.
func test_entrance_is_distinguishable_from_the_outline():
	const PixelPalette = preload("res://src/rendering/pixel_palette.gd")
	var outline := PixelPalette.new().outline_color()
	var entrance := ProceduralBeehiveSprite.ENTRANCE_COLOR
	var diff := Vector3(entrance.r - outline.r, entrance.g - outline.g, entrance.b - outline.b)
	assert_gt(diff.length(), 0.05, "the entrance mark should read as its own colour, not the outline")


func test_world_width_is_smallest_at_zero_growth():
	assert_almost_eq(
		ProceduralBeehiveSprite.world_width_for(0.0), ProceduralBeehiveSprite.HIVE_WORLD_WIDTH_MIN, 0.001
	)


func test_world_width_grows_with_growth_fraction():
	assert_gt(
		ProceduralBeehiveSprite.world_width_for(1.0), ProceduralBeehiveSprite.world_width_for(0.0)
	)


func test_world_width_is_largest_at_full_growth():
	assert_almost_eq(
		ProceduralBeehiveSprite.world_width_for(1.0), ProceduralBeehiveSprite.HIVE_WORLD_WIDTH_MAX, 0.001
	)


func test_world_width_clamps_out_of_range_growth():
	assert_almost_eq(
		ProceduralBeehiveSprite.world_width_for(2.0), ProceduralBeehiveSprite.world_width_for(1.0), 0.001
	)
	assert_almost_eq(
		ProceduralBeehiveSprite.world_width_for(-1.0), ProceduralBeehiveSprite.world_width_for(0.0), 0.001
	)


## Mirrors ProceduralAntMoundSprite's own growth curve shape exactly:
## reads fastest early, flattens out approaching full size.
func test_growth_reads_faster_early_than_late():
	var early_gain := ProceduralBeehiveSprite.world_width_for(0.5) - ProceduralBeehiveSprite.world_width_for(0.0)
	var late_gain := ProceduralBeehiveSprite.world_width_for(1.0) - ProceduralBeehiveSprite.world_width_for(0.5)
	assert_gt(early_gain, late_gain)


func test_world_scale_for_produces_the_declared_world_width():
	for growth_fraction in [0.0, 0.5, 1.0]:
		assert_almost_eq(
			float(ProceduralBeehiveSprite.SIZE) * ProceduralBeehiveSprite.world_scale_for(growth_fraction),
			ProceduralBeehiveSprite.world_width_for(growth_fraction), 0.01
		)


## A real wild comb hanging from a branch reads considerably smaller than
## a whole ant colony's excavated earthworks -- less dramatic than
## AntColony's own 1.5x-player-height ceiling (itself a live-tuned
## correction this doc has no equivalent live signal for yet; a real,
## named first-pass estimate, not claimed to be final).
func test_hive_ceiling_is_smaller_than_a_thriving_ant_mounds():
	const ProceduralAntMoundSprite = preload("res://src/rendering/procedural_ant_mound_sprite.gd")
	assert_lt(ProceduralBeehiveSprite.HIVE_WORLD_WIDTH_MAX, ProceduralAntMoundSprite.MOUND_WORLD_WIDTH_MAX)
