extends GutTest

## GPU river flow -- see river_flow_shader.gd and docs/concept/rivers.md.

const RiverFlowShader = preload("res://src/rendering/river_flow_shader.gd")
const TerrainPassability = preload("res://src/gameplay/terrain_passability.gd")

var flow: RiverFlowShader


func before_each():
	flow = RiverFlowShader.new()


func test_make_material_uses_the_real_shader_code():
	var material := flow.make_material()
	assert_eq(material.shader.code, RiverFlowShader.SHADER_CODE)


func test_shared_material_is_the_same_instance_every_call():
	assert_eq(flow.shared_material(), flow.shared_material())


func test_default_uniforms_match_the_tuned_constants():
	var material := flow.shared_material()
	assert_eq(material.get_shader_parameter("min_flow_speed"), RiverFlowShader.MIN_FLOW_SPEED)
	assert_eq(material.get_shader_parameter("max_flow_speed"), RiverFlowShader.MAX_FLOW_SPEED)
	assert_eq(material.get_shader_parameter("streak_frequency"), RiverFlowShader.STREAK_FREQUENCY)
	assert_eq(material.get_shader_parameter("streak_sharpness"), RiverFlowShader.STREAK_SHARPNESS)
	assert_eq(material.get_shader_parameter("streak_alpha"), RiverFlowShader.STREAK_ALPHA)
	assert_eq(material.get_shader_parameter("streak_color"), RiverFlowShader.STREAK_COLOR)
	assert_eq(material.get_shader_parameter("turbulence_strength"), RiverFlowShader.TURBULENCE_STRENGTH)
	assert_eq(material.get_shader_parameter("turbulence_scale"), RiverFlowShader.TURBULENCE_SCALE)
	assert_eq(material.get_shader_parameter("turbulence_speed"), RiverFlowShader.TURBULENCE_SPEED)


# -- speed_fraction_for_slope_deg: real terrain steepness -> visual flow speed

## Reported directly: "more natural water flow" -- flow speed was uniform
## everywhere, real rivers run faster where the terrain is steeper. Reuses
## TerrainPassability.HARD_THRESHOLD_DEG (already the real "genuine
## scrambling/technical-climbing" anchor BiomeClassifier's own
## SLOPE_MOUNTAIN_THRESHOLD_DEG reuses for a different purpose) as the top
## of the range, rather than inventing a second, independently-eyeballed
## steepness cap.
func test_speed_fraction_is_zero_on_flat_ground():
	assert_eq(RiverFlowShader.speed_fraction_for_slope_deg(0.0), 0.0)


func test_speed_fraction_is_one_at_or_beyond_the_hard_threshold():
	assert_eq(RiverFlowShader.speed_fraction_for_slope_deg(TerrainPassability.HARD_THRESHOLD_DEG), 1.0)
	assert_eq(RiverFlowShader.speed_fraction_for_slope_deg(TerrainPassability.HARD_THRESHOLD_DEG + 30.0), 1.0)


func test_speed_fraction_increases_monotonically_with_slope():
	var previous := 0.0
	for slope_deg in range(0, int(TerrainPassability.HARD_THRESHOLD_DEG), 5):
		var fraction := RiverFlowShader.speed_fraction_for_slope_deg(float(slope_deg))
		assert_gte(fraction, previous, "speed fraction must never decrease as slope increases")
		previous = fraction


func test_speed_fraction_stays_in_unit_range():
	for slope_deg in [-5.0, 0.0, 10.0, 45.0, 90.0, 500.0]:
		assert_between(RiverFlowShader.speed_fraction_for_slope_deg(slope_deg), 0.0, 1.0)


# -- streak_intensity: the CPU mirror of the shader's periodic-streak math --
# (turbulence is NOT mirrored here, same as WaterShader never mirroring its
# own cosmetic wind-shimmer noise -- only the ripple PHYSICS that another
# caller needs to reason about gets a CPU twin; a pure decorative wobble
# doesn't. flow_speed is now an explicit argument, not a shared constant,
# since real speed now varies per river cell.)

func test_streak_intensity_stays_in_unit_range():
	for along in [0.0, 3.7, 50.0, -22.0]:
		for t in [0.0, 0.5, 1.3, 10.0]:
			assert_between(RiverFlowShader.streak_intensity(along, t, RiverFlowShader.MAX_FLOW_SPEED), 0.0, 1.0)


## A single set of parallel streaks, not constant brightness -- the whole
## point of the technique (see the shader's own comment). A real scan along
## the flow axis at a fixed instant must find both bright peaks and near-zero
## troughs, not read as a flat glow.
func test_streak_intensity_is_not_uniform_along_the_flow_axis():
	var found_bright := false
	var found_dark := false
	for i in range(200):
		var value := RiverFlowShader.streak_intensity(float(i) * 0.5, 0.0, RiverFlowShader.MAX_FLOW_SPEED)
		if value > 0.5:
			found_bright = true
		if value < 0.05:
			found_dark = true
	assert_true(found_bright, "expected at least one bright streak peak")
	assert_true(found_dark, "expected at least one dark trough between streaks")


## The whole point of "flow": the pattern must actually move over time, not
## sit static -- a fixed point's intensity must differ from one instant to
## the next.
func test_streak_intensity_advances_with_time():
	var at_start := RiverFlowShader.streak_intensity(10.0, 0.0, RiverFlowShader.MAX_FLOW_SPEED)
	var at_later := RiverFlowShader.streak_intensity(10.0, 0.3, RiverFlowShader.MAX_FLOW_SPEED)
	assert_ne(at_start, at_later)


## flow_speed only ever multiplies TIME, so at t=0 it can't show up yet --
## sampled across a spread of positions at a fixed later instant instead.
## Real: a steep (fast) river cell's pattern must actually move differently
## from a gentle (slow) one's, not have the parameter plumbed through unused.
func test_streak_intensity_depends_on_flow_speed():
	var found_a_difference := false
	for i in range(20):
		var along := float(i) * 3.0
		var slow := RiverFlowShader.streak_intensity(along, 0.4, RiverFlowShader.MIN_FLOW_SPEED)
		var fast := RiverFlowShader.streak_intensity(along, 0.4, RiverFlowShader.MAX_FLOW_SPEED)
		if not is_equal_approx(slow, fast):
			found_a_difference = true
			break
	assert_true(found_a_difference, "flow_speed must actually affect the streak pattern")


func test_streak_intensity_is_deterministic():
	assert_eq(
		RiverFlowShader.streak_intensity(12.0, 4.0, RiverFlowShader.MAX_FLOW_SPEED),
		RiverFlowShader.streak_intensity(12.0, 4.0, RiverFlowShader.MAX_FLOW_SPEED)
	)
