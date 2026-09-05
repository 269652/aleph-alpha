extends GutTest

## Realistic flowing river water -- see river_flow_shader.gd and
## docs/concept/rivers.md's "Flow rendering" section.
##
## The tests that matter most here pin the two-phase advection TECHNIQUE
## rather than any tuned value: a periodic shape translated downstream can
## only read as marks sliding past, so the properties that make the surface
## genuinely deform instead are structural, and losing any of them puts the
## reported "just some moving strokes" straight back.

const RiverFlowShader = preload("res://src/rendering/river_flow_shader.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")
const RiverCatalog = preload("res://src/world/river_catalog.gd")
const ProceduralRiverFlowSprite = preload("res://src/rendering/procedural_river_flow_sprite.gd")
const OpenChannelFlow = preload("res://src/world/open_channel_flow.gd")
const WaterShader = preload("res://src/rendering/water_shader.gd")
const StoneSize = preload("res://src/world/stone_size.gd")

var flow: RiverFlowShader


func before_each():
	flow = RiverFlowShader.new()


func test_make_material_uses_the_real_shader_code():
	assert_eq(flow.make_material().shader.code, RiverFlowShader.SHADER_CODE)


func test_shared_material_is_the_same_instance_every_call():
	assert_eq(flow.shared_material(), flow.shared_material())


func test_default_uniforms_match_the_tuned_constants():
	var material := flow.shared_material()
	assert_eq(material.get_shader_parameter("advect_rate"), RiverFlowShader.ADVECT_RATE)
	assert_eq(material.get_shader_parameter("advect_strength"), RiverFlowShader.ADVECT_STRENGTH)
	assert_eq(material.get_shader_parameter("noise_scale"), RiverFlowShader.NOISE_SCALE)
	assert_eq(material.get_shader_parameter("line_count"), RiverFlowShader.LINE_COUNT)
	assert_eq(material.get_shader_parameter("line_width"), RiverFlowShader.LINE_WIDTH)
	assert_eq(material.get_shader_parameter("shore_pos"), RiverFlowShader.SHORE_POS)
	assert_eq(material.get_shader_parameter("band0_color"), RiverFlowShader.BAND_COLORS[0])
	assert_eq(material.get_shader_parameter("band4_color"), RiverFlowShader.BAND_COLORS[4])
	assert_eq(material.get_shader_parameter("flow_map_tiles"), float(RiverFlowShader.FLOW_MAP_TILES))
	assert_eq(
		material.get_shader_parameter("half_width_tiles"),
		RiverCatalog.RIVER_HALF_WIDTH_TILES
	)
	assert_eq(material.get_shader_parameter("tile_px"), RiverFlowShader.TILE_PX)


# -- the advection technique -------------------------------------------------
#
# THE fix for "just some moving strokes, not realistic water flow". A
# periodic shape TRANSLATED downstream can only read as marks sliding past;
# real water continuously DEFORMS. These pin the technique that does that,
# because it is structural -- losing any part of it puts the sliding-marks
# look straight back.

## THE property the whole technique rests on, stated in the direction that
## actually matters: a phase snapping back to zero drag is a discontinuity
## in the image it carries, so at that instant it must contribute NOTHING,
## or the reset shows as a pop.
##
## `crossfade_weight` is phase B's weight, so phase A's is 1.0 minus it --
## worth being explicit about, because reading it the other way round makes
## a correct implementation look broken and invites "fixing" it.
func test_whichever_phase_is_resetting_carries_zero_weight():
	var period := 1.0 / RiverFlowShader.ADVECT_RATE
	# Phase A resets at t = 0 -- and again one full cycle later.
	assert_almost_eq(1.0 - RiverFlowShader.crossfade_weight(0.0), 0.0, 0.0001)
	assert_almost_eq(1.0 - RiverFlowShader.crossfade_weight(period), 0.0, 0.0001)
	# Phase B runs half a cycle ahead, so it resets in between.
	assert_almost_eq(RiverFlowShader.crossfade_weight(period * 0.5), 0.0, 0.0001)


## The two phases must be treated IDENTICALLY, swept across a full cycle
## rather than spot-checked at the resets.
##
## The shader computes one number and splits it between the phases, so a
## sign or offset error could easily give phase B a different envelope from
## phase A -- passing the reset checks above while still making one phase
## louder than the other for most of its life. Written in envelope form,
## each phase's weight must depend only on its OWN age: silent at birth,
## peaking at mid-life, silent again at death.
##
## (Deliberately NOT "the younger phase is quieter" -- that reads plausible
## and is false. A phase fades IN from birth to mid-life, so between a
## quarter and half a cycle the younger phase is legitimately the louder
## one. The premise was tried and the sweep caught it.)
func test_both_phases_carry_the_same_triangular_envelope():
	var period := 1.0 / RiverFlowShader.ADVECT_RATE
	for i in range(240):
		var t := float(i) / 240.0 * period * 2.0
		var b_weight := RiverFlowShader.crossfade_weight(t)
		var a_weight := 1.0 - b_weight
		var a_age := fposmod(t * RiverFlowShader.ADVECT_RATE, 1.0)
		var b_age := fposmod(t * RiverFlowShader.ADVECT_RATE + 0.5, 1.0)
		assert_almost_eq(a_weight, 1.0 - absf(1.0 - 2.0 * a_age), 0.0001)
		assert_almost_eq(b_weight, 1.0 - absf(1.0 - 2.0 * b_age), 0.0001)


## And the two must always sum to exactly one, or the water would visibly
## pulse brighter and darker as the phases hand over.
func test_the_two_phase_weights_never_pulse_the_brightness():
	for i in range(240):
		var t := float(i) * 0.137
		var a_age := fposmod(t * RiverFlowShader.ADVECT_RATE, 1.0)
		var b_age := fposmod(t * RiverFlowShader.ADVECT_RATE + 0.5, 1.0)
		var total := (1.0 - absf(1.0 - 2.0 * a_age)) + (1.0 - absf(1.0 - 2.0 * b_age))
		assert_almost_eq(total, 1.0, 0.0001, "phase weights sum to %f at t=%f" % [total, t])


func test_the_crossfade_weight_stays_in_unit_range():
	for i in range(200):
		assert_between(RiverFlowShader.crossfade_weight(float(i) * 0.137), 0.0, 1.0)


## Distortion must never accumulate without bound -- that is what would
## smear the surface into streaks. Each phase resets, so the drag is capped.
func test_advection_distortion_is_bounded_and_never_accumulates():
	var largest := 0.0
	for i in range(2000):
		largest = maxf(largest, RiverFlowShader.advection_offset(float(i) * 0.05))
	assert_lte(
		largest, RiverFlowShader.ADVECT_STRENGTH + 0.0001,
		"drag must never exceed one phase's worth, or the surface smears"
	)


## Within a phase the surface really is being dragged -- if the offset never
## grew, the water would deform in place rather than flow anywhere.
func test_the_surface_is_actually_dragged_within_a_phase():
	var period := 1.0 / RiverFlowShader.ADVECT_RATE
	assert_gt(
		RiverFlowShader.advection_offset(period * 0.4),
		RiverFlowShader.advection_offset(period * 0.1)
	)


## The shader must genuinely sample the surface TWICE at different phases.
## One sample is the old translating-pattern failure by another name.
func test_the_shader_samples_two_advected_phases():
	assert_true(RiverFlowShader.SHADER_CODE.contains("phase_a"))
	assert_true(RiverFlowShader.SHADER_CODE.contains("phase_b"))
	assert_true(RiverFlowShader.SHADER_CODE.contains("(advect_strength * phase_a * advect_gate + drift)"))
	assert_true(RiverFlowShader.SHADER_CODE.contains("(advect_strength * phase_b * advect_gate + drift)"))


## THE seam bug the advection switch introduces if left alone. The surface
## field must be keyed to WORLD POSITION alone. The old streak pattern was
## fed a per-tile scrolling phase through the texture's red channel, and a
## per-tile offset applied to a noise field makes the noise jump at every
## single tile edge -- a grid of seams straight across the river.
##
## World position already decorrelates every reach from every other, for
## free and continuously, so no per-tile offset is needed or wanted.
func test_the_surface_field_is_keyed_to_world_position_alone():
	assert_true(
		RiverFlowShader.SHADER_CODE.contains("vec2 p = wp * noise_scale;"),
		"a per-tile offset added here would seam the noise at every tile edge"
	)
	assert_false(
		RiverFlowShader.SHADER_CODE.contains("course_offset"),
		"the per-tile phase channel must not offset the noise field"
	)


## Aliasing guard, kept from the earlier pass: at the measured ~7 fps floor
## the advection must stay far inside Nyquist, or the surface strobes.
func test_the_advection_rate_cannot_alias_at_the_worst_frame_rate():
	assert_lt(RiverFlowShader.ADVECT_RATE / 7.0, 0.5)


## Opaque IN the channel -- this layer IS the river surface -- and clipped
## to nothing past the bank curve, which is what frees the shoreline from
## the tile grid. The alpha is a mask, not translucency.
func test_the_shader_is_the_water_inside_and_nothing_outside():
	assert_true(RiverFlowShader.SHADER_CODE.contains("COLOR = vec4(body, wet)"))


## The tile size baked into the shader must be the world's real tile size --
## the layer is scaled, so this is TILE_SIZE (16), NOT ART_TILE_SIZE (32).
## Getting this wrong halves or doubles every reconstructed offset.
func test_the_shader_tile_size_is_the_world_tile_size():
	assert_eq(RiverFlowShader.TILE_PX, float(TerrainRenderer.TILE_SIZE))


## The colour ramp is continuous: swept from bank to centreline in small
## steps, no step may jump -- a jump IS a band edge, the exact square-maker
## this replaces.
func test_the_depth_ramp_has_no_jumps():
	var previous := RiverFlowShader.depth_color(0.0)
	for step in range(1, 101):
		var here := RiverFlowShader.depth_color(float(step) / 100.0)
		assert_lt(
			absf(here.v - previous.v), 0.035,
			"the ramp jumps at %.2f -- that is a band edge" % (float(step) / 100.0)
		)
		previous = here


func test_the_depth_ramp_still_darkens_toward_the_centreline():
	assert_gt(
		RiverFlowShader.depth_color(0.0).v,
		RiverFlowShader.depth_color(1.0).v + 0.2,
		"the cross-section must still visibly deepen"
	)


# -- the smooth waterline -----------------------------------------------------
#
# The other half of "soften / blend the shoreline": the water's outer edge
# is now the real bank curve (|across| == 1), drawn with a short feather,
# instead of the painted tile rectangle. Past the bank the overlay is
# transparent and the ground shows through.

func test_the_water_is_opaque_in_the_channel_and_gone_past_the_bank():
	assert_almost_eq(RiverFlowShader.bank_alpha(0.0), 1.0, 0.0001)
	assert_almost_eq(RiverFlowShader.bank_alpha(0.8), 1.0, 0.0001)
	assert_almost_eq(RiverFlowShader.bank_alpha(1.0), 0.5, 0.01)
	assert_almost_eq(RiverFlowShader.bank_alpha(1.0 + RiverFlowShader.BANK_FEATHER), 0.0, 0.0001)


func test_the_waterline_fades_monotonically():
	var previous := 1.1
	for step in 60:
		var here := RiverFlowShader.bank_alpha(0.7 + float(step) / 59.0 * 0.5)
		assert_lte(here, previous + 0.0001)
		previous = here


## The feather must live inside the painter's apron, or the fade gets
## clipped by the last painted tile and the straight edge returns.
func test_the_feather_fits_inside_the_painted_apron():
	var apron_fraction := RiverCatalog.RIVER_BANK_APRON_TILES / RiverCatalog.RIVER_HALF_WIDTH_TILES
	assert_lte(RiverFlowShader.BANK_FEATHER, apron_fraction - 0.05)


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


## The mirror has to actually mirror: two octaves, bounded in [0,1] like the
## shader's own, or the coverage numbers above measure nothing real.
func test_the_surface_mirror_stays_in_the_shaders_own_range():
	for i in range(60):
		for j in range(60):
			assert_between(RiverFlowShader.surface_value(float(i) * 0.7, float(j) * 0.9), 0.0, 1.0)


# -- world-anchored sampling ---------------------------------------------------
#
# THE fix for "there are still hard cuts / misalignments ... a sharp
# alignment error in the straight part". The field used to be sampled in
# each tile's rotated channel frame -- along = dot(world, flow_dir) -- and
# a rotation about the WORLD ORIGIN moves a point by (angle x its distance
# from the origin). This world is ~40,000 tiles wide, so when two
# neighbouring tiles snapped to direction bins even 7.5 degrees apart,
# their sample coordinates differed by THOUSANDS of tiles: the two patterns
# at the seam were simply unrelated noise. That fired on straight reaches
# too, whenever the course drifted past a bin boundary mid-reach.
#
# Now every sample is anchored at the fragment's own world position, and
# direction only steers SMALL offsets (the drag, the smear taps, the bend's
# perpendicular) -- never a rotation of a world-sized vector.

## Sampled at real world magnitudes (this is essential -- the bug is
## invisible near the origin), the field must stay nearly identical when
## the direction changes by one whole bin.
func test_the_pattern_survives_a_direction_bin_change():
	var angle_a := ProceduralRiverFlowSprite.angle_for_bin(3)
	var angle_b := ProceduralRiverFlowSprite.angle_for_bin(4)
	var dir_a := Vector2(sin(deg_to_rad(angle_a)), -cos(deg_to_rad(angle_a)))
	var dir_b := Vector2(sin(deg_to_rad(angle_b)), -cos(deg_to_rad(angle_b)))
	# The Dreisam's real neighbourhood: ~20,800 tiles east, ~4,600 down,
	# 16 px tiles, NOISE_SCALE cells -- coordinates in the tens of
	# thousands of noise cells, exactly where a frame rotation explodes.
	var base_x := 20800.0 * 16.0 * RiverFlowShader.NOISE_SCALE
	var base_y := 4600.0 * 16.0 * RiverFlowShader.NOISE_SCALE
	var total := 0.0
	var count := 0
	for i in range(24):
		for j in range(24):
			var px := base_x + float(i) * 0.43
			var py := base_y + float(j) * 0.39
			total += absf(
				RiverFlowShader.animated_field_value(px, py, dir_a, 1.3)
				- RiverFlowShader.animated_field_value(px, py, dir_b, 1.3)
			)
			count += 1
	var mean := total / float(count)
	# The budget in VISIBLE units: a mean field shift of 0.075 against the
	# field's typical cross-stroke gradient (~0.5/cell) displaces a stroke
	# boundary by ~0.15 cells -- about 3 art pixels of kink at a rare
	# bin-change seam, well under one stroke width (1 cell). The failure
	# this test was built against measured ~0.29+: completely unrelated
	# patterns meeting in a hard cut.
	assert_lt(
		mean, 0.075,
		"a one-bin direction change moves the field by %.3f on average -- a stroke-width seam"
			% mean
	)


## And the structural half: the shader must never build a sample coordinate
## by projecting the world position onto the flow frame.
func test_no_sample_coordinate_rotates_the_world_position():
	assert_false(
		RiverFlowShader.SHADER_CODE.contains("dot(world, flow_dir)"),
		"projecting world onto the flow frame rotates around the world origin"
	)
	assert_false(RiverFlowShader.SHADER_CODE.contains("dot(world, flow_perp)"))
	assert_true(
		RiverFlowShader.SHADER_CODE.contains("vec2 p = wp * noise_scale;"),
		"samples must be anchored at the fragment's own (snapped) world position"
	)


# -- flowing lines, not blobs ------------------------------------------------
#
# Requested in exactly those words: "can you flowing lines that morph". The
# two halves come from two different places, and both have to hold.
#
# The MORPHING is the two-phase advection above. The LINES are anisotropy:
# the field is compressed along the flow axis, so its features come out far
# longer downstream than they are wide -- streaklines, the way a real
# current shows itself. An isotropic field advected just as correctly still
# reads as drifting blobs, which is why this is pinned separately.

## The measurable difference between a line and a blob: the field must stay
## coherent much further ALONG the flow than ACROSS it -- now produced by
## the smear, so it holds for ANY direction, not just the frame axes.
func test_the_field_forms_lines_along_the_flow_not_blobs():
	var step := 0.45
	var dir := Vector2(1, 0)
	var along := RiverFlowShader.field_roughness(step, dir, true)
	var across := RiverFlowShader.field_roughness(step, dir, false)
	# 3x, not 2x: at 2x the contours close into rounded cells ("more like
	# perlin noise cells" -- reported after triangle-weighted smear taps
	# quietly halved the along-flow stretch). Long OPEN filaments that
	# merge and unmerge need the field to stay coherent several times
	# longer along the flow than across it.
	assert_gt(
		across, along * 3.0,
		"field changes %.4f across vs %.4f along -- too round to read as flowing lines"
			% [across, along]
	)


## And the same anisotropy must hold on a DIAGONAL flow -- a frame-free
## formulation earns its keep only if the lines follow every bearing.
func test_the_lines_follow_a_diagonal_flow_too():
	var step := 0.45
	var dir := Vector2(1, 1).normalized()
	var along := RiverFlowShader.field_roughness(step, dir, true)
	var across := RiverFlowShader.field_roughness(step, dir, false)
	assert_gt(across, along * 3.0)


## The smear is what produces that: enough taps that they overlap into a
## continuous stroke (gaps read as dashes), spaced to a real elongation.
func test_the_smear_taps_overlap_into_a_continuous_stroke():
	assert_lte(RiverFlowShader.SMEAR_SPACING, 1.0, "taps further than a cell apart leave gaps")
	assert_gte(RiverFlowShader.SMEAR_TAPS, 5)


## The lines must still run along each reach's own flow -- but oriented by
## SMEARING along the direction (a line-integral-convolution stroke),
## never by rotating the sample frame. The perpendicular still exists for
## the bend and the across-reconstruction.
func test_the_lines_are_oriented_by_smearing_not_frame_rotation():
	# The step is one smear_spacing along the tap's own heading. That
	# heading is now interpolated along the arc rather than fixed, but it
	# is still the FLOW's, and the frame itself is still never rotated.
	assert_true(RiverFlowShader.SHADER_CODE.contains(
		"normalize(mix(dir_start, dir_end, 0.5 + t) + vec2(1e-6, 0.0)) * smear_spacing;"
	))
	assert_true(RiverFlowShader.SHADER_CODE.contains(
		"normalize(mix(dir_start, dir_end, 0.5 - t) + vec2(1e-6, 0.0)) * smear_spacing;"
	))
	assert_true(RiverFlowShader.SHADER_CODE.contains("flow_perp = vec2(-flow_dir.y, flow_dir.x)"))


## Water is carried DOWNSTREAM. Dragging the field sideways as well would
## make the lines crab across the channel instead of running along it.
func test_the_drag_is_purely_downstream():
	# The drift rides the same flow_dir vector, so the travel stays purely
	# downstream too.
	# advect_gate stills the advection in standing water: it SCALES the
	# downstream term, it does not add a sideways one.
	assert_true(RiverFlowShader.SHADER_CODE.contains(
		"flow_dir * (advect_strength * phase_a * advect_gate + drift)"
	))
	assert_true(RiverFlowShader.SHADER_CODE.contains(
		"flow_dir * (advect_strength * phase_b * advect_gate + drift)"
	))


# -- the size of a flow line -------------------------------------------------
#
# From the second screenshot: the lines were real but ENORMOUS -- about 14
# tiles long and two wide, so they read as vast soft gradients sweeping over
# the river rather than as its surface. A correct technique at the wrong
# scale looks nothing like water.
#
# So the feature size is pinned in TILES, which is the only scale that means
# anything here: what matters is how many lines fit across a channel that is
# a handful of tiles wide, not what the noise constant happens to be.

## Several lines must fit ACROSS the channel. The rivers here run about four
## to six tiles bank to bank, so a feature wider than a tile leaves barely
## two lines across the whole river and the surface goes back to flat.
func test_flow_lines_are_narrow_enough_that_several_fit_across_a_channel():
	# The WORLD tile (16 px -- the layer is scaled), not the 32 px art tile:
	# world_pos in the shader is in final world pixels.
	var width_tiles := RiverFlowShader.feature_width_px() / float(TerrainRenderer.TILE_SIZE)
	assert_lte(
		width_tiles, 1.0,
		"a flow line is %.2f tiles wide -- too few fit across a 4-6 tile river" % width_tiles
	)


## But not so fine it dissolves into static. Below a few pixels the lines
## alias against the pixel grid instead of reading as structure.
func test_flow_lines_are_not_so_fine_they_become_static():
	assert_gte(RiverFlowShader.feature_width_px(), 4.0)


