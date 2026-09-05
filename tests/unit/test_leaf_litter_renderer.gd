extends GutTest

## LeafLitterRenderer: one MultiMeshInstance2D per chunk, GPU-instanced
## fallen-leaf litter (see docs/concept/leaf_litter.md). Mirrors
## IllustratedGrassPatch's shape (pure data-prep headlessly testable, the
## real MultiMesh fill needs a real renderer -- see
## test_leaf_litter_renderer_smoke.gd), minus Y-sort banding.
##
## The fall/sway math is ported BY HAND from DroppedItem's own tested
## _step_fall/_step_ground_sway (see that file's own doc comment) into a
## GDScript mirror kept in sync with the GLSL by hand -- the same
## relationship SnowBombShader's own static funcs have to ITS shader, and
## for the same reason: a fragment/vertex shader cannot be asserted headless.

const LeafLitterRenderer = preload("res://src/rendering/leaf_litter_renderer.gd")
const LeafLitterField = preload("res://src/world/leaf_litter_field.gd")
const LeafLitterAtlas = preload("res://src/rendering/leaf_litter_atlas.gd")
const ProceduralItemSprite = preload("res://src/rendering/procedural_item_sprite.gd")


# -- packing: every channel round-trips ---------------------------------------

func test_cell_index_round_trips_for_every_real_cell():
	var atlas := LeafLitterAtlas.new()
	for index in atlas.cell_count():
		var packed := LeafLitterRenderer.pack_cell_index(index, atlas.cell_count())
		assert_eq(LeafLitterRenderer.unpack_cell_index(packed, atlas.cell_count()), index)


func test_cell_index_packs_into_a_valid_0_to_1_fraction():
	var atlas := LeafLitterAtlas.new()
	for index in atlas.cell_count():
		var packed := LeafLitterRenderer.pack_cell_index(index, atlas.cell_count())
		assert_gte(packed, 0.0)
		assert_lte(packed, 1.0)


func test_offset_axis_round_trips_within_the_packed_resolution():
	for value in [-380.0, -100.0, -1.0, 0.0, 1.0, 100.0, 380.0]:
		var packed := LeafLitterRenderer.pack_offset_axis(value)
		var unpacked := LeafLitterRenderer.unpack_offset_axis(packed)
		# 8-bit-channel resolution (see MAX_TRANSITION_OFFSET's own doc
		# comment): each step is 2*MAX_TRANSITION_OFFSET/255 wide.
		var step := 2.0 * LeafLitterRenderer.MAX_TRANSITION_OFFSET / 255.0
		assert_almost_eq(unpacked, value, step)


func test_offset_axis_clamps_to_the_packable_range():
	var huge := LeafLitterRenderer.MAX_TRANSITION_OFFSET * 100.0
	var packed := LeafLitterRenderer.pack_offset_axis(huge)
	assert_almost_eq(packed, 1.0, 0.001)
	assert_almost_eq(LeafLitterRenderer.unpack_offset_axis(packed), LeafLitterRenderer.MAX_TRANSITION_OFFSET, 0.01)


func test_time_fraction_is_a_valid_0_to_1_fraction():
	for seconds in [0.0, 1.5, 100.0, 12345.6]:
		var packed := LeafLitterRenderer.pack_time_fraction(seconds)
		assert_gte(packed, 0.0)
		assert_lt(packed, 1.0)


# -- the ported fall/sway math -------------------------------------------------
#
# Mirrors DroppedItem's own test_a_falling_leaf_reaches_its_landing_position_
# after_the_fall_duration / test_a_falling_leaf_drifts_sideways_partway_
# through_its_fall / test_a_landed_leaf_keeps_swaying_gently.

func test_a_transition_starts_at_full_offset():
	assert_almost_eq(LeafLitterRenderer.remaining_offset_fraction(0.0), 1.0, 0.0001)


func test_a_transition_reaches_zero_offset_once_complete():
	assert_almost_eq(LeafLitterRenderer.remaining_offset_fraction(1.0), 0.0, 0.0001)


