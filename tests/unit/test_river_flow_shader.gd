extends GutTest

## GPU river flow -- see river_flow_shader.gd and docs/concept/rivers.md.

const RiverFlowShader = preload("res://src/rendering/river_flow_shader.gd")

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
	assert_eq(material.get_shader_parameter("flow_speed"), RiverFlowShader.FLOW_SPEED)
	assert_eq(material.get_shader_parameter("streak_frequency"), RiverFlowShader.STREAK_FREQUENCY)
	assert_eq(material.get_shader_parameter("streak_sharpness"), RiverFlowShader.STREAK_SHARPNESS)
	assert_eq(material.get_shader_parameter("streak_alpha"), RiverFlowShader.STREAK_ALPHA)
	assert_eq(material.get_shader_parameter("streak_color"), RiverFlowShader.STREAK_COLOR)


# -- streak_intensity: the CPU mirror of the shader's fragment() math -------

func test_streak_intensity_stays_in_unit_range():
	for along in [0.0, 3.7, 50.0, -22.0]:
		for t in [0.0, 0.5, 1.3, 10.0]:
			assert_between(RiverFlowShader.streak_intensity(along, t), 0.0, 1.0)


## A single set of parallel streaks, not constant brightness -- the whole
## point of the technique (see the shader's own comment). A real scan along
## the flow axis at a fixed instant must find both bright peaks and near-zero
## troughs, not read as a flat glow.
func test_streak_intensity_is_not_uniform_along_the_flow_axis():
	var found_bright := false
	var found_dark := false
	for i in range(200):
		var value := RiverFlowShader.streak_intensity(float(i) * 0.5, 0.0)
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
	var at_start := RiverFlowShader.streak_intensity(10.0, 0.0)
	var at_later := RiverFlowShader.streak_intensity(10.0, 0.3)
	assert_ne(at_start, at_later)


func test_streak_intensity_is_deterministic():
	assert_eq(RiverFlowShader.streak_intensity(12.0, 4.0), RiverFlowShader.streak_intensity(12.0, 4.0))