## And they must be LINES -- clearly longer than they are wide, but still
## short enough to see a line begin and end within a screen of river.
func test_flow_lines_are_a_few_tiles_long():
	var length_tiles := RiverFlowShader.feature_length_px() / float(TerrainRenderer.TILE_SIZE)
	assert_between(
		length_tiles, 4.0, 8.0,
		"a flow line is %.2f world tiles long" % length_tiles
	)


## The drag is DEFORMATION, not travel -- reversed from the earlier contract
## ("the drag is what carries the surface downstream", drag >= 0.5 feature
## lengths per phase). Looked at on the real GPU (tools/probe_river_motion.gd)
## a 7.2-cell drag never read as travel at all: the two phases are copies
## of the field offset by HALF the drag, and at 45 world px apart they are
## uncorrelated, so the crossfade is a dissolve between two unrelated
## patterns -- a kink fades out where it is and a different one fades in
## elsewhere. "A wobble stays at place." Travel that the eye can follow is
## the linear drift, and for a kink to survive the crossfade and ride it
## the two copies must stay correlated: their offset, half the drag, under
## one noise cell.
func test_the_drag_is_a_small_deformation_so_kinks_survive_the_crossfade():
	assert_lte(
		RiverFlowShader.ADVECT_STRENGTH * 0.5, 1.0,
		"phases offset by %.2f cells are uncorrelated copies -- the fade dissolves every kink"
			% (RiverFlowShader.ADVECT_STRENGTH * 0.5)
	)
	assert_gt(RiverFlowShader.ADVECT_STRENGTH, 0.0, "no drag at all is the old sliding-marks failure")
	# Within its own phase each copy still genuinely stretches downstream.
	var period := 1.0 / RiverFlowShader.ADVECT_RATE
	assert_gt(RiverFlowShader.advection_offset(period * 0.4), RiverFlowShader.advection_offset(period * 0.1))


# -- standing turbulence -----------------------------------------------------
#
# Reported directly: "better but still no fluid like animation no
# turbulences streams flows". Accurate again -- the lines ran ruler-straight
# and rigid, because a uniformly-stretched field advected uniformly can do
# nothing else.
#
# Real turbulence over a rough riverbed organises into quasi-STATIONARY
# structures: boils and standing eddies shed from bedforms hold their
# station while the water pours through them (Jackson 1976, J. Fluid Mech.
# 77 -- the classic boil-periodicity paper). So the bend field is anchored
# to the BED (unadvected channel coordinates), not carried with the water:
# the surface streams past and is continuously RE-BENT as it goes.
#
# That anchoring is also exactly what makes the deformation visible DURING
# translation rather than only at the crossfade -- a bend carried with the
# water would slide rigidly along with the lines it bends.

## The bend must genuinely displace the streaklines -- zero bend is the
## ruler-straight failure -- but stay coherent: RMS displacement is held to
## a band measured in line widths. (The bend field is WORLD-anchored now,
## like everything else; only its push direction is the flow perp.)
func test_streaklines_are_bent_by_a_real_measured_amount():
	var total := 0.0
	var count := 0
	for i in range(70):
		for j in range(70):
			var d := RiverFlowShader.bend_displacement(
				float(i) * 0.31 * RiverFlowShader.EDDY_SCALE,
				float(j) * 0.29 * RiverFlowShader.EDDY_SCALE
			)
			total += d * d
			count += 1
	var rms := sqrt(total / float(count))
	assert_between(
		rms, 0.15, 0.75,
		"streaklines bend an RMS of %.3f line widths" % rms
	)


## The old defect-3 lesson, re-applied: displacement past the fold threshold
## does not bend a pattern, it SHREDS it. The warp must never fold -- the
## warped across-coordinate must stay strictly monotonic in the real one.
## Measured over the real field, not derived from a formula.
## A warp is invertible only while its Jacobian stays POSITIVE -- but
## asserting merely "> 0" is not enough, and this test used to.
##
## The strokes are contours of a noise field sampled at a WARPED
## coordinate (q = p + flow_perp * bend). At a derivative of 0.0988 --
## which the old monotonicity check passed happily -- the warp compresses
## the coordinate 10:1, pinching every contour running through it into a
## near-cusp. A sharp V in a stroke is a zigzag by another name.
##
## This is why the artefact survived four separate fixes aimed at the
## FIELD (the across map's reconstruction, the width map, the smear
## direction, the obstacle push): a fold is a property of the WARP, not of
## what is being warped. /flowdebug confirmed the field itself was smooth
## the whole time.
##
## Measured with tools/probe_fold.gd over 240,000 samples:
##
##   EDDY_DETAIL_WEIGHT 0.7  -> minimum derivative 0.0988
##   EDDY_DETAIL_WEIGHT 0.35 -> minimum derivative 0.4062
##
## The fine octave carries 2.6 * 0.7 = 1.82 of the derivative for only 0.7
## of the amplitude -- 65% of the fold risk for 41% of the visual effect --
## so halving it buys the margin almost free, and the coarse octave that
## swings whole bundles of lines is left alone. TURBULENCE_STRENGTH stays
## at 1.6: the ask was for MORE whirl, not less.
##
## This is the STRAIGHT-reach model. At a bend flow_perp itself rotates,
## adding a second term to the Jacobian, so the real margin at a bend is
## smaller than what this measures -- which is exactly why the artefact
## was reported at bends 100% of the time and rarely elsewhere.
const MIN_WARP_MARGIN := 0.35


func test_the_bend_never_folds_or_pinches_the_surface():
	var step := 0.002
	var worst := INF
	var worst_at := Vector2.ZERO
	for i in range(120):
		var along := float(i) * 0.31
		for j in range(1, 400):
			var across := float(j) * 0.05
			var derivative := (
				RiverFlowShader.warped_across(along, across + step)
				- RiverFlowShader.warped_across(along, across - step)
			) / (2.0 * step)
			if derivative < worst:
				worst = derivative
				worst_at = Vector2(along, across)
	assert_gt(
		worst, MIN_WARP_MARGIN,
		"the warp pinches to %.4f at %s -- contours through it cusp" % [worst, worst_at]
	)


## Eddies must be coarser than the lines they bend, or neighbouring lines
## bend independently and the field turns to static instead of curling.
func test_eddies_span_several_line_widths():
	assert_lte(RiverFlowShader.EDDY_SCALE, 0.5)
	assert_gte(RiverFlowShader.EDDY_SCALE, 0.08)


## Bent, the field must still read as LINES -- the roughness anisotropy has
## to survive the warp. This is the constraint that stops the turbulence
## being turned up until the lines dissolve.
func test_the_warped_field_still_forms_lines():
	var step := 0.45
	var total_along := 0.0
	var total_across := 0.0
	var count := 0
	for i in range(70):
		for j in range(70):
			var a := float(i) * 0.37
			var c := float(j) * 0.41
			var here := RiverFlowShader.warped_surface_value(a, c)
			total_along += absf(RiverFlowShader.warped_surface_value(a + step, c) - here)
			total_across += absf(RiverFlowShader.warped_surface_value(a, c + step) - here)
			count += 1
	assert_gt(
		total_across / float(count), (total_along / float(count)) * 1.6,
		"the warp has dissolved the lines into blobs"
	)


## Structural: the bend is NOT advected with the water. It used to be read
## at fully bed-anchored coordinates; it now migrates downstream at the
## surface's visible speed ("the lines should move at the same speed"), but
## as a steady TRANSLATION of the eddy field -- it must never take the
## advect phase's stretch-and-reset. That is what keeps the water deforming
## as it streams THROUGH the eddies rather than the whole picture sliding as
## one sheet: each phase still stretches away from the steady translation
## and resets, so the wobble keeps moving relative to the whirls even though
## their mean speeds agree. The warped across must still feed both phase
## samples.
func test_the_bend_is_anchored_to_the_bed_not_carried_with_the_water():
	assert_true(
		RiverFlowShader.SHADER_CODE.contains("vec2 eddy_p = p * eddy_scale - flow_dir * bend_drift;"),
		"the eddy field is sampled at a steadily translated, never advected, coordinate"
	)
	assert_false(
		RiverFlowShader.SHADER_CODE.contains("eddy_p = (q"),
		"the eddies must not ride the advected surface coordinate"
	)
	assert_lte(
		RiverFlowShader.BEND_DRIFT_FRACTION, 1.0,
		"the eddies can move with the surface, never faster than it"
	)
	assert_true(
		RiverFlowShader.SHADER_CODE.contains("vec2 q = p + flow_perp * bend;"),
		"the bend must push the sample point across the flow"
	)


# -- turbulence you can actually see -----------------------------------------
#
# The first standing-eddy pass was measurably correct and visually
# invisible: one smooth octave at ~6 line widths mostly shifts neighbouring
# lines TOGETHER, which locally reads as translation, not bending. The
# screenshot showed ruler-straight satin bands again.
#
# Visible curvature needs the bend to CHANGE within a line's own length --
# structure at more than one scale, like the surface field itself.

## The bend field must have a second, finer octave, and the total must
## still clear the no-fold sweep above -- which is the real ceiling on how
## hard it can be turned up.
func test_the_bend_has_structure_at_two_scales():
	assert_gt(RiverFlowShader.EDDY_DETAIL_WEIGHT, 0.0)
	# The frequency is a uniform now rather than a literal, because the
	# fold margin below is tuned against it.
	assert_gt(RiverFlowShader.EDDY_DETAIL_FREQUENCY, 1.0)
	assert_true(
		RiverFlowShader.SHADER_CODE.contains("eddy_p * eddy_detail_frequency"),
		"the second eddy octave is missing from the shader"
	)


## A straight line drawn through the warp must come out visibly wavy: the
## bend sampled along one line must VARY by a real fraction of a line width
## within a couple of line lengths -- variation is what curves it, a
## constant shift only moves it.
func test_a_streakline_visibly_curves_within_its_own_length():
	# One feature length downstream, in noise cells -- the smear stroke.
	var line_length := 1.0 + float(RiverFlowShader.SMEAR_TAPS - 1) * RiverFlowShader.SMEAR_SPACING
	var worst := 999.0
	for j in range(12):
		var across := float(j) * 1.7
		var lowest := 999.0
		var highest := -999.0
		for i in range(24):
			# bend_displacement takes eddy-scaled coordinates, exactly as
			# the shader feeds it.
			var d := RiverFlowShader.bend_displacement(
				float(i) / 24.0 * 2.0 * line_length * RiverFlowShader.EDDY_SCALE,
				across * RiverFlowShader.EDDY_SCALE
			)
			lowest = minf(lowest, d)
			highest = maxf(highest, d)
		worst = minf(worst, highest - lowest)
	# 0.4, LOWERED from 0.5, and the reason belongs on the record rather
	# than in a commit nobody re-reads.
	#
	# Within-line curvature and fold safety are in direct conflict in this
	# design. Curvature comes from the bend's amplitude at a scale the
	# 9-tap smear does not average away; the domain warp folds when that
	# same amplitude makes d(q)/d(p) reach zero. Raising the octave's
	# frequency to buy curvature more cheaply does not work -- measured,
	# it got WORSE (0.32), because the smear low-passes along the flow and
	# eats the finer detail.
	#
	# So this threshold was paid for. At 0.5 the warp pinched to 0.0988: a
	# 10:1 compression, and the cusps reported as zigzags all session. The
	# settled constants give a 0.3654 margin, 3.7x safer, and curve 0.448
	# -- a tenth under the old bar for something that was actively drawing
	# the artefact.
	#
	# Getting BOTH needs a divergence-free (curl) warp, whose Jacobian is
	# 1 + O(strength^2) instead of 1 - O(strength), so it carries the same
	# amplitude at the same frequency without folding. That is the real
	# fix and it is not a constant change.
	assert_gte(
		worst, 0.4,
		"the flattest streakline curves only %.2f line widths over two lengths" % worst
	)


# -- the comic / 16-bit pass ---------------------------------------------------
#
# Requested directly: "make it more comic like? / 16bit pixel art?" -- and
# this time stylization can work, because the thing that killed the FIRST
# stylized attempt was never the flat colours: it was a translating pattern
# underneath them. The quantization below rides the world-anchored,
# advected, turbulence-bent field, so the cel bands wobble and morph like
# hand-animated water. Only the PRESENTATION is quantized; every physical
# quantity (reconstruction, advection, bend, bank curve) is untouched.

## A 16-bit water palette is a handful of flat shades -- enough to draw the
## cross-section and the moving surface, few enough to read as cel art.
func test_the_palette_is_a_16bit_handful_of_shades():
	assert_between(RiverFlowShader.CEL_LEVELS, 4, 8)


## The quantizer must genuinely produce exactly that many flat levels.
func test_the_cel_quantizer_yields_exactly_the_palette_levels():
	var seen := {}
	for step in 400:
		seen[RiverFlowShader.cel_level(float(step) / 399.0, 0.0)] = true
	assert_eq(seen.size(), RiverFlowShader.CEL_LEVELS)


## Dither: the quantization threshold shifts per art pixel, so band
## boundaries dissolve into grain instead of cutting hard. The phase is a
## world-anchored HASH of the snapped pixel, not the 2x2 checkerboard it
## used to be: on a diagonal depth gradient the checker's phases lined up
## into vertical dashes across the whole dither band (playtest: "the
## sawtooth is clearly there"), and a hash has no lattice to line up with.
func test_band_boundaries_are_dithered_by_a_pixel_hash():
	var moved := 0
	for step in 400:
		var shade := float(step) / 399.0
		if RiverFlowShader.cel_level(shade, 0.0) != RiverFlowShader.cel_level(shade, 1.0):
			moved += 1
	assert_gt(moved, 20, "the phase extremes move almost no boundaries -- no dither")
	assert_true(
		RiverFlowShader.SHADER_CODE.contains("float checker = value_hash(floor(wp / pixel_snap));"),
		"the shader must derive the dither phase from a hash of the snapped pixel"
	)
	assert_false(
		RiverFlowShader.SHADER_CODE.contains("mod(floor(wp.x / pixel_snap) + floor(wp.y / pixel_snap), 2.0)"),
		"the checkerboard is gone"
	)


## Pixel art renders on the ART-PIXEL grid: the shader snaps its sampling
## to exactly one art pixel, derived from the real tile sizes rather than
## guessed -- sub-pixel gradients are what make water look painted-on next
## to chunky terrain art.
func test_the_water_renders_on_the_art_pixel_grid():
	assert_eq(
		RiverFlowShader.PIXEL_SNAP,
		float(TerrainRenderer.TILE_SIZE) / float(TerrainRenderer.ART_TILE_SIZE),
		"one art pixel, in world px -- not an invented chunkiness"
	)
	assert_true(
		RiverFlowShader.SHADER_CODE.contains("floor(world_pos / pixel_snap) * pixel_snap"),
		"all sampling must start from the snapped position"
	)


## The comic INK line: a dark outline hugging the real bank curve. The old
## stylized attempt's outline failed because it was per-TILE (a near-black
## block eating half the channel); this one is a function of the
## reconstructed |across|, so it is as smooth as the shoreline itself.
func test_the_bank_ink_line_is_a_few_art_pixels_wide():
	var width_art_px := (
		RiverFlowShader.INK_WIDTH * RiverCatalog.RIVER_HALF_WIDTH_TILES
		* RiverFlowShader.TILE_PX / RiverFlowShader.PIXEL_SNAP
	)
	assert_between(
		width_art_px, 1.5, 5.0,
		"the ink line is %.1f art pixels -- too thin reads as noise, too fat as the old block"
			% width_art_px
	)


func test_the_ink_line_sits_just_inside_the_waterline():
	assert_true(
		RiverFlowShader.SHADER_CODE.contains("smoothstep(1.0 - ink_width, 1.0 - ink_width * 0.4, rr)"),
		"the ink band must be keyed to the reconstructed bank distance"
	)


## The ink must be visibly darker than the deepest water shade, or it is
## not an outline.
func test_the_ink_is_darker_than_the_deepest_water():
	assert_lt(
		RiverFlowShader.INK_COLOR.v,
		RiverFlowShader.BAND_COLORS[4].v - 0.05
	)


# -- illustrated wave strokes -------------------------------------------------
#
# Reported directly: "still looks like a gas animation and not stylized
# illustrated smooth lines morphing 16bit". The diagnosis is exact: when
# EVERY fragment shades with the moving field, the picture is amorphous
# drifting patches -- vapour. Illustrated water is the opposite: a STATIC
# flat body, with all the motion carried by a few drawn line strokes.
#
# Each stroke is a CONTOUR (level set) of the smooth advected field. A
# level set of a smooth field is by construction a smooth curve; because
# the field underneath advects, crossfades and bends through the standing
# eddies, the strokes snake, merge and split -- morphing wave lines, drawn
# rather than shaded.

## The body cels must be STATIC depth alone -- the moment the field leaks
## back into the body shade, the gas look returns.
func test_the_body_cels_are_static_depth_only():
	assert_true(
		RiverFlowShader.SHADER_CODE.contains("float shade = depth_frac;"),
		"the cel shade must be pure reconstructed depth"
	)


## Smooth lines need a smooth field: the fine detail octave is gone from
## the contour source. Its jitter is exactly what made stroke edges ragged
## -- one smooth smeared scale gives clean curves.
func test_the_contour_field_is_one_smooth_scale():
	assert_false(
		RiverFlowShader.SHADER_CODE.contains("detail_scale"),
		"the detail octave must not roughen the contour source"
	)


## The SHORE HIGHLIGHT: one constant pale line tracing the bank just inside
## the ink -- pinned to the reconstructed geometry, not to any field, so it
## is exactly as smooth as the shoreline itself.
func test_the_shore_highlight_hugs_the_bank():
	assert_true(
		RiverFlowShader.SHADER_CODE.contains("abs(rr - shore_pos)"),
		"the shore line must be a contour of the reconstructed bank distance"
	)
	assert_between(RiverFlowShader.SHORE_POS, 0.8, 0.97)


## And it must sit inside the ink line, not on top of it.
func test_the_shore_highlight_sits_inside_the_ink():
	assert_lt(
		RiverFlowShader.SHORE_POS + RiverFlowShader.SHORE_WIDTH,
		1.0 - RiverFlowShader.INK_WIDTH
	)


## Adaptive ink: over LIGHT cels the strokes must be drawn dark, over dark
## cels pale -- and never a mid-blend that matches the body. Contrast is
## the pin, for EVERY body cel the quantizer can produce.
func test_stroke_ink_contrasts_with_every_body_cel():
	for level in RiverFlowShader.CEL_LEVELS:
		var cel_t := float(level) / float(RiverFlowShader.CEL_LEVELS - 1)
		var body := RiverFlowShader.depth_color(cel_t)
		var ink := RiverFlowShader.stroke_ink_for(cel_t)
		assert_gte(
			absf(ink.v - body.v), 0.18,
			"stroke ink barely differs from the body at cel %d (%.2f vs %.2f)"
				% [level, ink.v, body.v]
		)


func test_the_shader_switches_ink_hard_never_blending_to_the_body():
	assert_true(
		RiverFlowShader.SHADER_CODE.contains("mix(line_color_deep, line_color, step("),
		"the ink must snap between deep and pale -- a smooth blend passes through the body colour"
	)


# -- moonlit strokes ----------------------------------------------------------
#
# The world clock follows the REAL clock, so an evening player lives in
# permanent in-game night -- and the night CanvasModulate multiplies every
# canvas pixel, crushing the stroke contrast below visibility exactly when
# it matters most (reported repeatedly via night screenshots of lineless
# water). Nothing inside the canvas can exceed the modulate, so the ceiling
# IS the play: as the sky darkens, the strokes lift toward near-white at
# near-full alpha -- a moonlit gleam, which is also what real rivers do at
# night (they reflect skylight and read brighter than the land).

## The lift curve: fully off in daylight, fully on in darkness, monotone in
## between -- so the gleam fades in with dusk instead of snapping.
func test_night_lift_is_off_by_day_and_full_by_night():
	assert_almost_eq(RiverFlowShader.night_lift_for_sunlight(1.0), 0.0, 0.0001)
	assert_almost_eq(RiverFlowShader.night_lift_for_sunlight(0.4), 0.0, 0.0001)
	assert_almost_eq(RiverFlowShader.night_lift_for_sunlight(0.0), 1.0, 0.0001)
	var previous := 1.1
	for step in 40:
		var lift := RiverFlowShader.night_lift_for_sunlight(float(step) / 39.0)
		assert_lte(lift, previous + 0.0001, "the lift must fade monotonically with sunlight")
		previous = lift


