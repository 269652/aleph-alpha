extends GutTest

## Stylized cartoon river water -- see river_flow_shader.gd and
## docs/concept/rivers.md's "Flow rendering" section.
##
## The art direction is expressed as much by NEGATIVES as positives (no
## gradients, no noise, no soft edges), so several of these tests assert the
## ABSENCE of things -- which is what stops the shader drifting back toward
## the realism it deliberately moved away from.

const RiverFlowShader = preload("res://src/rendering/river_flow_shader.gd")
const RiverPhaseField = preload("res://src/world/river_phase_field.gd")
const ProceduralRiverFlowSprite = preload("res://src/rendering/procedural_river_flow_sprite.gd")
const WaterMovementModel = preload("res://src/gameplay/water_movement_model.gd")

var flow: RiverFlowShader


func before_each():
	flow = RiverFlowShader.new()


func test_make_material_uses_the_real_shader_code():
	assert_eq(flow.make_material().shader.code, RiverFlowShader.SHADER_CODE)


func test_shared_material_is_the_same_instance_every_call():
	assert_eq(flow.shared_material(), flow.shared_material())


func test_default_uniforms_match_the_tuned_constants():
	var material := flow.shared_material()
	assert_eq(material.get_shader_parameter("wavelength_px"), RiverFlowShader.WAVELENGTH_PX)
	assert_eq(material.get_shader_parameter("streak_rate_hz"), RiverPhaseField.STREAK_RATE_HZ)
	assert_eq(material.get_shader_parameter("line_thickness"), RiverFlowShader.LINE_THICKNESS)
	assert_eq(material.get_shader_parameter("shallow_color"), RiverFlowShader.SHALLOW_COLOR)
	assert_eq(material.get_shader_parameter("bank_color"), RiverFlowShader.BANK_COLOR)


# -- the art direction, asserted as negatives --------------------------------

## No noise anywhere. The realism passes used value_noise/hash fields for
## turbulence and foam speckle; a flat cel look has no place for either, and
## their return would be the clearest sign of drift.
func test_the_shader_contains_no_noise_at_all():
	for banned in ["value_noise", "value_hash", "turbulence"]:
		assert_false(
			RiverFlowShader.SHADER_CODE.contains(banned),
			"%s is noise -- the stylized look excludes it entirely" % banned
		)


## Every boundary must be a hard step(); a smoothstep is a gradient by
## another name.
## Checks for the CALL form specifically -- the shader's own comments
## mention smoothstep to explain why it is absent, and a bare substring
## match would flag that as a violation.
func test_the_shader_uses_no_smoothstep():
	assert_false(
		RiverFlowShader.SHADER_CODE.contains("smoothstep("),
		"a soft edge reads as a gradient, which this look excludes"
	)


## Opaque. Unlike this project's other overlays, this layer IS the river's
## surface -- a translucent stylized layer over the noisy realistic water
## beneath would read as neither.
func test_the_shader_outputs_a_fully_opaque_colour():
	assert_true(RiverFlowShader.SHADER_CODE.contains("wave_color, line), 1.0)"))


## The palette must be small and its bands clearly separated, or the flat
## bands read as a gradient someone forgot to smooth.
func test_the_depth_bands_are_clearly_separated_not_a_gradient():
	var shallow: Color = RiverFlowShader.SHALLOW_COLOR
	var mid: Color = RiverFlowShader.MID_COLOR
	var deep: Color = RiverFlowShader.DEEP_COLOR
	assert_gt(shallow.v - mid.v, 0.08, "shallow and mid must be visibly distinct")
	assert_gt(mid.v - deep.v, 0.08, "mid and deep must be visibly distinct")


## The bank outline must be darker than every water band, or it does not
## read as an outline.
func test_the_bank_outline_is_darker_than_any_water_band():
	for band in [RiverFlowShader.SHALLOW_COLOR, RiverFlowShader.MID_COLOR, RiverFlowShader.DEEP_COLOR]:
		assert_lt(RiverFlowShader.BANK_COLOR.v, band.v)


func test_the_wave_lines_are_brighter_than_every_water_band():
	for band in [RiverFlowShader.SHALLOW_COLOR, RiverFlowShader.MID_COLOR, RiverFlowShader.DEEP_COLOR]:
		assert_gt(RiverFlowShader.WAVE_COLOR.v, band.v)


# -- depth bands carry real gameplay meaning ---------------------------------
#
# The first threshold is WaterMovementModel.WADE_DEPTH_METERS itself, so the
# colour a player sees and what they can actually do never disagree.

func test_a_wadeable_depth_is_the_shallow_band():
	assert_eq(RiverFlowShader.depth_band_for(WaterMovementModel.WADE_DEPTH_METERS - 0.1), 0)


func test_a_swimmable_depth_leaves_the_shallow_band():
	assert_eq(RiverFlowShader.depth_band_for(WaterMovementModel.WADE_DEPTH_METERS + 0.1), 1)


func test_a_deep_river_is_the_deepest_band():
	assert_eq(RiverFlowShader.depth_band_for(10.0), 2)


