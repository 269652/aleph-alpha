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
	assert_eq(material.get_shader_parameter("surface_contrast"), RiverFlowShader.SURFACE_CONTRAST)
	assert_eq(material.get_shader_parameter("band0_color"), RiverFlowShader.BAND_COLORS[0])
	assert_eq(material.get_shader_parameter("band4_color"), RiverFlowShader.BAND_COLORS[4])


## The atlas packing is what carries per-cell depth and speed into the
## shader -- a TileMapLayer cell can only pick an atlas tile, so these two
## must agree or every cell decodes to the wrong band.
func test_the_packing_uniforms_match_the_sprite_atlas():
	var material := flow.shared_material()
	assert_eq(
		material.get_shader_parameter("packed_levels"),
		float(ProceduralRiverFlowSprite.PACKED_LEVELS)
	)
	assert_eq(
		material.get_shader_parameter("speed_levels"),
		float(ProceduralRiverFlowSprite.SPEED_LEVELS)
	)


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
	assert_true(RiverFlowShader.SHADER_CODE.contains("advect_strength * phase_a"))
	assert_true(RiverFlowShader.SHADER_CODE.contains("advect_strength * phase_b"))


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
		RiverFlowShader.SHADER_CODE.contains("vec2 world = world_pos * noise_scale;"),
		"a per-tile offset added here would seam the noise at every tile edge"
	)
	assert_false(
		RiverFlowShader.SHADER_CODE.contains("course_offset"),
		"the per-tile phase channel must not offset the noise field"
	)


## Real water has structure at more than one scale -- a single octave reads
## as a lava lamp rather than a surface.
func test_the_surface_has_more_than_one_octave():
	assert_gt(RiverFlowShader.DETAIL_SCALE, 1.0)
	assert_true(RiverFlowShader.SHADER_CODE.contains("detail_scale"))


## Aliasing guard, kept from the earlier pass: at the measured ~7 fps floor
## the advection must stay far inside Nyquist, or the surface strobes.
func test_the_advection_rate_cannot_alias_at_the_worst_frame_rate():
	assert_lt(RiverFlowShader.ADVECT_RATE / 7.0, 0.5)


## Foam must be driven by the SAME advecting field as the surface, so it
## travels with the water. Static foam is one of the clearest tells of fake
## water.
func test_foam_moves_with_the_water_rather_than_sitting_still():
	assert_true(
		RiverFlowShader.SHADER_CODE.contains("foam_threshold, foam_threshold + 0.12, n)"),
		"foam must be a function of the advected surface field n"
	)


## Still opaque: this layer IS the river surface, not a decoration over the
## noisy base water layer.
func test_the_shader_outputs_a_fully_opaque_colour():
	assert_true(RiverFlowShader.SHADER_CODE.contains("COLOR = vec4(body, 1.0)"))


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