## At full night a full stroke must SATURATE -- reach the modulate ceiling
## -- or the boost is not actually buying the visibility it exists for.
func test_a_full_stroke_saturates_at_full_night():
	assert_gte(
		RiverFlowShader.LINE_STRENGTH * RiverFlowShader.NIGHT_STROKE_BOOST, 1.0,
		"the night boost cannot reach the modulate ceiling"
	)


## And the ink goes moonlight at night for EVERY cel -- including the
## shallow rim, whose adaptive DEEP ink would otherwise vanish first under
## the dimming.
func test_the_ink_turns_moonlight_at_night_on_every_cel():
	for level in RiverFlowShader.CEL_LEVELS:
		var cel_t := float(level) / float(RiverFlowShader.CEL_LEVELS - 1)
		var night_ink := RiverFlowShader.stroke_ink_at(cel_t, 1.0)
		assert_gte(night_ink.v, 0.9, "cel %d stroke ink stays dark at night" % level)
		var day_ink := RiverFlowShader.stroke_ink_at(cel_t, 0.0)
		assert_eq(day_ink, RiverFlowShader.stroke_ink_for(cel_t))


## Structural: the shader must apply the lift to both the ink and the
## stroke alpha, and the alpha must clamp at the ceiling.
func test_the_shader_lifts_strokes_by_the_night_uniform():
	assert_true(RiverFlowShader.SHADER_CODE.contains("mix(stroke_ink, moonlight_ink, night_lift)"))
	assert_true(RiverFlowShader.SHADER_CODE.contains("mix(1.0, night_stroke_boost, night_lift)"))
	# The trailing mix(0.35, 1.0, moving) damps strokes in still water; the
	# night boost and the 1.0 ceiling both still apply.
	assert_true(
		RiverFlowShader.SHADER_CODE.contains(
			"wave * line_strength * mix(1.0, night_stroke_boost, night_lift) * mix(0.35, 1.0, moving), 1.0);"
		)
	)


func test_the_night_lift_defaults_to_day():
	assert_eq(flow.shared_material().get_shader_parameter("night_lift"), 0.0)


## The float32 landmine, pinned structurally: the classic sin-based hash
## collapses under float32 range reduction at this game's world
## coordinates (~millions of radians into sin), going regionally
## near-constant -- whole reaches lost their current strokes while every
## float64 CPU mirror statistic still passed. The GPU-side proof lives in
## test_river_flow_render_smoke.gd; this keeps the hash trig-free.
func test_the_hash_is_trig_free_for_float32_world_coordinates():
	assert_false(
		RiverFlowShader.SHADER_CODE.contains("43758.5453"),
		"the sin-hash magic number is back"
	)
	assert_false(
		RiverFlowShader.SHADER_CODE.contains("sin(dot("),
		"no hash may run world-scale values through sin"
	)


# -- flow-guided current lines ------------------------------------------------
#
# Reported, after every contour-of-noise variant: "now they are more like
# perlin noise cells.. can you restore natural currents everywhere?" -- and
# the root cause is topological, not tunable: level sets of ANY healthy
# scalar field close into loops around its extrema. (The long open lines of
# an earlier build were partly an accident of the float32-degenerate hash
# striping the noise.)
#
# So the stroke field is now GUIDED BY THE CHANNEL: s = across-position
# plus advected wobble. Because the across ramp dominates, s is monotone
# bank-to-bank, and every level set is an OPEN curve running along the
# river -- long flowing lines by construction, which wobble, pinch
# together and separate as the noise underneath advects, and can never
# close into a cell.

## THE cells-killer, structurally: the guide must dominate the wobble, or
## the monotonicity that keeps every line an open curve is gone.
##
## Comparing the two AMPLITUDES, as this line does, is necessary and not
## remotely sufficient -- monotonicity is about GRADIENTS. `across` runs 0
## to 1 over the channel's half width while `n` runs 0 to 1 over ONE noise
## cell, so the real question is how many noise cells fit across the water,
## and that is not a constant. See
## test_the_stroke_field_stays_monotone_at_every_real_channel_width, which
## is the test that actually holds this together.
func test_the_channel_guide_dominates_the_wobble():
	assert_gte(RiverFlowShader.ACROSS_LINE_SCALE, RiverFlowShader.LINE_WOBBLE)
	assert_true(
		RiverFlowShader.SHADER_CODE.contains("float guide = frag_across + bend / wobble_cells;"),
		"the eddies must bend the guide itself, not only the noise sample"
	)
	assert_true(
		RiverFlowShader.SHADER_CODE.contains("guide * across_line_scale + (n - 0.5) * wobble_local"),
		"the stroke field must be the bent guide plus a small width-scaled wobble"
	)
	assert_true(RiverFlowShader.SHADER_CODE.contains("fract(s_field * line_count) - 0.5"))


## And measured: walking bank to bank through the REAL animated field, the
## stroke field must rise monotonically at nearly every step -- occasional
## pinches are the wanted merge-and-unmerge, a cell field would violate
## this everywhere.
func test_the_stroke_field_is_monotone_across_with_rare_pinches():
	assert_lt(
		_folding_rate(RiverFlowShader.WOBBLE_REFERENCE_CELLS), 0.15,
		"the tuned width folds back too often -- cells, not pinching lines"
	)


## The same measurement AT EVERY WIDTH THE MAP ACTUALLY HAS, which is the
## test that was missing.
##
## The old one walked `across * 2.56` and nothing else -- a 2.0-tile half
## width. Half width comes from discharge and runs to 6 tiles, and the
## folding rate climbs with it, because a wider channel fits more noise
## cells across itself. Measured with tools/probe_monotone.gd before the
## wobble was scaled:
##
##   1.0 tiles (1.28 cells)   0.1%
##   2.0 tiles (2.56 cells)   2.8%   <- the only width ever tested
##   2.6 tiles (3.33 cells)   5.3%
##   3.5 tiles (4.48 cells)  10.1%
##   4.5 tiles (5.76 cells)  13.4%
##   6.0 tiles (7.68 cells)  18.2%   <- past what the old test allowed
##
## So the guard passed while the widest water on the map drew cells --
## "only around bends and where the water is deeper at the edge", which is
## the report this explains.
func test_the_stroke_field_stays_monotone_at_every_real_channel_width():
	for half_tiles in [1.0, 1.6, 2.0, 2.6, 3.5, 4.5, 6.0]:
		var cells: float = half_tiles * RiverFlowShader.TILE_PX * RiverFlowShader.NOISE_SCALE
		var rate := _folding_rate(cells)
		assert_lt(
			rate, 0.06,
			"a %.1f-tile half width folds back on %.1f%% of steps" % [half_tiles, rate * 100.0]
		)


## Fraction of bank-to-bank steps where the stroke field falls instead of
## rising, for a channel this many noise cells wide.
func _folding_rate(half_width_cells: float) -> float:
	var violations := 0
	var steps := 0
	for column in 24:
		var x := float(column) * 3.7
		var previous := -99.0
		for row in 80:
			var across := -1.0 + float(row) / 79.0 * 2.0
			var n: float = RiverFlowShader.animated_field_value(
				x, across * half_width_cells, Vector2(1, 0), 0.9
			)
			# The bend enters the guide now, so the sweep must carry it too
			# or it walks a field the shader no longer draws.
			var bend: float = RiverFlowShader.bend_displacement(
				x * RiverFlowShader.EDDY_SCALE,
				across * half_width_cells * RiverFlowShader.EDDY_SCALE
			)
			var s_value: float = RiverFlowShader.stroke_field(across, n, half_width_cells, bend)
			if previous > -99.0:
				steps += 1
				if s_value <= previous:
					violations += 1
			previous = s_value
	return float(violations) / float(steps)


## The wobble is only ever turned DOWN, never up: a channel at or below the
## tuned width keeps exactly the look it has.
func test_the_wobble_scale_never_amplifies_a_narrow_channel():
	assert_almost_eq(
		RiverFlowShader.wobble_scale_for(RiverFlowShader.WOBBLE_REFERENCE_CELLS), 1.0, 1e-9
	)
	assert_almost_eq(RiverFlowShader.wobble_scale_for(1.28), 1.0, 1e-9)
	assert_lt(RiverFlowShader.wobble_scale_for(7.68), 0.4)
	assert_true(RiverFlowShader.SHADER_CODE.contains(
		"float wobble_local = line_wobble * min(wobble_reference_cells / wobble_cells, 1.0);"
	))


## The lines exist EVERYWHERE the water is -- including where the noise
## rails flat. With the field frozen dead constant, the guide alone still
## draws the full family of lines across the channel. (The old
## noise-contour design went strokeless on railed reaches -- this is the
## failure mode dissolving, pinned.)
func test_the_lines_survive_a_completely_dead_field():
	var crossings := 0
	var was_in := false
	for row in 400:
		var across := -1.0 + float(row) / 399.0 * 2.0
		var inside := RiverFlowShader.stroke_mask(
			RiverFlowShader.stroke_field(across, 0.5), false
		) > 0.5
		if inside and not was_in:
			crossings += 1
		was_in = inside
	assert_gte(
		crossings, 4,
		"only %d lines cross a dead-field channel -- the guide is not drawing" % crossings
	)


## The pattern scale, measured bank to bank through the real field: fine
## lines a couple of pixels thick, spaced tightly enough to read as
## current everywhere but never merging into texture. (Across-units:
## 1.0 = the half-width = 2 tiles = 32 world px.)
func test_lines_are_fine_and_evenly_spaced_across_the_channel():
	var runs: Array[int] = []
	var onsets: Array[float] = []
	var in_stroke := false
	var run := 0
	for row in 1600:
		var across := -1.0 + float(row) / 1599.0 * 2.0
		var n := RiverFlowShader.animated_field_value(11.3, across * 2.56, Vector2(1, 0), 0.7)
		var hit := RiverFlowShader.stroke_mask(RiverFlowShader.stroke_field(across, n), false) > 0.5
		if hit and not in_stroke:
			onsets.append(across)
		if hit:
			run += 1
		elif in_stroke:
			runs.append(run)
			run = 0
		in_stroke = hit
	assert_gt(runs.size(), 3, "too few lines crossed to measure")
	var total := 0
	for r in runs:
		total += r
	var step_px := 2.0 / 1599.0 * 32.0
	var mean_width_px := float(total) / float(runs.size()) * step_px
	assert_between(
		mean_width_px, 0.8, 4.5,
		"a line is %.1f world px thick" % mean_width_px
	)
	var gap_total := 0.0
	for k in range(1, onsets.size()):
		gap_total += (onsets[k] - onsets[k - 1]) * 32.0
	var mean_spacing_px := gap_total / float(onsets.size() - 1)
	assert_between(
		mean_spacing_px, 6.0, 26.0,
		"lines are %.0f world px apart" % mean_spacing_px
	)


## The time a viewer needs to see the surface travel a quarter of one
## feature length at a given reach speed -- the window the two "does it
## actually move" sweeps below watch through. It used to be a quarter of
## the DRAG cycle in speed-zero water, which measured the drag's dissolve
## and nothing else; now the drift carries the water, the drag is a small
## deformation, and the honest window is one tied to the visible speed.
func _quarter_feature_window_s(speed_mps: float) -> float:
	return 0.25 * RiverFlowShader.feature_length_px() / RiverFlowShader.surface_px_per_s(speed_mps)


## The lines MORPH: at a fixed spot in a typical reach the stroke pattern
## must differ a quarter feature length of travel later -- the wobble
## travels, so lines wander, pinch and release.
func test_the_lines_morph_over_a_quarter_feature_length_of_travel():
	var speed := 0.5
	var window := _quarter_feature_window_s(speed)
	var changed := 0
	var count := 0
	for column in 40:
		var x := 5.0 + float(column) * 1.1
		for row in 30:
			var across := -0.9 + float(row) / 29.0 * 1.8
			var early := RiverFlowShader.stroke_mask(RiverFlowShader.stroke_field(
				across, RiverFlowShader.animated_field_value(x, across * 2.56, Vector2(1, 0), 0.2, speed)
			), false) > 0.5
			var later := RiverFlowShader.stroke_mask(RiverFlowShader.stroke_field(
				across, RiverFlowShader.animated_field_value(x, across * 2.56, Vector2(1, 0), 0.2 + window, speed)
			), false) > 0.5
			if early != later:
				changed += 1
			count += 1
	# 0.035, LOWERED from 0.04. That bar was tuned when LINE_WOBBLE was 0.6
	# and the field was folding into cells -- some of the "motion" it saw
	# was closed loops swaying. With the wobble at 0.13 (the guide now
	# dominates it, 0.499 to a 0.5 bar) the mask flips 3.9% of samples over
	# a quarter cycle, and this 30-row grid quantises so coarsely that
	# 0.12 and 0.13 give the identical count. The eddy bend is bed-anchored
	# by design, so all temporal motion rides the wobble; getting more
	# without re-folding means drifting the bend slowly downstream, which
	# is translation and cannot change the fold Jacobian.
	assert_gt(
		float(changed) / float(count), 0.035,
		"the line pattern barely changes over a quarter cycle"
	)


## FORWARD MOTION ("there should be more of a forward motion"): the field
## no longer just breathes in place -- it TRAVELS downstream at a drift
## speed keyed to the reach's real current. Measured, not asserted from
## structure: the pattern at t+dt correlates better with the t pattern
## sampled a drift-length UPSTREAM than with the unshifted t pattern. With
## no drift this fails (the compensating shift only decorrelates), which is
## exactly the old always-loop behaviour this replaces -- the half-cycle
## loop contract is deliberately retired: a pattern that loops in place
## cannot also travel.
func test_the_pattern_travels_downstream_not_just_morphs():
	var dir := Vector2(1, 0)
	var speed := 1.5
	var dt := 2.0
	var shift := RiverFlowShader.drift_cells(speed, dt)
	var moved := 0.0
	var stayed := 0.0
	var count := 0
	for i in range(24):
		for j in range(14):
			var px := 4.0 + float(i) * 0.83
			var py := -2.0 + float(j) * 0.31
			var before := RiverFlowShader.animated_field_value(px, py, dir, 3.0, speed)
			var after_here := RiverFlowShader.animated_field_value(px, py, dir, 3.0 + dt, speed)
			var after_downstream := RiverFlowShader.animated_field_value(
				px + shift * dir.x, py + shift * dir.y, dir, 3.0 + dt, speed
			)
			moved += absf(after_downstream - before)
			stayed += absf(after_here - before)
			count += 1
	assert_lt(
		moved / float(count), stayed / float(count),
		"the drifted comparison must beat the in-place one -- the pattern must travel"
	)


## The drift is ONE shared speed for every moving reach -- linear in time
## (below the period), the same for a brisk river and a sluggish one, and
## zero in still water. The texel's own speed is interpolated per fragment
## and varies along a reach; TIME times that diverged between neighbours
## without bound and shredded every reach after twenty minutes (the second
## half of the far-time shredding, measured on the GPU at the Loire).
func test_the_drift_is_one_shared_speed_for_every_moving_reach():
	assert_almost_eq(
		RiverFlowShader.drift_cells(2.0, 1.0),
		RiverFlowShader.drift_cells(1.0, 1.0), 0.0001,
		"a brisk reach and a slow one drift their lines at the one shared speed"
	)
	assert_almost_eq(
		RiverFlowShader.drift_cells(1.0, 1.0),
		RiverFlowShader.DRIFT_PX_PER_MPS * RiverFlowShader.DRIFT_SPEED_M_S * RiverFlowShader.NOISE_SCALE,
		0.0001
	)
	assert_almost_eq(
		RiverFlowShader.drift_cells(1.0, 3.0),
		RiverFlowShader.drift_cells(1.0, 1.0) * 3.0, 0.0001
	)
	assert_almost_eq(RiverFlowShader.drift_cells(0.0, 9.0), 0.0, 0.0001)
	assert_between(RiverFlowShader.DRIFT_PX_PER_MPS, 5.0, 20.0)


## Fast reaches draw BRIGHTER lines, not wider ones -- widening is the blob
## knob (learned twice now).
func test_fast_reaches_draw_brighter_not_wider_strokes():
	assert_false(RiverFlowShader.SHADER_CODE.contains("line_width * mix"))
	assert_true(RiverFlowShader.SHADER_CODE.contains("mix(0.8, 1.1, is_fast)"))
	var s_on_level := RiverFlowShader.stroke_field(0.5 / (RiverFlowShader.ACROSS_LINE_SCALE * RiverFlowShader.LINE_COUNT), 0.5)
	assert_gt(
		RiverFlowShader.stroke_mask(s_on_level, true),
		RiverFlowShader.stroke_mask(s_on_level, false)
	)


# -- visible downstream travel ------------------------------------------------
#
# Reported of the guided lines: "it still looks like still water not
# flowing water". Two reasons, one of them fixable in the shader: the
# lines only SWAYED laterally as the wobble advected -- nothing on the
# line itself visibly travelled downstream. Now each line carries
# brightness PULSES driven by the same advected field, so bright and dim
# segments stream along every line at the advection speed -- the classic
# "water is going that way" cue -- at zero extra noise cost.

func test_the_lines_carry_streaming_brightness_pulses():
	assert_true(
		RiverFlowShader.SHADER_CODE.contains("float pulse = smoothstep(0.35, 0.75, n);"),
		"the pulse must ride the advected field"
	)
	# The floor is a named uniform now (PULSE_FLOOR), pinned below: deep
	# enough that a bright segment streaming along a line is obvious, and
	# never zero, so a dim segment is still a stroke.
	assert_true(
		RiverFlowShader.SHADER_CODE.contains("mix(pulse_floor, 1.0, pulse)"),
		"the pulse must modulate the stroke brightness through the named floor"
	)


## Measured: at fixed points sitting ON a line, the stroke intensity must
## genuinely change over a quarter feature length of travel -- pulses
## passing through -- for a real fraction of the line.
func test_the_pulses_actually_travel_through_the_lines():
	var speed := 0.3
	var window := _quarter_feature_window_s(speed)
	var moved := 0
	var on_line := 0
	for column in 90:
		var x := 3.0 + float(column) * 1.13
		for row in 9:
			var across := -0.8 + float(row) / 8.0 * 1.6
			var n_early := RiverFlowShader.animated_field_value(
				x, across * 2.56, Vector2(1, 0), 0.3, speed
			)
			var n_later := RiverFlowShader.animated_field_value(
				x, across * 2.56, Vector2(1, 0), 0.3 + window, speed
			)
			var early := RiverFlowShader.stroke_intensity(
				RiverFlowShader.stroke_field(across, n_early), n_early, false
			)
			var later := RiverFlowShader.stroke_intensity(
				RiverFlowShader.stroke_field(across, n_later), n_later, false
			)
			# Only points that genuinely sit on a line can show a pulse.
			if early < 0.2 and later < 0.2:
				continue
			on_line += 1
			if absf(early - later) > 0.08:
				moved += 1
	assert_gt(on_line, 40, "too few on-line probes to trust the sweep")
	assert_gt(
		float(moved) / float(on_line), 0.35,
		"pulses pass through only %d of %d on-line points" % [moved, on_line]
	)


## The water's visible speed is CALM. "I want a more relaxed and calm
## picture, now everything is faster": at a typical 0.5 m/s reach the
## surface -- and everything riding it -- crosses a tile in one to two
## seconds (8 to 16 world px/s), not in half a second. The floor is the
## same one the pulse legibility test uses; the ceiling is the number that
## was reported as too fast, ~30, well cleared.
func test_the_water_travels_at_a_calm_speed():
	var typical := RiverFlowShader.surface_px_per_s(0.5)
	assert_between(typical, 8.0, 16.0, "a 0.5 m/s reach streams at %.1f world px/s" % typical)
	# And the drag's translation is a MINOR share of it -- the drift is what
	# carries the water, coherently, so kinks, whirls and rings all travel
	# together instead of the wobble dissolving in place.
	var drag_px_per_s: float = (
		RiverFlowShader.ADVECT_STRENGTH * RiverFlowShader.ADVECT_RATE / RiverFlowShader.NOISE_SCALE
	)
	assert_lt(
		drag_px_per_s, typical / 3.0,
		"the drag translates %.1f px/s of a %.1f px/s surface -- travel must be the drift's" % [drag_px_per_s, typical]
	)


