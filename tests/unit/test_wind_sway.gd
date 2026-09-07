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


# -- sapling->mature morph dissolve (see tree_morph_shader.gd) ---------------

func test_shader_carries_the_morph_dissolve():
	assert_string_contains(WindSway.SHADER_CODE, "morph_canopy")


func test_a_real_material_compiles_with_the_morph_uniforms_and_defaults_to_fully_mature():
	const TreeMorphShader = preload("res://src/rendering/tree_morph_shader.gd")
	var material := wind.make_material()
	# 1.0 (fully mature, no sapling involved) is the GLSL uniform's OWN
	# default -- a freshly built material that never called TreeMorphShader.
	# apply() should already read as "done morphing", the same "off unless
	# told otherwise" shape snow_coverage already has on this material.
	assert_almost_eq(float(material.get_shader_parameter("morph_progress")), 1.0, 0.001)

	var sapling_texture := ImageTexture.create_from_image(Image.create(4, 4, false, Image.FORMAT_RGBA8))
	TreeMorphShader.apply(material, sapling_texture, 3, 0.5)
	assert_eq(material.get_shader_parameter("morph_sapling_texture"), sapling_texture)
	assert_almost_eq(float(material.get_shader_parameter("morph_progress")), 0.5, 0.001)


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


# -- canopy sparkle (see docs/concept/snow_cover.md, "Sparkle: specular
# glints on lying snow" -- the shared twinkle pattern + colour gate are
# pinned by test_snow_sparkle_shader.gd; these tests are WindSway's own
# WIRING: uniform plumbing, defaults, and tree-vs-tuft isolation) ----------

const SnowSparkleShader = preload("res://src/rendering/snow_sparkle_shader.gd")


## The two shaders must never silently drift apart -- ground's own copy is
## pinned the same way in test_snow_bomb_shader.gd.
func test_the_shader_code_contains_the_shared_sparkle_snippet_verbatim():
	assert_string_contains(WindSway.SHADER_CODE, SnowSparkleShader.GLSL_SNIPPET)


## world_pos must be computed AFTER the sway displacement (i.e. from the
## swaying VERTEX, not the pre-sway one) so a glint rides along with the
## twig it sits on rather than floating independently of it -- see
## sparkle_intensity's own call site for why that is the intended, more
## physically correct behaviour, not an oversight.
func test_world_pos_is_computed_after_the_sway_displacement():
	var code: String = WindSway.SHADER_CODE
	var sway_line := code.find("VERTEX.x += gust")
	var world_pos_line := code.find("world_pos = (MODEL_MATRIX")
	assert_true(sway_line >= 0 and world_pos_line >= 0, "could not locate both lines")
	assert_gt(world_pos_line, sway_line, "world_pos must be computed after VERTEX is swayed")


## fragment() must read the incoming COLOR (already texture * modulate, per
## Godot's own canvas_item default) rather than re-sampling TEXTURE itself --
## re-sampling would silently drop whatever modulate a tree/tuft node might
## carry, a real behaviour change this feature has no business making.
## Comments stripped first -- a comment EXPLAINING that COLOR already equals
## texture(TEXTURE, UV) must not itself be what trips this (the same
## comment-vs-code trap test_snow_bomb_shader.gd's own
## test_the_lattice_hash_is_trig_free doc comment warns about).
func test_fragment_reuses_the_incoming_color_rather_than_resampling_texture():
	var code: String = WindSway.SHADER_CODE
	var start := code.find("void fragment()")
	assert_true(start >= 0, "no fragment() found")
	var raw_body := code.substr(start, code.length() - start)
	var body := ""
	for line in raw_body.split("\n"):
		var stripped: String = line
		var comment := stripped.find("//")
		if comment >= 0:
			stripped = stripped.substr(0, comment)
		body += stripped + "\n"
	assert_false(body.contains("texture(TEXTURE"), "fragment() must reuse COLOR, not resample TEXTURE")
	assert_string_contains(body, "COLOR")


