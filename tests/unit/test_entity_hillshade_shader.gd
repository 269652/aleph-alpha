extends GutTest

## EntityHillshadeShader: per-entity relief shading for individual sprites
## that have no separate ground-overlay layer to composite onto (see
## entity_hillshade_shader.gd) -- a sibling to HillshadeShader (the ground
## overlay) that darkens a sprite's OWN texture directly, using one fixed
## slope/aspect per entity (an instance uniform) rather than per-pixel data
## sampled from a texture. Contract tests only; the visual result can't be
## asserted headless (same documented boundary test_hillshade_shader.gd
## already accepts).

const EntityHillshadeShader = preload("res://src/rendering/entity_hillshade_shader.gd")
const HillshadeShader = preload("res://src/rendering/hillshade_shader.gd")
const Hillshade = preload("res://src/rendering/hillshade.gd")

var entity_hillshade := EntityHillshadeShader.new()


func test_make_material_returns_a_shader_material_with_a_shader():
	var material := entity_hillshade.make_material()
	assert_true(material is ShaderMaterial)
	assert_not_null(material.shader)


func test_shader_declares_canvas_item_and_a_fragment_function():
	var code: String = EntityHillshadeShader.SHADER_CODE
	assert_string_contains(code, "shader_type canvas_item")
	assert_string_contains(code, "void fragment()")


## Per-entity slope/aspect must be INSTANCE uniforms -- a per-CanvasItem
## override on one shared material -- since every vein sprite has its own
## fixed slope/aspect but they all share ONE material (see
## docs/concept/terrain_relief.md's "Mountain ore" section).
func test_slope_and_aspect_are_instance_uniforms():
	var code: String = EntityHillshadeShader.SHADER_CODE
	assert_string_contains(code, "instance uniform float slope_deg")
	assert_string_contains(code, "instance uniform float aspect_deg")


## Sun position stays a REGULAR (shared) uniform -- the same real sun
## applies to every entity at once, exactly like HillshadeShader's own
## ground-overlay uniforms, so one set_sun_position call re-shades every
## sprite sharing the material at once.
func test_sun_position_uniforms_are_not_instance_uniforms():
	var code: String = EntityHillshadeShader.SHADER_CODE
	assert_string_contains(code, "uniform float sun_elevation_deg")
	assert_false(code.contains("instance uniform float sun_elevation_deg"))


## The structural difference from HillshadeShader: that shader composites a
## translucent overlay OVER a separate layer; this one darkens its OWN
## texture directly, since an entity sprite has no separate layer to sit
## under.
func test_shader_darkens_its_own_texture_rather_than_compositing_an_overlay():
	var code: String = EntityHillshadeShader.SHADER_CODE
	assert_string_contains(code, "texture(TEXTURE, UV)")
	assert_string_contains(code, "tex_color.rgb * dim")


## Godot's shader compiler rejects an early `return` inside fragment() --
## this project hit that exact bug once already building HillshadeShader
## (see that file's own doc comment). This shader avoids it the same way:
## branches only ever SET `dim`, applied once at the end.
func test_fragment_never_returns_early():
	var code: String = EntityHillshadeShader.SHADER_CODE
	var fragment_start := code.find("void fragment()")
	assert_true(fragment_start != -1)
	assert_false(code.substr(fragment_start).contains("return"))


func test_shared_material_is_reused():
	assert_eq(entity_hillshade.shared_material(), entity_hillshade.shared_material())


## min_lit_fraction is not a fresh eyeballed number -- it is the exact same
## floor brightness the ground tile beneath a vein already darkens to in
## full shadow (1.0 - HillshadeShader.MAX_SHADOW_ALPHA), so a vein in
## shadow reads as consistently lit with the rock around it rather than an
## unrelated second darkening curve.
func test_min_lit_fraction_is_derived_from_hillshade_shaders_max_shadow_alpha():
	assert_eq(EntityHillshadeShader.MIN_LIT_FRACTION, 1.0 - HillshadeShader.MAX_SHADOW_ALPHA)


func test_min_lit_fraction_is_pushed_into_the_materials_default():
	var material := entity_hillshade.make_material()
	assert_eq(material.get_shader_parameter("min_lit_fraction"), EntityHillshadeShader.MIN_LIT_FRACTION)