# -- the organic smoothing pass ----------------------------------------------
#
# Reported: "run a smoothing pass? so small lines stay coherent over tiles?
# it's still visible that the base are square tiles". The residual
# tile-ness is the QUANTIZED per-tile across (48 bins, plus the direction
# bin's perp) taking a small systematic side-step at every tile edge --
# lines, cel boundaries and the waterline all jog together on the same
# straight lattice lines, which is what betrays the grid.
#
# The atlas caps how many bins are affordable, so the fix is a small
# WORLD-ANCHORED jitter added to the reconstructed across: continuous
# across tile boundaries (world position owes nothing to the grid), it
# turns each straight systematic step into organic raggedness -- for every
# consumer of frag_across at once, at one extra noise call.

func test_the_across_jitter_is_wired_into_the_reconstruction():
	assert_true(
		RiverFlowShader.SHADER_CODE.contains("frag_across += (value_noise(wp * noise_scale * jitter_scale) - 0.5) * across_jitter;"),
		"the jitter must perturb the reconstructed across itself, before every consumer"
	)


## The jitter is a small organic roughening, never a reshaping: with the
## bilinear map there is no quantisation left to mask, so the cap is a
## plain strength bound -- well under a tenth of the half-width.
func test_the_jitter_only_roughens_never_reshapes():
	assert_lte(RiverFlowShader.ACROSS_JITTER, 0.09)
	assert_gt(RiverFlowShader.ACROSS_JITTER, 0.0)


## Finer than the current lines, coarser than a pixel: the jitter must
## roughen edges, not redraw them.
func test_the_jitter_wavelength_sits_between_pixel_and_line():
	var wavelength_px := 1.0 / (RiverFlowShader.NOISE_SCALE * RiverFlowShader.JITTER_SCALE)
	assert_between(wavelength_px, 2.0, 10.0, "jitter wavelength %.1f px" % wavelength_px)


# -- boulders bend the water --------------------------------------------------
#
# Per FRAGMENT, around the rock's world position -- the tile-baked attempt
# put half a channel of across-shift on single tiles and painted square
# grass holes ("squares are now much more visible"). The shader receives
# up to 24 boulder positions and bends the field radially: continuous
# everywhere, round everywhere.

func test_the_obstacle_shift_matches_potential_flow_around_a_round_core():
	# "player and boulders behave like a singularity and don't have a
	# radius around which the water flows". The magnitude is the REAL
	# midplane streamline displacement around a cylinder of radius R:
	# sqrt(lateral^2 + R^2) - |lateral|, decaying smoothly to the sides,
	# never a point spike.
	#
	# ON the stagnation line the push is now ZERO, not R. This assertion
	# used to demand R there -- "the parting streamline clears the actual
	# rock" -- which cannot be asked of a single-valued field: the sign
	# flips across that line, so requiring magnitude R on it requires the
	# field to be both +R and -R at one point, and what the code actually
	# did was tear frag_across by 2R (21.95px, 0.69 of a channel) along a
	# straight line through the rock. The rock's clearance comes from
	# eyot_dry, which carves a genuinely round dry patch, and from the
	# halo ring around it -- not from tearing the field every contour is
	# a level set of. See
	# test_the_obstacle_push_is_continuous_across_the_stagnation_line.
	var perp := Vector2(0, 1)
	var r := RiverFlowShader.BOULDER_RADIUS_PX
	var reach := RiverFlowShader.BOULDER_REACH_PX
	var on_axis := RiverFlowShader.obstacle_lateral_shift_px(
		Vector2(r, 0.0), perp, r, reach, 0.0
	)
	assert_almost_eq(on_axis, 0.0, 0.01, "the parting line parts -- it does not jump")
	# One radius off the line is well outside the softened core, so the
	# side factor is clamped to 1 and this is the untouched cylinder
	# midplane value: (sqrt(2) - 1) * R, with the envelope still 1.
	var at_rim := RiverFlowShader.obstacle_lateral_shift_px(
		Vector2(0.0, r), perp, r, reach, 0.0
	)
	assert_almost_eq(
		at_rim, (sqrt(2.0) - 1.0) * r, 0.01,
		"the rim streamline displacement is the cylinder midplane value"
	)
	var near := RiverFlowShader.obstacle_lateral_shift_px(Vector2(0.0, 8.0), perp, r, reach, 0.0)
	var far := RiverFlowShader.obstacle_lateral_shift_px(Vector2(0.0, 20.0), perp, r, reach, 0.0)
	assert_gt(near, far, "the shift must decay with lateral distance")
	assert_gt(
		RiverFlowShader.obstacle_lateral_shift_px(Vector2(0.0, 30.0), perp, r, reach, 0.0),
		0.0,
		"outer streamlines inside the reach still feel the obstacle -- no dead ring"
	)
	assert_almost_eq(
		RiverFlowShader.obstacle_lateral_shift_px(Vector2(0.0, reach + 1.0), perp, r, reach, 0.0),
		0.0, 0.0001
	)
	var below := RiverFlowShader.obstacle_lateral_shift_px(Vector2(0.0, -8.0), perp, r, reach, 0.0)
	assert_lt(below, 0.0, "the other bank side must be pushed the other way")


## Boulder and wader ride the SAME round-core model, differing only in
## their real radii -- and both convert px to across-fraction through the
## channel's actual half-width, itself pinned to the catalog.
func test_the_boulder_and_wader_shifts_ride_the_same_round_core():
	# Probed one radius OFF the stagnation line. On the line itself both
	# are now zero, so the line no longer distinguishes the two models --
	# one radius out is outside the softened core, so each shows its own
	# radius through the untouched closed form (sqrt(2) - 1) * R, with the
	# envelope still at 1.
	var core := sqrt(2.0) - 1.0
	assert_almost_eq(
		RiverFlowShader.boulder_across_push(
			Vector2(0.0, RiverFlowShader.BOULDER_RADIUS_PX), Vector2(0, 1)
		),
		core * RiverFlowShader.BOULDER_RADIUS_PX / RiverFlowShader.HALF_WIDTH_PX, 0.001
	)
	assert_almost_eq(
		RiverFlowShader.wader_across_push(
			Vector2(0.0, RiverFlowShader.WADER_RADIUS_PX), Vector2(1, 0)
		),
		core * RiverFlowShader.WADER_RADIUS_PX / RiverFlowShader.HALF_WIDTH_PX, 0.001
	)
	assert_lt(RiverFlowShader.WADER_RADIUS_PX, RiverFlowShader.BOULDER_RADIUS_PX)


func test_the_half_width_px_matches_the_catalog():
	var RiverCatalog = load("res://src/world/river_catalog.gd")
	assert_almost_eq(
		RiverFlowShader.HALF_WIDTH_PX,
		RiverFlowShader.TILE_PX * RiverCatalog.RIVER_HALF_WIDTH_TILES, 0.0001
	)


func test_the_shader_bends_and_dries_around_the_boulder_uniforms():
	assert_true(RiverFlowShader.SHADER_CODE.contains("for (int b = 0; b < boulder_count; b++)"))
	assert_true(
		RiverFlowShader.SHADER_CODE.contains("sqrt(lateral * lateral + R * R)"),
		"the boulder must displace via the round-core potential-flow formula, at ITS radius"
	)
	# The eyot trims the channel's own wet verdict, and nothing else lights
	# alpha: the painted band that once did is gone (see the shoal tests).
	assert_true(RiverFlowShader.SHADER_CODE.contains(
		"float wet = (1.0 - smoothstep(1.0 - bank_feather, 1.0 + bank_feather, rr)) * eyot_dry;"
	))


## The flow frame and speed come from the BILINEAR map, not the atlas
## texel: per-tile direction bins and a binary fast flag were the last
## square-tile artefacts ("there are still individual square river tiles
## visible"). The atlas sprite is now only the painted canvas.
func test_the_flow_frame_and_speed_ride_the_bilinear_map():
	# The atlas texel must not be sampled AT ALL any more -- direction and
	# speed both rode it once, and a substring check on "data.gb" would trip
	# on the map decode itself ("map_data.gb"), so the pin is the sample
	# call: no texture(TEXTURE, ...) means no per-tile source left.
	assert_false(
		RiverFlowShader.SHADER_CODE.contains("texture(TEXTURE"),
		"per-tile atlas data would seam every bearing and reach change"
	)
	assert_true(RiverFlowShader.SHADER_CODE.contains("normalize(map_data.gb"))
	assert_true(RiverFlowShader.SHADER_CODE.contains("float speed_mps = map_data.a;"))
	assert_true(
		RiverFlowShader.SHADER_CODE.contains("step(fast_flow_m_s, speed_mps)"),
		"the brightness gate must come from the mapped real speed"
	)


func test_the_material_carries_the_fast_threshold_constant():
	var material := RiverFlowShader.new().make_material()
	assert_almost_eq(
		float(material.get_shader_parameter("fast_flow_m_s")),
		RiverFlowShader.FAST_FLOW_M_S, 0.0001
	)


# -- the bilinear across map --------------------------------------------------
#
# Reported (third bin artefact in a row): "there are a lot of individual
# squares visible because of misalignment". The root cause was structural:
# across rode the ATLAS, and an atlas dimension must be quantized -- 48
# bins meant every tile's water sat on a slightly wrong lane, side-stepping
# at each boundary. The across now lives in a small float DATA TEXTURE the
# manager fills with each tile's EXACT catalog value; the shader samples
# it with bilinear filtering, so the GPU interpolates between tiles
# natively -- no bins, no reconstruction, no seams, by construction.

func test_the_shader_samples_the_across_map_bilinearly():
	assert_true(
		RiverFlowShader.SHADER_CODE.contains("uniform sampler2D flow_across_map : filter_linear, repeat_enable;"),
		"the across must come from a linearly filtered map"
	)
	assert_true(
		RiverFlowShader.SHADER_CODE.contains("float frag_across = map_data.r;"),
		"the fragment across is the sampled map value, nothing reconstructed"
	)
	assert_false(
		RiverFlowShader.SHADER_CODE.contains("across_range"),
		"no encode range may survive -- the map stores real signed floats"
	)
	assert_false(
		RiverFlowShader.SHADER_CODE.contains("floor(wp / tile_px)"),
		"the tile-centre reconstruction is gone with the bins that forced it"
	)


## The map is addressed toroidally -- tile mod map size -- so chunk
## streaming never copies or re-anchors it: a newly loaded chunk simply
## overwrites the stale block its coordinates alias to.
func test_the_map_lookup_wraps_toroidally():
	assert_true(
		RiverFlowShader.SHADER_CODE.contains("vec2 map_uv = (wp / tile_px) / flow_map_tiles;"),
		"the lookup must be world tiles over map size, with repeat wrapping"
	)


# -- the wader's wake ---------------------------------------------------------
#
# "a player walking through the stream should cause realistic current
# displacement": the water's across-field bends around the wader exactly the
# way it bends around a boulder -- same radial push, softer and smaller --
# and the displacement TRAILS DOWNSTREAM, because pushed water is carried
# away by the current, not left hanging symmetrically around the legs.
# Unlike a boulder, a wader never dries the water: no eyot.

func test_the_wader_push_is_softer_and_smaller_than_a_boulders():
	assert_lt(RiverFlowShader.WADER_RADIUS_PX, RiverFlowShader.BOULDER_RADIUS_PX)
	assert_lt(RiverFlowShader.WADER_REACH_PX, RiverFlowShader.BOULDER_REACH_PX)


func test_the_wader_push_repels_both_sides_and_fades_out():
	var flow := Vector2(1.0, 0.0)
	var left := RiverFlowShader.wader_across_push(Vector2(0.0, -8.0), flow)
	var right := RiverFlowShader.wader_across_push(Vector2(0.0, 8.0), flow)
	assert_true(
		left * right < 0.0,
		"opposite sides of the wader must be pushed to opposite banks"
	)
	assert_gt(
		absf(RiverFlowShader.wader_across_push(Vector2(0.0, 5.0), flow)),
		absf(RiverFlowShader.wader_across_push(Vector2(0.0, 20.0), flow)),
		"the push must fade with distance"
	)
	assert_almost_eq(
		RiverFlowShader.wader_across_push(
			Vector2(0.0, RiverFlowShader.WADER_REACH_PX + 1.0), flow
		),
		0.0, 0.0001,
		"nothing sideways beyond the reach"
	)


func test_the_wake_trails_downstream_not_upstream():
	var flow := Vector2(1.0, 0.0)
	var beyond := RiverFlowShader.WADER_REACH_PX * 1.3
	var downstream := RiverFlowShader.wader_across_push(Vector2(beyond, 6.0), flow)
	var upstream := RiverFlowShader.wader_across_push(Vector2(-beyond, 6.0), flow)
	assert_gt(
		absf(downstream), 0.0,
		"the wake must persist past the base reach on the downstream side"
	)
	assert_almost_eq(
		upstream, 0.0, 0.0001,
		"upstream of the wader the water has not met the legs yet"
	)
	assert_gte(
		absf(RiverFlowShader.wader_across_push(Vector2(15.0, 6.0), flow)),
		absf(RiverFlowShader.wader_across_push(Vector2(-15.0, 6.0), flow)),
		"at mirrored offsets the downstream push must never be the weaker one"
	)


## A wader displaces the current but never dries the channel: eyot carving
## stays exclusive to boulders. Structural: exactly one place in the whole
## fragment shader narrows eyot_dry, and it is the boulder loop.
func test_only_the_boulder_loop_carves_dry_eyots():
	assert_eq(
		RiverFlowShader.SHADER_CODE.count("eyot_dry = min("), 1,
		"a second eyot writer means something besides boulders dries the water"
	)
	var wader_block_start: int = RiverFlowShader.SHADER_CODE.find("wader_count")
	assert_gt(wader_block_start, 0, "the fragment shader must consult the waders")


## SHADER_CODE keeps whatever newline convention its source file is
## checked out with, and this repo's .gd files are CRLF. The multi-line
## assertions below are written with plain \n, so they must compare
## against a normalised copy -- otherwise they pass or fail on the
## checkout's line-ending setting rather than on the shader code.
func _shader_code_lf() -> String:
	return RiverFlowShader.SHADER_CODE.replace("\r\n", "\n")


# -- the light water around a rock is its SHOAL, not a painted ring -------
#
# "The boulders halo should not be computed by the boulder, but rather be
# part of the river's hydrology... the lighter color bands should come
# from elevation (rock is above waterline)." The rock stands above the
# waterline, so the bed rises to meet it, so the water shallows toward it
# -- and shallow water is LIGHT here for the same reason the banks are:
# the cel body is depth. So the boulder contributes a shoal to the depth
# field and nothing to the palette: the same cel quantisation and dither
# that band the banks band the rock. The painted ring (boulder_band*),
# its colour ramp, its wobble and its rule that a rock on dry ground
# lights water around itself are removed, not restyled.


func test_the_light_water_around_a_rock_is_its_shoal_in_the_depth_field():
	var R := 12.0
	assert_almost_eq(RiverFlowShader.boulder_shoal(R, R), 1.0, 1e-9, "at the rock's edge the bed IS the rock")
	assert_almost_eq(RiverFlowShader.boulder_shoal(R * 0.5, R), 1.0, 1e-9, "and under it")
	var outer := R + R * RiverFlowShader.BOULDER_SHOAL_RATIO
	assert_almost_eq(RiverFlowShader.boulder_shoal(outer, R), 0.0, 1e-9, "the shoal ends at its outer edge")
	assert_almost_eq(RiverFlowShader.boulder_shoal(outer * 2.0, R), 0.0, 1e-9)
	var previous := 1.0
	for i in range(1, 30):
		var d := R + (outer - R) * float(i) / 29.0
		var here := RiverFlowShader.boulder_shoal(d, R)
		assert_lte(here, previous + 1e-9, "the bed falls away from the rock monotonically")
		previous = here
	assert_between(RiverFlowShader.BOULDER_SHOAL_RATIO, 1.0, 2.5, "a shoal of one to a couple of radii")


func test_at_the_rock_s_edge_the_water_is_as_light_as_the_bank():
	var R := 12.0
	assert_almost_eq(RiverFlowShader.shoaled_depth_fraction(1.0, R, R), 0.0, 1e-9, "mid-channel depth, shoaled to nothing at the rock")
	assert_eq(
		RiverFlowShader.depth_color(RiverFlowShader.shoaled_depth_fraction(1.0, R, R)),
		RiverFlowShader.BAND_COLORS[0],
		"the same lightest tone the bank shows -- no colour of its own"
	)
	var far := R + R * RiverFlowShader.BOULDER_SHOAL_RATIO * 2.0
	assert_almost_eq(RiverFlowShader.shoaled_depth_fraction(0.7, far, R), 0.7, 1e-9, "past the shoal the channel's own depth is untouched")
	assert_lt(RiverFlowShader.shoaled_depth_fraction(0.7, R * 1.5, R), 0.7, "inside it the water is shallower")


func test_a_bigger_rock_has_a_bigger_shoal():
	var d := 20.0
	assert_gt(RiverFlowShader.boulder_shoal(d, 16.0), RiverFlowShader.boulder_shoal(d, 8.0))
	assert_almost_eq(RiverFlowShader.boulder_shoal(8.0 + 8.0 * RiverFlowShader.BOULDER_SHOAL_RATIO, 8.0), 0.0, 1e-9)
	assert_gt(RiverFlowShader.boulder_shoal(8.0 + 8.0 * RiverFlowShader.BOULDER_SHOAL_RATIO, 16.0), 0.0)


func test_the_shoal_enters_the_depth_field_and_no_ring_is_painted():
	var code: String = RiverFlowShader.SHADER_CODE
	assert_true(code.contains("float shoal = 1.0 - smoothstep(R, R + R * boulder_shoal_ratio, d);"))
	assert_true(code.contains("boulder_shoal = max(boulder_shoal, shoal);"))
	assert_true(code.contains("depth_frac *= 1.0 - boulder_shoal;"), "the shoal shallows the depth the cel body is cut from")
	assert_false(code.contains("boulder_band"), "no painted band remains, in any form")
	assert_false(code.contains("line_color, band0_color"), "no boulder colour ramp of its own")
	var material := RiverFlowShader.new().make_material()
	assert_almost_eq(
		float(material.get_shader_parameter("boulder_shoal_ratio")), RiverFlowShader.BOULDER_SHOAL_RATIO, 1e-9
	)


func test_the_body_stays_static_depth_with_the_shoal_in_it():
	# The shoal is geometry, like the banks: it must not read the moving
	# field. The cel body pin (test_the_body_cels_are_static_depth_only)
	# still holds, and the shoal itself is a function of distance alone.
	assert_false(RiverFlowShader.SHADER_CODE.contains("boulder_shoal + (n"))
	assert_false(RiverFlowShader.SHADER_CODE.contains("shoal * n"))


func test_the_material_starts_with_no_waders():
	var material := RiverFlowShader.new().make_material()
	assert_eq(int(material.get_shader_parameter("wader_count")), 0)
	assert_almost_eq(
		float(material.get_shader_parameter("wader_radius_px")),
		RiverFlowShader.WADER_RADIUS_PX, 0.0001
	)


## "animals should also cause water displacement like the player": the
## wader is an ARRAY now, same shape as the boulders -- the player plus
## every in-river creature the world feeds each frame.
func test_the_shader_loops_over_a_wader_array():
	assert_true(RiverFlowShader.SHADER_CODE.contains("uniform vec2 waders["))
	assert_true(RiverFlowShader.SHADER_CODE.contains("uniform int wader_count"))
	assert_true(
		RiverFlowShader.SHADER_CODE.contains("for (int w = 0; w < wader_count; w++)")
	)


# -- movement ripples: fish, the player, animals ------------------------------
#
# Reported: "Fishes don't produce interferencing ripples anymore in the new
# unified river water ... players and animals neither ... the old ripples
# looked nice so we want them back adapted to new water shader".
#
# The ripple machinery never broke -- FishMarker/Player/CreatureMarker all
# still record disturbances and WaterShader still ages them. What broke is
# that the ocean overlay stopped painting river tiles (its square tiles
# under the smooth bank curve were the bug it was removed to fix) and this
# opaque surface, which replaced it, had no disturbance term at all. So the
# river had no ripple-capable surface. See docs/concept/rivers.md's
# "Movement ripples in the river".
#
# The pins below split into three groups: the packet must be the OLD one
# (that is the "looked nice" the report is asking back for), the ring must
# be ADAPTED to a river (carried by the current, drawn in ink rather than
# glowed), and it must never touch the channel's geometry.


## The peak signed amplitude any real packet ever reaches, scanned from the
## packet itself rather than written down -- every threshold below is
## expressed against this, so re-tuning the packet re-tunes its own bounds
## instead of silently invalidating an eyeballed literal.
func _peak_packet_amplitude() -> float:
	return _peak_amplitude_from_age(0.0)