func test_a_transition_is_partway_offset_in_the_middle():
	var mid := LeafLitterRenderer.remaining_offset_fraction(0.5)
	assert_gt(mid, 0.0)
	assert_lt(mid, 1.0)


## t is computed from the packed wrapped-fraction clock, mirroring how the
## shader will read it (see elapsed_seconds/transition_t) -- a leaf that
## started "now" (start_fraction == current_fraction) has zero elapsed time.
func test_transition_t_is_zero_right_at_the_start():
	var now := LeafLitterRenderer.pack_time_fraction(10.0)
	assert_almost_eq(LeafLitterRenderer.transition_t(now, now), 0.0, 0.0001)


func test_transition_t_reaches_one_after_a_full_transition_duration():
	var start := LeafLitterRenderer.pack_time_fraction(10.0)
	var current := LeafLitterRenderer.pack_time_fraction(10.0 + LeafLitterField.TRANSITION_DURATION + 0.1)
	assert_almost_eq(LeafLitterRenderer.transition_t(start, current), 1.0, 0.0001)


func test_transition_t_is_partway_through_mid_transition():
	var start := LeafLitterRenderer.pack_time_fraction(10.0)
	var current := LeafLitterRenderer.pack_time_fraction(10.0 + LeafLitterField.TRANSITION_DURATION * 0.5)
	var t := LeafLitterRenderer.transition_t(start, current)
	assert_gt(t, 0.0)
	assert_lt(t, 1.0)


## The swirling path (see "swirl: a curling path, not a fixed-axis wobble"
## below) is nonzero partway through -- mirrors
## test_a_falling_leaf_drifts_sideways_partway_through_its_fall, now for a
## genuine 2D curl rather than a scalar sway on one fixed axis.
func test_swirl_offset_is_nonzero_partway_through():
	var offset := LeafLitterRenderer.instance_swirl_offset(
		0.3, 0.7, 0.4, Vector2.RIGHT, Vector2.UP
	)
	assert_ne(offset, Vector2.ZERO)


## The swirl must taper to (0,0) by the time the transition completes (see
## DroppedItem._step_fall's own "however it wanders on the way down, it
## always settles exactly at the position step_fruiting actually chose") --
## a leaf's swirl must never leave it stranded off its real, logical target.
func test_swirl_offset_reaches_zero_once_complete():
	for phase in [0.0, 1.0, 2.5, 4.0]:
		for swirl_seed in [0.0, 0.3, 0.8, 1.0]:
			var offset := LeafLitterRenderer.instance_swirl_offset(
				1.0, phase, swirl_seed, Vector2.RIGHT, Vector2.UP
			)
			assert_almost_eq(offset.x, 0.0, 0.0001)
			assert_almost_eq(offset.y, 0.0, 0.0001)


func test_transition_rotation_reaches_zero_once_complete():
	for phase in [0.0, 1.0, 2.5, 4.0]:
		assert_almost_eq(LeafLitterRenderer.transition_rotation(1.0, phase), 0.0, 0.0001)


# -- tumble: a real leaf visibly SPINS while blowing across open ground ------
#
# Reported: "the leaves blowing in the wind animation... they should twirl
# more and have more realistic / natural motion paths". transition_rotation
# above only ever WOBBLES (oscillates back toward zero, see the test just
# above) -- real litter tumbling in wind visibly spins THROUGH, completing
# real turns rather than rocking in place (see docs/concept/leaf_litter.md's
# own "Real-world grounding": "a dry leaf's large surface-area-to-mass ratio
# is why it visibly tumbles and skitters across open ground in an ordinary
# breeze"). tumble_rotation adds an ACCUMULATING spin on top of the existing
# wobble -- scaled by how FAR this transition travels (raw_offset's own
# length), so a leaf merely settling back into place after a footstep nudge
# barely turns, where one genuinely carried across a real wind-blown journey
# visibly cartwheels several times, same real-world distinction the report
# itself draws between "walking over" and "a gust blows".

func test_tumble_turns_for_distance_is_minimum_at_zero_distance():
	assert_almost_eq(
		LeafLitterRenderer.tumble_turns_for_distance(0.0), LeafLitterRenderer.MIN_TUMBLE_TURNS, 0.0001
	)


