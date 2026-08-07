extends GutTest

## WindSway: the shared canvas_item vertex shader that makes trees and grass
## tufts sway in real time. Pure resource-building logic -- the visual result
## can't be asserted headless, but the shader's contract can: it must animate
## over TIME, weight displacement by UV.y so sprite bases stay pinned to the
## ground (a tree trunk doesn't slide, its canopy sways), and phase-shift by
## world position so neighboring plants don't sway in robotic lockstep.

const WindSway = preload("res://src/rendering/wind_sway.gd")

var wind := WindSway.new()


func test_make_material_returns_a_shader_material_with_a_shader():
	var material := wind.make_material()
	assert_true(material is ShaderMaterial)
	assert_not_null(material.shader)


func test_shader_is_a_canvas_item_vertex_animation():
	var code: String = WindSway.SHADER_CODE
	assert_string_contains(code, "shader_type canvas_item")
	assert_string_contains(code, "void vertex()")
	assert_string_contains(code, "TIME")


func test_shader_pins_sprite_bases_by_weighting_with_uv_y():
	assert_string_contains(WindSway.SHADER_CODE, "UV.y")


func test_shader_phase_shifts_by_world_position():
	assert_string_contains(WindSway.SHADER_CODE, "MODEL_MATRIX")


func test_material_exposes_the_pinned_default_sway_parameters():
	var material := wind.make_material()
	assert_eq(material.get_shader_parameter("amplitude_px"), WindSway.DEFAULT_AMPLITUDE_PX)
	assert_eq(material.get_shader_parameter("wind_speed"), WindSway.DEFAULT_SPEED)


func test_shared_material_is_reused_not_rebuilt_per_call():
	# Hundreds of tufts/trees share one material -- per-node materials would
	# defeat batching for zero visual gain.
	assert_eq(wind.shared_material(), wind.shared_material())