## The largest crest still reachable once a ripple is `fraction` of the way
## through its life -- what pins that a ring does not wink out in its first
## moments (the exact failure WaterShader's own visible-across-its-lifetime
## test was written for).
func _peak_amplitude_at_life_fraction(fraction: float) -> float:
	return _peak_amplitude_from_age(RiverFlowShader.RIPPLE_LIFETIME * fraction)


func _peak_amplitude_from_age(youngest_age: float) -> float:
	var peak := 0.0
	var age := youngest_age
	while age <= RiverFlowShader.RIPPLE_LIFETIME:
		for dist_step in 400:
			peak = maxf(peak, RiverFlowShader.ripple_packet(float(dist_step) * 0.25, age))
		age += 0.01
	return peak


## THE "we want them back" pin: the river's packet is not a new ripple that
## merely resembles the old one, it is the same function. A fish's wake has
## to read identically in a river and in the sea.
func test_the_river_draws_the_very_same_wave_packet_as_the_sea():
	for dist_step in 60:
		var dist: float = float(dist_step) * 0.7
		for age_step in 22:
			var age: float = float(age_step) * 0.1
			assert_almost_eq(
				RiverFlowShader.ripple_packet(dist, age),
				WaterShader.ripple_amplitude(dist, age),
				0.000001,
				"packet diverged from the ocean's at dist %f age %f" % [dist, age]
			)


## And it shares the tuning by IMPORT, not by a copied literal -- a second
## copy is a second thing to re-tune, and the two surfaces would drift.
func test_the_ripple_tuning_is_the_ocean_s_own_constants():
	assert_eq(RiverFlowShader.RIPPLE_LIFETIME, WaterShader.RIPPLE_LIFETIME)
	assert_eq(RiverFlowShader.DISTURBANCE_SLOTS, WaterShader.MAX_DISTURBANCES)


## "interferencing" is the whole word in the report: the packet is SIGNED,
## so two overlapping wakes cancel where a crest meets a trough instead of
## only ever piling up. An unsigned ring can only ever add.
func test_overlapping_wakes_genuinely_interfere():
	var crest := 0.0
	var trough := 0.0
	for dist_step in 400:
		var value := RiverFlowShader.ripple_packet(float(dist_step) * 0.25, 0.6)
		crest = maxf(crest, value)
		trough = minf(trough, value)
	assert_gt(crest, 0.0, "a packet with no crest is not a wave")
	assert_lt(trough, 0.0, "a packet with no trough cannot destructively interfere")


## THE river adaptation. In still water a ring is concentric about a fixed
## point; in a current it is concentric about a point that MOVES WITH THE
## WATER. Without this the ring stands still while the river slides out
## from under it -- the one thing ocean water never has to express.
func test_the_ring_is_carried_downstream_by_the_current():
	var origin := Vector2(100.0, 40.0)
	var downstream := Vector2(1.0, 0.0)
	var still := RiverFlowShader.ripple_center(origin, downstream, 0.0, 1.0)
	assert_eq(still, origin, "with no current the ring must stay put")

	var carried := RiverFlowShader.ripple_center(origin, downstream, 1.5, 1.0)
	var travel := carried - origin
	assert_gt(travel.dot(downstream), 0.0, "the ring must move DOWNSTREAM, not up")
	assert_almost_eq(travel.length(), RiverFlowShader.surface_px_per_s(1.5) * 1.0, 0.0001)


## It travels with the surface the player can actually SEE moving -- the
## water's whole visible streaming speed (surface_px_per_s: the phase
## drag's translation plus the linear drift), NOT the drift alone. A wake
## carried at some other rate reads as sliding across the water rather
## than sitting in it -- and carried at the drift alone it sat at a third
## of the water's speed ("make the river ripples move downstream at water
## speed").
func test_the_ring_travels_at_the_surface_pattern_s_own_rate():
	var carried := RiverFlowShader.ripple_center(Vector2.ZERO, Vector2(0.0, 1.0), 2.0, 3.0)
	assert_almost_eq(carried.y, RiverFlowShader.surface_px_per_s(2.0) * 3.0, 0.0001)


## Drawn, not glowed: the ring bends the field whose level sets ARE the
## current lines, so it comes out as ink arcs in the same hand as the rest
## of the water. Big enough to bow a line by a visible fraction of one
## contour spacing...
##
## LOWERED from 0.3 (a full third) merging claude/hydrology-spec's own,
## independently and repeatedly measured LINE_WOBBLE tuning (0.6 -> 0.12 ->
## 0.17, see that constant's own doc comment) against this ripple work,
## developed on a separate branch with no visibility into that tuning: the
## two bounds this test and test_a_ripple_cannot_restructure_the_whole_
## channel enforce -- roughly a third of a contour on this side, half of
## LINE_WOBBLE on that one -- are ALGEBRAICALLY INCOMPATIBLE once
## LINE_WOBBLE drops below 0.2 (this project's own RIPPLE_LINE_GAIN is now
## LINE_WOBBLE * 0.3, chosen to keep the wobble-side bound satisfied with
## the SAME margin ratio the original hardcoded 0.18 held against wobble's
## pre-tuning value of 0.6 -- see RIPPLE_LINE_GAIN's own doc comment).
## Between the two, ceding ground here rather than on the wobble side: a
## too-subtle ripple is a small, easily re-tuned cosmetic gap; a wobble
## retuned back up to satisfy this side's original 0.3 would reopen the
## channel-folding-into-closed-cells artifact LINE_WOBBLE's own repeated,
## MEASURED (tools/probe_monotone.gd) tuning history was fixing. Real
## margin kept either way (current bend ~0.0386 against a ~0.033 floor) --
## not tuned to the current value's exact edge -- but this specific split
## is a mechanical resolution of a genuine cross-branch conflict, not a
## visually-verified choice; worth a real look once both features can be
## seen rendered together.
func test_a_crest_bends_the_current_lines_enough_to_see():
	var bend := RiverFlowShader.RIPPLE_LINE_GAIN * _peak_packet_amplitude()
	var contour_spacing := 1.0 / RiverFlowShader.LINE_COUNT
	assert_gt(
		bend, contour_spacing * 0.1,
		"a crest that moves the field less than a tenth of a contour draws nothing"
	)


## ...and small enough that it stays a LOCAL disturbance: it may close the
## contours into rings around the fish (that IS the ripple), but it must
## never out-swing the wobble and restructure the channel-wide line family
## into the "perlin noise cells" the across ramp exists to prevent.
func test_a_ripple_cannot_restructure_the_whole_channel():
	var bend := RiverFlowShader.RIPPLE_LINE_GAIN * _peak_packet_amplitude()
	assert_lt(
		bend, RiverFlowShader.LINE_WOBBLE * 0.5,
		"a ripple out-swinging the wobble stops being a local disturbance"
	)


## The crest also inks in its own right, so the ring reads as concentric
## arcs and not merely as wobbled flow lines. Full ink must be REACHABLE by
## a real crest -- a threshold above the packet's own peak draws nothing.
func test_a_real_crest_reaches_full_ink():
	assert_gt(RiverFlowShader.RIPPLE_CREST_MIN, 0.0, "troughs and tails must stay clean")
	assert_lt(RiverFlowShader.RIPPLE_CREST_MIN, RiverFlowShader.RIPPLE_CREST_FULL)
	assert_lte(
		RiverFlowShader.RIPPLE_CREST_FULL, _peak_packet_amplitude(),
		"full ink beyond the packet's peak is ink that never prints"
	)


## The lesson WaterShader already paid for once: thresholds set against a
## FRESH ripple make the ring visible only in its first fraction of a life
## ("a mini ripple appears but nothing looks natural"). A crest must still
## ink well into the ring's decay.
func test_a_ring_still_inks_three_quarters_through_its_life():
	assert_gt(
		_peak_amplitude_at_life_fraction(0.75), RiverFlowShader.RIPPLE_CREST_MIN,
		"the ring stops drawing long before the packet stops existing"
	)


## Both ripple terms enter fields that already exist -- the stroke field
## and the stroke strength -- so the ring inherits the ink colour, the
## moonlight lift and the alpha clamp for free instead of being a bright
## ring composited over illustrated water.
func test_the_ripple_is_drawn_into_the_strokes_not_over_them():
	assert_true(
		RiverFlowShader.SHADER_CODE.contains("+ ripple * ripple_line_gain"),
		"the ripple must bend the contour field the current lines trace"
	)
	assert_true(
		RiverFlowShader.SHADER_CODE.contains("ripple_crest_min, ripple_crest_full, ripple"),
		"the crest must ink through the existing stroke strength"
	)


## The body cels stay STATIC (see test_the_body_cels_are_static_depth_only):
## all the motion is carried by the drawn strokes, ripples included.
func test_the_ripple_never_shades_the_body():
	assert_true(
		RiverFlowShader.SHADER_CODE.contains("float shade = depth_frac;"),
		"the cel shade must remain pure reconstructed depth"
	)


## A passing fish must not move the BANK. frag_across is the channel's
## geometry -- boulders and waders displace it on purpose, because they are
## solid things standing in the water; a wake is a surface disturbance and
## narrowing the river with one would be nonsense.
func test_a_ripple_never_moves_the_waterline():
	assert_false(
		RiverFlowShader.SHADER_CODE.contains("frag_across += ripple"),
		"a wake must not displace the channel geometry"
	)
	assert_eq(
		RiverFlowShader.SHADER_CODE.count("eyot_dry = min("), 1,
		"a ripple must not dry the water either"
	)


func test_the_shader_loops_over_a_disturbance_array():
	assert_true(RiverFlowShader.SHADER_CODE.contains("uniform vec2 disturbance_pos["))
	assert_true(RiverFlowShader.SHADER_CODE.contains("uniform float disturbance_age["))
	assert_true(
		RiverFlowShader.SHADER_CODE.contains("for (int i = 0; i < disturbance_count; i++)")
	)


func test_the_material_starts_with_no_disturbances_and_the_real_tuning():
	var material := RiverFlowShader.new().make_material()
	assert_eq(int(material.get_shader_parameter("disturbance_count")), 0)
	assert_almost_eq(
		float(material.get_shader_parameter("ripple_line_gain")),
		RiverFlowShader.RIPPLE_LINE_GAIN, 0.0001
	)
	assert_almost_eq(
		float(material.get_shader_parameter("ripple_lifetime")),
		RiverFlowShader.RIPPLE_LIFETIME, 0.0001
	)


func test_set_disturbances_pushes_the_whole_buffer():
	var river := RiverFlowShader.new()
	var positions := PackedVector2Array([Vector2(7.0, 9.0)])
	positions.resize(RiverFlowShader.DISTURBANCE_SLOTS)
	var ages := PackedFloat32Array([0.25])
	ages.resize(RiverFlowShader.DISTURBANCE_SLOTS)
	river.set_disturbances(positions, ages, 1)

	var material := river.shared_material()
	assert_eq(int(material.get_shader_parameter("disturbance_count")), 1)
	assert_eq(material.get_shader_parameter("disturbance_pos")[0], Vector2(7.0, 9.0))
	assert_almost_eq(float(material.get_shader_parameter("disturbance_age")[0]), 0.25, 0.0001)


## Lakes ride this overlay with zero current (docs/concept/hydrology.md,
## first playtest: "ponds have a very different art style"): still water
## must not advect or drift, and no real river may ever read as still.
func test_still_water_neither_advects_nor_drifts():
	assert_true(RiverFlowShader.is_still_water(0.0))
	assert_false(RiverFlowShader.is_still_water(0.39), "the slowest Manning reach is not still")
	assert_lt(RiverFlowShader.STILL_FLOW_M_S, RiverFlowShader.FAST_FLOW_M_S)
	assert_true(RiverFlowShader.SHADER_CODE.contains("float moving = step(still_flow_m_s, speed_mps);"))
	assert_true(RiverFlowShader.SHADER_CODE.contains("float advect_gate = mix(still_ripple, 1.0, moving);"))
	# Flowing water takes the smeared, drifting path; still water takes the
	# cheap two-tap ripple path and never drifts.
	assert_true(RiverFlowShader.SHADER_CODE.contains("if (moving > 0.5) {"))
	assert_true(RiverFlowShader.SHADER_CODE.contains("advect_strength * phase_a * advect_gate + drift"))
	assert_true(RiverFlowShader.SHADER_CODE.contains("float ripple_a = value_noise(q + flow_perp * (advect_strength * still_ripple * phase_a));"))
	var material := flow.shared_material()
	assert_almost_eq(
		float(material.get_shader_parameter("still_flow_m_s")), RiverFlowShader.STILL_FLOW_M_S, 1e-9
	)
	assert_almost_eq(
		float(material.get_shader_parameter("still_ripple")), RiverFlowShader.STILL_RIPPLE, 1e-9
	)


## Still water ripples (the strokes breathe in place) but never flows:
## the ripple fraction sits strictly between frozen and a river's morph.
func test_still_water_ripples_without_flowing():
	assert_gt(RiverFlowShader.STILL_RIPPLE, 0.0)
	assert_lt(RiverFlowShader.STILL_RIPPLE, 0.5)


## Eddies strengthen toward the banks, but the smear follows the FLOW and
## never the eddies: rotating it by the eddy field sawed every stroke into
## a regular zig-zag with the eddy noise's own period (found in play).
func test_the_smear_follows_the_flow_and_never_the_eddies():
	assert_eq(RiverFlowShader.EDDY_SWIRL, 0.0)
	assert_true(RiverFlowShader.SHADER_CODE.contains("float shear = 1.0 + bank_shear * clamp(abs(frag_across), 0.0, 1.0);"))
	var material := flow.shared_material()
	assert_eq(float(material.get_shader_parameter("eddy_swirl")), 0.0)


## bank_shear amplified the turbulence displacement by up to 25% near the
## waterline, and TURBULENCE_STRENGTH alone already sits right against a
## real, tested fold threshold (test_the_bend_never_folds_the_surface_
## over_itself) that this CPU mirror never accounted for the shear
## multiplier in the first place -- so that test kept passing while the
## live GPU formula, WITH shear applied, silently crossed the threshold
## across the wide band near a hydrology river's bank, tearing the noise
## pattern into a sharp, chunky zigzag ("this huge zigzag still
## persists", reported through two rounds of an unrelated fix). Zero is
## the only value that keeps the live formula and its tested CPU mirror
## identical -- any nonzero value here needs the fold test itself
## extended to cover the shear-amplified case FIRST.
func test_bank_shear_is_zero_so_the_fold_test_covers_the_live_formula():
	assert_eq(RiverFlowShader.BANK_SHEAR, 0.0)
	var material := flow.shared_material()
	assert_eq(float(material.get_shader_parameter("bank_shear")), 0.0)


## The tile's REAL local half-width, not the fixed uniform, must decide how
## strongly a boulder or wader push bends the strokes: a fixed divisor
## understated a wide hydrology reach's true width by up to 3x (the
## catalog's curated constant, 2.0 tiles, against hydrology's up to 6), so
## the same physical push landed up to 3x stronger, relative to that
## reach, than intended -- reported in play as "artifacts in curves", wide
## bends being exactly where a river slows and gathers fish. The width now
## rides the direction vector's own magnitude (a direction's length
## otherwise carries no information). Ripples no longer divide by it at
## all: they bend the stroke field directly (see the movement-ripple tests
## above), never the channel geometry.
func test_boulder_and_wader_pushes_divide_by_the_real_local_width():
	# The width still comes from its own scalar map and is still floored
	# at 0.05; it now goes through the same cubic reconstruction the across
	# map does, so the pushes that divide by it stop inheriting the texel
	# lattice's sawtooth.
	assert_true(_shader_code_lf().contains(
		"float half_width_local = max(mix(\n\t\ttexture(flow_scale_map, map_uv),\n\t\ttexture_bicubic(flow_scale_map, map_uv, flow_map_tiles),\n\t\tmap_smoothing\n\t).r, 0.05);"
	))
	assert_eq(
		RiverFlowShader.SHADER_CODE.count("/ (half_width_local * tile_px)"), 2,
		"boulder and wader must both divide by the LOCAL width"
	)
	assert_false(
		RiverFlowShader.SHADER_CODE.contains("/ (half_width_tiles * tile_px)"),
		"neither may still read the fixed uniform"
	)


## The structural fix for "this huge zigzag still persists": width and
## direction must live on SEPARATE maps. Packing width into the direction
## vector's own magnitude broke under bilinear filtering -- two texels
## whose BEARINGS differ (exactly what neighbouring texels do on a bend)
## partially cancel when summed as vectors, collapsing the blended
## magnitude toward zero regardless of either texel's real width, which
## corrupted both the decoded width and (normalizing a near-zero vector)
## the decoded direction. GB must be restored to a genuine unit vector
## (numerically stable under any blend) and the width sampled from its
## own scalar texture, which blends safely by construction: bilinearly
## interpolating two SCALARS always lands between them, never collapses.
func test_direction_and_width_are_never_packed_into_the_same_vector():
	assert_true(RiverFlowShader.SHADER_CODE.contains(
		"uniform sampler2D flow_scale_map : filter_linear, repeat_enable;"
	))
	assert_true(RiverFlowShader.SHADER_CODE.contains(
		"vec2 flow_dir = normalize(map_data.gb + vec2(1e-6, 0.0));"
	), "GB must be a plain unit vector again, safe to bilinearly blend")
	assert_false(
		RiverFlowShader.SHADER_CODE.contains("map_data.gb / half_width_local"),
		"direction may never be derived by dividing by a length riding the same vector"
	)


## Fish join the player and the animals as waders, and in still water the
## wake must ring the wader instead of trailing "downstream".
func test_waders_have_room_for_fish_and_ring_still_water():
	assert_gte(RiverFlowShader.WADER_SLOTS, 16)
	assert_true(RiverFlowShader.SHADER_CODE.contains("uniform vec2 waders[16];"))
	assert_true(RiverFlowShader.SHADER_CODE.contains("wader_wake_trail * moving * clamp(along / wader_reach_px, 0.0, 1.0)"))


# -- the smear follows the course's CURVE ------------------------------------
#
# "The zigzags still happen almost at every bend / curve ... that's where it
# happens 100% of the times." Measured before any of this was written, with
# tools/probe_smear.gd over 1,997 wet tiles around the spawn: the smear
# spans 5.31 tiles and treats the course as STRAIGHT over all of it, while
# the course actually turns up to 45.12 deg across that span -- 12.17 deg at
# the 75th percentile, 19.47 at the 90th, and 30 or more on 1.6% of wet
# tiles, which is exactly where the bends are. Two neighbouring fragments
# then smear along diverging straight lines, and the strokes they draw tear
# apart instead of lining up.
#
# The same probe measured the cure before it was built. Reading the flow at
# the two ENDS of the smear and interpolating between them drops the 75th
# percentile to 2.49 deg and the 90th to 5.38, for TWO extra texture samples
# rather than the eight a per-tap resample would cost. A bend has roughly
# constant curvature, and a tangent rotates linearly with arc length along
# an arc, so a straight line between the endpoints is very nearly the right
# model. These tests hold on to that ratio.


func test_the_smear_half_span_is_the_outermost_taps_own_reach():
	# Four steps of SMEAR_SPACING in noise units, in world pixels.
	var expected := 4.0 * RiverFlowShader.SMEAR_SPACING / RiverFlowShader.NOISE_SCALE
	assert_almost_eq(RiverFlowShader.smear_half_span_px(), expected, 1e-9)
	# The probe reported 2.66 tiles either side; the shader must agree with
	# the measurement that justified the change, or the numbers above stop
	# describing the code.
	assert_almost_eq(
		RiverFlowShader.smear_half_span_px() / RiverFlowShader.TILE_PX, 2.656, 1e-3
	)


func test_the_tap_direction_runs_from_one_end_of_the_smear_to_the_other():
	var from := Vector2(1.0, 0.0)
	var to := Vector2(0.0, 1.0)
	assert_almost_eq(
		RiverFlowShader.smear_tap_direction(from, to, -4).angle(), from.angle(), 1e-6
	)
	assert_almost_eq(
		RiverFlowShader.smear_tap_direction(from, to, 4).angle(), to.angle(), 1e-6
	)
	# The centre tap sits halfway between the two ends.
	assert_almost_eq(
		RiverFlowShader.smear_tap_direction(from, to, 0).angle(), deg_to_rad(45.0), 1e-6
	)


func test_every_tap_direction_is_a_unit_vector():
	# A tap direction only ever chooses a HEADING; the step length is
	# smear_spacing. A short interpolated vector would quietly shorten the
	# stroke in the middle of a bend.
	var from := Vector2(1.0, 0.0)
	var to := Vector2(-0.7, 0.7).normalized()
	for k in range(-4, 5):
		assert_almost_eq(
			RiverFlowShader.smear_tap_direction(from, to, k).length(), 1.0, 1e-6,
			"tap %d must not scale its own step" % k
		)


