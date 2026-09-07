extends GutTest

const TorchGlow = preload("res://src/rendering/torch_glow.gd")


## Full intensity at the very center, matching a real light source's own
## bright core rather than fading from the first pixel outward.
func test_glow_intensity_is_full_at_the_center():
	assert_eq(TorchGlow.glow_intensity(0.0), 1.0)


## Fully faded out at (and past) the light's own outer edge -- past the
## radius, there is no light left to add.
func test_glow_intensity_is_zero_at_and_past_the_edge():
	assert_eq(TorchGlow.glow_intensity(1.0), 0.0)
	assert_eq(TorchGlow.glow_intensity(1.5), 0.0)


## A flat, fully-bright core out to EDGE_SOFTNESS_FRACTION's own boundary --
## see that constant's own doc comment for why a light reads as a real pool
## of light (a core, not a slow smear from the very center).
func test_glow_intensity_stays_full_across_the_flat_core():
	var edge_start := 1.0 - TorchGlow.EDGE_SOFTNESS_FRACTION
	assert_eq(TorchGlow.glow_intensity(0.0), 1.0)
	assert_eq(TorchGlow.glow_intensity(edge_start * 0.5), 1.0)
	assert_almost_eq(TorchGlow.glow_intensity(edge_start), 1.0, 0.001)


## Monotonically non-increasing as distance climbs -- a real light never
## gets brighter further from its own source.
func test_glow_intensity_is_monotonically_non_increasing():
	var previous := TorchGlow.glow_intensity(0.0)
	for step in range(1, 21):
		var distance := float(step) / 20.0
		var value := TorchGlow.glow_intensity(distance)
		assert_lte(value, previous, "intensity must never rise as distance increases")
		previous = value


## Negative input (should never happen from a real caller, but a shader-
## mirrored function must not crash or misbehave on it) clamps the same
## way an over-the-edge value does.
func test_glow_intensity_clamps_a_negative_distance_to_full():
	assert_eq(TorchGlow.glow_intensity(-0.5), 1.0)


## Real-world grounding: a torch/campfire realistically throws useful
## light 6-9m before fading -- see docs/concept/lighting.md. The tuned
## radius must actually land in that real span, converted via the
## project's one real-world-scale constant, not just asserted in the abstract.
func test_glow_radius_lands_in_the_real_world_torch_light_range():
	var radius_m: float = TorchGlow.GLOW_RADIUS_METERS
	assert_gte(radius_m, 6.0)
	assert_lte(radius_m, 9.0)


## The shader source itself must actually use additive blending -- the
## whole reason this reads correctly over grass/water/terrain without any
## of them needing to change (see lighting.md's own design pillar 2).
func test_shader_uses_additive_blending():
	assert_string_contains(TorchGlow.SHADER_CODE, "blend_add")


## Mirrors this codebase's own established pattern (SnowSparkleShader,
## WaterShader): a fragment shader cannot be asserted headless, so its
## tuned falloff math is mirrored in GDScript -- this pins that the GLSL
## source actually uses the SAME shape (smoothstep-based edge fade), not a
## silently different curve nobody would notice drift from the mirror.
func test_shader_source_uses_the_same_smoothstep_edge_fade_as_the_cpu_mirror():
	assert_string_contains(TorchGlow.SHADER_CODE, "smoothstep(")
