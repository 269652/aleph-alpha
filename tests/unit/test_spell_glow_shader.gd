extends GutTest

## The additive halo every spell atom casts (docs/concept/spell_vfx.md,
## "SpellGlowShader"). Mirrors TorchGlow's own convention -- a fragment
## shader cannot be asserted headless, so every tuned curve exists first as
## a plain CPU function, and the GLSL is a restatement of it, not a second
## untested copy.
##
## Two axes, tested separately: a SPATIAL radial falloff (own constant --
## deliberately independent of TorchGlow's, so retuning a torch's light pool
## can never silently retune a magic halo) and a TEMPORAL grow/hold/fade
## envelope timed off SpellEffectMarker's own beat (new; TorchGlow has no
## temporal component at all, it is a static light).

const SpellGlowShader = preload("res://src/rendering/spell_glow_shader.gd")
const ProceduralSpellEffectSprite = preload("res://src/rendering/procedural_spell_effect_sprite.gd")
const TorchGlow = preload("res://src/rendering/torch_glow.gd")


# -- the temporal envelope: alpha_for_progress -----------------------------

func test_alpha_is_zero_at_the_very_start_of_a_real_grow_window():
	assert_almost_eq(SpellGlowShader.alpha_for_progress(0.0, 0.2, 0.25, 0.5), 0.0, 0.001)


func test_alpha_reaches_peak_during_the_hold_window():
	# grow ends at 0.2, hold ends at 0.45 -- the midpoint of the hold
	# window is a real "currently holding" moment, not an edge case.
	assert_almost_eq(SpellGlowShader.alpha_for_progress(0.32, 0.2, 0.25, 0.5), 0.5, 0.001)


func test_alpha_is_zero_at_the_very_end():
	assert_almost_eq(SpellGlowShader.alpha_for_progress(1.0, 0.2, 0.25, 0.5), 0.0, 0.001)


func test_alpha_rises_monotonically_through_the_grow_window():
	var previous: float = SpellGlowShader.alpha_for_progress(0.0, 0.2, 0.25, 0.5)
	for step in range(1, 20):
		var progress: float = 0.2 * float(step) / 20.0
		var value: float = SpellGlowShader.alpha_for_progress(progress, 0.2, 0.25, 0.5)
		assert_gte(value, previous, "alpha must not fall while gathering")
		previous = value


func test_alpha_falls_monotonically_through_the_fade_window():
	var previous: float = SpellGlowShader.alpha_for_progress(0.45, 0.2, 0.25, 0.5)
	for step in range(1, 20):
		var progress: float = 0.45 + (1.0 - 0.45) * float(step) / 20.0
		var value: float = SpellGlowShader.alpha_for_progress(progress, 0.2, 0.25, 0.5)
		assert_lte(value, previous, "alpha must not rise while fading")
		previous = value


func test_alpha_never_exceeds_the_requested_peak():
	for step in range(0, 21):
		var progress: float = float(step) / 20.0
		assert_lte(SpellGlowShader.alpha_for_progress(progress, 0.2, 0.25, 0.5), 0.5)


func test_alpha_clamps_progress_outside_zero_one():
	assert_almost_eq(
		SpellGlowShader.alpha_for_progress(-0.5, 0.2, 0.25, 0.5),
		SpellGlowShader.alpha_for_progress(0.0, 0.2, 0.25, 0.5), 0.001
	)
	assert_almost_eq(
		SpellGlowShader.alpha_for_progress(1.5, 0.2, 0.25, 0.5),
		SpellGlowShader.alpha_for_progress(1.0, 0.2, 0.25, 0.5), 0.001
	)


## A degenerate zero-length grow window must not divide by zero -- it should
## simply already be at peak from progress 0.
func test_alpha_handles_a_zero_length_grow_window():
	assert_almost_eq(SpellGlowShader.alpha_for_progress(0.0, 0.0, 0.5, 0.5), 0.5, 0.001)


## A degenerate zero-length fade window (hold runs to progress 1.0) must
## not divide by zero either -- it should drop straight to zero at the end.
func test_alpha_handles_a_zero_length_fade_window():
	assert_almost_eq(SpellGlowShader.alpha_for_progress(1.0, 0.2, 0.8, 0.5), 0.0, 0.001)


# -- the spatial falloff: radial_intensity ----------------------------------

func test_radial_intensity_is_full_at_the_center():
	assert_eq(SpellGlowShader.radial_intensity(0.0), 1.0)