func test_tumble_turns_for_distance_is_maximum_at_the_reference_distance():
	assert_almost_eq(
		LeafLitterRenderer.tumble_turns_for_distance(LeafLitterRenderer.MAX_TRANSITION_OFFSET),
		LeafLitterRenderer.MAX_TUMBLE_TURNS, 0.0001
	)


## A journey longer than the largest real transition can ever be (see
## MAX_TRANSITION_OFFSET's own doc comment: it is already sized to the
## largest possible single hop) must still clamp, not extrapolate past
## MAX_TUMBLE_TURNS into an ever-faster spin.
func test_tumble_turns_for_distance_clamps_past_the_reference_distance():
	var huge := LeafLitterRenderer.MAX_TRANSITION_OFFSET * 100.0
	assert_almost_eq(
		LeafLitterRenderer.tumble_turns_for_distance(huge), LeafLitterRenderer.MAX_TUMBLE_TURNS, 0.0001
	)


func test_tumble_turns_for_distance_is_between_min_and_max_partway():
	var turns := LeafLitterRenderer.tumble_turns_for_distance(LeafLitterRenderer.MAX_TRANSITION_OFFSET * 0.5)
	assert_gt(turns, LeafLitterRenderer.MIN_TUMBLE_TURNS)
	assert_lt(turns, LeafLitterRenderer.MAX_TUMBLE_TURNS)


## Two leaves landing centimetres apart must not all spin the same way --
## the same "banding" concern phase_for_position's own doc comment already
## raises for flutter/sway, now for spin direction too.
func test_spin_direction_for_phase_is_only_ever_plus_or_minus_one():
	for phase in [0.0, 0.5, 1.0, PI, PI * 1.5, TAU - 0.001]:
		var direction := LeafLitterRenderer.spin_direction_for_phase(phase)
		assert_true(direction == 1.0 or direction == -1.0, "got %f" % direction)


func test_spin_direction_for_phase_is_deterministic():
	assert_eq(
		LeafLitterRenderer.spin_direction_for_phase(1.23), LeafLitterRenderer.spin_direction_for_phase(1.23)
	)


func test_spin_direction_for_phase_takes_both_values_across_real_phases():
	var directions := {}
	for i in 20:
		var phase := LeafLitterRenderer.phase_for_position(Vector2(100.0 + i * 5.25, 200.0))
		directions[LeafLitterRenderer.spin_direction_for_phase(phase)] = true
	assert_eq(directions.size(), 2, "twenty real leaf phases should not all spin the same direction")


func test_tumble_rotation_is_zero_at_the_start_of_any_transition():
	for distance in [0.0, 50.0, LeafLitterRenderer.MAX_TRANSITION_OFFSET]:
		assert_almost_eq(LeafLitterRenderer.tumble_rotation(0.0, distance, 0.7), 0.0, 0.0001)


## UNLIKE transition_rotation (which decays back to zero, see the wobble test
## above), a real tumble does not un-spin itself -- it must reach its own
## full turn count by the time the transition completes, in the direction
## spin_direction_for_phase says this leaf spins.
func test_tumble_rotation_reaches_its_full_spin_once_the_transition_completes():
	var phase := 2.1
	var distance := LeafLitterRenderer.MAX_TRANSITION_OFFSET * 0.5
	var expected := (
		LeafLitterRenderer.tumble_turns_for_distance(distance) * TAU
		* LeafLitterRenderer.spin_direction_for_phase(phase)
	)
	assert_almost_eq(LeafLitterRenderer.tumble_rotation(1.0, distance, phase), expected, 0.0001)


func test_a_longer_journey_tumbles_more_than_a_shorter_one_at_the_same_progress():
	var phase := 0.9
	var short_spin := absf(LeafLitterRenderer.tumble_rotation(0.6, 20.0, phase))
	var long_spin := absf(
		LeafLitterRenderer.tumble_rotation(0.6, LeafLitterRenderer.MAX_TRANSITION_OFFSET, phase)
	)
	assert_gt(long_spin, short_spin)