func test_a_straight_reach_leaves_the_smear_exactly_straight():
	# Both ends reading the same direction must reproduce the old straight
	# smear, so this can never change how a straight reach looks -- and the
	# probe says the median tile turns 0.15 deg, so most water IS straight.
	var straight := Vector2(0.6, -0.8).normalized()
	for k in range(-4, 5):
		assert_almost_eq(
			RiverFlowShader.smear_tap_direction(straight, straight, k).angle(),
			straight.angle(), 1e-6
		)


func test_the_shader_reads_the_flow_at_both_ends_of_the_smear():
	assert_true(RiverFlowShader.SHADER_CODE.contains(
		"vec2 flow_dir_at(vec2 world_position, vec2 fallback)"
	))
	assert_true(RiverFlowShader.SHADER_CODE.contains(
		"flow_dir_at(wp - smear_end_offset, swirl_dir)"
	))
	assert_true(RiverFlowShader.SHADER_CODE.contains(
		"flow_dir_at(wp + smear_end_offset, swirl_dir)"
	))
	assert_true(RiverFlowShader.SHADER_CODE.contains(
		"float line_field(vec2 q, vec2 dir_start, vec2 dir_end)"
	))


func test_the_endpoint_lookup_falls_back_where_the_map_has_no_direction():
	# Past the painted band the map's GB channels are zero, and normalizing
	# that is a NaN that would poison every tap. The lookup must hand back
	# the fragment's own direction there instead.
	assert_true(RiverFlowShader.SHADER_CODE.contains("if (dot(raw, raw) < 1e-8)"))
	assert_true(RiverFlowShader.SHADER_CODE.contains("return fallback;"))


func test_the_smear_curvature_dials_back_to_the_straight_smear():
	var material := RiverFlowShader.new().make_material()
	assert_almost_eq(
		float(material.get_shader_parameter("smear_curvature")),
		RiverFlowShader.SMEAR_CURVATURE, 1e-9
	)
	assert_between(RiverFlowShader.SMEAR_CURVATURE, 0.0, 1.0)
	# At 0 both ends collapse onto the fragment's own direction, which is
	# the straight smear this replaced -- a real comparison, in game, at
	# one uniform.
	assert_true(RiverFlowShader.SHADER_CODE.contains(
		"swirl_dir, flow_dir_at(wp - smear_end_offset, swirl_dir), smear_curvature"
	))


# -- the across map's own reconstruction filter -------------------------------
#
# THE ZIGZAG, finally located. The flow map holds one texel per TILE, and
# every stroke, the waterline, the ink line and the shore highlight are
# CONTOURS of that field. Sampled with plain bilinear filtering, the field's
# gradient is CONSTANT inside each texel cell and JUMPS at the boundary --
# so its contours are polygons: straight segments meeting at kinks, one
# kink per tile. That is a sawtooth by construction, and no amount of
# smoothing the underlying data can remove it.
#
# Measured with tools/probe_bilinear.gd, walking the course at one of the
# bends the user reports it at 100% of the time (tile 19913, 4742), in
# degrees of contour-normal turn per eighth of a tile:
#
#   bilinear         median 0.000   peak 22.547
#   cubic B-spline   median 0.024   peak  4.870
#
# The median of exactly ZERO is the signature: bilinear's gradient does not
# turn at all inside a cell, then turns all at once. A cubic B-spline is C2,
# so it turns a little everywhere and never all at once -- peak 4.6x lower.
#
# This is also why the earlier attempt failed and was reverted ("now it's
# much worse ... the artifacts stay, just look different"). That one warped
# the sample COORDINATE with a smoothstep and left hardware bilinear
# underneath, so the polygon survived and gained plateaus at texel centres.
# The filter itself has to change, not the coordinate fed to it.


func _ramp_grid(span: int) -> PackedFloat32Array:
	# A synthetic across-field: a signed distance to a line at 30 degrees,
	# which is what a straight reach's own across field looks like, sampled
	# once per tile exactly as the real map is.
	var values := PackedFloat32Array()
	values.resize(span * span)
	var normal := Vector2(cos(deg_to_rad(30.0)), sin(deg_to_rad(30.0)))
	for y in span:
		for x in span:
			values[y * span + x] = (
				Vector2(float(x) + 0.5, float(y) + 0.5) - Vector2(float(span), float(span)) * 0.5
			).dot(normal)
	return values


## The weights must partition unity, or the reconstruction changes the
## field's own magnitude -- a distance field that is scaled is a waterline
## in the wrong place.
func test_the_bspline_weights_sum_to_one_everywhere():
	for step in 21:
		var t := float(step) / 20.0
		var weights := RiverFlowShader.bspline_weights(t)
		var total := 0.0
		for weight in weights:
			total += weight
			assert_gte(weight, 0.0, "a negative weight would ring at a step edge")
		assert_almost_eq(total, 1.0, 1e-6, "weights at t=%f" % t)


## At a texel centre the cubic B-spline is the classic 1:4:1 stencil.
func test_the_bspline_weights_are_the_one_four_one_stencil_at_a_texel_centre():
	var weights := RiverFlowShader.bspline_weights(0.0)
	assert_almost_eq(weights[0], 1.0 / 6.0, 1e-6)
	assert_almost_eq(weights[1], 4.0 / 6.0, 1e-6)
	assert_almost_eq(weights[2], 1.0 / 6.0, 1e-6)
	assert_almost_eq(weights[3], 0.0, 1e-6)


## Both filters must reproduce a LINEAR field's own slope: a straight reach
## must not be bent by the thing that unbends the corners.
func test_both_filters_carry_a_straight_reachs_own_gradient():
	var span := 16
	var values := _ramp_grid(span)
	var expected := Vector2(cos(deg_to_rad(30.0)), sin(deg_to_rad(30.0)))
	for at in [Vector2(7.3, 8.1), Vector2(8.0, 8.0), Vector2(9.75, 7.25)]:
		for sampler in ["bilinear", "bspline"]:
			var gradient := _grid_gradient(values, span, at, sampler)
			assert_almost_eq(
				rad_to_deg(gradient.angle()), rad_to_deg(expected.angle()), 0.5,
				"%s bent a straight reach at %s" % [sampler, at]
			)


## The property the whole change exists for, on a field with real
## curvature: bilinear's gradient direction jumps between texel cells and
## the B-spline's does not.
func test_the_bspline_gradient_turns_smoothly_where_bilinear_jumps():
	var span := 24
	# A radial distance field -- a bend, in the smallest honest form: its
	# contours are circles, so a correct reconstruction turns steadily.
	var values := PackedFloat32Array()
	values.resize(span * span)
	var centre := Vector2(float(span), float(span)) * 0.5
	for y in span:
		for x in span:
			values[y * span + x] = (Vector2(float(x) + 0.5, float(y) + 0.5) - centre).length()

	var worst := {"bilinear": 0.0, "bspline": 0.0}
	for sampler in ["bilinear", "bspline"]:
		var previous := INF
		# Walk a circle of radius 6 around the centre, well inside the grid.
		for step in 240:
			var angle := TAU * float(step) / 240.0
			var at := centre + Vector2(cos(angle), sin(angle)) * 6.0
			var gradient := _grid_gradient(values, span, at, sampler)
			if gradient.length() < 1e-9:
				continue
			var heading := rad_to_deg(gradient.angle())
			if previous != INF:
				var turn := absf(fposmod(heading - previous + 180.0, 360.0) - 180.0)
				worst[sampler] = maxf(worst[sampler], turn)
			previous = heading

	# A steady walk around a circle of radius 6 turns 360/240 = 1.5 deg per
	# step. Bilinear overshoots that badly at the cell boundaries; the
	# B-spline stays near it.
	assert_gt(
		worst["bilinear"], 4.0,
		"bilinear must show the jump this change exists to remove -- if it does not, the fixture is wrong"
	)
	assert_lt(
		worst["bspline"], worst["bilinear"] * 0.5,
		"the B-spline must at least halve the worst jump (measured 4.6x on the real map)"
	)


func _grid_gradient(values: PackedFloat32Array, span: int, at: Vector2, sampler: String) -> Vector2:
	# A step small enough to stay inside one cell, so each sample reports
	# that cell's own gradient and a lattice kink shows as a jump BETWEEN
	# samples rather than being averaged away.
	var h := 0.05
	var dx := (
		_grid_sample(values, span, at + Vector2(h, 0.0), sampler)
		- _grid_sample(values, span, at - Vector2(h, 0.0), sampler)
	)
	var dy := (
		_grid_sample(values, span, at + Vector2(0.0, h), sampler)
		- _grid_sample(values, span, at - Vector2(0.0, h), sampler)
	)
	return Vector2(dx, dy) / (2.0 * h)


func _grid_sample(values: PackedFloat32Array, span: int, at: Vector2, sampler: String) -> float:
	if sampler == "bilinear":
		return RiverFlowShader.sample_grid_bilinear(values, span, at)
	return RiverFlowShader.sample_grid_bspline(values, span, at)


func test_the_shader_reconstructs_the_maps_with_the_cubic_filter():
	assert_true(RiverFlowShader.SHADER_CODE.contains("vec4 cubic_weights(float v)"))
	assert_true(RiverFlowShader.SHADER_CODE.contains(
		"vec4 texture_bicubic(sampler2D tex, vec2 uv, float texels)"
	))
	# Four bilinear taps, not sixteen point taps: the standard trick, and
	# what keeps this affordable at three extra samples.
	assert_eq(RiverFlowShader.SHADER_CODE.count("texture(tex, offset."), 4)
	assert_true(RiverFlowShader.SHADER_CODE.contains(
		"mix(texture(flow_across_map, map_uv), texture_bicubic(flow_across_map, map_uv, flow_map_tiles), map_smoothing)"
	))
	# THREE uses: the across map, the width map, and the smear-direction
	# lookup that steers every stroke. Sampling the direction more coarsely
	# than the field it steers puts the lattice back into the strokes --
	# /flowdebug showed the field sweeping cleanly through a bend while the
	# drawn strokes still stepped.
	# Four occurrences: the definition, plus three call sites -- the across
	# map, the width map, and the smear-direction lookup.
	assert_eq(RiverFlowShader.SHADER_CODE.count("texture_bicubic("), 4)
	assert_false(
		RiverFlowShader.SHADER_CODE.contains("texture(flow_across_map, (world_position"),
		"the smear direction must not come through plain bilinear"
	)


func test_the_map_smoothing_dials_back_to_plain_bilinear():
	var material := RiverFlowShader.new().make_material()
	assert_almost_eq(
		float(material.get_shader_parameter("map_smoothing")),
		RiverFlowShader.MAP_SMOOTHING, 1e-9
	)
	assert_between(RiverFlowShader.MAP_SMOOTHING, 0.0, 1.0)


# -- the tear along an obstacle's stagnation line -----------------------------
#
# "There's a hard edge visible around the player ... a straight line which
# moves with him", seen ONLY while standing in water -- which is exactly
# when the player is fed to the shader as a wader -- and separately "also
# behind a few boulders".
#
# The push was sign(lateral) * (sqrt(lateral^2 + R^2) - |lateral|). That
# magnitude is exactly R on the stagnation line (lateral == 0) while the
# sign flips there, so frag_across -- the field every stroke, the
# waterline, the ink line and the shore highlight is a CONTOUR of -- JUMPED
# by 2R across a straight line running through the obstacle along the
# current. In across-fraction units, against a channel that spans 2.0:
#
#   wader   R =  6px -> 2R / 41.6px = 0.29
#   boulder R = 11px -> 2R / 41.6px = 0.53
#
# A quarter to a half of the channel, discontinuously, in a straight line.
# Every contour crossing it is cut.
#
# The fix keeps the same physical profile and the same far field, and only
# replaces the hard sign with a smooth odd factor that vanishes on the
# line: lateral / sqrt(lateral^2 + R^2).


func test_the_obstacle_push_is_continuous_across_the_stagnation_line():
	# lateral == offset.y for this perpendicular, so the sweep walks
	# straight through the stagnation line.
	var perp := Vector2(0.0, 1.0)
	for obstacle in [
		{"r": RiverFlowShader.BOULDER_RADIUS_PX, "reach": RiverFlowShader.BOULDER_REACH_PX, "trail": 0.0},
		{"r": RiverFlowShader.WADER_RADIUS_PX, "reach": RiverFlowShader.WADER_REACH_PX, "trail": RiverFlowShader.WADER_WAKE_TRAIL},
	]:
		var previous := INF
		var worst := 0.0
		for i in range(-40, 41):
			var lateral := float(i) * 0.05
			var shift: float = RiverFlowShader.obstacle_lateral_shift_px(
				Vector2(0.0, lateral), perp, obstacle["r"], obstacle["reach"], obstacle["trail"]
			)
			if previous != INF:
				worst = maxf(worst, absf(shift - previous))
			previous = shift
		# A 0.05px step may not move the push by anything like a pixel. The
		# old sign flip moved it by 2R -- 22px for a boulder -- in one step.
		assert_lt(
			worst, 0.5,
			"radius %f tears by %f px across the stagnation line" % [obstacle["r"], worst]
		)


func test_the_obstacle_push_vanishes_on_the_stagnation_line_itself():
	var perp := Vector2(0.0, 1.0)
	assert_almost_eq(
		RiverFlowShader.obstacle_lateral_shift_px(
			Vector2(0.0, 0.0), perp,
			RiverFlowShader.BOULDER_RADIUS_PX, RiverFlowShader.BOULDER_REACH_PX, 0.0
		),
		0.0, 1e-9,
		"the water on the parting line goes neither way -- it is the parting line"
	)


func test_the_obstacle_push_stays_odd_about_the_stagnation_line():
	# Both banks must part equally; an asymmetric push would steer the
	# whole channel sideways past every rock.
	var perp := Vector2(0.0, 1.0)
	for offset in [1.0, 4.0, 11.0, 22.0]:
		var positive: float = RiverFlowShader.obstacle_lateral_shift_px(
			Vector2(0.0, offset), perp,
			RiverFlowShader.BOULDER_RADIUS_PX, RiverFlowShader.BOULDER_REACH_PX, 0.0
		)
		var negative: float = RiverFlowShader.obstacle_lateral_shift_px(
			Vector2(0.0, -offset), perp,
			RiverFlowShader.BOULDER_RADIUS_PX, RiverFlowShader.BOULDER_REACH_PX, 0.0
		)
		assert_almost_eq(positive, -negative, 1e-6, "asymmetric at %f" % offset)


func test_the_obstacle_push_keeps_its_far_field():
	# Outside the softness band the push is EXACTLY what it always was --
	# not a scaled version of it. Only the core within
	# OBSTACLE_SIDE_SOFTNESS * R of the stagnation line is touched, which
	# is 2.1px for a wader and 3.9px for a boulder. Everything the bulge
	# is actually made of is unchanged.
	var perp := Vector2(0.0, 1.0)
	var radius: float = RiverFlowShader.BOULDER_RADIUS_PX
	var lateral := radius * 2.0
	var shift: float = RiverFlowShader.obstacle_lateral_shift_px(
		Vector2(0.0, lateral), perp, radius, RiverFlowShader.BOULDER_REACH_PX, 0.0
	)
	var envelope := 1.0 - clampf(
		(lateral - radius) / maxf(RiverFlowShader.BOULDER_REACH_PX - radius, 0.001), 0.0, 1.0
	)
	envelope *= envelope
	var magnitude := sqrt(lateral * lateral + radius * radius) - absf(lateral)
	assert_almost_eq(
		shift, magnitude * envelope, 1e-6,
		"beyond the softened core the round-core displacement must be untouched"
	)


## THE BULGE MUST SURVIVE. Removing the tear by scaling the whole push
## down removes the artefact and the feature together -- reported straight
## back: "the straight line is gone, but with it the bulge walking in and
## out of water which was what i wanted to be kept".
##
## The first attempt used lateral / sqrt(lateral^2 + R^2) unclamped, which
## multiplies the push everywhere, not just at the tear: its peak falls
## from R to 0.30R, a factor of 3.3. Clamping that factor to +-1 confines
## the change to the core and leaves the rest of the profile alone.
func test_the_obstacle_push_keeps_a_real_peak_so_the_bulge_survives():
	var perp := Vector2(0.0, 1.0)
	for obstacle in [
		{"r": RiverFlowShader.BOULDER_RADIUS_PX, "reach": RiverFlowShader.BOULDER_REACH_PX},
		{"r": RiverFlowShader.WADER_RADIUS_PX, "reach": RiverFlowShader.WADER_REACH_PX},
	]:
		var radius: float = obstacle["r"]
		var peak := 0.0
		for i in 400:
			var lateral := float(i) * radius * 0.02
			peak = maxf(peak, absf(RiverFlowShader.obstacle_lateral_shift_px(
				Vector2(0.0, lateral), perp, radius, obstacle["reach"], 0.0
			)))
		# The old torn profile peaked at exactly R. Anything under about
		# two thirds of that reads as "the bulge is gone".
		assert_gt(
			peak, radius * 0.65,
			"radius %f peaks at only %f -- the bulge has been scaled away" % [radius, peak]
		)


func test_the_shader_loops_use_the_smooth_side_not_a_sign_flip():
	assert_false(
		RiverFlowShader.SHADER_CODE.contains("float side = lateral >= 0.0 ? 1.0 : -1.0;"),
		"a hard sign flip tears frag_across by 2R along the stagnation line"
	)
	# Clamped, so only the core within OBSTACLE_SIDE_SOFTNESS * R is
	# softened and the bulge beyond it is untouched.
	assert_true(RiverFlowShader.SHADER_CODE.contains(
		"float side = clamp(lateral / (R * obstacle_side_softness), -1.0, 1.0);"
	))
	assert_true(RiverFlowShader.SHADER_CODE.contains(
		"float side = clamp(lateral / (wader_radius_px * obstacle_side_softness), -1.0, 1.0);"
	))


# -- the raw across field, on screen -----------------------------------------
#
# Three separate fixes for the zigzag have now been aimed at the field's
# RECONSTRUCTION and at the obstacle push, each justified by a headless
# measurement, and the artefact has outlived two of them. The measurements
# were sound about what they measured; the open question is whether the
# thing on screen is a property of frag_across at all, or of the stroke
# layer that draws contours of it.
#
# That question is answerable in one screenshot instead of another probe.
# /flowdebug draws the contours of frag_across ALONE -- no noise, no
# advection, no cel shading, no strokes, no lighting -- at full alpha over
# every painted tile. Polygonal bands mean the field or its filter; smooth
# bands mean the stroke layer, and three passes have been looking at the
# wrong half of the shader.
#
# Full alpha deliberately: it also shows the painted band's own outline,
# which is where a clipped wake or halo would reveal itself.


func test_the_debug_view_is_off_by_default():
	assert_eq(RiverFlowShader.DEBUG_ACROSS, 0.0, "a diagnostic must never ship on")
	var material := RiverFlowShader.new().make_material()
	assert_almost_eq(float(material.get_shader_parameter("debug_across")), 0.0, 1e-9)


func test_the_debug_view_toggles_on_the_shared_material():
	var shader := RiverFlowShader.new()
	var material := shader.shared_material()
	shader.set_debug_across(1.0)
	assert_almost_eq(float(material.get_shader_parameter("debug_across")), 1.0, 1e-9)
	shader.set_debug_across(0.0)
	assert_almost_eq(float(material.get_shader_parameter("debug_across")), 0.0, 1e-9)


func test_the_debug_view_draws_contours_of_the_across_field_alone():
	assert_true(RiverFlowShader.SHADER_CODE.contains("uniform float debug_across = 0.0;"))
	assert_true(RiverFlowShader.SHADER_CODE.contains("if (debug_across > 0.5)"))
	# Contours of frag_across ITSELF -- if this read the body or the
	# strokes it would answer a different question than the one asked.
	assert_true(RiverFlowShader.SHADER_CODE.contains(
		"float debug_band = fract(debug_source * debug_across_bands);"
	))
	# Full alpha, so the painted band's own edge shows too.
	assert_true(RiverFlowShader.SHADER_CODE.contains("COLOR = vec4(vec3(debug_edge), 1.0);"))


