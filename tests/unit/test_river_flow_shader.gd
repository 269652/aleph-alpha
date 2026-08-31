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
	assert_eq(material.get_shader_parameter("across_range"), ProceduralRiverFlowSprite.ACROSS_RANGE)
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
	assert_true(RiverFlowShader.SHADER_CODE.contains("(advect_strength * phase_a)"))
	assert_true(RiverFlowShader.SHADER_CODE.contains("(advect_strength * phase_b)"))


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


# -- the continuous cross-section --------------------------------------------
#
# THE fix for "still a lot of individual squares". Depth used to be a
# per-tile quantized band, so every water tile broadcast one flat colour
# over its whole area -- at this camera zoom, a mosaic of rectangles, and no
# amount of softening the band MIXING could hide that the underlying value
# jumped at every tile edge.
#
# Now the tile bakes its centre's SIGNED across-offset and every FRAGMENT
# reconstructs its own: centre offset + (position within the tile projected
# on the flow perpendicular). The parabola is shaded from that, per pixel,
# so the cross-section glides straight through tile boundaries.

## The reconstruction identity, at the exact worst spot: a shared tile edge
## evaluated from BOTH sides. The only disagreement allowed is the across
## quantisation step -- the full-band jumps are structurally gone.
func test_reconstruction_is_continuous_across_a_tile_edge():
	var worst := 0.0
	for step in 160:
		# A straight channel: the true field is x / HALF_WIDTH. Two tile
		# centres one tile apart, their baked (quantized) centre values,
		# and the shared edge halfway between them, seen from each side.
		var left_centre := lerpf(-2.4, 1.4, float(step) / 159.0)
		var right_centre := left_centre + 1.0
		var left_baked := ProceduralRiverFlowSprite.fraction_for_bin(
			ProceduralRiverFlowSprite.across_bin_for(
				left_centre / RiverCatalog.RIVER_HALF_WIDTH_TILES
			)
		)
		var right_baked := ProceduralRiverFlowSprite.fraction_for_bin(
			ProceduralRiverFlowSprite.across_bin_for(
				right_centre / RiverCatalog.RIVER_HALF_WIDTH_TILES
			)
		)
		var from_left := RiverFlowShader.reconstructed_across(left_baked, 0.5)
		var from_right := RiverFlowShader.reconstructed_across(right_baked, -0.5)
		worst = maxf(worst, absf(from_left - from_right))
	var bin_step := (
		2.0 * ProceduralRiverFlowSprite.ACROSS_RANGE
		/ float(ProceduralRiverFlowSprite.ACROSS_BINS)
	)
	assert_lte(
		worst, bin_step + 0.0001,
		"tile edges disagree by %.4f -- more than one quantisation step" % worst
	)


## The within-tile refinement must actually refine: a fragment half a tile
## toward the bank sits measurably farther across than its tile centre.
func test_fragments_within_one_tile_get_their_own_across_offset():
	assert_gt(
		RiverFlowShader.reconstructed_across(0.5, 0.5),
		RiverFlowShader.reconstructed_across(0.5, 0.0)
	)


## Structural: the shader must derive the within-tile delta from world
## position against the real tile grid, and project it on the same
## flow-perpendicular the catalog's sign convention uses.
func test_the_shader_reconstructs_from_the_real_tile_grid():
	assert_true(RiverFlowShader.SHADER_CODE.contains("floor(wp / tile_px)"))
	assert_true(RiverFlowShader.SHADER_CODE.contains("dot(delta_tiles, flow_perp) / half_width_tiles"))


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


## And the sprite's encodable range must cover every painted cell's centre,
## out to the far corner of the outermost apron tile.
func test_the_across_range_covers_the_painted_apron():
	var needed := (
		(RiverCatalog.RIVER_HALF_WIDTH_TILES + RiverCatalog.RIVER_BANK_APRON_TILES)
		/ RiverCatalog.RIVER_HALF_WIDTH_TILES
	)
	assert_gte(ProceduralRiverFlowSprite.ACROSS_RANGE, needed)


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
	assert_true(RiverFlowShader.SHADER_CODE.contains("flow_dir * (float(k) * smear_spacing)"))
	assert_true(RiverFlowShader.SHADER_CODE.contains("flow_perp = vec2(-flow_dir.y, flow_dir.x)"))


## Water is carried DOWNSTREAM. Dragging the field sideways as well would
## make the lines crab across the channel instead of running along it.
func test_the_drag_is_purely_downstream():
	assert_true(RiverFlowShader.SHADER_CODE.contains("flow_dir * (advect_strength * phase_a)"))
	assert_true(RiverFlowShader.SHADER_CODE.contains("flow_dir * (advect_strength * phase_b)"))


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


## Classic 16-bit ordered dither: on the checkerboard's other phase the
## quantization threshold shifts, so band boundaries interleave in a 2x2
## weave instead of cutting hard.
func test_band_boundaries_are_ordered_dithered():
	var moved := 0
	for step in 400:
		var shade := float(step) / 399.0
		if RiverFlowShader.cel_level(shade, 0.0) != RiverFlowShader.cel_level(shade, 1.0):
			moved += 1
	assert_gt(moved, 20, "the checker phase moves almost no boundaries -- no dither weave")
	assert_true(
		RiverFlowShader.SHADER_CODE.contains("mod(floor(wp.x / pixel_snap) + floor(wp.y / pixel_snap), 2.0)"),
		"the shader must derive the dither phase from the snapped pixel grid"
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
	assert_true(
		RiverFlowShader.SHADER_CODE.contains("min(wave * line_strength * mix(1.0, night_stroke_boost, night_lift), 1.0)")
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


## The half-cycle loop contract, restated on the guided field.
func test_the_animation_loops_exactly_each_half_cycle():
	var period := 1.0 / RiverFlowShader.ADVECT_RATE
	for i in range(30):
		var px := 15.0 + float(i) * 0.9
		assert_almost_eq(
			RiverFlowShader.animated_field_value(px, 11.0, Vector2(1, 0), 0.37),
			RiverFlowShader.animated_field_value(px, 11.0, Vector2(1, 0), 0.37 + period * 0.5),
			0.0001
		)


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