## The ongoing ground sway once settled -- mirrors
## test_a_landed_leaf_keeps_swaying_gently: different moments must give
## different rotations, so a settled leaf visibly keeps rocking rather than
## freezing.
func test_settled_sway_rotation_changes_over_time():
	var a := LeafLitterRenderer.settled_sway_rotation(0.0, 0.5)
	var b := LeafLitterRenderer.settled_sway_rotation(0.25, 0.5)
	assert_ne(a, b)


func test_settled_sway_rotation_stays_within_its_own_amplitude():
	for fraction in [0.0, 0.1, 0.37, 0.6, 0.99]:
		var rotation: float = LeafLitterRenderer.settled_sway_rotation(fraction, 1.2)
		assert_lte(absf(rotation), LeafLitterRenderer.GROUND_SWAY_RADIANS + 0.0001)


## Two different positions must (almost always) get different phases, or
## every leaf in a dense patch would flutter/sway in lockstep -- the exact
## "banding" trap this project has hit repeatedly with anything derived from
## a naive input.
func test_phase_for_position_differs_across_nearby_leaves():
	var phases := {}
	for i in 20:
		var phase := LeafLitterRenderer.phase_for_position(Vector2(100.0 + i * 5.25, 200.0))
		phases[snappedf(phase, 0.05)] = true
	assert_gt(phases.size(), 10, "twenty nearby leaves collapsed into %d distinct phases" % phases.size())


func test_phase_for_position_is_deterministic():
	var p := Vector2(123.0, 456.0)
	assert_eq(LeafLitterRenderer.phase_for_position(p), LeafLitterRenderer.phase_for_position(p))


# -- swirl: a curling path, not a fixed-axis wobble --------------------------
#
# Reported directly: "the leaves and blossoms have a lot of left/right
# movements where they end up on the same place where they started and it
# doesn't look natural as it's a straight line ... move them a bit with a
# left right swirl / spiral motion or tumbles or so ... varying". The
# previous transition_flutter_world/perpendicular-axis-offset shape moved
# ALONG ONE FIXED AXIS (perpendicular to the straight-line travel direction)
# with an amplitude that decayed to exactly zero by landing -- which reads
# exactly as described: a straight line with a symmetric side-to-side
# wobble riding on top, always snapping back onto the line itself. A real
# leaf/petal spiralling down instead curls THROUGH both the direction-of-
# travel and perpendicular axes together, tracing a shrinking loop around
# its own straight-line path rather than oscillating along one fixed line.
#
# instance_swirl_offset replaces the old scalar flutter + single-axis
# offset with a genuine 2D curl, in the SAME (direction, perpendicular)
# basis the shader already computes -- see that function's own doc comment.

## Two different positions must (almost always) get different swirl seeds,
## independently of phase_for_position's own hash (different magic
## constants, deliberately) -- so a leaf's swirl shape (how many loops, how
## wide) varies independently of its flutter/tumble phase, the "varying"
## the report asks for.
func test_swirl_seed_for_position_differs_across_nearby_leaves():
	var seeds := {}
	for i in 20:
		var seed_value := LeafLitterRenderer.swirl_seed_for_position(Vector2(100.0 + i * 5.25, 200.0))
		seeds[snappedf(seed_value, 0.05)] = true
	assert_gt(seeds.size(), 10, "twenty nearby leaves collapsed into %d distinct swirl seeds" % seeds.size())


func test_swirl_seed_for_position_is_deterministic():
	var p := Vector2(321.0, 654.0)
	assert_eq(
		LeafLitterRenderer.swirl_seed_for_position(p), LeafLitterRenderer.swirl_seed_for_position(p)
	)


func test_swirl_turns_for_seed_is_minimum_at_seed_zero():
	assert_almost_eq(
		LeafLitterRenderer.swirl_turns_for_seed(0.0), LeafLitterRenderer.MIN_SWIRL_TURNS, 0.0001
	)


func test_swirl_turns_for_seed_is_maximum_at_seed_one():
	assert_almost_eq(
		LeafLitterRenderer.swirl_turns_for_seed(1.0), LeafLitterRenderer.MAX_SWIRL_TURNS, 0.0001
	)