func test_radial_intensity_is_zero_at_and_past_the_edge():
	assert_eq(SpellGlowShader.radial_intensity(1.0), 0.0)
	assert_eq(SpellGlowShader.radial_intensity(1.5), 0.0)


func test_radial_intensity_is_monotonically_non_increasing():
	var previous: float = SpellGlowShader.radial_intensity(0.0)
	for step in range(1, 21):
		var value: float = SpellGlowShader.radial_intensity(float(step) / 20.0)
		assert_lte(value, previous, "intensity must never rise further from center")
		previous = value


## A magic halo is meant to read soft/diffuse, not as a practical light
## source with a usable core the way a torch does -- so its own edge
## softness is deliberately a wider fraction of the radius than TorchGlow's,
## a real design claim pinned here rather than left as an accidental number.
func test_the_halo_edge_is_softer_than_torch_glows_own():
	assert_gt(SpellGlowShader.EDGE_SOFTNESS_FRACTION, TorchGlow.EDGE_SOFTNESS_FRACTION)


# -- sizing: bigger than the sprite it surrounds ----------------------------

## The whole point (spell_vfx.md): a halo that exactly matches the sprite's
## own silhouette reads as a coloured outline, not light spilling outward.
func test_halo_is_genuinely_larger_than_the_sprite_it_surrounds():
	assert_gt(SpellGlowShader.HALO_SIZE_MULTIPLIER, 1.0)
	assert_lt(SpellGlowShader.HALO_SIZE_MULTIPLIER, 6.0, "a halo this much bigger reads as a screen flash, not light spill")


# -- the shader source itself -----------------------------------------------

func test_shader_uses_additive_blending():
	assert_string_contains(SpellGlowShader.SHADER_CODE, "blend_add")


## Same relationship TorchGlow's own test pins: the GLSL restates the SAME
## smoothstep-based shape as the CPU mirror, not a silently different curve.
func test_shader_source_uses_smoothstep_for_both_axes():
	var count: int = SpellGlowShader.SHADER_CODE.count("smoothstep(")
	assert_gte(count, 2, "both the spatial falloff and the temporal envelope must use it")


func test_shader_declares_a_progress_uniform_for_per_instance_animation():
	assert_string_contains(SpellGlowShader.SHADER_CODE, "uniform float progress")


func test_shader_declares_a_glow_color_uniform_for_per_atom_tinting():
	assert_string_contains(SpellGlowShader.SHADER_CODE, "uniform vec3 glow_color")


# -- material_for: a fresh, correctly-tinted instance per cast --------------

## Two markers can be mid-cast at once (two Fire Bolts in flight), and a
## SHARED ShaderMaterial instance would make the second marker's `progress`
## write stomp the first's -- ShaderMaterial is a Resource, mutated by
## reference. Unlike TorchGlow.material() (cached: there is only ever ONE
## torch glow live at a time), this must hand back an independent instance
## every call.
func test_material_for_returns_a_fresh_instance_each_call():
	var first: ShaderMaterial = SpellGlowShader.material_for("fire_damage")
	var second: ShaderMaterial = SpellGlowShader.material_for("fire_damage")
	assert_ne(first, second)


## But the compiled GLSL itself is genuinely shared -- cheap, and correct,
## since only the per-cast uniform VALUES need to be independent, not the
## shader code driving them.
func test_material_for_shares_the_underlying_shader_resource():
	var first: ShaderMaterial = SpellGlowShader.material_for("fire_damage")
	var second: ShaderMaterial = SpellGlowShader.material_for("frost_damage")
	assert_eq(first.shader, second.shader)


## The whole reason color_for exists as the one shared table: a spell's
## halo and its sprite must never disagree about what colour that atom is.
func test_material_for_tints_by_the_atoms_own_registered_color():
	var material: ShaderMaterial = SpellGlowShader.material_for("fire_damage")
	var expected: Color = ProceduralSpellEffectSprite.color_for("fire_damage")
	var tint: Vector3 = material.get_shader_parameter("glow_color")
	assert_almost_eq(tint.x, expected.r, 0.001)
	assert_almost_eq(tint.y, expected.g, 0.001)
	assert_almost_eq(tint.z, expected.b, 0.001)


func test_material_for_two_different_atoms_have_different_tints():
	var fire: Vector3 = SpellGlowShader.material_for("fire_damage").get_shader_parameter("glow_color")
	var frost: Vector3 = SpellGlowShader.material_for("frost_damage").get_shader_parameter("glow_color")
	assert_ne(fire, frost)