func test_the_shallow_to_mid_boundary_is_exactly_the_wading_threshold():
	assert_eq(RiverFlowShader.MID_BAND_DEPTH_M, WaterMovementModel.WADE_DEPTH_METERS)


func test_depth_bands_never_leave_their_valid_range():
	for depth in [-5.0, 0.0, 0.9, 1.5, 3.0, 100.0]:
		assert_between(
			RiverFlowShader.depth_band_for(depth), 0, ProceduralRiverFlowSprite.DEPTH_BANDS - 1
		)


# -- fast flow and the bank flag ---------------------------------------------

func test_a_still_pool_is_not_fast():
	assert_false(RiverFlowShader.is_fast_flow(0.0))


func test_a_real_moving_river_is_fast():
	assert_true(RiverFlowShader.is_fast_flow(1.2))


## Calibrated against real figures rather than eyeballed: NIWA/Jowett call
## 0.3-0.5 m/s "good" instream flow, so the threshold sits above that band
## and well under a real flood peak (~3 m/s).
func test_the_fast_threshold_sits_between_real_habitat_flow_and_a_flood_peak():
	assert_gt(RiverFlowShader.FAST_FLOW_M_S, 0.5)
	assert_lt(RiverFlowShader.FAST_FLOW_M_S, 3.0)


func test_the_channel_centre_is_not_bank():
	assert_false(RiverFlowShader.is_bank_cell(0.0, 2.0))


func test_the_channel_edge_is_bank():
	assert_true(RiverFlowShader.is_bank_cell(2.0, 2.0))


func test_bank_detection_survives_a_zero_width_channel():
	assert_false(RiverFlowShader.is_bank_cell(1.0, 0.0))


# -- wave lines: hard-edged by construction ----------------------------------

## The CPU mirror returns a BOOL, not an intensity -- there is no partial
## coverage anywhere in this look, and a float return would invite one back.
func test_a_wave_line_is_present_at_the_start_of_a_cycle():
	assert_true(RiverFlowShader.is_wave_line(0.0, 0.0, 0.0))


func test_there_is_no_wave_line_mid_cycle():
	assert_false(RiverFlowShader.is_wave_line(0.5, 0.0, 0.0))


## Marks must be a minority of the water, or they stop reading as marks.
func test_wave_marks_cover_only_a_small_fraction_of_the_water():
	var hits := 0
	var total := 0
	for i in range(120):
		for j in range(40):
			var along := (float(i) / 120.0) * RiverFlowShader.WAVELENGTH_PX
			var across := (float(j) / 40.0) * RiverFlowShader.DASH_ROW_PX * 2.0
			total += 1
			if RiverFlowShader.is_wave_line(0.0, along, 0.0, across):
				hits += 1
	var coverage := float(hits) / float(total)
	assert_between(coverage, 0.02, 0.2, "wave marks should be sparse ticks, not stripes")


## THE fix for the first stylized attempt, whose lines ran unbroken across
## the whole channel and read as diagonal hazard tape. A mark must be
## bounded ACROSS the flow as well as along it -- so at a fixed point in
## the cycle, moving sideways must eventually leave the mark.
func test_a_wave_mark_is_a_dash_not_a_stripe_spanning_the_channel():
	var found_gap := false
	for j in range(200):
		var across := (float(j) / 200.0) * RiverFlowShader.DASH_ROW_PX * 3.0
		if not RiverFlowShader.is_wave_line(0.0, 0.0, 0.0, across):
			found_gap = true
			break
	assert_true(found_gap, "a mark that never ends across the flow is a stripe, not a dash")


## Alternate dash rows are offset half a step, so marks never line up into a
## visible grid. Brick offset rather than random jitter keeps this entirely
## noise-free while still breaking the regularity.
func test_alternate_dash_rows_are_offset_from_each_other():
	var row_a: Array[bool] = []
	var row_b: Array[bool] = []
	for i in range(60):
		var along := (float(i) / 60.0) * RiverFlowShader.WAVELENGTH_PX
		row_a.append(RiverFlowShader.is_wave_line(0.0, along, 0.0, 0.0))
		row_b.append(RiverFlowShader.is_wave_line(0.0, along, 0.0, RiverFlowShader.DASH_ROW_PX))
	assert_ne(row_a, row_b, "adjacent dash rows must not be in phase, or they form a grid")


func test_the_lines_scroll_over_time():
	var moved := false
	for i in range(20):
		var later := RiverFlowShader.is_wave_line(0.0, 2.0, float(i) * 0.1)
		if later != RiverFlowShader.is_wave_line(0.0, 2.0, 0.0):
			moved = true
			break
	assert_true(moved, "the wave lines must actually travel downstream")


## Still one global rate, so the scroll can never alias at low frame rates
## (see RiverPhaseField) -- hard-edged lines would strobe far more visibly
## than the old soft streaks if this regressed.
func test_the_scroll_rate_still_cannot_alias():
	assert_lt(RiverPhaseField.STREAK_RATE_HZ / 7.0, 0.5)