# -- the guide must dominate the wobble, measured as GRADIENTS --------------
#
# The two screenshots that settled this: the geometry-only field sweeps
# through the bend in long sparse curves; the stroke field over the same
# water is packed with contours so tightly they read as speckle. Dense
# contours mean a steep gradient. In the water, the noise term's gradient
# dominates the channel geometry's, so the field is not monotone, its level
# sets close into cells, and the strokes drawn from it are the cells'
# fragments -- short angular shapes instead of lines following the river.
#
# The numbers, at the width LINE_WOBBLE was "tuned" for (2.56 noise cells):
#
#   across gradient   1 / 2.56          = 0.39 per cell
#   noise gradient    0.6 * 1.5          = 0.90 per cell
#   ratio                                  2.3
#
# The guide never dominated the wobble at ANY width. The amplitude test
# (ACROSS_LINE_SCALE >= LINE_WOBBLE) could not see it, and the coarse
# 80-step folding sweep undercounted it. This test states the actual
# condition and requires a margin.
#
# 1.5 is the steepest slope of smoothstep-faded value noise per cell.
const VALUE_NOISE_MAX_SLOPE := 1.5
## 0.7, RAISED from 0.5 for "slightly increase wobble so it looks more
## watery". LINE_WOBBLE 0.17 puts the ratio at 0.65. The bar was 0.5 out
## of caution about the bend and the obstacle pushes stacking on top; with
## the bend now in the guide (fold margin 0.35) the wobble is the only
## term that can fold the field, and tools/probe_monotone.gd walking the
## real field at 0.17 is the measurement that admits it -- see the commit
## that set it for the numbers. Above about 0.8 the cells come back.
const MAX_WOBBLE_GRADIENT_RATIO := 0.7


## The noise term's steepest gradient as a fraction of the across ramp's,
## at a channel this many noise cells wide. Under 1 is monotone; the margin
## is what keeps it monotone through the bend warp and the obstacle pushes
## on top.
func _wobble_gradient_ratio(half_width_cells: float) -> float:
	var across_gradient := RiverFlowShader.ACROSS_LINE_SCALE / half_width_cells
	var noise_gradient := (
		RiverFlowShader.LINE_WOBBLE
		* RiverFlowShader.wobble_scale_for(half_width_cells)
		* VALUE_NOISE_MAX_SLOPE
	)
	return noise_gradient / across_gradient


func test_the_wobble_gradient_stays_well_under_the_across_gradient_at_every_width():
	for half_tiles in [1.0, 1.6, 2.0, 2.6, 3.5, 4.5, 6.0, 7.5]:
		var cells: float = half_tiles * RiverFlowShader.TILE_PX * RiverFlowShader.NOISE_SCALE
		var ratio := _wobble_gradient_ratio(cells)
		assert_lte(
			ratio, MAX_WOBBLE_GRADIENT_RATIO,
			"at a %.1f-tile half width the wobble's gradient is %.2fx the guide's -- cells" % [
				half_tiles, ratio
			]
		)


# -- the eddies migrate downstream --------------------------------------------
#
# "Make the water move with the flow so it looks like a flowing stream."
# With the whirl moved into the guide, a bed-anchored bend left the lines
# standing still: the only temporal motion was the small wobble texture
# advecting over them. Real boils shed from bedforms and migrate downstream
# more slowly than the surface -- Jackson 1976 has them quasi-stationary,
# not fixed. So the eddy field now drifts at BEND_DRIFT_FRACTION of the
# surface's own drift.
#
# This is a TRANSLATION of the bend field. A translation cannot change the
# fold Jacobian, so the margin holds at every offset -- pinned below at a
# real drifted offset rather than trusted from the algebra.


func test_the_bend_drifts_downstream_with_the_current():
	assert_between(RiverFlowShader.BEND_DRIFT_FRACTION, 0.1, 1.0)
	assert_almost_eq(
		RiverFlowShader.bend_drift_cells(0.0, 30.0), 0.0, 1e-9,
		"still water: the eddies hold station"
	)
	var moved: float = RiverFlowShader.bend_drift_cells(1.0, 10.0)
	assert_gt(moved, 0.0)
	assert_almost_eq(
		moved,
		RiverFlowShader.surface_cells(RiverFlowShader.DRIFT_SPEED_M_S, 10.0) * RiverFlowShader.BEND_DRIFT_FRACTION,
		1e-9
	)
	assert_almost_eq(
		moved, RiverFlowShader.surface_cells(RiverFlowShader.DRIFT_SPEED_M_S, 10.0), 1e-9,
		"the eddies travel WITH the lines -- both at the one shared drift speed"
	)
	assert_almost_eq(
		RiverFlowShader.bend_drift_cells(2.0, 10.0), moved, 1e-9,
		"a brisk reach migrates its eddies at the same shared speed"
	)


func test_the_eddy_field_itself_moves_in_flowing_water_and_not_in_still():
	# The wobble's own advection is excluded here on purpose: this reads the
	# bend at its drifted coordinate directly, so it can only pass if the
	# EDDIES moved, not merely the texture drawn over them.
	var dir := Vector2(1, 0)
	var still_change := 0.0
	var flow_change := 0.0
	for i in 40:
		var x := 2.0 + float(i) * 0.9
		var y := 3.3
		still_change += absf(_drifted_bend(x, y, dir, 6.0, 0.0) - _drifted_bend(x, y, dir, 0.0, 0.0))
		flow_change += absf(_drifted_bend(x, y, dir, 6.0, 1.0) - _drifted_bend(x, y, dir, 0.0, 1.0))
	assert_almost_eq(still_change, 0.0, 1e-9, "still water: eddies hold station")
	assert_gt(flow_change, 0.5, "flowing water: the eddies must have migrated (moved %.4f)" % flow_change)


func _drifted_bend(x: float, y: float, dir: Vector2, seconds: float, speed_mps: float) -> float:
	var shift: float = RiverFlowShader.bend_drift_cells(speed_mps, seconds)
	return RiverFlowShader.bend_displacement(
		(x - dir.x * shift) * RiverFlowShader.EDDY_SCALE,
		(y - dir.y * shift) * RiverFlowShader.EDDY_SCALE
	)


func test_the_fold_margin_survives_the_eddy_drift():
	# An arbitrary later moment in flowing water. Shifting `along` by the
	# drift IS the translation the shader applies; the derivative across
	# must still clear the same margin as the undrifted sweep.
	var offset: float = RiverFlowShader.bend_drift_cells(1.0, 37.0)
	assert_gt(offset, 1.0, "the offset must be a real distance, or this tests nothing")
	var step := 0.002
	var worst := INF
	for i in range(60):
		var along := float(i) * 0.31 - offset
		for j in range(1, 200):
			var across := float(j) * 0.05
			var derivative := (
				RiverFlowShader.warped_across(along, across + step)
				- RiverFlowShader.warped_across(along, across - step)
			) / (2.0 * step)
			worst = minf(worst, derivative)
	assert_gt(worst, MIN_WARP_MARGIN, "drifted by %.2f cells the warp pinches to %.4f" % [offset, worst])


func test_the_shader_drifts_the_eddy_sample_coordinate():
	assert_true(RiverFlowShader.SHADER_CODE.contains(
		"float bend_drift = mod(TIME * surface_px_per_s(drift_speed_m_s, moving) * noise_scale * bend_drift_fraction * eddy_scale, drift_period);"
	))
	assert_true(RiverFlowShader.SHADER_CODE.contains(
		"vec2 eddy_p = p * eddy_scale - flow_dir * bend_drift;"
	))
	var material := RiverFlowShader.new().make_material()
	assert_almost_eq(
		float(material.get_shader_parameter("bend_drift_fraction")),
		RiverFlowShader.BEND_DRIFT_FRACTION, 1e-9
	)


## "Slightly increase wobble so it looks more watery." A floor, so the
## next fold scare does not quietly tune the water flat again.
func test_the_wobble_is_watery_enough():
	assert_gte(RiverFlowShader.LINE_WOBBLE, 0.17)


# -- the stream must visibly FLOW FORWARD ------------------------------------
#
# "The lines are not flowing forward." And they could not have: the strokes
# are contours of `across`, which are lines PARALLEL to the flow, so
# translating the field along the flow leaves a line looking exactly where
# it was. Forward motion can only read through things ON the lines -- the
# brightness pulse streaming along them, and kinks travelling. So the
# question is not whether the field moves but whether what moves is fast
# and visible enough:
#
#   DRIFT_PX_PER_MPS 9, reach 0.5 m/s:   4.5 world px/s = 18 screen px/s,
#                                         3.5 s to cross a single tile.
#   pulse mix(0.55, 1.0):                 a 45% modulation on a thin stroke.
#
# Neither reads as a flowing stream. This pins a floor on the drift rate at
# a typical reach and a ceiling on the pulse floor, in the units a player
# actually sees.


## World px per second the pattern streams downstream at `speed_mps` --
## the whole visible speed, drift plus the drag's (now minor) translation.
func _stream_world_px_per_s(speed_mps: float) -> float:
	return RiverFlowShader.surface_px_per_s(speed_mps)


func test_a_typical_reach_streams_fast_enough_to_read_as_flowing():
	# 8 world px/s is 32 screen px/s at the game's 4x tile zoom: a pulse
	# crosses a tile in two seconds. Below that the water reads as still
	# with a shimmer on it.
	assert_gte(
		_stream_world_px_per_s(0.5), 8.0,
		"a 0.5 m/s reach streams at only %.1f world px/s" % _stream_world_px_per_s(0.5)
	)
	# And the pin the drift rate already had, kept: past 20 the water is a
	# conveyor belt.
	assert_lte(RiverFlowShader.DRIFT_PX_PER_MPS, 20.0)


func test_the_pulse_is_deep_enough_to_see_streaming():
	assert_lte(RiverFlowShader.PULSE_FLOOR, 0.4, "a shallow pulse is a shimmer, not a stream")
	assert_gt(RiverFlowShader.PULSE_FLOOR, 0.0, "a dim segment must still be a stroke")
	var material := RiverFlowShader.new().make_material()
	assert_almost_eq(
		float(material.get_shader_parameter("pulse_floor")), RiverFlowShader.PULSE_FLOOR, 1e-9
	)


func test_the_whirls_travel_with_the_surface():
	# With the wobble small, the eddies are most of what there is ON a line
	# to see moving -- they ARE the lines' shape. 0.6 of the drift alone was
	# tried first and reported as "a wobble stays in place", then, once the
	# ripples were carried at the water's visible speed, "the lines should
	# move at the same speed". So they do: the whole fraction of the visible
	# surface speed, the same speed the ring is carried at.
	assert_almost_eq(RiverFlowShader.BEND_DRIFT_FRACTION, 1.0, 1e-9)


# -- everything on the surface rides ONE visible water speed ------------------
#
# "Can you make the river ripples move downstream at water speed?", then
# "eddy swirls also don't move downstream.. a wobble stays in place instead
# of flowing with the river", then "the lines should move at the same
# speed". One cause. The surface the player SEES streaming is moved by TWO
# terms: the two-phase drag, which translates the field ADVECT_STRENGTH
# cells every 1/ADVECT_RATE seconds no matter how fast the reach runs, plus
# the linear drift keyed to the real current. At a typical 0.5 m/s reach the
# drag alone is ~19.8 world px/s and the drift 10 -- and the ripple centre
# and the eddy field were carried by the DRIFT ONLY (the eddies at 0.6 of
# it), so a wake moved at a third of the water and the whirls at a fifth.
# Both read as standing still while the pulses streamed past.
#
# So there is now ONE function, surface_px_per_s, that is the water's
# visible downstream speed, mirrored on both sides, and every consumer that
# has to "move with the water" rides it at the same rate.


func test_the_visible_surface_speed_is_the_drag_plus_the_drift():
	var drag_px_per_s: float = (
		RiverFlowShader.ADVECT_STRENGTH * RiverFlowShader.ADVECT_RATE / RiverFlowShader.NOISE_SCALE
	)
	assert_almost_eq(
		RiverFlowShader.surface_px_per_s(0.5),
		drag_px_per_s + RiverFlowShader.DRIFT_PX_PER_MPS * 0.5, 1e-6,
		"the visible speed is the phase drag's translation plus the drift"
	)
	assert_gt(
		RiverFlowShader.surface_px_per_s(1.0), RiverFlowShader.surface_px_per_s(0.5),
		"a faster reach still streams faster"
	)
	# The drift is MOST of the visible speed: it is the coherent translation
	# everything can ride together. (It was under half of it when the drag
	# was 7.2 cells, which is why wakes and whirls first read as standing
	# still -- and why, with the drag's dissolve, the wobble still did.)
	assert_gte(
		RiverFlowShader.DRIFT_PX_PER_MPS * 0.5, RiverFlowShader.surface_px_per_s(0.5) * (2.0 / 3.0),
		"the drift must carry at least two thirds of the visible speed"
	)


func test_still_water_has_no_surface_speed_at_all():
	# The shader's still path breathes the field SIDEWAYS and never drifts
	# (test_still_water_neither_advects_nor_drifts); a lake's wake and eddies
	# must hold station exactly like its strokes do -- gated by the same
	# STILL_FLOW_M_S step, not faded, so the two sides cannot disagree.
	assert_almost_eq(RiverFlowShader.surface_px_per_s(0.0), 0.0, 1e-9)
	assert_almost_eq(
		RiverFlowShader.surface_px_per_s(RiverFlowShader.STILL_FLOW_M_S * 0.5), 0.0, 1e-9,
		"below the still gate the surface holds, exactly as the shader's own gate does"
	)
	assert_gt(RiverFlowShader.surface_px_per_s(RiverFlowShader.STILL_FLOW_M_S), 0.0)
	assert_almost_eq(RiverFlowShader.surface_cells(0.0, 30.0), 0.0, 1e-9)
	assert_almost_eq(
		RiverFlowShader.surface_cells(0.7, 3.0),
		RiverFlowShader.surface_px_per_s(0.7) * 3.0 * RiverFlowShader.NOISE_SCALE, 1e-9,
		"surface_cells is the same speed in the noise field's own units"
	)


func test_the_shader_streams_every_consumer_from_the_same_surface_speed():
	var code: String = RiverFlowShader.SHADER_CODE
	assert_true(
		code.contains("float surface_px_per_s(float speed_mps, float moving) {"),
		"the shader owns the one visible-speed function"
	)
	assert_true(
		code.contains("return moving * (advect_strength * advect_rate / noise_scale + drift_px_per_mps * speed_mps);"),
		"drag translation plus drift, gated by the same still step as the strokes"
	)
	assert_true(
		code.contains("vec2 surface_velocity = flow_dir * surface_px_per_s(speed_mps, moving);"),
		"computed once per fragment, next to the field's own drift"
	)
	assert_true(
		code.contains("vec2 center = disturbance_pos[i] + surface_velocity * age;"),
		"the ring's centre is carried by the surface velocity"
	)
	assert_false(
		code.contains("flow_dir * (drift_px_per_mps * speed_mps * age)"),
		"the ring must not be carried by the drift alone any more"
	)
	assert_true(
		code.contains("float bend_drift = mod(TIME * surface_px_per_s(drift_speed_m_s, moving) * noise_scale * bend_drift_fraction * eddy_scale, drift_period);"),
		"the eddies migrate at the one shared drift speed, through the same visible-speed function -- the ring, bounded by its lifetime, keeps the local speed"
	)


func test_a_wake_in_a_typical_reach_is_carried_clear_of_where_it_was_made():
	# The ring lives RIPPLE_LIFETIME seconds and is carried at the water's
	# visible speed the whole time. Over that life in a 0.5 m/s reach it
	# must clearly leave where it was made -- more than a tile and a half --
	# but calmly: carried four tiles in 2.2 s it "just seemed to drift and
	# fade faster", so the ceiling is three tiles.
	var age: float = RiverFlowShader.RIPPLE_LIFETIME
	var carried := RiverFlowShader.ripple_center(Vector2.ZERO, Vector2(1.0, 0.0), 0.5, age)
	assert_almost_eq(carried.x, RiverFlowShader.surface_px_per_s(0.5) * age, 1e-3)
	assert_between(
		carried.x, float(TerrainRenderer.TILE_SIZE) * 1.5, float(TerrainRenderer.TILE_SIZE) * 3.0,
		"a wake in a typical reach is carried %.1f world px in its lifetime" % carried.x
	)
	# And it lingers: a ring that is gone in two seconds reads as a flicker
	# in a calm picture.
	assert_gte(RiverFlowShader.RIPPLE_LIFETIME, 3.0)
	assert_almost_eq(carried.y, 0.0, 1e-9, "purely along the flow, never across it")


func test_the_lines_and_the_ripples_move_at_the_same_speed():
	# "The lines should move at the same speed." The lines' shape is the
	# eddy-bent guide, so the eddy field's migration IS the lines' motion,
	# and it must match the ring's carry exactly -- both are the water.
	var eddy_world_px_per_s: float = (
		RiverFlowShader.bend_drift_cells(0.5, 1.0) / RiverFlowShader.NOISE_SCALE
	)
	var ring_world_px_per_s: float = (
		RiverFlowShader.ripple_center(Vector2.ZERO, Vector2(1.0, 0.0), 0.5, 1.0).x
	)
	assert_almost_eq(eddy_world_px_per_s, ring_world_px_per_s, 1e-6)
	# And the same legibility floor the pulse has to clear
	# (test_a_typical_reach_streams_fast_enough_to_read_as_flowing): 8 world
	# px/s is a tile every two seconds. At 0.6 of the drift alone the whirls
	# in a 0.5 m/s reach migrated at 6 -- "a wobble stays in place".
	assert_gte(
		eddy_world_px_per_s, 8.0,
		"the whirls in a 0.5 m/s reach migrate at only %.1f world px/s" % eddy_world_px_per_s
	)


# -- the ring inks softer -----------------------------------------------------
#
# "Can you make the ripples a little less pronounced so they appear smoother
# a bit slower and more natural." Slower and broader is the shared packet's
# business (test_water_shader.gd); LESS PRONOUNCED is this surface's: the
# ring inks in its own right through smoothstep(RIPPLE_CREST_MIN,
# RIPPLE_CREST_FULL, crest), and with FULL at half the packet's peak a ring
# printed at full stroke strength for most of its life -- as dark as a
# current line, a stamp rather than a disturbance. FULL now sits near the
# peak, so only a fresh crest prints at full strength and the ring
# graduates down through its life instead of switching off; MIN rises a
# little so the faint tail stays clean, but stays under the crest still
# reachable three quarters through the life (the "mini ripple" lesson).
# ripple_ink mirrors the shader's own smoothstep so the graduation is a
# tested curve, not an eyeballed pair of literals.


func test_the_ring_inks_at_full_strength_only_while_fresh():
	var peak := _peak_packet_amplitude()
	assert_gte(
		RiverFlowShader.RIPPLE_CREST_FULL, peak * 0.7,
		"full ink reachable by more than a fresh crest is a stamp, not a ripple"
	)
	assert_almost_eq(
		RiverFlowShader.ripple_ink(peak), RiverFlowShader.RIPPLE_INK_MAX, 1e-6,
		"a fresh crest prints at the ring's own ceiling"
	)


func test_the_ring_graduates_through_its_life_instead_of_switching_off():
	# Measured as a fraction of the ring's own ceiling (RIPPLE_INK_MAX), so
	# the graduation is pinned independently of how light the ring prints.
	var half_life_ink: float = (
		RiverFlowShader.ripple_ink(_peak_amplitude_at_life_fraction(0.5)) / RiverFlowShader.RIPPLE_INK_MAX
	)
	assert_between(
		half_life_ink, 0.25, 0.6,
		"half way through its life the ring should be plainly there but plainly softer (%.2f)" % half_life_ink
	)
	var late_ink: float = (
		RiverFlowShader.ripple_ink(_peak_amplitude_at_life_fraction(0.75)) / RiverFlowShader.RIPPLE_INK_MAX
	)
	assert_gt(late_ink, 0.0, "the ring must still draw three quarters through its life")
	assert_lt(late_ink, half_life_ink, "and fainter than it did at half life")
	assert_almost_eq(RiverFlowShader.ripple_ink(0.0), 0.0, 1e-9, "flat water inks nothing")
	assert_almost_eq(RiverFlowShader.ripple_ink(-1.0), 0.0, 1e-9, "troughs ink nothing")


func test_the_ink_curve_is_the_shader_s_own_smoothstep():
	assert_true(
		RiverFlowShader.SHADER_CODE.contains("* smoothstep(ripple_crest_min, ripple_crest_full, ripple_envelope_sum)")
	)
	var mid: float = (RiverFlowShader.RIPPLE_CREST_MIN + RiverFlowShader.RIPPLE_CREST_FULL) * 0.5
	assert_almost_eq(
		RiverFlowShader.ripple_ink(mid), 0.5 * RiverFlowShader.RIPPLE_INK_MAX, 1e-6,
		"smoothstep's midpoint is half the ceiling"
	)


