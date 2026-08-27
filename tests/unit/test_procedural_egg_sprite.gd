extends GutTest

## The pre-hatch visual for a pollinator's offspring (see LifeCycle's
## COURTING/MATED/EGG stages) -- a small pale oval, NOT an insect silhouette,
## shown before AmbientFlyerMarker switches to the existing scaled-down-adult
## sprite at STAGE_JUVENILE. See docs/concept/ecosystem_dynamics.md's
## "Courtship, and where births come from".

const ProceduralEggSprite = preload("res://src/rendering/procedural_egg_sprite.gd")
const ProceduralButterflySprite = preload("res://src/rendering/procedural_butterfly_sprite.gd")

var generator := ProceduralEggSprite.new()


func test_image_has_the_expected_size():
	var image := generator.generate_image(0)
	assert_eq(image.get_width(), ProceduralEggSprite.SIZE.x)
	assert_eq(image.get_height(), ProceduralEggSprite.SIZE.y)


func test_has_transparent_corners_and_an_opaque_body():
	var image := generator.generate_image(0)
	assert_eq(image.get_pixel(0, 0).a, 0.0)
	var mid := Vector2i(ProceduralEggSprite.SIZE.x / 2, ProceduralEggSprite.SIZE.y / 2)
	assert_gt(image.get_pixel(mid.x, mid.y).a, 0.0)


func test_is_deterministic_for_the_same_seed():
	var a := generator.generate_image(5)
	var b := generator.generate_image(5)
	assert_eq(a.get_data(), b.get_data())


func test_generate_texture_returns_an_image_texture():
	var texture := generator.generate_texture(3)
	assert_eq(texture.get_width(), ProceduralEggSprite.SIZE.x)


## The whole point: an egg is a plain, mostly-filled oval blob, not a
## butterfly's silhouette -- which is deliberately full of NEGATIVE space
## (the gap between the two wing pairs either side of a thin body/antennae,
## see ProceduralButterflySprite._paint_butterfly). A solid ellipse fills a
## clear majority of its own bounding box; two wings split by a thin waist
## do not. This is a real, structural difference between "an egg" and "a
## tiny insect", not a tautology about the two images merely differing.
func test_the_egg_is_a_solid_blob_unlike_the_butterflys_split_silhouette():
	var egg_fill := _opaque_fraction(generator.generate_image(0))
	var butterfly_fill := _opaque_fraction(ProceduralButterflySprite.new().generate_image("monarch", 0))
	assert_gt(
		egg_fill, 0.6,
		"an egg should read as a solid filled oval, not a shape full of gaps"
	)
	assert_gt(
		egg_fill, butterfly_fill,
		"an egg's silhouette should be far more solid than a butterfly's wings-and-gap silhouette"
	)


func _opaque_fraction(image: Image) -> float:
	var opaque := 0
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a > 0.0:
				opaque += 1
	return float(opaque) / float(image.get_width() * image.get_height())


## Real insect eggs are pale/unremarkable, unlike the vividly saturated adult
## butterflies this stage precedes (see ProceduralButterflySprite's
## SPECIES_BASE_COLORS doc comment) -- an egg should not itself be a vivid,
## saturated color.
func test_the_egg_is_pale_not_vividly_colored():
	assert_lt(ProceduralEggSprite.BASE_COLOR.s, 0.3, "an egg should read as pale, not vivid")
