extends GutTest

## GPU river flow -- see river_flow_shader.gd and docs/concept/rivers.md.

const RiverFlowShader = preload("res://src/rendering/river_flow_shader.gd")
const RiverPhaseField = preload("res://src/world/river_phase_field.gd")
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
	assert_eq(material.get_shader_parameter("wavelength_px"), RiverFlowShader.WAVELENGTH_PX)
	assert_eq(material.get_shader_parameter("streak_rate_hz"), RiverPhaseField.STREAK_RATE_HZ)
	assert_eq(material.get_shader_parameter("streak_sharpness"), RiverFlowShader.STREAK_SHARPNESS)
	assert_eq(material.get_shader_parameter("streak_alpha"), RiverFlowShader.STREAK_ALPHA)
	assert_eq(material.get_shader_parameter("turbulence_wavelengths"), RiverFlowShader.TURBULENCE_WAVELENGTHS)
	assert_eq(material.get_shader_parameter("foam_coverage"), RiverFlowShader.FOAM_COVERAGE)


# -- the three fixed defects ------------------------------------------------

## DEFECT 3: the old turbulence displaced the phase by +/-1.8 WAVELENGTHS,
## which decorrelates bands rather than wavering them -- the iso-phase map
## folds back on itself. Expressing displacement as a fraction of a
## wavelength makes that error impossible to reintroduce by accident.
func test_turbulence_cannot_fold_the_phase_map():
	assert_lt(
		RiverFlowShader.TURBULENCE_WAVELENGTHS, 0.5,
		"turbulence past half a wavelength scrambles the bands instead of bending them"
	)
	assert_gt(RiverFlowShader.TURBULENCE_WAVELENGTHS, 0.0, "some waver is the point")


## DEFECT 2: one global temporal rate. Speed must NOT appear in the phase's
## time term at all -- that is what made the fastest rivers alias past
## Nyquist and visibly flow backwards.
func test_the_streak_advances_at_one_rate_regardless_of_speed():
	# streak_intensity takes no speed argument by design; the same phase and
	# time must give the same answer whatever a cell's current is.
	var a := RiverFlowShader.streak_intensity(0.3, 12.0, 0.4)
	var b := RiverFlowShader.streak_intensity(0.3, 12.0, 0.4)
	assert_eq(a, b)
	assert_false(
		RiverFlowShader.SHADER_CODE.contains("TIME * flow_speed"),
		"a per-cell speed in the time term is exactly what caused the aliasing"
	)


## DEFECT 1: the phase must come from the BAKED course phase, not from
## projecting an absolute world position onto a per-tile direction.
func test_the_shader_reads_a_baked_phase_rather_than_projecting_world_position():
	assert_true(
		RiverFlowShader.SHADER_CODE.contains("baked_phase"),
		"the continuous course phase is the whole fix"
	)
	assert_false(
		RiverFlowShader.SHADER_CODE.contains("dot(world_pos, flow_dir)"),
		"projecting absolute world position is what reset the phase every tile"
	)


## Two cells one wavelength apart along the flow must be at the same point
## in the streak cycle -- the continuity the whole rewrite exists for.
func test_points_one_wavelength_apart_are_in_phase():
	var here := RiverFlowShader.streak_intensity(0.2, 0.0, 0.0)
	var one_on := RiverFlowShader.streak_intensity(0.2, RiverFlowShader.WAVELENGTH_PX, 0.0)
	assert_almost_eq(here, one_on, 0.0001)


## The shader's wavelength and the phase field's must agree, or the pattern
## would advance at one scale and repeat at another.
func test_the_shader_wavelength_agrees_with_the_phase_field():
	assert_almost_eq(
		RiverFlowShader.WAVELENGTH_PX,
		RiverPhaseField.STREAK_WAVELENGTH_TILES * RiverFlowShader.TILE_SIZE_PX,
		0.0001
	)


