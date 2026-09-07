extends GutTest

## Procedural art for a solitary wild bee's nest hole -- see
## WildBeeNestMarker, docs/concept/bees.md's "Wild bee nests". No
## illustrated art was supplied for this (unlike the honeybee hive) --
## a real, named gap for future art, not a blocker (see bees.md). A
## small twig stub with a dark entrance hole: the same "posterized
## circle + darker entrance dot" technique ProceduralAntMoundSprite
## already established for a structurally similar "small ground/branch
## feature with a hole" shape, recoloured to bark/wood rather than
## soil.
##
## Unlike ProceduralAntMoundSprite/ProceduralBeehiveSprite, this has NO
## growth-fraction sizing at all -- a hole is a fixed physical feature
## of existing deadwood; only its OCCUPANCY changes (see
## WildBeePatch.residents_at), never its own size.

const ProceduralWildBeeNestSprite = preload("res://src/rendering/procedural_wild_bee_nest_sprite.gd")

var sprite: ProceduralWildBeeNestSprite


func before_each():
	sprite = ProceduralWildBeeNestSprite.new()


func test_generate_texture_returns_the_declared_size():
	var image: Image = sprite.generate_texture().get_image()
	assert_eq(image.get_width(), ProceduralWildBeeNestSprite.SIZE)
	assert_eq(image.get_height(), ProceduralWildBeeNestSprite.SIZE)


func test_generate_image_is_deterministic():
	var a := sprite.generate_image()
	var b := sprite.generate_image()
	for y in a.get_height():
		for x in a.get_width():
			assert_eq(a.get_pixel(x, y), b.get_pixel(x, y))


func test_draws_something():
	var image := sprite.generate_image()
	var has_opaque_pixel := false
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a > 0.0:
				has_opaque_pixel = true
				break
		if has_opaque_pixel:
			break
	assert_true(has_opaque_pixel)


## Mirrors ProceduralAntMoundSprite's own entrance-vs-outline distinction
## exactly -- a true near-black entrance would recreate the "fill colour
## lands on the outline ring" black-blob failure this project has
## already hit once.
func test_entrance_is_distinguishable_from_the_outline():
	const PixelPalette = preload("res://src/rendering/pixel_palette.gd")
	var outline := PixelPalette.new().outline_color()
	var entrance := ProceduralWildBeeNestSprite.ENTRANCE_COLOR
	var diff := Vector3(entrance.r - outline.r, entrance.g - outline.g, entrance.b - outline.b)
	assert_gt(diff.length(), 0.05, "the entrance hole should read as its own colour, not the outline")


## Bark/wood, not the honeybee hive's own golden wax palette -- the two
## must read as visually distinct structures, not a reskin of one.
func test_bark_colour_is_distinguishable_from_the_honeybee_hives_wax_colour():
	const ProceduralBeehiveSprite = preload("res://src/rendering/procedural_beehive_sprite.gd")
	var bark := ProceduralWildBeeNestSprite.BARK_COLOR
	var wax := ProceduralBeehiveSprite.HIVE_COLOR
	var diff := Vector3(bark.r - wax.r, bark.g - wax.g, bark.b - wax.b)
	assert_gt(diff.length(), 0.1)


## A real, fixed physical feature -- a whole nest hole reads noticeably
## smaller than even a founding honeybee hive (a hole in a twig, not a
## hanging comb).
func test_world_width_is_smaller_than_a_founding_honeybee_hive():
	const ProceduralBeehiveSprite = preload("res://src/rendering/procedural_beehive_sprite.gd")
	assert_lt(ProceduralWildBeeNestSprite.WORLD_WIDTH, ProceduralBeehiveSprite.HIVE_WORLD_WIDTH_MIN)


func test_world_scale_produces_the_declared_world_width():
	assert_almost_eq(
		float(ProceduralWildBeeNestSprite.SIZE) * ProceduralWildBeeNestSprite.WORLD_SCALE,
		ProceduralWildBeeNestSprite.WORLD_WIDTH, 0.01
	)