func test_default_sun_position_uniforms_are_pushed():
	var material := entity_hillshade.make_material()
	assert_eq(material.get_shader_parameter("sun_elevation_deg"), EntityHillshadeShader.DEFAULT_SUN_ELEVATION_DEG)
	assert_eq(material.get_shader_parameter("sun_azimuth_deg"), EntityHillshadeShader.DEFAULT_SUN_AZIMUTH_DEG)


func test_set_sun_position_updates_the_shared_materials_regular_uniforms():
	entity_hillshade.set_sun_position(62.0, 210.0)
	var material := entity_hillshade.shared_material()
	assert_eq(material.get_shader_parameter("sun_elevation_deg"), 62.0)
	assert_eq(material.get_shader_parameter("sun_azimuth_deg"), 210.0)


## Confirms this project's actual Godot 4.7 (GL Compatibility) engine really
## accepts a real CanvasItem.set_instance_shader_parameter call against this
## shared material -- not just trusted from documentation. This project has
## already hit a real, hardware-measured instance-uniform caveat once
## before (see IllustratedGrassPatch/long_grass.md: a global ~4096 slot cap
## shared by the WHOLE SCENE, overflowed by a single chunk's worth of
## MultiMesh grass blade instances) -- it does not apply here because
## mountain veins are landmark-rare (MountainOrePlacement's own vein-chance
## ceiling) real, individual CanvasItems, nowhere near that count at once.
func test_a_real_canvasitem_accepts_the_shared_materials_instance_uniforms():
	var sprite := Sprite2D.new()
	sprite.material = entity_hillshade.shared_material()
	sprite.set_instance_shader_parameter("slope_deg", 30.0)
	sprite.set_instance_shader_parameter("aspect_deg", 120.0)
	assert_eq(sprite.get_instance_shader_parameter("slope_deg"), 30.0)
	assert_eq(sprite.get_instance_shader_parameter("aspect_deg"), 120.0)
	sprite.free()


# -- lit_fraction: the CPU mirror of exactly what the shader's fragment() draws -

## Differs from HillshadeShader.shadow_alpha's night case (which returns
## 0.0, i.e. no EXTRA darkening on top of an already-dark night): this
## shader multiplies a texture's own colour by `dim` rather than
## compositing a black overlay on top of it, so "no extra darkening" here
## means dim==1.0 (texture unchanged), not 0.0. Both defer to the same
## existing global day/night CanvasModulate tint rather than adding a
## second darkening of their own -- they just land on opposite numeric
## outputs to express the same policy.
func test_lit_fraction_is_one_at_night_regardless_of_slope():
	assert_eq(EntityHillshadeShader.lit_fraction(60.0, 90.0, -5.0, 180.0), 1.0)
	assert_eq(EntityHillshadeShader.lit_fraction(60.0, 90.0, 0.0, 180.0), 1.0)


func test_lit_fraction_matches_hillshades_illumination_formula_during_the_day():
	var slope := 40.0
	var aspect := 120.0
	var sun_elevation := 35.0
	var sun_azimuth := 200.0
	var expected_illumination := Hillshade.illumination(slope, aspect, sun_elevation, sun_azimuth)
	var expected_fraction := lerpf(EntityHillshadeShader.MIN_LIT_FRACTION, 1.0, expected_illumination)
	assert_almost_eq(
		EntityHillshadeShader.lit_fraction(slope, aspect, sun_elevation, sun_azimuth), expected_fraction, 0.0001
	)


func test_lit_fraction_is_lower_for_a_slope_facing_away_from_the_sun():
	var sun_azimuth := 90.0
	var facing_sun := EntityHillshadeShader.lit_fraction(45.0, sun_azimuth, 30.0, sun_azimuth)
	var facing_away := EntityHillshadeShader.lit_fraction(45.0, sun_azimuth + 180.0, 30.0, sun_azimuth)
	assert_lt(facing_away, facing_sun)


func test_lit_fraction_never_drops_below_min_lit_fraction():
	assert_gte(EntityHillshadeShader.lit_fraction(90.0, 0.0, 5.0, 180.0), EntityHillshadeShader.MIN_LIT_FRACTION)


func test_lit_fraction_never_exceeds_one():
	assert_lte(EntityHillshadeShader.lit_fraction(0.0, -1.0, 90.0, 0.0), 1.0)