# -- speed now reads through the REAL solved current -------------------------

func test_a_still_reach_reads_as_no_speed():
	assert_eq(RiverFlowShader.speed_fraction_for_velocity(0.0), 0.0)


func test_a_fast_real_current_saturates_the_speed_scale():
	assert_eq(RiverFlowShader.speed_fraction_for_velocity(50.0), 1.0)


## Calibrated against real river speeds: NIWA/Jowett call 0.3-0.5 m/s "good"
## habitat flow and USGS-gauged flood peaks reach ~3 m/s, so an ordinary
## river must land mid-scale rather than saturating.
func test_an_ordinary_real_current_lands_mid_scale():
	assert_between(RiverFlowShader.speed_fraction_for_velocity(0.7), 0.15, 0.6)


func test_speed_fraction_rises_with_real_velocity():
	assert_gt(
		RiverFlowShader.speed_fraction_for_velocity(2.0),
		RiverFlowShader.speed_fraction_for_velocity(0.5)
	)


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
#
# Signature changed with the rewrite: (baked_phase, along_px, time). Speed
# is deliberately GONE from it -- a per-cell speed in the time term is
# exactly what aliased. Turbulence and foam are not mirrored, for the same
# reason WaterShader never mirrors its own wind shimmer: only physics
# another caller might reason about gets a CPU twin, not decoration.

func test_streak_intensity_stays_in_unit_range():
	for along in [0.0, 3.7, 50.0, -22.0]:
		for t in [0.0, 0.5, 1.3, 10.0]:
			assert_between(RiverFlowShader.streak_intensity(0.4, along, t), 0.0, 1.0)


## A set of parallel streaks, not constant brightness -- a real scan along
## the flow axis at a fixed instant must find both bright peaks and
## near-zero troughs, not read as a flat glow.
func test_streak_intensity_is_not_uniform_along_the_flow_axis():
	var found_bright := false
	var found_dark := false
	for i in range(200):
		var value := RiverFlowShader.streak_intensity(0.0, float(i) * 0.25, 0.0)
		if value > 0.5:
			found_bright = true
		if value < 0.05:
			found_dark = true
	assert_true(found_bright, "expected at least one bright streak peak")
	assert_true(found_dark, "expected at least one dark trough between streaks")


## The pattern must actually move over time.
func test_streak_intensity_advances_with_time():
	assert_ne(
		RiverFlowShader.streak_intensity(0.1, 10.0, 0.0),
		RiverFlowShader.streak_intensity(0.1, 10.0, 0.6)
	)


## Advancing time by exactly one period must return the pattern to where it
## started -- the period being 1/STREAK_RATE_HZ, one global constant.
func test_the_pattern_repeats_after_exactly_one_period():
	var period := 1.0 / RiverPhaseField.STREAK_RATE_HZ
	assert_almost_eq(
		RiverFlowShader.streak_intensity(0.1, 10.0, 0.0),
		RiverFlowShader.streak_intensity(0.1, 10.0, period),
		0.0001
	)


## The baked course phase must genuinely shift the pattern -- it is the
## whole mechanism by which neighbouring tiles line up.
func test_the_baked_phase_shifts_the_pattern():
	assert_ne(
		RiverFlowShader.streak_intensity(0.0, 5.0, 0.0),
		RiverFlowShader.streak_intensity(0.5, 5.0, 0.0)
	)


func test_streak_intensity_is_deterministic():
	assert_eq(
		RiverFlowShader.streak_intensity(0.3, 12.0, 4.0),
		RiverFlowShader.streak_intensity(0.3, 12.0, 4.0)
	)


# -- "make the flow effect more visible" (2026-08-30) ------------------------
#
# PORTED, not re-derived. These four claims came from a separate, concurrent
# fix for a "make the flow effect more visible" report that landed while the
# phase-field rewrite was in progress. The rewrite changed the phase
# MECHANISM; these constants are orthogonal to it, so their tuning is kept
# intact and their regression tests carried across rather than silently
# overwritten. Only the duty-fraction test's plumbing changed, to match
# streak_intensity's new (baked_phase, along_px, time) signature -- the
# claim and its thresholds are theirs, unaltered.