## Different leaves must not all trace the SAME loop -- some wider/more
## turns than others, the concrete shape "varying" takes here.
func test_swirl_turns_for_seed_varies_across_real_seeds():
	var turns := {}
	for i in 20:
		var seed_value := LeafLitterRenderer.swirl_seed_for_position(Vector2(100.0 + i * 5.25, 200.0))
		turns[snappedf(LeafLitterRenderer.swirl_turns_for_seed(seed_value), 0.05)] = true
	assert_gt(turns.size(), 5, "twenty real leaves' swirl turn-counts collapsed into %d distinct values" % turns.size())


func test_swirl_radius_fraction_for_seed_stays_within_its_own_bounds():
	for seed_value in [0.0, 0.1, 0.37, 0.6, 0.99, 1.0]:
		var fraction: float = LeafLitterRenderer.swirl_radius_fraction_for_seed(seed_value)
		assert_gte(fraction, LeafLitterRenderer.MIN_SWIRL_RADIUS_FRACTION - 0.0001)
		assert_lte(fraction, LeafLitterRenderer.MAX_SWIRL_RADIUS_FRACTION + 0.0001)


## The radius fraction must vary independently of the turn count -- if the
## same raw seed drove both identically, every leaf that swirls WIDE would
## also always swirl with the SAME turn count, collapsing two supposedly
## independent axes of "varying" back into one.
func test_swirl_radius_fraction_is_not_simply_the_turns_fraction_restated():
	var differs := false
	for i in 20:
		var seed_value := LeafLitterRenderer.swirl_seed_for_position(Vector2(100.0 + i * 5.25, 200.0))
		var turns_fraction := (
			(LeafLitterRenderer.swirl_turns_for_seed(seed_value) - LeafLitterRenderer.MIN_SWIRL_TURNS)
			/ (LeafLitterRenderer.MAX_SWIRL_TURNS - LeafLitterRenderer.MIN_SWIRL_TURNS)
		)
		var radius_fraction := (
			(LeafLitterRenderer.swirl_radius_fraction_for_seed(seed_value) - LeafLitterRenderer.MIN_SWIRL_RADIUS_FRACTION)
			/ (LeafLitterRenderer.MAX_SWIRL_RADIUS_FRACTION - LeafLitterRenderer.MIN_SWIRL_RADIUS_FRACTION)
		)
		if absf(turns_fraction - radius_fraction) > 0.1:
			differs = true
	assert_true(differs, "turn-count and loop-width tracked each other in lockstep across 20 real leaves")


## THE core fix: unlike the old fixed-axis flutter (confined to the
## perpendicular axis alone), the swirl must actually move the leaf ALONG
## its own straight-line direction too, partway through -- proof this is a
## genuine 2D curl rather than the same one-axis wobble under a new name.
func test_swirl_offset_moves_along_the_direction_axis_too_not_only_perpendicular():
	var moved_along_direction := false
	for t in [0.1, 0.2, 0.4, 0.6, 0.8]:
		var offset := LeafLitterRenderer.instance_swirl_offset(t, 0.9, 0.5, Vector2.RIGHT, Vector2.UP)
		if absf(offset.x) > 0.01:
			moved_along_direction = true
	assert_true(
		moved_along_direction,
		"the swirl never displaced along the travel direction -- still a perpendicular-only wobble"
	)


## The swirl's own radius is a BUMP (zero at both ends, widest in the
## middle -- see instance_swirl_offset's own doc comment), not a one-sided
## decay from a nonzero start: a leaf's real transition_from IS its true
## starting point, so the swirl should not displace it away from that
## point at t==0 any more than it should leave it stranded off its real
## target at t==1.
func test_swirl_offset_is_zero_at_the_very_start_of_a_transition():
	for phase in [0.0, 1.3, 3.5]:
		for swirl_seed in [0.0, 0.5, 1.0]:
			var offset := LeafLitterRenderer.instance_swirl_offset(
				0.0, phase, swirl_seed, Vector2.RIGHT, Vector2.UP
			)
			assert_almost_eq(offset.length(), 0.0, 0.0001)


# -- pure data prep: position / atlas index / packed fall-start --------------

