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


## The water has to visibly MOVE. The drag is what carries the surface
## downstream, so measured in the field's own feature lengths it must cover
## a real fraction of a line per phase -- below that the surface deforms
## almost in place and the river looks still.
##
## This is the trap the first version fell into: the drag was applied before
## the anisotropic stretch, so 1.15 "units" came out as 0.18 of a feature --
## nearly motionless.
func test_the_water_visibly_travels_within_each_phase():
	assert_gte(
		RiverFlowShader.drag_in_feature_lengths(), 0.5,
		"the surface travels only %.2f of a line per phase -- reads as still water"
			% RiverFlowShader.drag_in_feature_lengths()
	)


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
func test_the_bend_never_folds_the_surface_over_itself():
	for i in range(40):
		var along := float(i) * 0.47
		var previous := RiverFlowShader.warped_across(along, 0.0)
		for j in range(1, 160):
			var here := RiverFlowShader.warped_across(along, float(j) * 0.05)
			assert_gt(here, previous, "the warp folds at along=%.2f" % along)
			previous = here


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


## Structural: the bend is anchored to the bed. It must be computed from the
## UNADVECTED coordinates (along_raw), and the warped across must feed both
## phase samples -- that is what makes the water deform as it streams
## through the standing eddies.
func test_the_bend_is_anchored_to_the_bed_not_carried_with_the_water():
	assert_true(
		RiverFlowShader.SHADER_CODE.contains("p * eddy_scale"),
		"the eddy field must be sampled at unadvected world coordinates"
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
	assert_true(
		RiverFlowShader.SHADER_CODE.contains("eddy_p * 2.6"),
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
	assert_gte(
		worst, 0.5,
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
func test_the_channel_guide_dominates_the_wobble():
	assert_gte(RiverFlowShader.ACROSS_LINE_SCALE, RiverFlowShader.LINE_WOBBLE)
	assert_true(
		RiverFlowShader.SHADER_CODE.contains("frag_across * across_line_scale + (n - 0.5) * line_wobble"),
		"the stroke field must be the across ramp plus advected wobble"
	)
	assert_true(RiverFlowShader.SHADER_CODE.contains("fract(s_field * line_count) - 0.5"))


## And measured: walking bank to bank through the REAL animated field, the
## stroke field must rise monotonically at nearly every step -- occasional
## pinches are the wanted merge-and-unmerge, a cell field would violate
## this everywhere.
func test_the_stroke_field_is_monotone_across_with_rare_pinches():
	var violations := 0
	var steps := 0
	for column in 24:
		var x := float(column) * 3.7
		var previous := -99.0
		for row in 80:
			var across := -1.0 + float(row) / 79.0 * 2.0
			var n := RiverFlowShader.animated_field_value(x, across * 2.56, Vector2(1, 0), 0.9)
			var s_value := RiverFlowShader.stroke_field(across, n)
			if previous > -99.0:
				steps += 1
				if s_value <= previous:
					violations += 1
			previous = s_value
	assert_lt(
		float(violations) / float(steps), 0.15,
		"%.0f%% of across-steps fold back -- cells, not pinching lines"
			% (float(violations) / float(steps) * 100.0)
	)


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


## The lines MORPH: at a fixed spot the stroke pattern must differ a
## quarter advection cycle later -- the wobble travels, so lines wander,
## pinch and release.
func test_the_lines_morph_over_a_quarter_cycle():
	var period := 1.0 / RiverFlowShader.ADVECT_RATE
	var changed := 0
	var count := 0
	for column in 40:
		var x := 5.0 + float(column) * 1.1
		for row in 30:
			var across := -0.9 + float(row) / 29.0 * 1.8
			var early := RiverFlowShader.stroke_mask(RiverFlowShader.stroke_field(
				across, RiverFlowShader.animated_field_value(x, across * 2.56, Vector2(1, 0), 0.2)
			), false) > 0.5
			var later := RiverFlowShader.stroke_mask(RiverFlowShader.stroke_field(
				across, RiverFlowShader.animated_field_value(x, across * 2.56, Vector2(1, 0), 0.2 + period * 0.25)
			), false) > 0.5
			if early != later:
				changed += 1
			count += 1
	assert_gt(
		float(changed) / float(count), 0.04,
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


## The drift is a tested function of the reach's REAL current speed --
## linear in speed and time, and paced so a brisk river visibly travels
## (order of a tile per second) without strobing.
func test_the_drift_is_pinned_to_the_real_current_speed():
	assert_almost_eq(
		RiverFlowShader.drift_cells(2.0, 1.0),
		RiverFlowShader.drift_cells(1.0, 1.0) * 2.0, 0.0001
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
	assert_true(
		RiverFlowShader.SHADER_CODE.contains("mix(0.55, 1.0, pulse)"),
		"the pulse must modulate the stroke brightness, dim never to zero"
	)


## Measured: at fixed points sitting ON a line, the stroke intensity must
## genuinely change over a quarter cycle -- pulses passing through -- for
## a real fraction of the line.
func test_the_pulses_actually_travel_through_the_lines():
	var period := 1.0 / RiverFlowShader.ADVECT_RATE
	var moved := 0
	var on_line := 0
	for column in 90:
		var x := 3.0 + float(column) * 1.13
		for row in 9:
			var across := -0.8 + float(row) / 8.0 * 1.6
			var n_early := RiverFlowShader.animated_field_value(
				x, across * 2.56, Vector2(1, 0), 0.3
			)
			var n_later := RiverFlowShader.animated_field_value(
				x, across * 2.56, Vector2(1, 0), 0.3 + period * 0.25
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


## The loop lengthens so the repeat is harder to spot, without giving up
## travel speed -- the strength rises to match. Both halves pinned: the
## per-second travel stays real, and the drag still covers most of a
## feature length per phase.
func test_the_water_still_travels_at_a_real_speed():
	var cells_per_second := RiverFlowShader.ADVECT_STRENGTH * RiverFlowShader.ADVECT_RATE
	assert_between(
		cells_per_second, 1.0, 2.6,
		"the surface travels %.2f cells/s" % cells_per_second
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
	# radius around which the water flows". The shift is now the REAL
	# midplane streamline displacement around a cylinder of radius R:
	# sqrt(lateral^2 + R^2) - |lateral| -- R exactly on the stagnation
	# line (the parting streamline clears the actual rock), decaying
	# smoothly to the sides, never a point spike.
	var perp := Vector2(0, 1)
	var r := RiverFlowShader.BOULDER_RADIUS_PX
	var reach := RiverFlowShader.BOULDER_REACH_PX
	var on_axis := RiverFlowShader.obstacle_lateral_shift_px(
		Vector2(r, 0.0), perp, r, reach, 0.0
	)
	assert_almost_eq(on_axis, r, 0.01, "the parting streamline must clear the full radius")
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
	assert_almost_eq(
		RiverFlowShader.boulder_across_push(
			Vector2(RiverFlowShader.BOULDER_RADIUS_PX, 0.0), Vector2(0, 1)
		),
		RiverFlowShader.BOULDER_RADIUS_PX / RiverFlowShader.HALF_WIDTH_PX, 0.001
	)
	assert_almost_eq(
		RiverFlowShader.wader_across_push(
			Vector2(RiverFlowShader.WADER_RADIUS_PX, 0.0), Vector2(1, 0)
		),
		RiverFlowShader.WADER_RADIUS_PX / RiverFlowShader.HALF_WIDTH_PX, 0.001
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
		RiverFlowShader.SHADER_CODE.contains(
			"sqrt(lateral * lateral + boulder_radius_px * boulder_radius_px)"
		),
		"the boulder must displace via the round-core potential-flow formula"
	)
	# eyot_dry now trims one arm of a max(); the other arm is the halo
	# ring, which must survive where the channel verdict alone is dry.
	assert_true(RiverFlowShader.SHADER_CODE.contains(
		"(1.0 - smoothstep(1.0 - bank_feather, 1.0 + bank_feather, rr)) * eyot_dry,"
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


## "Boulders on a grass field inside the river should be surrounded by
## the light blue shore band as well": every boulder gets its own ring,
## a function of distance to the ROCK alone -- unlike eyot_dry (which can
## only ever REMOVE wet alpha), the halo can light up alpha and tint the
## body on its own, so a rock sitting on ordinary dry bank ground still
## reads as part of the river.
func test_every_boulder_gets_its_own_shore_halo():
	assert_gt(RiverFlowShader.BOULDER_HALO_WIDTH_PX, 0.0)
	assert_gt(RiverFlowShader.BOULDER_HALO_ALPHA, 0.0)
	assert_lte(RiverFlowShader.BOULDER_HALO_ALPHA, 1.0)
	assert_true(_shader_code_lf().contains(
		"smoothstep(boulder_radius_px * 0.6, boulder_radius_px, d)\n\t\t\t\t* (1.0 - smoothstep(boulder_radius_px, boulder_radius_px + boulder_halo_width_px, d))"
	), "the halo must be a RING -- a disc lights alpha under the rock and undoes its own dry patch")
	assert_true(RiverFlowShader.SHADER_CODE.contains(
		"body = mix(body, line_color, boulder_halo * boulder_halo_alpha * mix(0.5, 0.85, night_lift));"
	))
	assert_true(RiverFlowShader.SHADER_CODE.contains("boulder_halo * boulder_halo_alpha"))
	var material := RiverFlowShader.new().make_material()
	assert_almost_eq(
		float(material.get_shader_parameter("boulder_halo_width_px")), RiverFlowShader.BOULDER_HALO_WIDTH_PX, 1e-9
	)
	assert_almost_eq(
		float(material.get_shader_parameter("boulder_halo_alpha")), RiverFlowShader.BOULDER_HALO_ALPHA, 1e-9
	)


## The halo's own CPU mirror: zero under the rock (that ground is the
## eyot, not the ring), a full ring just outside it, gone beyond the halo
## band -- and, crucially, defined with NO reference to the channel's own
## wet/dry state, so a rock on dry land gets exactly the same ring a rock
## mid-channel does.
func test_boulder_halo_factor_rings_the_rock_and_nothing_else():
	assert_eq(RiverFlowShader.boulder_halo_factor(0.0), 0.0, "under the rock is the eyot, not the ring")
	assert_eq(RiverFlowShader.boulder_halo_factor(RiverFlowShader.BOULDER_RADIUS_PX), 1.0, "the ring peaks right at the rock's edge")
	assert_eq(
		RiverFlowShader.boulder_halo_factor(RiverFlowShader.BOULDER_RADIUS_PX + RiverFlowShader.BOULDER_HALO_WIDTH_PX), 0.0
	)
	assert_between(
		RiverFlowShader.boulder_halo_factor(RiverFlowShader.BOULDER_RADIUS_PX + RiverFlowShader.BOULDER_HALO_WIDTH_PX * 0.5),
		0.0, 1.0
	)


## The halo must be able to light alpha up even where the channel's own
## baseline would leave the fragment fully transparent -- a boulder past
## the true bank but still within the newly-bled paint band.
func test_the_boulder_halo_can_light_alpha_on_otherwise_dry_ground():
	assert_true(_shader_code_lf().contains(
		"float wet = max(\n\t\t(1.0 - smoothstep(1.0 - bank_feather, 1.0 + bank_feather, rr)) * eyot_dry,\n\t\tboulder_halo * boulder_halo_alpha\n\t);"
	))


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


## Disturbance rings live in the contour system now (the old overlay's
## rings vanished with it): a ring travels outward, peaks on its own
## radius, and is gone after its lifetime.
func test_disturbance_rings_travel_outward_and_fade():
	var age := 1.0
	var on_ring := RiverFlowShader.ripple_push_px(age * RiverFlowShader.RIPPLE_SPEED_PX, age)
	var inside := RiverFlowShader.ripple_push_px(age * RiverFlowShader.RIPPLE_SPEED_PX - 3.0 * RiverFlowShader.RIPPLE_WIDTH_PX, age)
	assert_gt(on_ring, inside * 10.0, "the push is a band on the ring, not a disc")
	assert_almost_eq(on_ring, RiverFlowShader.RIPPLE_AMPLITUDE_PX * (1.0 - age / RiverFlowShader.RIPPLE_LIFETIME), 1e-9)
	assert_eq(RiverFlowShader.ripple_push_px(10.0, RiverFlowShader.RIPPLE_LIFETIME + 0.1), 0.0)
	assert_eq(RiverFlowShader.ripple_push_px(10.0, -0.1), 0.0, "a ring from the future is nothing yet")
	assert_true(RiverFlowShader.SHADER_CODE.contains("uniform vec3 ripples[24];"))
	assert_true(RiverFlowShader.SHADER_CODE.contains("for (int i = 0; i < ripple_count; i++)"))
	assert_eq(RiverFlowShader.RIPPLE_SLOTS, 24)
	var material := flow.shared_material()
	assert_almost_eq(float(material.get_shader_parameter("ripple_lifetime")), RiverFlowShader.RIPPLE_LIFETIME, 1e-9)
	assert_almost_eq(float(material.get_shader_parameter("ripple_width_px")), RiverFlowShader.RIPPLE_WIDTH_PX, 1e-9)
	assert_almost_eq(float(material.get_shader_parameter("ripple_amplitude_px")), RiverFlowShader.RIPPLE_AMPLITUDE_PX, 1e-9)


## A ring bends the strokes it crosses and never spawns new ones: its
## steepest slope, in across units per pixel on a two-tile river, stays
## under the channel's own cross-gradient (found in play as dense
## concentric arcs filling a river full of flapping fish).
func test_a_ring_bends_strokes_without_adding_any():
	# Steepest slope of a Gaussian band of amplitude A and width w is
	# A * sqrt(2) * exp(-0.5) / w, in px of displacement per px.
	var steepest_px_per_px := RiverFlowShader.RIPPLE_AMPLITUDE_PX * sqrt(2.0) * exp(-0.5) / RiverFlowShader.RIPPLE_WIDTH_PX
	var steepest_across_per_px := steepest_px_per_px / (2.0 * 16.0)
	assert_lt(steepest_across_per_px, RiverFlowShader.CHANNEL_ACROSS_GRADIENT_PER_PX * 0.5)


## A dozen fish flapping at one bend must never compound past what ONE
## ring alone can do: found in play as dense fanned lines at a bend and
## unexplained round bumps on the bank ("artifacts in curves",
## "semispheres on the edge") once several rings landed on the same
## fragments and summed straight into the across field.
func test_many_overlapping_rings_never_exceed_one_rings_own_push():
	assert_true(RiverFlowShader.SHADER_CODE.contains(
		"ripple_push_px = clamp(ripple_push_px, -ripple_amplitude_px, ripple_amplitude_px);"
	))


## A ring must never itself be what pushes a fragment past the real
## waterline -- the bank curve is drawn by frag_across crossing 1.0, and a
## ring reaching it without this fade bulged that very line into a round
## bump with no visible source object (the "semisphere" reported at the
## edge). The fade reads frag_across BEFORE any ripple is added.
func test_ripples_fade_out_before_they_reach_the_bank():
	assert_true(RiverFlowShader.SHADER_CODE.contains(
		"float bank_fade = 1.0 - smoothstep(0.7, 1.0, abs(frag_across));"
	))
	assert_true(RiverFlowShader.SHADER_CODE.contains(
		"frag_across += ripple_push_px * bank_fade / (half_width_local * tile_px);"
	))


## The tile's REAL local half-width, not the fixed uniform, must decide
## how strongly a boulder/wader/ripple push bends the strokes: a fixed
## divisor understated a wide hydrology reach's true width by up to 3x
## (the catalog's curated constant, 2.0 tiles, against hydrology's up to
## 6), so the same physical push landed up to 3x stronger, relative to
## that reach, than intended -- reported in play as "artifacts in
## curves", wide bends being exactly where a river slows and gathers
## fish. The width now rides the direction vector's own magnitude
## (a direction's length otherwise carries no information).
func test_boulder_wader_and_ripple_pushes_divide_by_the_real_local_width():
	# The width still comes from its own scalar map and is still floored
	# at 0.05; it now goes through the same cubic reconstruction the across
	# map does, so the pushes that divide by it stop inheriting the texel
	# lattice's sawtooth.
	assert_true(_shader_code_lf().contains(
		"float half_width_local = max(mix(\n\t\ttexture(flow_scale_map, map_uv),\n\t\ttexture_bicubic(flow_scale_map, map_uv, flow_map_tiles),\n\t\tmap_smoothing\n\t).r, 0.05);"
	))
	assert_eq(
		RiverFlowShader.SHADER_CODE.count("/ (half_width_local * tile_px)"), 3,
		"boulder, wader and ripple must all divide by the LOCAL width"
	)
	assert_false(
		RiverFlowShader.SHADER_CODE.contains("/ (half_width_tiles * tile_px)"),
		"none of the three may still read the fixed uniform"
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


func test_the_map_smoothing_dials_back_to_plain_bilinear():
	var material := RiverFlowShader.new().make_material()
	assert_almost_eq(
		float(material.get_shader_parameter("map_smoothing")),
		RiverFlowShader.MAP_SMOOTHING, 1e-9
	)
	assert_between(RiverFlowShader.MAP_SMOOTHING, 0.0, 1.0)