const _PRIOR_STREAK_ALPHA := 0.35
const _PRIOR_STREAK_SHARPNESS := 4.0
const _PRIOR_STREAK_COLOR := Color(0.75, 0.88, 1.0)
const HillshadeShader = preload("res://src/rendering/hillshade_shader.gd")
const WaterShader = preload("res://src/rendering/water_shader.gd")


func test_streak_alpha_was_raised_above_the_reported_too_faint_baseline():
	assert_gt(
		RiverFlowShader.STREAK_ALPHA, _PRIOR_STREAK_ALPHA,
		"the prior alpha was reported as an easy-to-miss glint"
	)
	assert_eq(RiverFlowShader.STREAK_ALPHA, 0.5, "tuned value pinned, not left to drift")


## The streak sits UNDER HillshadeShader's own overlay (up to 0.55 of
## near-black on the same tile), so it needs contrast to punch through --
## but it must never outweigh either the shading it sits on or the base
## water tile it decorates.
func test_streak_alpha_stays_under_this_projects_own_overlay_alpha_precedents():
	assert_lt(RiverFlowShader.STREAK_ALPHA, HillshadeShader.MAX_SHADOW_ALPHA)
	assert_lt(RiverFlowShader.STREAK_ALPHA, WaterShader.WATER_ALPHA)


## The bright (>0.5) part of each streak cycle must cover a measurably
## broader fraction of the water than the prior sharpness=4.0's ~18%, while
## still reading as a periodic streak rather than a flat, motionless tint.
## Duty fraction depends only on the sharpness exponent, so the rewrite's
## change of wavelength and phase source cannot affect it.
func test_streak_bright_duty_fraction_is_measurably_broader_than_the_prior_sharpness():
	var samples := 2000
	var bright_count := 0
	for i in range(samples):
		var along := (float(i) / float(samples)) * RiverFlowShader.WAVELENGTH_PX
		if RiverFlowShader.streak_intensity(0.0, along, 0.0) > 0.5:
			bright_count += 1
	var bright_fraction := float(bright_count) / float(samples)
	assert_gt(
		bright_fraction, 0.22,
		"the bright part of the cycle must cover measurably more water than the prior ~18%"
	)
	assert_lt(
		bright_fraction, 0.45,
		"must still read as a periodic streak, not a constant, motionless-looking tint"
	)
	assert_lt(RiverFlowShader.STREAK_SHARPNESS, _PRIOR_STREAK_SHARPNESS)


## Brightening the colour is the second, alpha-independent lever: the blend
## lands lighter at the same alpha, which matters most over a near-black
## hillshade tile. It must stay a pale water-toned highlight, not a
## saturated or neon hue, with blue still dominant.
func test_streak_color_was_brightened_without_turning_saturated_or_neon():
	var new_color: Color = RiverFlowShader.STREAK_COLOR
	assert_gte(new_color.r, _PRIOR_STREAK_COLOR.r, "red channel must not darken")
	assert_gte(new_color.g, _PRIOR_STREAK_COLOR.g, "green channel must not darken")
	assert_gte(new_color.b, _PRIOR_STREAK_COLOR.b, "blue channel must not darken")
	assert_true(
		new_color.r > _PRIOR_STREAK_COLOR.r or new_color.g > _PRIOR_STREAK_COLOR.g,
		"at least one channel must actually brighten"
	)
	for channel in [new_color.r, new_color.g, new_color.b]:
		assert_between(channel, 0.7, 1.0, "must stay a pale highlight, not a saturated/neon hue")
	assert_gte(new_color.b, new_color.r, "blue stays dominant -- a water highlight")