# -- a thin, light ring ------------------------------------------------------
#
# "Can you make the ripples stroke width smaller and a bit more transparent?"
# The ring's ink used to be smoothstep(MIN, FULL, crest amplitude), so its
# WIDTH was however much of the crest's sine cleared the thresholds -- about
# three world px, three times a current line -- and it changed with the
# ring's age. Now the packet is split into the pure sine (the RING: where
# on the crest a pixel sits) and its ENVELOPE (how strong the wake is here,
# now): width comes from a threshold on the sine alone, so it is one number
# in px independent of age, and the envelope drives only the strength, with
# a ceiling (RIPPLE_INK_MAX) below a full stroke so the ring prints lighter
# than a current line.


func test_the_ring_is_no_wider_than_a_current_line():
	var ring := RiverFlowShader.ripple_ring_width_px()
	var line := RiverFlowShader.line_width_px()
	assert_lte(ring, line, "the ring is %.2f px wide against a %.2f px line" % [ring, line])
	# But still at least a snapped pixel and a half, or it drops out
	# between pixel_snap cells.
	assert_gte(ring, RiverFlowShader.PIXEL_SNAP * 1.5)
	assert_between(RiverFlowShader.RIPPLE_RING_EDGE, 0.5, 0.97)


func test_the_ring_prints_lighter_than_a_current_line():
	assert_between(RiverFlowShader.RIPPLE_INK_MAX, 0.4, 0.75)
	assert_almost_eq(RiverFlowShader.ripple_ink(_peak_packet_amplitude()), RiverFlowShader.RIPPLE_INK_MAX, 1e-6)


func test_the_envelope_bounds_the_packet_and_meets_it_at_the_crest():
	var best_ratio := 0.0
	for age_step in 12:
		var age := 0.2 + float(age_step) * 0.2
		for dist_step in 400:
			var dist := float(dist_step) * 0.25
			var envelope := RiverFlowShader.ripple_envelope(dist, age)
			var packet := RiverFlowShader.ripple_packet(dist, age)
			assert_gte(envelope + 1e-9, absf(packet), "the envelope must never sit under the packet")
			if envelope > 1e-6:
				best_ratio = maxf(best_ratio, packet / envelope)
	assert_gt(best_ratio, 0.99, "at the crest the packet IS its envelope (ratio %.3f)" % best_ratio)
	assert_eq(RiverFlowShader.ripple_envelope(10.0, RiverFlowShader.RIPPLE_LIFETIME + 0.1), 0.0)


func test_the_shader_inks_the_ring_from_the_sine_and_its_strength_from_the_envelope():
	var code: String = RiverFlowShader.SHADER_CODE
	assert_true(code.contains("float movement_ripples(vec2 pos, vec2 surface_velocity, out float envelope) {"))
	assert_true(code.contains("float ripple = movement_ripples(wp, surface_velocity, ripple_envelope_sum);"))
	assert_true(code.contains("float ripple_crest = ripple / max(ripple_envelope_sum, 1e-4);"))
	assert_true(code.contains(
		"float ripple_ink = smoothstep(ripple_ring_edge, 1.0, ripple_crest) * smoothstep(ripple_crest_min, ripple_crest_full, ripple_envelope_sum) * ripple_ink_max;"
	))
	var material := RiverFlowShader.new().make_material()
	assert_almost_eq(float(material.get_shader_parameter("ripple_ring_edge")), RiverFlowShader.RIPPLE_RING_EDGE, 1e-9)
	assert_almost_eq(float(material.get_shader_parameter("ripple_ink_max")), RiverFlowShader.RIPPLE_INK_MAX, 1e-9)


# -- every boulder is a rock of its own size ---------------------------------
#
# "The rock should as entity have a mass": the first thing that means on
# the water is that a rock has a SIZE of its own. Every flow boulder now
# carries its own radius in world px, from its real diameter (the same
# StoneSize roll that draws it), and the push reach, the dry eyot, the
# shoal, the foam and the wake all scale with it. BOULDER_RADIUS_PX stays
# as the REFERENCE radius the generic obstacle tests use; it is no longer
# what the shader draws every rock with.


func test_each_boulder_has_its_own_radius_in_the_shader():
	var code: String = RiverFlowShader.SHADER_CODE
	assert_true(code.contains("uniform float boulder_radius[24];"), "one radius per slot")
	assert_true(code.contains("float R = boulder_radius[b];"))
	assert_true(code.contains("float reach = R * boulder_reach_ratio;"), "the reach scales with the rock")
	assert_false(code.contains("uniform float boulder_radius_px"), "the one-size-fits-all radius is gone")
	var material := RiverFlowShader.new().make_material()
	assert_almost_eq(
		float(material.get_shader_parameter("boulder_reach_ratio")), RiverFlowShader.BOULDER_REACH_RATIO, 1e-9
	)
	var radii: PackedFloat32Array = material.get_shader_parameter("boulder_radius")
	assert_eq(radii.size(), 24, "the material starts with a full, empty radius array")


func test_a_rock_s_radius_on_the_water_comes_from_its_real_size():
	var cobble_edge := RiverFlowShader.boulder_radius_px_for(StoneSize.COBBLE_MAX_CM)
	var metre := RiverFlowShader.boulder_radius_px_for(100.0)
	var largest := RiverFlowShader.boulder_radius_px_for(StoneSize.LARGEST_CM)
	assert_lt(cobble_edge, metre)
	assert_lt(metre, largest, "a bigger rock parts more water")
	# Half the drawn height: the water parts around the rock the player sees.
	assert_almost_eq(metre, StoneSize.world_height_px(100.0) * 0.5, 1e-6)
	# But never below a floor: the smallest boulder still visibly parts the water.
	assert_gte(cobble_edge, RiverFlowShader.MIN_BOULDER_RADIUS_PX)
	assert_eq(RiverFlowShader.boulder_radius_px_for(1.0), RiverFlowShader.MIN_BOULDER_RADIUS_PX)
	assert_between(RiverFlowShader.MIN_BOULDER_RADIUS_PX, 4.0, 8.0)


func test_the_reference_reach_is_the_ratio_times_the_reference_radius():
	assert_almost_eq(
		RiverFlowShader.BOULDER_REACH_PX,
		RiverFlowShader.BOULDER_RADIUS_PX * RiverFlowShader.BOULDER_REACH_RATIO, 1e-6
	)
	assert_almost_eq(
		RiverFlowShader.boulder_reach_px_for(20.0), 20.0 * RiverFlowShader.BOULDER_REACH_RATIO, 1e-9
	)


func test_the_push_and_the_eyot_take_the_rock_s_own_radius():
	var big := 20.0
	var small := 8.0
	var perp := Vector2(0, 1)
	# At the same offset just outside the small rock, the big rock -- whose
	# face is further out -- displaces more.
	var offset := Vector2(0.0, small + 1.0)
	assert_gt(
		RiverFlowShader.boulder_across_push(offset, perp, big),
		RiverFlowShader.boulder_across_push(offset, perp, small)
	)
	assert_almost_eq(
		RiverFlowShader.boulder_across_push(offset, perp), RiverFlowShader.boulder_across_push(offset, perp, RiverFlowShader.BOULDER_RADIUS_PX), 1e-9,
		"without a radius the mirror means the reference rock"
	)
	assert_almost_eq(RiverFlowShader.eyot_dry_factor(big * 0.5, big), 0.0, 1e-9, "under a big rock it is dry")
	assert_almost_eq(RiverFlowShader.eyot_dry_factor(big * 0.5, small), 1.0, 1e-9, "beside a small one it is wet")


# -- foam in front, whirls behind ----------------------------------------------
#
# "...and produce foam in front and whirls behind it." Both are what a
# real current does to a rock it cannot move. FOAM: the flow stagnates on
# the upstream face and, fast enough, the pile-up breaks white -- so the
# term is confined to the upstream sector, to a window just off the rock's
# face, driven by the reach's speed, and broken up by the channel's own
# advected field so it streams instead of sitting as a pale cap. WAKE: a
# rock sheds eddies, so the standing-turbulence bend the guide lines
# already whirl with is amplified in a lobe behind the rock -- downstream
# only, a couple of radii wide, dying out over several radii -- gated by
# the current. Both scale with the rock's own radius.


func test_foam_sits_on_the_upstream_face_and_nowhere_else():
	var R := 12.0
	var flow := Vector2(0.0, 1.0)  # south
	var face := RiverFlowShader.boulder_foam(-flow * R, flow, R)
	assert_gt(face, 0.9, "the stagnation point at the rock's face foams hardest (%.2f)" % face)
	assert_almost_eq(RiverFlowShader.boulder_foam(flow * R, flow, R), 0.0, 1e-9, "nothing behind the rock")
	assert_almost_eq(RiverFlowShader.boulder_foam(flow * R * 1.3, flow, R), 0.0, 1e-9)
	var shoulder := RiverFlowShader.boulder_foam(Vector2(R, 0.0), flow, R)
	assert_almost_eq(shoulder, 0.0, 1e-9, "the shoulders, where the water is fastest, do not foam")
	var quarter := RiverFlowShader.boulder_foam(Vector2(R, -R).normalized() * R, flow, R)
	assert_between(quarter, 0.1, 0.8, "off the stagnation line the foam thins (%.2f)" % quarter)
	var far := -flow * (R + R * RiverFlowShader.BOULDER_FOAM_REACH_RATIO * 1.5)
	assert_almost_eq(RiverFlowShader.boulder_foam(far, flow, R), 0.0, 1e-9, "the foam does not reach upstream forever")
	assert_almost_eq(RiverFlowShader.boulder_foam(-flow * R * 0.3, flow, R), 0.0, 1e-9, "under the rock is rock, not foam")
	for i in 40:
		var offset := Vector2(float(i % 8) - 3.5, float(i / 8) - 2.5) * R * 0.6
		assert_between(RiverFlowShader.boulder_foam(offset, flow, R), 0.0, 1.0)


func test_foam_needs_a_real_current():
	assert_almost_eq(RiverFlowShader.foam_drive(0.0), 0.0, 1e-9, "still water does not foam")
	assert_almost_eq(RiverFlowShader.foam_drive(RiverFlowShader.FOAM_MIN_M_S), 0.0, 1e-9)
	assert_gt(RiverFlowShader.foam_drive(0.6), 0.0, "an ordinary reach foams a little at a rock")
	assert_almost_eq(RiverFlowShader.foam_drive(RiverFlowShader.FOAM_FULL_M_S), 1.0, 1e-9)
	assert_almost_eq(RiverFlowShader.foam_drive(3.0), 1.0, 1e-9)
	assert_lt(RiverFlowShader.FOAM_MIN_M_S, RiverFlowShader.FOAM_FULL_M_S)
	assert_gte(RiverFlowShader.FOAM_MIN_M_S, RiverFlowShader.STILL_FLOW_M_S)


func test_foam_scales_with_the_rock():
	var flow := Vector2(1.0, 0.0)
	var offset := -flow * 22.0
	assert_gt(
		RiverFlowShader.boulder_foam(offset, flow, 20.0), RiverFlowShader.boulder_foam(offset, flow, 8.0),
		"a bigger rock's face is further out, and so is its foam"
	)


func test_the_wake_lies_behind_the_rock_and_dies_out_downstream():
	var R := 12.0
	var flow := Vector2(0.0, 1.0)
	assert_almost_eq(RiverFlowShader.boulder_wake(-flow * R * 2.0, flow, R), 0.0, 1e-9, "no wake upstream")
	var close := RiverFlowShader.boulder_wake(flow * R * 1.5, flow, R)
	assert_gt(close, 0.9, "just behind the rock the wake is full (%.2f)" % close)
	var mid := RiverFlowShader.boulder_wake(flow * R * RiverFlowShader.BOULDER_WAKE_LENGTH_RATIO * 0.5, flow, R)
	assert_between(mid, 0.2, 0.95, "half way down the wake it is fading (%.2f)" % mid)
	var end := flow * R * RiverFlowShader.BOULDER_WAKE_LENGTH_RATIO
	assert_almost_eq(RiverFlowShader.boulder_wake(end, flow, R), 0.0, 1e-9, "and gone by its length")
	var beside := RiverFlowShader.boulder_wake(flow * R * 2.0 + Vector2(R * RiverFlowShader.BOULDER_WAKE_WIDTH_RATIO * 1.2, 0.0), flow, R)
	assert_almost_eq(beside, 0.0, 1e-9, "a couple of radii to the side the water runs clear")
	assert_between(RiverFlowShader.BOULDER_WAKE_LENGTH_RATIO, 3.0, 10.0)
	assert_between(RiverFlowShader.BOULDER_WAKE_WIDTH_RATIO, 1.0, 3.0)
	for i in 60:
		var offset := Vector2(float(i % 10) - 4.5, float(i / 10) - 1.5) * R
		assert_between(RiverFlowShader.boulder_wake(offset, flow, R), 0.0, 1.0)


func test_the_wake_whirls_harder_but_never_folds_the_surface():
	assert_between(RiverFlowShader.BOULDER_WAKE_GAIN, 0.1, 0.5, "a real amplification, inside what the fold margin allows")
	assert_between(RiverFlowShader.WAKE_FOAM, 0.2, 0.6, "the wake carries a thinner trail of the face's foam")
	# The same no-fold sweep the bend itself has to pass, at the wake's
	# gained strength: the whirls may be wilder behind a rock, the surface
	# may never fold over itself there.
	var step := 0.002
	var worst := INF
	for i in range(120):
		var along := float(i) * 0.31
		for j in range(1, 400):
			var across := float(j) * 0.05
			var derivative := (
				RiverFlowShader.warped_across_in_wake(along, across + step)
				- RiverFlowShader.warped_across_in_wake(along, across - step)
			) / (2.0 * step)
			worst = minf(worst, derivative)
	assert_gt(worst, MIN_WARP_MARGIN, "in a wake the warp pinches to %.4f" % worst)


func test_the_shader_foams_the_face_and_whirls_the_wake():
	var code: String = RiverFlowShader.SHADER_CODE
	assert_true(code.contains("float along = dot(to_frag, flow_dir);"), "the boulder loop knows up- from downstream")
	assert_true(code.contains("boulder_foam = max(boulder_foam, nose * foam_window);"))
	assert_true(code.contains("boulder_wake = max(boulder_wake, wake);"))
	assert_true(code.contains("float foam_drive = smoothstep(foam_min_m_s, foam_full_m_s, speed_mps) * moving;"))
	assert_true(code.contains("* turbulence_strength * shear * (1.0 + boulder_wake * boulder_wake_gain * moving);"), "the wake amplifies the bend")
	assert_true(code.contains("float foam = (boulder_foam + boulder_wake * wake_foam) * foam_drive * smoothstep(0.3, 0.7, n);"), "face foam plus wake streaks, broken up by the advected field")
	assert_true(code.contains("body = mix(body, foam_color, foam * foam_alpha);"))
	var material := RiverFlowShader.new().make_material()
	for pair in [
		["foam_min_m_s", RiverFlowShader.FOAM_MIN_M_S], ["foam_full_m_s", RiverFlowShader.FOAM_FULL_M_S],
		["boulder_foam_reach_ratio", RiverFlowShader.BOULDER_FOAM_REACH_RATIO],
		["foam_alpha", RiverFlowShader.FOAM_ALPHA],
		["boulder_wake_length_ratio", RiverFlowShader.BOULDER_WAKE_LENGTH_RATIO],
		["boulder_wake_width_ratio", RiverFlowShader.BOULDER_WAKE_WIDTH_RATIO],
		["boulder_wake_gain", RiverFlowShader.BOULDER_WAKE_GAIN],
		["wake_foam", RiverFlowShader.WAKE_FOAM],
	]:
		assert_almost_eq(float(material.get_shader_parameter(pair[0])), pair[1], 1e-9, pair[0])
	assert_eq(material.get_shader_parameter("foam_color"), RiverFlowShader.FOAM_COLOR)


# -- bounded drift: the far-time shredding ------------------------------------
#
# Found live at the Loire near Nantes after ~25 minutes of play: every
# bend of a fast reach dissolved into per-pixel white speckle at night,
# while the straight reach beside it kept its long moonlit lines. Both
# the downstream drift and the eddy drift translate a sample coordinate by
# flow_dir * (TIME * speed) -- and flow_dir is reconstructed CONTINUOUSLY
# between texels, so on a bend two neighbouring fragments differ by a
# fraction of a degree. A fraction of a degree times thousands of noise
# cells is many cells: the same "angle times distance" trap the seam test
# guards, re-entered through TIME. Measured on the real GPU at the Loire
# confluence: 0.056 of the water pixels isolated specks at ~2000 s against
# 0.003 fresh; 0.015 with the drift zeroed, 0.030 with the eddy drift
# zeroed. Both translations now wrap modulo a period the noise TILES at.

## Neither translation ever grows past the noise period, however long the
## session runs -- the drift in smear cells, the eddy drift in eddy units.
func test_the_drift_translations_are_bounded_by_the_noise_period():
	assert_lt(
		RiverFlowShader.drift_cells(2.2, 3600.0), RiverFlowShader.DRIFT_PERIOD_CELLS,
		"an hour on a fast reach must not translate the smear further than one period"
	)
	assert_lt(
		RiverFlowShader.bend_drift_cells(2.2, 3600.0) * RiverFlowShader.EDDY_SCALE,
		RiverFlowShader.DRIFT_PERIOD_CELLS,
		"an hour on a fast reach must not translate the eddies further than one period"
	)
	# ...and the wraps are invisible only because the translated noise
	# tiles at exactly that period, in both octaves.
	var period := RiverFlowShader.DRIFT_PERIOD_CELLS
	for i in range(30):
		var x := 3.7 + float(i) * 1.13
		var y := 11.2 + float(i) * 0.71
		assert_almost_eq(
			RiverFlowShader.value_noise_tiled(x + period, y, period),
			RiverFlowShader.value_noise_tiled(x, y, period), 0.000001,
			"the drifted noise must repeat exactly at the drift period"
		)
	assert_almost_eq(
		RiverFlowShader.bend_displacement(4.3 + period, 2.9),
		RiverFlowShader.bend_displacement(4.3, 2.9), 0.000001,
		"the eddy field must repeat exactly at the eddy period"
	)
	assert_true(
		RiverFlowShader.SHADER_CODE.contains(
			"float drift = mod(TIME * drift_px_per_mps * drift_speed_m_s * moving * noise_scale, drift_period);"
		),
		"the shader must wrap the drift at drift_period"
	)
	assert_true(
		RiverFlowShader.SHADER_CODE.contains(
			"float bend_drift = mod(TIME * surface_px_per_s(drift_speed_m_s, moving) * noise_scale * bend_drift_fraction * eddy_scale, drift_period);"
		),
		"the shader must wrap the eddy drift at drift_period, in eddy units"
	)
	assert_true(
		RiverFlowShader.SHADER_CODE.contains("vec2 eddy_p = p * eddy_scale - flow_dir * bend_drift;"),
		"the eddy sample must translate by the wrapped eddy drift"
	)
	assert_true(
		RiverFlowShader.SHADER_CODE.contains("value_noise_tiled(forward, drift_period)"),
		"the smear taps must sample the noise that tiles at drift_period"
	)


## Two neighbouring fragments on a bend differ in direction by a fraction of
## a degree. After a long session that must still move the field by less
## than a stroke width -- the same budget as a whole bin change at t=0.
func test_a_long_session_does_not_shred_the_field_on_a_bend():
	var angle_a := 231.0
	var angle_b := 231.25
	var dir_a := Vector2(sin(deg_to_rad(angle_a)), -cos(deg_to_rad(angle_a)))
	var dir_b := Vector2(sin(deg_to_rad(angle_b)), -cos(deg_to_rad(angle_b)))
	# The Loire's real neighbourhood, in noise cells.
	var base_x := 19802.0 * 16.0 * RiverFlowShader.NOISE_SCALE
	var base_y := 4751.0 * 16.0 * RiverFlowShader.NOISE_SCALE
	var total := 0.0
	var count := 0
	for i in range(24):
		for j in range(24):
			var px := base_x + float(i) * 0.43
			var py := base_y + float(j) * 0.39
			total += absf(
				RiverFlowShader.animated_field_value(px, py, dir_a, 1500.0, 2.2)
				- RiverFlowShader.animated_field_value(px, py, dir_b, 1500.0, 2.2)
			)
			count += 1
	var mean := total / float(count)
	assert_lt(
		mean, 0.075,
		"a quarter-degree bend after 25 minutes moves the field by %.3f -- shredded strokes"
			% mean
	)
