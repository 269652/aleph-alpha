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


## Tuft sprites keep their blade pixels in the LOWER half of the quad, where
## the trees' squared falloff leaves sub-pixel motion (the reported
## "streaks don't sway" bug) -- so tufts get a linear, stronger preset.
func test_tuft_material_bends_linearly_and_harder_than_trees():
	var tuft := wind.tuft_material()
	assert_eq(tuft.get_shader_parameter("bend_exponent"), WindSway.TUFT_BEND_EXPONENT)
	assert_eq(tuft.get_shader_parameter("amplitude_px"), WindSway.TUFT_AMPLITUDE_PX)
	assert_eq(WindSway.TUFT_BEND_EXPONENT, 1.0)
	assert_gt(WindSway.TUFT_AMPLITUDE_PX, WindSway.DEFAULT_AMPLITUDE_PX)
	assert_eq(wind.tuft_material(), wind.tuft_material())
	assert_ne(wind.tuft_material(), wind.shared_material())


## Sway must scale with the live wind strength (see WeatherModel.
## wind_strength_for, forwarded via EarthChunkManager.set_wind_strength) --
## a calm day sways less, a storm sways harder, reusing the SAME live value
## water's own wind_strength already does rather than inventing a parallel
## wind concept. DEFAULT_WIND_STRENGTH is calibrated to
## WeatherModel.wind_strength_for("clear") == 1.0, so the default reproduces
## today's fixed-amplitude look exactly at that (majority, see CLEAR_THRESHOLD)
## baseline.
func test_make_material_defaults_wind_strength_to_the_calibration_anchor():
	var material := wind.make_material()
	assert_eq(material.get_shader_parameter("wind_strength"), WindSway.DEFAULT_WIND_STRENGTH)
	assert_eq(WindSway.DEFAULT_WIND_STRENGTH, 1.0)


func test_shader_scales_amplitude_by_the_live_wind_strength_uniform():
	assert_string_contains(WindSway.SHADER_CODE, "uniform float wind_strength")
	assert_string_contains(WindSway.SHADER_CODE, "amplitude_px * wind_strength")


func test_set_wind_strength_updates_both_shared_and_tuft_materials():
	var shared := wind.shared_material()
	var tuft := wind.tuft_material()
	wind.set_wind_strength(1.8)
	assert_eq(shared.get_shader_parameter("wind_strength"), 1.8)
	assert_eq(tuft.get_shader_parameter("wind_strength"), 1.8)
	wind.set_wind_strength(WindSway.DEFAULT_WIND_STRENGTH)
	assert_eq(shared.get_shader_parameter("wind_strength"), WindSway.DEFAULT_WIND_STRENGTH)


## A caller (EarthChunkManager) may call set_wind_strength before any tree/
## tuft has actually been spawned yet (materials are built lazily, on first
## shared_material()/tuft_material() call) -- the live value must still land
## on whatever gets built afterward, not just on materials that already exist.
func test_set_wind_strength_before_materials_are_built_still_applies_once_built():
	var fresh := WindSway.new()
	fresh.set_wind_strength(1.4)
	assert_eq(fresh.shared_material().get_shader_parameter("wind_strength"), 1.4)
	assert_eq(fresh.tuft_material().get_shader_parameter("wind_strength"), 1.4)