## Sparkle must be gated on BOTH snow_coverage and the shared colour gate --
## structural presence of both conditions, since the actual colour math is
## already pinned by test_snow_sparkle_shader.gd's own gate tests.
func test_fragment_gates_sparkle_on_coverage_and_the_colour_gate():
	var code: String = WindSway.SHADER_CODE
	assert_string_contains(code, "snow_coverage")
	assert_string_contains(code, "sparkle_min_value")
	assert_string_contains(code, "sparkle_max_saturation")
	assert_string_contains(code, "sparkle_intensity(world_pos, TIME)")


func test_make_material_defaults_snow_coverage_to_zero():
	var material := wind.make_material()
	assert_eq(material.get_shader_parameter("snow_coverage"), 0.0)


func test_the_material_carries_every_shared_sparkle_uniform():
	var material := wind.make_material()
	var expected := {
		"sparkle_cell_world": SnowSparkleShader.SPARKLE_CELL_WORLD,
		"sparkle_density": SnowSparkleShader.SPARKLE_DENSITY,
		"sparkle_jitter_world": SnowSparkleShader.SPARKLE_JITTER_WORLD,
		"sparkle_point_radius_world": SnowSparkleShader.SPARKLE_POINT_RADIUS_WORLD,
		"sparkle_hz": SnowSparkleShader.SPARKLE_HZ,
		"sparkle_duty_exponent": SnowSparkleShader.SPARKLE_DUTY_EXPONENT,
		"sparkle_brightness": SnowSparkleShader.SPARKLE_BRIGHTNESS,
	}
	for name in expected:
		assert_almost_eq(
			float(material.get_shader_parameter(name)), float(expected[name]), 0.0001,
			"the shader's %s does not match SnowSparkleShader's own constant" % name
		)


func test_the_material_carries_the_colour_gate_uniforms():
	var material := wind.make_material()
	assert_almost_eq(
		float(material.get_shader_parameter("sparkle_min_value")),
		SnowSparkleShader.SPARKLE_MIN_VALUE, 0.0001
	)
	assert_almost_eq(
		float(material.get_shader_parameter("sparkle_max_saturation")),
		SnowSparkleShader.SPARKLE_MAX_SATURATION, 0.0001
	)


## THE isolation guarantee: sparkle was asked for on trees and ground, not
## grass -- set_snow_coverage must reach shared_material() (trees) and must
## NEVER reach tuft_material() (grass/scrub/blooms), which stays at its
## fixed 0.0 default forever, structurally incapable of sparkling.
func test_set_snow_coverage_updates_the_shared_material_but_never_the_tuft_material():
	var shared := wind.shared_material()
	var tuft := wind.tuft_material()
	wind.set_snow_coverage(0.8)
	assert_eq(shared.get_shader_parameter("snow_coverage"), 0.8)
	assert_eq(
		tuft.get_shader_parameter("snow_coverage"), 0.0,
		"grass/scrub tufts must never receive snow_coverage -- sparkle is trees+ground only"
	)


## Mirrors set_wind_strength's own store-and-forward shape: a caller may push
## snow_coverage before shared_material() has ever been built.
func test_set_snow_coverage_before_material_is_built_still_applies_once_built():
	var fresh := WindSway.new()
	fresh.set_snow_coverage(0.5)
	assert_eq(fresh.shared_material().get_shader_parameter("snow_coverage"), 0.5)
	# And still never the tuft material, even freshly built after the push.
	assert_eq(fresh.tuft_material().get_shader_parameter("snow_coverage"), 0.0)


func test_set_snow_coverage_clamps_to_zero_one():
	var shared := wind.shared_material()
	wind.set_snow_coverage(5.0)
	assert_almost_eq(float(shared.get_shader_parameter("snow_coverage")), 1.0, 0.0001)
	wind.set_snow_coverage(-2.0)
	assert_almost_eq(float(shared.get_shader_parameter("snow_coverage")), 0.0, 0.0001)
