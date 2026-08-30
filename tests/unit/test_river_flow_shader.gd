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
const OpenChannelFlow = preload("res://src/world/open_channel_flow.gd")

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
	assert_eq(material.get_shader_parameter("band0_color"), RiverFlowShader.BAND_COLORS[0])
	assert_eq(material.get_shader_parameter("band4_color"), RiverFlowShader.BAND_COLORS[4])


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


# -- the channel cross-section ----------------------------------------------
#
# THE fix for "doesn't look natural": the river used to be one flat slab of
# colour. It now draws its real parabolic cross-section in flat bands --
# light at the shallow edge, dark at the deep centreline -- which is what
# makes it read as a channel. Banded by cross-channel FRACTION, not
# absolute metres, so a small stream shows structure too.

func test_the_shallow_edge_is_the_first_band():
	assert_eq(RiverFlowShader.cross_section_band_for(0.0), 0)


func test_the_deep_centreline_is_the_last_band():
	assert_eq(
		RiverFlowShader.cross_section_band_for(1.0),
		ProceduralRiverFlowSprite.DEPTH_BANDS - 1
	)


func test_bands_deepen_monotonically_toward_the_centreline():
	var previous := -1
	for step in 21:
		var band := RiverFlowShader.cross_section_band_for(float(step) / 20.0)
		assert_gte(band, previous, "bands must not lighten toward the centreline")
		previous = band


func test_every_band_is_reachable_across_a_real_channel():
	# Walking bank to centreline through the real parabolic profile must
	# actually visit every band -- otherwise the cross-section collapses
	# back toward a flat slab.
	var seen := {}
	for i in range(200):
		var across := float(i) / 199.0
		seen[RiverFlowShader.cross_section_band_for(
			OpenChannelFlow.cross_channel_depth_fraction(across)
		)] = true
	assert_eq(
		seen.size(), ProceduralRiverFlowSprite.DEPTH_BANDS,
		"a real channel crossing should show every band, saw %d" % seen.size()
	)


func test_bands_never_leave_their_valid_range():
	for fraction in [-1.0, 0.0, 0.5, 1.0, 5.0]:
		assert_between(
			RiverFlowShader.cross_section_band_for(fraction),
			0, ProceduralRiverFlowSprite.DEPTH_BANDS - 1
		)


## The palette must step evenly and darken monotonically, or the section
## reads as a gradient someone forgot to smooth rather than as banding.
func test_the_band_palette_darkens_evenly_toward_the_centreline():
	var colors: Array[Color] = RiverFlowShader.BAND_COLORS
	assert_eq(colors.size(), ProceduralRiverFlowSprite.DEPTH_BANDS)
	for i in range(colors.size() - 1):
		assert_gt(
			colors[i].v - colors[i + 1].v, 0.05,
			"band %d and %d are too close to read as separate" % [i, i + 1]
		)


# -- fast flow ---------------------------------------------------------------

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


## The dashes must stay brighter than every band they are drawn over.
func test_the_wave_dashes_are_brighter_than_every_band():
	for band in RiverFlowShader.BAND_COLORS:
		assert_gt(RiverFlowShader.WAVE_COLOR.v, band.v)
