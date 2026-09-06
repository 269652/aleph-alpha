extends GutTest

## ProceduralMushroomSprite -- the fallback for any species with no real
## illustrated sheet registered in IllustratedMushroomSprite (none today,
## see docs/concept/mushrooms.md). Same house style as every other
## procedural generator here (PixelForm's lit-spheroid shading through
## PixelRamp, PixelPalette's outline). `identified` is still a real,
## tested parameter of this generator (a plain shared look vs. the
## species' own colour) even though MushroomMarker itself always calls it
## with `true` now (see docs/concept/mushrooms.md's "Revised again: the
## identification gate is gone").

const ProceduralMushroomSprite = preload("res://src/rendering/procedural_mushroom_sprite.gd")
const MushroomSpecies = preload("res://src/world/mushroom_species.gd")
const PixelPalette = preload("res://src/rendering/pixel_palette.gd")

var _sprite: ProceduralMushroomSprite


func before_each():
	_sprite = ProceduralMushroomSprite.new()


func test_generates_an_image_of_the_declared_size():
	var image := _sprite.generate_image("chanterelle", true)
	assert_eq(image.get_width(), ProceduralMushroomSprite.SIZE.x)
	assert_eq(image.get_height(), ProceduralMushroomSprite.SIZE.y)


func test_is_deterministic():
	var a := _sprite.generate_image("black_trumpet", true)
	var b := _sprite.generate_image("black_trumpet", true)
	assert_eq(a.get_data(), b.get_data())


# -- unidentified: one shared look, species-agnostic ----------------------

func test_unidentified_looks_the_same_regardless_of_true_species():
	var fly_agaric := _sprite.generate_image("fly_agaric", false)
	var psylo := _sprite.generate_image("psylo", false)
	var chanterelle := _sprite.generate_image("chanterelle", false)
	assert_eq(fly_agaric.get_data(), psylo.get_data())
	assert_eq(fly_agaric.get_data(), chanterelle.get_data())


func test_unidentified_colour_matches_no_real_species():
	var unidentified := _sprite.generate_image("fly_agaric", false)
	for id in MushroomSpecies.IDS:
		var identified := _sprite.generate_image(id, true)
		assert_ne(
			unidentified.get_data(),
			identified.get_data(),
			"unidentified should not accidentally match %s's real look" % id
		)


# -- identified: the real species' own colour -----------------------------

func test_identified_species_look_different_from_each_other():
	var chanterelle := _sprite.generate_image("chanterelle", true)
	var black_trumpet := _sprite.generate_image("black_trumpet", true)
	assert_ne(chanterelle.get_data(), black_trumpet.get_data())


func test_identified_differs_from_unidentified_for_the_same_species():
	var identified := _sprite.generate_image("parasol", true)
	var unidentified := _sprite.generate_image("parasol", false)
	assert_ne(identified.get_data(), unidentified.get_data())


# -- shape/outline ---------------------------------------------------------

## Per-channel epsilon rather than Color.is_equal_approx -- matching
## test_procedural_decomposer_sprite.gd's own _contains_color technique:
## the outline is drawn straight from a Color literal but read back through
## an 8-bit RGBA texture, and is_equal_approx's epsilon is tighter than a
## normal quantization round-trip tolerates.
const _TONE_EPSILON := 1.0 / 255.0


func _contains_color(image: Image, color: Color) -> bool:
	for y in image.get_height():
		for x in image.get_width():
			var pixel := image.get_pixel(x, y)
			if pixel.a <= 0.0:
				continue
			if (
				absf(pixel.r - color.r) < _TONE_EPSILON
				and absf(pixel.g - color.g) < _TONE_EPSILON
				and absf(pixel.b - color.b) < _TONE_EPSILON
			):
				return true
	return false


func test_has_an_outline_pixel():
	var image := _sprite.generate_image("black_trumpet", true)
	var outline := PixelPalette.new().outline_color()
	assert_true(_contains_color(image, outline), "expected at least one outline-colored pixel")


func test_something_is_actually_drawn():
	var image := _sprite.generate_image("chanterelle", true)
	var opaque_pixels := 0
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a > 0.0:
				opaque_pixels += 1
	assert_gt(opaque_pixels, 0)


# -- world scale ------------------------------------------------------------

func test_world_width_and_scale_are_positive():
	assert_gt(ProceduralMushroomSprite.MUSHROOM_WORLD_WIDTH, 0.0)
	assert_gt(ProceduralMushroomSprite.MUSHROOM_WORLD_SCALE, 0.0)


## "Smaller than an ant mound" was retired as the binding constraint (see
## MUSHROOM_WORLD_WIDTH's own doc comment -- ant mounds grew substantially
## the same day this test itself was revised, for the identical "a player
## should actually be able to notice this" reason). A mushroom is still a
## small object, just no longer measured against a mound that has since
## grown well past being a useful ceiling -- a whole tilled soil patch
## (ProceduralSoilSprite.SOIL_WORLD_WIDTH) is the more meaningful "still
## clearly smaller than X" comparison now.
func test_is_smaller_on_the_ground_than_a_tilled_soil_patch():
	var soil = load("res://src/rendering/procedural_soil_sprite.gd")
	assert_lt(ProceduralMushroomSprite.MUSHROOM_WORLD_WIDTH, soil.SOIL_WORLD_WIDTH)
