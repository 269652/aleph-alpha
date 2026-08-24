extends GutTest

## HillshadeShader: the GPU relief-shading overlay (see hillshade_shader.gd)
## -- a translucent black overlay whose alpha rises in shadowed terrain and
## falls to zero where a slope directly faces the sun, driven by the real
## sun position (solar_position.gd) and real per-tile slope/aspect DATA
## (procedural_hillshade_sprite.gd), the same "bake data, shade it on the
## GPU" shape water_shader.gd already established. Contract tests only; the
## visual result can't be asserted headless (same documented boundary
## test_water_shader.gd already accepts).

const HillshadeShader = preload("res://src/rendering/hillshade_shader.gd")
const Hillshade = preload("res://src/rendering/hillshade.gd")

var hillshade := HillshadeShader.new()


func test_make_material_returns_a_shader_material_with_a_shader():
	var material := hillshade.make_material()
	assert_true(material is ShaderMaterial)
	assert_not_null(material.shader)


func test_shader_declares_canvas_item_and_a_fragment_function():
	var code: String = HillshadeShader.SHADER_CODE
	assert_string_contains(code, "shader_type canvas_item")
	assert_string_contains(code, "void fragment()")


## The shader must read the overlay tile's own texture as slope/aspect DATA
## (see procedural_hillshade_sprite.gd) -- what actually lets a mountain's
## real relief drive its own shading instead of a flat, uniform tint.
func test_shader_samples_the_tile_texture_as_slope_aspect_data():
	var code: String = HillshadeShader.SHADER_CODE
	assert_string_contains(code, "texture(TEXTURE, UV)")


func test_shared_material_is_reused():
	assert_eq(hillshade.shared_material(), hillshade.shared_material())


func test_overlay_stays_translucent_so_the_ground_underneath_shows_through():
	assert_lt(HillshadeShader.MAX_SHADOW_ALPHA, 0.75)
	assert_gt(HillshadeShader.MAX_SHADOW_ALPHA, 0.2)
	var material := hillshade.make_material()
	assert_eq(material.get_shader_parameter("max_shadow_alpha"), HillshadeShader.MAX_SHADOW_ALPHA)


func test_default_sun_position_uniforms_are_pushed():
	var material := hillshade.make_material()
	assert_eq(material.get_shader_parameter("sun_elevation_deg"), HillshadeShader.DEFAULT_SUN_ELEVATION_DEG)
	assert_eq(material.get_shader_parameter("sun_azimuth_deg"), HillshadeShader.DEFAULT_SUN_AZIMUTH_DEG)


func test_set_sun_position_updates_the_shared_materials_uniforms():
	hillshade.set_sun_position(62.0, 210.0)
	var material := hillshade.shared_material()
	assert_eq(material.get_shader_parameter("sun_elevation_deg"), 62.0)
	assert_eq(material.get_shader_parameter("sun_azimuth_deg"), 210.0)


# -- shadow_alpha: the CPU mirror of exactly what the shader's fragment() draws -

func test_shadow_alpha_is_zero_at_night_regardless_of_slope():
	# Deliberately NOT max_shadow_alpha: the existing day/night CanvasModulate
	# darkening already handles nighttime globally. Hillshade only expresses
	# RELATIVE shading differences a directional sun creates, so it must add
	# nothing on top of an already-dark night rather than double-darkening.
	assert_eq(HillshadeShader.shadow_alpha(60.0, 90.0, -5.0, 180.0), 0.0)
	assert_eq(HillshadeShader.shadow_alpha(60.0, 90.0, 0.0, 180.0), 0.0)


func test_shadow_alpha_matches_hillshades_illumination_formula_during_the_day():
	var slope := 40.0
	var aspect := 120.0
	var sun_elevation := 35.0
	var sun_azimuth := 200.0
	var expected_illumination := Hillshade.illumination(slope, aspect, sun_elevation, sun_azimuth)
	var expected_alpha := (1.0 - expected_illumination) * HillshadeShader.MAX_SHADOW_ALPHA
	assert_almost_eq(
		HillshadeShader.shadow_alpha(slope, aspect, sun_elevation, sun_azimuth), expected_alpha, 0.0001
	)


func test_shadow_alpha_is_higher_for_a_slope_facing_away_from_the_sun():
	var sun_azimuth := 90.0
	var facing_sun := HillshadeShader.shadow_alpha(45.0, sun_azimuth, 30.0, sun_azimuth)
	var facing_away := HillshadeShader.shadow_alpha(45.0, sun_azimuth + 180.0, 30.0, sun_azimuth)
	assert_gt(facing_away, facing_sun)


func test_shadow_alpha_never_exceeds_max_shadow_alpha():
	assert_lte(HillshadeShader.shadow_alpha(90.0, 0.0, 5.0, 180.0), HillshadeShader.MAX_SHADOW_ALPHA)


func test_shadow_alpha_never_drops_below_zero():
	assert_gte(HillshadeShader.shadow_alpha(0.0, -1.0, 90.0, 0.0), 0.0)
