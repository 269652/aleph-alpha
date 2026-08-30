extends GutTest

## GPU river flow -- see river_flow_shader.gd and docs/concept/rivers.md.

const RiverFlowShader = preload("res://src/rendering/river_flow_shader.gd")
const TerrainPassability = preload("res://src/gameplay/terrain_passability.gd")
const HillshadeShader = preload("res://src/rendering/hillshade_shader.gd")
const WaterShader = preload("res://src/rendering/water_shader.gd")

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


# -- "make the flow effect more visible" (2026-08-30) --
#
# Reported directly, after the z-order fix above made the effect actually
# reach the screen: it still reads as a subtle, easy-to-miss glint rather
# than obviously flowing water. Two real, measured causes, not a single
# "raise the alpha" guess:
#   1. STREAK_ALPHA=0.35 was faint even in isolation, and now sits UNDER a
#      hillshade overlay that can paint up to alpha 0.55 of near-black on
#      the very same tile (HillshadeShader.MAX_SHADOW_ALPHA) -- the streak
#      needs to punch through that darkness, not just be visible in a
#      vacuum.
#   2. STREAK_SHARPNESS=4.0 raises a clamped sine to the 4th power, which
#      keeps the bright (>0.5 intensity) part of each cycle to only ~18% of
#      the period (see the derivation below) -- a thin, sparse band, not a
#      current that visibly covers the water.
#
# These two tests measure both causes directly against real trig, not an
# eyeballed "looks better" judgment, and are RED against the prior
# STREAK_ALPHA=0.35 / STREAK_SHARPNESS=4.0 baseline.

## Prior baseline this pass is measured against (the exact values shipped
## by the z-order fix in eae510d, before this visibility pass).
const _PRIOR_STREAK_ALPHA := 0.35
const _PRIOR_STREAK_SHARPNESS := 4.0
const _PRIOR_STREAK_COLOR := Color(0.75, 0.88, 1.0)

func test_streak_alpha_was_raised_above_the_reported_too_faint_baseline():
	assert_gt(RiverFlowShader.STREAK_ALPHA, _PRIOR_STREAK_ALPHA,
		"STREAK_ALPHA must be raised from the 0.35 baseline that read as an easy-to-miss glint")
	assert_eq(RiverFlowShader.STREAK_ALPHA, 0.5, "tuned value pinned, not left to drift")


## The "never fully opaque" ceiling this project's own overlays already
## establish: WaterShader.WATER_ALPHA (0.6, the base water tile itself) and
## HillshadeShader.MAX_SHADOW_ALPHA (0.55, the darkening overlay river-flow
## now draws on top of) are this codebase's own real precedent for "visible
## but not overwhelming." River-flow is a SPARSE, pulsing highlight on top
## of both -- it must stay under both, never becoming the dominant layer in
## the stack or reading as opaque/UI-like.
func test_streak_alpha_stays_under_this_projects_own_overlay_alpha_precedents():
	assert_lt(RiverFlowShader.STREAK_ALPHA, HillshadeShader.MAX_SHADOW_ALPHA,
		"river-flow highlight must stay under hillshade's own established overlay ceiling")
	assert_lt(RiverFlowShader.STREAK_ALPHA, WaterShader.WATER_ALPHA,
		"river-flow highlight must stay under the base water overlay's own opacity")


## Real derivation, not an eyeballed number: for streak_intensity's
## pow(max(sin(phase*TAU), 0), STREAK_SHARPNESS), the fraction of one full
## period where intensity exceeds 0.5 is (pi - 2*asin(0.5^(1/n))) / (2*pi).
## At the prior n=4 that's ~18.1% of the period -- a thin band. At the new,
## broadened sharpness it must be at least ~22%, a real, measurably wider
## current at any instant, while a lower bound (not just "bigger is better")
## keeps it reading as a streak rather than dissolving into a flat, motion-
## less tint (a lower bound of 0 would trivially pass at STREAK_SHARPNESS=0,
## which is a constant, not a streak at all).
func test_streak_bright_duty_fraction_is_measurably_broader_than_the_prior_sharpness():
	var period := 1.0 / RiverFlowShader.STREAK_FREQUENCY
	var samples := 2000
	var bright_count := 0
	for i in range(samples):
		var along := (float(i) / float(samples)) * period
		if RiverFlowShader.streak_intensity(along, 0.0, RiverFlowShader.MAX_FLOW_SPEED) > 0.5:
			bright_count += 1
	var bright_fraction := float(bright_count) / float(samples)
	assert_gt(bright_fraction, 0.22,
		"the bright (>0.5) part of the streak cycle must cover a measurably broader fraction of the water than the prior sharpness=4.0's ~18%%")
	assert_lt(bright_fraction, 0.45,
		"must still read as a periodic streak, not broaden into a constant, motionless-looking tint")
	assert_lt(RiverFlowShader.STREAK_SHARPNESS, _PRIOR_STREAK_SHARPNESS,
		"STREAK_SHARPNESS must be lowered from the prior 4.0 to broaden the visible band")


## The pale highlight color itself was raised too -- brightening the color
## increases the blended result's luminance at the SAME alpha (lerp(dark
## background, brighter color, alpha) lands lighter), which is the second,
## alpha-independent lever for punching through a near-black hillshade tile
## sitting underneath, not just "brighter in isolation." Every channel must
## move up (never darken), and it must stay a pale water-toned highlight,
## not a saturated/neon hue -- still all channels close to 1.0, blue
## remaining the brightest channel exactly as the prior color already was.
func test_streak_color_was_brightened_without_turning_saturated_or_neon():
	var prior := _PRIOR_STREAK_COLOR
	var new_color := RiverFlowShader.STREAK_COLOR
	assert_gte(new_color.r, prior.r, "red channel must not darken")
	assert_gte(new_color.g, prior.g, "green channel must not darken")
	assert_gte(new_color.b, prior.b, "blue channel must not darken")
	assert_true(new_color.r > prior.r or new_color.g > prior.g,
		"at least one channel must genuinely brighten, not just hold steady")
	for channel in [new_color.r, new_color.g, new_color.b]:
		assert_between(channel, 0.7, 1.0, "must stay a pale highlight, not a saturated/neon hue")
	assert_gte(new_color.b, new_color.r, "blue stays the dominant channel -- a water highlight, not a warm/neutral tint")
