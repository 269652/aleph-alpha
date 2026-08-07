extends GutTest

## WaterShader: the GPU water overlay (see water_shader.gd) -- continuous,
## physically-inspired waves rendered in world space over ocean cells:
## ambient wind chop, a shore reflection band, and raindrop ripples, all
## summed into one interfering wave field. Contract tests only; the visual
## result can't be asserted headless.

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


func test_overlay_is_translucent_so_the_base_tile_layer_shows_through():
	# The overlay must NOT be opaque: the baked base water tile (and its
	# calmer tint near shore, once faded) stays part of the final look.
	assert_lt(WaterShader.WATER_ALPHA, 0.75)
	assert_gt(WaterShader.WATER_ALPHA, 0.2)
	var material := water.make_material()
	assert_eq(material.get_shader_parameter("alpha_strength"), WaterShader.WATER_ALPHA)


func test_shared_material_is_reused():
	assert_eq(water.shared_material(), water.shared_material())


# -- shore-distance-driven edge blending + reflection --------------------------

## The shader must read the WaterFx tile's own texture as shore-distance
## DATA (see procedural_shore_distance_sprite.gd), not ignore it as before --
## this is what lets the ocean edge fade smoothly into the coast on the GPU
## instead of cutting off at a baked tile boundary.
func test_shader_samples_the_tile_texture_as_shore_distance():
	var code: String = WaterShader.SHADER_CODE
	assert_string_contains(code, "texture(TEXTURE, UV)")
	assert_string_contains(code, "shore_dist")


## Incident + reflected wave components summed near the coast -- a real
## standing-wave interference pattern at a boundary ("waves bounce off the
## shore"), confined near shore and fading in open water.
func test_shader_sums_an_incident_and_reflected_wave_near_shore():
	var code: String = WaterShader.SHADER_CODE
	assert_string_contains(code, "incident")
	assert_string_contains(code, "reflected")
	assert_string_contains(code, "shore_band")


# -- raindrop ripples --------------------------------------------------------

func test_shader_has_a_continuous_rain_intensity_uniform_defaulting_to_zero():
	var material := water.make_material()
	assert_eq(material.get_shader_parameter("rain_intensity"), 0.0)
	assert_string_contains(WaterShader.SHADER_CODE, "uniform float rain_intensity")


## Raindrops spawn expanding ring ripples from a hash-seeded grid of drop
## points, sampling neighboring cells too so a ring crossing a cell boundary
## still renders -- and the result feeds into the same combined wave field as
## the ambient chop and shore reflection, so overlapping ripples genuinely
## interfere rather than drawing over each other.
func test_shader_generates_raindrop_ripples_that_feed_the_combined_wave_field():
	var code: String = WaterShader.SHADER_CODE
	assert_string_contains(code, "raindrop_ripples")
	assert_string_contains(code, "float wave = ")


func test_set_rain_intensity_updates_the_shared_materials_uniform():
	var material := water.shared_material()
	water.set_rain_intensity(1.0)
	assert_eq(material.get_shader_parameter("rain_intensity"), 1.0)
	water.set_rain_intensity(0.0)
	assert_eq(material.get_shader_parameter("rain_intensity"), 0.0)