func test_instances_for_leaves_places_the_transform_at_the_leafs_position():
	var atlas := LeafLitterAtlas.new()
	var leaves: Array[Dictionary] = [{
		"position": Vector2(50.0, 60.0), "species": "cherry", "season": "autumn",
		"transition_from": Vector2(50.0, 20.0), "transition_start": 5.0,
	}]
	var instances := LeafLitterRenderer.instances_for_leaves(leaves, atlas, 0.0)
	assert_eq(instances.size(), 1)
	assert_eq(instances[0].transform.origin, Vector2(50.0, 60.0))


func test_instances_for_leaves_packs_the_right_atlas_cell():
	var atlas := LeafLitterAtlas.new()
	var leaves: Array[Dictionary] = [{
		"position": Vector2.ZERO, "species": "acorn", "season": "summer",
		"transition_from": Vector2.ZERO, "transition_start": 0.0,
	}]
	var instances := LeafLitterRenderer.instances_for_leaves(leaves, atlas, 0.0)
	var expected_index := atlas.cell_index("acorn", "summer")
	var custom: Color = instances[0].custom_data
	var packed_index: float = custom.r
	assert_eq(
		LeafLitterRenderer.unpack_cell_index(packed_index, atlas.cell_count()), expected_index
	)


func test_instances_for_leaves_packs_a_real_offset_for_an_unsettled_leaf():
	var atlas := LeafLitterAtlas.new()
	var leaves: Array[Dictionary] = [{
		"position": Vector2(50.0, 60.0), "species": "cherry", "season": "autumn",
		"transition_from": Vector2(50.0, 60.0 - LeafLitterField.FALL_HEIGHT), "transition_start": 0.0,
	}]
	var instances := LeafLitterRenderer.instances_for_leaves(leaves, atlas, 0.0)
	var custom: Color = instances[0].custom_data
	var offset_y := LeafLitterRenderer.unpack_offset_axis(custom.b)
	assert_almost_eq(offset_y, -LeafLitterField.FALL_HEIGHT, 3.0)


func test_instances_for_leaves_covers_every_leaf_given():
	var atlas := LeafLitterAtlas.new()
	var leaves: Array[Dictionary] = []
	for i in 5:
		leaves.append({
			"position": Vector2(i * 10.0, 0.0), "species": "cherry", "season": "autumn",
			"transition_from": Vector2(i * 10.0, 0.0), "transition_start": 0.0,
		})
	assert_eq(LeafLitterRenderer.instances_for_leaves(leaves, atlas, 0.0).size(), 5)


# -- housekeeping: mesh/material can be built headless (no MultiMesh fill) ---

func test_mesh_is_a_fixed_world_size_quad():
	var renderer := LeafLitterRenderer.new()
	var mesh := renderer.mesh()
	assert_almost_eq(mesh.size.x, LeafLitterRenderer.WORLD_SIZE, 0.001)
	assert_almost_eq(mesh.size.y, LeafLitterRenderer.WORLD_SIZE, 0.001)


## Reported directly: "leaves should be half as big" -- pins the real value
## (not just "the mesh uses whatever WORLD_SIZE is", which the test above
## already covers and would pass regardless of the constant's own value).
## Half of the previous 1.5x-walnut-width sizing, so 0.75x.
func test_world_size_is_half_its_previous_walnut_relative_size():
	assert_almost_eq(
		LeafLitterRenderer.WORLD_SIZE, ProceduralItemSprite.WALNUT_WORLD_WIDTH * 0.75, 0.001
	)


func test_material_is_a_shader_material_with_the_atlas_texture_assigned():
	var renderer := LeafLitterRenderer.new()
	var material := renderer.material()
	assert_true(material is ShaderMaterial)
	assert_not_null(material.get_shader_parameter("atlas_texture"))


func test_set_current_time_pushes_a_wrapped_fraction_uniform():
	var renderer := LeafLitterRenderer.new()
	renderer.set_current_time(12345.0)
	var pushed: float = renderer.material().get_shader_parameter("current_time_fraction")
	assert_almost_eq(pushed, LeafLitterRenderer.pack_time_fraction(12345.0), 0.0001)
