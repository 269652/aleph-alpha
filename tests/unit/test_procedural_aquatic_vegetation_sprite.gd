extends GutTest

## Offline pixel art for a real aquatic vegetation patch (see docs/concept/
## aquatic_foraging.md) -- a small cluster of tapered blades rising from one
## base point, the same "hand-drawn procedural style, real illustrated art
## later" convention ProceduralWormSprite/ProceduralAntMoundSprite already
## follow.

const ProceduralAquaticVegetationSprite = preload("res://src/rendering/procedural_aquatic_vegetation_sprite.gd")
const PixelPalette = preload("res://src/rendering/pixel_palette.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")

var sprite: ProceduralAquaticVegetationSprite


func before_each():
	sprite = ProceduralAquaticVegetationSprite.new()


func test_generates_a_texture_of_the_declared_size():
	var texture := sprite.generate_texture(1)
	assert_not_null(texture)
	assert_eq(texture.get_width(), ProceduralAquaticVegetationSprite.SIZE.x)
	assert_eq(texture.get_height(), ProceduralAquaticVegetationSprite.SIZE.y)


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
## original float Color -- is_equal_approx's own tiny default epsilon is
## too strict for that, the same reason test_procedural_mushroom_sprite.gd's
## own _contains_color helper uses a real per-channel tolerance instead.
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


# -- real-world size ----------------------------------------------------------

func test_world_width_is_smaller_than_a_full_tile():
	assert_lt(ProceduralAquaticVegetationSprite.WORLD_WIDTH, TerrainRenderer.TILE_SIZE)


func test_world_scale_actually_produces_the_declared_world_width():
	assert_almost_eq(
		ProceduralAquaticVegetationSprite.world_scale() * float(ProceduralAquaticVegetationSprite.SIZE.x),
		ProceduralAquaticVegetationSprite.WORLD_WIDTH, 0.001
	)
