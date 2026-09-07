extends GutTest

## Offline pixel art for a real aquatic invertebrate patch (see docs/concept/
## aquatic_foraging.md's "Revised (2026-09-07)") -- a small cluster of
## curved larvae/nymphs, the same "hand-drawn procedural style, real
## illustrated art later" convention ProceduralAquaticVegetationSprite
## already follows for the sibling producer layer. A genuinely different
## silhouette AND palette from vegetation's own tapered green blades (real
## aquatic insect larvae read as tan/brown grubs, not a plant) so the two
## food layers read as different things at a glance, not two colours of
## the same icon.

const ProceduralAquaticInvertebrateSprite = preload("res://src/rendering/procedural_aquatic_invertebrate_sprite.gd")
const ProceduralAquaticVegetationSprite = preload("res://src/rendering/procedural_aquatic_vegetation_sprite.gd")
const PixelPalette = preload("res://src/rendering/pixel_palette.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")

var sprite: ProceduralAquaticInvertebrateSprite


func before_each():
	sprite = ProceduralAquaticInvertebrateSprite.new()


func test_generates_a_texture_of_the_declared_size():
	var texture := sprite.generate_texture(1)
	assert_not_null(texture)
	assert_eq(texture.get_width(), ProceduralAquaticInvertebrateSprite.SIZE.x)
	assert_eq(texture.get_height(), ProceduralAquaticInvertebrateSprite.SIZE.y)


func test_something_is_actually_drawn():
	var image := sprite.generate_image(1)
	var drawn := false
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a > 0.0:
				drawn = true
				break
	assert_true(drawn, "the sprite should not be entirely blank")


func test_generation_is_deterministic_for_the_same_seed():
	var a := sprite.generate_image(7)
	var b := sprite.generate_image(7)
	assert_eq(a.get_data(), b.get_data())


func test_different_seeds_look_different():
	var a := sprite.generate_image(1)
	var b := sprite.generate_image(2)
	assert_ne(a.get_data(), b.get_data())


## RGBA8 quantization means a stored pixel is never bit-exact with the
## original float Color -- see test_procedural_aquatic_vegetation_sprite.gd's
## own identical helper/epsilon.
const _TONE_EPSILON := 0.02


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
	var image := sprite.generate_image(1)
	var outline := PixelPalette.new().outline_color()
	assert_true(_contains_color(image, outline), "expected at least one outline-coloured pixel")


## The one thing this sprite must NOT do: read as a recolored copy of
## vegetation's own green blade. Real aquatic insect larvae are tan/brown,
## not green.
func test_does_not_use_vegetations_own_blade_color():
	var image := sprite.generate_image(1)
	assert_false(
		_contains_color(image, ProceduralAquaticVegetationSprite.BLADE_COLOR),
		"invertebrates must read as a genuinely different thing from vegetation, not a green recolor"
	)


# -- real-world size ----------------------------------------------------------

func test_world_width_is_smaller_than_a_full_tile():
	assert_lt(ProceduralAquaticInvertebrateSprite.WORLD_WIDTH, TerrainRenderer.TILE_SIZE)


func test_world_scale_actually_produces_the_declared_world_width():
	assert_almost_eq(
		ProceduralAquaticInvertebrateSprite.world_scale() * float(ProceduralAquaticInvertebrateSprite.SIZE.x),
		ProceduralAquaticInvertebrateSprite.WORLD_WIDTH, 0.001
	)
