extends GutTest

## Screen-space warp at the instant a burst-family atom releases
## (docs/concept/spell_vfx.md, "SpellImpactDistortionShader") -- the real
## optical distinction that doc's "Real-world grounding" section draws: heat
## visibly bends the air near a sudden release of energy, which a coloured
## sprite alone cannot show no matter how it is drawn.
##
## Gated to the burst family ONLY, read from
## `ProceduralSpellEffectSprite.shape_for` rather than a second atom list --
## a ring settling into place or a cloud drifting onto a target should not
## visibly warp the world around it.

const SpellImpactDistortionShader = preload("res://src/rendering/spell_impact_distortion_shader.gd")
const ProceduralSpellEffectSprite = preload("res://src/rendering/procedural_spell_effect_sprite.gd")


# -- the gate: which atoms even get this ------------------------------------

func test_a_burst_family_atom_gets_distortion():
	assert_eq(ProceduralSpellEffectSprite.shape_for("fire_damage"), "burst", "precondition")
	assert_true(SpellImpactDistortionShader.atom_gets_distortion("fire_damage"))


func test_a_ring_family_atom_does_not_get_distortion():
	assert_eq(ProceduralSpellEffectSprite.shape_for("freeze"), "ring", "precondition")
	assert_false(SpellImpactDistortionShader.atom_gets_distortion("freeze"))


## Every family other than burst is excluded -- the drift guard: a new atom
## added to a non-burst family must not silently start warping the screen.
func test_only_the_documented_seven_burst_atoms_get_distortion():
	const SpellAtomCatalog = preload("res://src/gameplay/spell_atom_catalog.gd")
	var catalog := SpellAtomCatalog.new()
	var gated: Array = []
	for atom_id in catalog.known_ids():
		if SpellImpactDistortionShader.atom_gets_distortion(atom_id):
			gated.append(atom_id)
	gated.sort()
	var expected: Array = [
		"fire_damage", "frost_damage", "shock_damage", "ignite",
		"induce_mutation", "illuminate", "fear",
	]
	expected.sort()
	assert_eq(gated, expected)


# -- the spatial term: radial_strength --------------------------------------

func test_radial_strength_is_full_at_the_center():
	assert_eq(SpellImpactDistortionShader.radial_strength(0.0), 1.0)


func test_radial_strength_is_zero_at_and_past_the_edge():
	assert_eq(SpellImpactDistortionShader.radial_strength(1.0), 0.0)
	assert_eq(SpellImpactDistortionShader.radial_strength(1.4), 0.0)


func test_radial_strength_is_monotonically_non_increasing():
	var previous: float = SpellImpactDistortionShader.radial_strength(0.0)
	for step in range(1, 21):
		var value: float = SpellImpactDistortionShader.radial_strength(float(step) / 20.0)
		assert_lte(value, previous)
		previous = value


# -- the temporal term: a strike, not a light -------------------------------

## No hold plateau -- a shockwave does not linger the way ambient light
## does, the real distinction from SpellGlowShader.alpha_for_progress this
## function is deliberately shaped differently from.
func test_temporal_strength_is_zero_at_the_very_start_and_very_end():
	assert_almost_eq(SpellImpactDistortionShader.temporal_strength(0.0, 0.2), 0.0, 0.001)
	assert_almost_eq(SpellImpactDistortionShader.temporal_strength(1.0, 0.2), 0.0, 0.001)


func test_temporal_strength_peaks_exactly_at_the_given_fraction():
	var at_peak: float = SpellImpactDistortionShader.temporal_strength(0.2, 0.2)
	for step in range(0, 21):
		var progress: float = float(step) / 20.0
		if absf(progress - 0.2) < 0.001:
			continue
		assert_lte(SpellImpactDistortionShader.temporal_strength(progress, 0.2), at_peak)


func test_temporal_strength_rises_monotonically_before_the_peak():
	var previous: float = SpellImpactDistortionShader.temporal_strength(0.0, 0.3)
	for step in range(1, 15):
		var progress: float = 0.3 * float(step) / 15.0
		var value: float = SpellImpactDistortionShader.temporal_strength(progress, 0.3)
		assert_gte(value, previous)
		previous = value


func test_temporal_strength_falls_monotonically_after_the_peak():
	var previous: float = SpellImpactDistortionShader.temporal_strength(0.3, 0.3)
	for step in range(1, 15):
		var progress: float = 0.3 + (1.0 - 0.3) * float(step) / 15.0
		var value: float = SpellImpactDistortionShader.temporal_strength(progress, 0.3)
		assert_lte(value, previous)
		previous = value


func test_temporal_strength_handles_a_peak_fraction_at_either_extreme():
	# peak_fraction == 0.0 (rises instantly) and == 1.0 (never decays before
	# the end) must not divide by zero.
	assert_almost_eq(SpellImpactDistortionShader.temporal_strength(0.0, 0.0), 1.0, 0.001)
	assert_almost_eq(SpellImpactDistortionShader.temporal_strength(1.0, 1.0), 1.0, 0.001)


# -- combined: displacement_for ---------------------------------------------

func test_displacement_is_zero_far_from_center_even_at_peak_progress():
	assert_almost_eq(SpellImpactDistortionShader.displacement_for(1.0, 0.2, 0.2), 0.0, 0.001)


func test_displacement_is_zero_at_center_at_the_very_start():
	assert_almost_eq(SpellImpactDistortionShader.displacement_for(0.0, 0.0, 0.2), 0.0, 0.001)


func test_displacement_is_never_negative():
	for d_step in range(0, 5):
		for p_step in range(0, 5):
			var value: float = SpellImpactDistortionShader.displacement_for(
				float(d_step) / 4.0, float(p_step) / 4.0, 0.2
			)
			assert_gte(value, 0.0)


func test_displacement_never_exceeds_one():
	for d_step in range(0, 5):
		for p_step in range(0, 5):
			var value: float = SpellImpactDistortionShader.displacement_for(
				float(d_step) / 4.0, float(p_step) / 4.0, 0.2
			)
			assert_lte(value, 1.0)


# -- the magnitude constant, bounded and pinned -----------------------------

## A believable heat-shimmer, not a disorienting funhouse warp -- bounded
## both ends so a future retune cannot silently drift into either.
func test_max_displacement_is_a_small_but_real_fraction_of_the_screen():
	assert_gt(SpellImpactDistortionShader.MAX_DISPLACEMENT_UV, 0.0)
	assert_lt(SpellImpactDistortionShader.MAX_DISPLACEMENT_UV, 0.05)


# -- the shader source itself ------------------------------------------------

func test_shader_reads_the_screen_texture():
	assert_string_contains(SpellImpactDistortionShader.SHADER_CODE, "hint_screen_texture")


func test_shader_uses_smoothstep_matching_the_cpu_mirror():
	assert_string_contains(SpellImpactDistortionShader.SHADER_CODE, "smoothstep(")


func test_shader_declares_a_progress_uniform():
	assert_string_contains(SpellImpactDistortionShader.SHADER_CODE, "uniform float progress")


# -- material_for: independent instances, same reason as the glow ----------

func test_material_for_returns_a_fresh_instance_each_call():
	var first: ShaderMaterial = SpellImpactDistortionShader.material_for()
	var second: ShaderMaterial = SpellImpactDistortionShader.material_for()
	assert_ne(first, second)


func test_material_for_shares_the_underlying_shader_resource():
	var first: ShaderMaterial = SpellImpactDistortionShader.material_for()
	var second: ShaderMaterial = SpellImpactDistortionShader.material_for()
	assert_eq(first.shader, second.shader)
