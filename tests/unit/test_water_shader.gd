extends GutTest

## WaterShader: the GPU water overlay (see water_shader.gd) -- continuous
## noise-driven waves rendered in world space over ocean cells, replacing the
## 4-frame tile chop as the primary water motion. Contract tests only; the
## visual result can't be asserted headless.

const WaterShader = preload("res://src/rendering/water_shader.gd")

var water := WaterShader.new()


func test_make_material_returns_a_shader_material_with_a_shader():
	var material := water.make_material()
	assert_true(material is ShaderMaterial)
	assert_not_null(material.shader)


func test_shader_renders_continuous_world_space_waves():
	var code: String = WaterShader.SHADER_CODE
	assert_string_contains(code, "shader_type canvas_item")
	assert_string_contains(code, "MODEL_MATRIX")
	assert_string_contains(code, "TIME")
	assert_string_contains(code, "void fragment()")


func test_overlay_is_translucent_so_shore_foam_and_rain_show_through():
	# The overlay must NOT be opaque: the baked shoreline waterline band and
	# rain-ripple tiles render beneath it and stay visible.
	assert_lt(WaterShader.WATER_ALPHA, 0.75)
	assert_gt(WaterShader.WATER_ALPHA, 0.2)
	var material := water.make_material()
	assert_eq(material.get_shader_parameter("alpha_strength"), WaterShader.WATER_ALPHA)


func test_shared_material_is_reused():
	assert_eq(water.shared_material(), water.shared_material())