## The cross-section survives the return to realism -- it is real physics
## and reads as a channel in any style -- but its bands are subtler now:
## here they are a depth CUE under a moving surface, not the whole look.
func test_the_band_palette_darkens_evenly_toward_the_centreline():
	var colors: Array[Color] = RiverFlowShader.BAND_COLORS
	assert_eq(colors.size(), ProceduralRiverFlowSprite.DEPTH_BANDS)
	for i in range(colors.size() - 1):
		assert_gt(
			colors[i].v - colors[i + 1].v, 0.03,
			"band %d and %d must still darken toward the centreline" % [i, i + 1]
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


# -- what the thresholds actually light up -----------------------------------
#
# GLINT_THRESHOLD and FOAM_THRESHOLD were the last two eyeballed numbers in
# this shader, and both fail SILENTLY in a still frame: set too high nothing
# ever fires and the surface reads flat again -- the exact complaint this
# whole rewrite answers -- and set too low the river whites out. So they are
# measured against the field's real distribution instead.
#
# The intent is stated first and the constant is what moves to meet it:
# glints are SPARSE specular highlights, foam is an occasional break at the
# bank rather than a permanent white rim.
#
# Measured coverage of the real field, for the record:
#
#   threshold  0.50   0.55   0.60   0.62   0.65   0.70   0.75   0.80
#   coverage   48.6%  37.7%  27.0%  23.1%  18.2%  11.3%   6.5%   3.0%
#
# so GLINT_THRESHOLD 0.70 lights 11.3% and FOAM_THRESHOLD 0.62 lights 23.1%.
# The bounds below genuinely bite rather than admitting anything: a glint
# threshold of 0.50 would cover 48.6% and fail the cap outright.
#
# The shader ramps both with a smoothstep over the following 0.10/0.12, so
# these are the fractions that light up AT ALL -- full-strength glint needs
# n > 0.80, i.e. 3% of the surface. That is sparkle, not a sheen.

## Sparse: enough sparkle to read as a lit moving surface, nowhere near
## enough to wash the water out.
func test_glints_are_sparse_highlights_not_a_wash():
	var coverage := RiverFlowShader.surface_coverage_above(RiverFlowShader.GLINT_THRESHOLD)
	assert_between(
		coverage, 0.02, 0.25,
		"glints cover %.1f%% of the surface" % (coverage * 100.0)
	)


## And they must actually fire -- a threshold above the field's maximum
## would silently render no glints at all, which is indistinguishable from a
## flat surface in a screenshot.
func test_glints_actually_fire_somewhere():
	assert_gt(RiverFlowShader.surface_coverage_above(RiverFlowShader.GLINT_THRESHOLD), 0.0)


## Foam breaks at the bank now and then; it is not a permanent white rim
## drawn down both edges of every river.
func test_bank_foam_breaks_occasionally_rather_than_rimming_the_whole_bank():
	var coverage := RiverFlowShader.surface_coverage_above(RiverFlowShader.FOAM_THRESHOLD)
	assert_between(
		coverage, 0.05, 0.45,
		"foam covers %.1f%% of the bank band" % (coverage * 100.0)
	)


## Foam must be the more common of the two -- water breaks white at a bank
## far more readily than it throws a specular highlight.
func test_foam_is_more_common_than_glint():
	assert_gt(
		RiverFlowShader.surface_coverage_above(RiverFlowShader.FOAM_THRESHOLD),
		RiverFlowShader.surface_coverage_above(RiverFlowShader.GLINT_THRESHOLD)
	)


## The mirror has to actually mirror: two octaves, bounded in [0,1] like the
## shader's own, or the coverage numbers above measure nothing real.
func test_the_surface_mirror_stays_in_the_shaders_own_range():
	for i in range(60):
		for j in range(60):
			assert_between(RiverFlowShader.surface_value(float(i) * 0.7, float(j) * 0.9), 0.0, 1.0)


# -- water, not a mosaic -----------------------------------------------------
#
# Both of these come from looking at the running game rather than reasoning
# about it, and they share one root cause: EVERY per-tile quantity drawn as
# a flat fill reads as a blocky mosaic at this camera zoom, because a tile
# is tens of screen pixels. The same root cause already claimed the old bank
# outline (a near-black block eating half the channel).
#
# The first screenshot of the advection shader showed a river of perfectly
# uniform tile-sized blocks with no visible surface at all. Measured, the
# moving surface swung 0.070 in brightness against the depth banding's 0.26
# -- the static mosaic was 3.7x stronger than the water.

## So the moving surface must be at least as strong a signal as the entire
## depth profile. Below parity a still frame is dominated by flat per-tile
## colour, which is precisely the "blocky, not water" failure -- and it is a
## RELATION between two measured quantities, so it cannot be satisfied by
## quietly restyling either one alone.
func test_the_moving_surface_is_at_least_as_strong_as_the_depth_profile():
	var swing := RiverFlowShader.surface_swing() * RiverFlowShader.SURFACE_CONTRAST
	var profile := RiverFlowShader.depth_profile_span()
	assert_gte(
		swing, profile,
		"surface swings %.3f against a %.3f depth profile -- the static banding wins"
			% [swing, profile]
	)


## And the band boundaries themselves must be dithered by the surface field,
## or they land on straight tile edges and draw the mosaic's grid lines.
##
## The dither has to be wide enough for a boundary to wander at least half a
## band, which is what stops it aligning with the tile grid at all.
func test_band_edges_are_dithered_enough_to_break_the_tile_grid():
	var wander := RiverFlowShader.surface_swing() * 0.5 * RiverFlowShader.BAND_DITHER
	assert_gte(
		wander, 0.5,
		"band edges wander only %.3f of a band -- not enough to leave the tile grid" % wander
	)


func test_the_shader_actually_dithers_the_band_lookup():
	assert_true(
		RiverFlowShader.SHADER_CODE.contains("float band = depth_band + (n - 0.5) * band_dither;"),
		"the band index must be perturbed by the same advecting field"
	)
	assert_false(
		RiverFlowShader.SHADER_CODE.contains("step(0.5, depth_band)"),
		"the bands must step on the dithered index, not the raw per-tile one"
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
## coherent much further ALONG the flow than ACROSS it.
func test_the_field_forms_lines_along_the_flow_not_blobs():
	var step := 0.45
	var along := RiverFlowShader.field_roughness(step, true)
	var across := RiverFlowShader.field_roughness(step, false)
	assert_gt(
		across, along * 2.0,
		"field changes %.4f across vs %.4f along -- too round to read as flowing lines"
			% [across, along]
	)


## The stretch is what produces that, so it must genuinely stretch. At 1.0
## the field is isotropic and the lines are gone.
func test_the_line_stretch_actually_elongates_the_field():
	assert_lt(RiverFlowShader.LINE_STRETCH, 0.5)
	assert_gt(RiverFlowShader.LINE_STRETCH, 0.0)


## And the shader must sample in the channel's own frame, or "along the
## flow" has no meaning -- a world-axis-aligned stretch would draw lines
## pointing the same way regardless of which way the river runs.
func test_the_shader_samples_in_the_channels_own_frame():
	assert_true(RiverFlowShader.SHADER_CODE.contains("dot(world, flow_dir)"))
	assert_true(RiverFlowShader.SHADER_CODE.contains("dot(world, flow_perp)"))
	assert_true(RiverFlowShader.SHADER_CODE.contains("flow_perp = vec2(-flow_dir.y, flow_dir.x)"))


## Water is carried DOWNSTREAM. Dragging the field sideways as well would
## make the lines crab across the channel instead of running along it.
func test_the_drag_is_purely_downstream():
	assert_true(RiverFlowShader.SHADER_CODE.contains("line_field(along - advect_strength * phase_a, across_w)"))
	assert_true(RiverFlowShader.SHADER_CODE.contains("line_field(along - advect_strength * phase_b, across_w)"))


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
	var width_tiles := RiverFlowShader.feature_width_px() / float(TerrainRenderer.ART_TILE_SIZE)
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
	var length_tiles := RiverFlowShader.feature_length_px() / float(TerrainRenderer.ART_TILE_SIZE)
	assert_between(
		length_tiles, 2.0, 6.0,
		"a flow line is %.2f tiles long" % length_tiles
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
## a band measured in line widths.
func test_streaklines_are_bent_by_a_real_measured_amount():
	var total := 0.0
	var count := 0
	for i in range(70):
		for j in range(70):
			var d := RiverFlowShader.bend_displacement(float(i) * 0.31, float(j) * 0.29)
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
		RiverFlowShader.SHADER_CODE.contains("vec2(along_raw, across) * eddy_scale"),
		"the eddy field must be sampled at unadvected channel coordinates"
	)
	assert_true(
		RiverFlowShader.SHADER_CODE.contains("float across_w = across + bend * turbulence_strength;")
	)
