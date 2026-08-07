extends GutTest

## GroundTint: the world-space low-frequency noise shader on the terrain
## TileMapLayer. Every tile of a biome shares the same average color, so
## however good the per-tile art is, a field reads as a uniform printed
## carpet -- the "patterned and artificial" complaint. This shader drifts the
## ground's brightness in soft, tile-spanning patches (wavelength ~10 tiles),
## the way real meadows shift between lusher and drier grass. Contract tests
## only -- the visual result can't be asserted headless.

const GroundTint = preload("res://src/rendering/ground_tint.gd")

var tint := GroundTint.new()


func test_make_material_returns_a_shader_material_with_a_shader():
	var material := tint.make_material()
	assert_true(material is ShaderMaterial)
	assert_not_null(material.shader)


func test_shader_samples_noise_in_world_space():
	# World-space (via MODEL_MATRIX), not screen-space: the pattern must stay
	# glued to the ground as the camera moves, not swim across it.
	var code: String = GroundTint.SHADER_CODE
	assert_string_contains(code, "shader_type canvas_item")
	assert_string_contains(code, "MODEL_MATRIX")
	assert_string_contains(code, "void fragment()")


func test_tint_strength_is_subtle_and_pinned():
	# A gentle drift, not camo blotches: strength stays well under 20%.
	assert_lte(GroundTint.TINT_STRENGTH, 0.2)
	assert_gt(GroundTint.TINT_STRENGTH, 0.0)
	var material := tint.make_material()
	assert_eq(material.get_shader_parameter("tint_strength"), GroundTint.TINT_STRENGTH)


func test_noise_wavelength_spans_multiple_tiles():
	# The whole point is variation BIGGER than one tile: wavelength (1/scale)
	# must span at least 4 tiles' worth of pixels, else it's just more speckle.
	assert_lte(GroundTint.NOISE_SCALE, 1.0 / (4.0 * 16.0))


func test_shared_material_is_reused():
	assert_eq(tint.shared_material(), tint.shared_material())
