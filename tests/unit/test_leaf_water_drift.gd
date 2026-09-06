extends GutTest

## Pure motion math for a leaf/blossom floating on a river (see docs/concept/
## leaf_litter.md's "Floating on water" section). LeafLitterField.advance()
## calls this every frame for an on-water leaf.

const LeafWaterDrift = preload("res://src/world/leaf_water_drift.gd")
const RiverFlowShader = preload("res://src/rendering/river_flow_shader.gd")


# -- velocity_px_s: current is the dominant term -----------------------------

func test_current_alone_moves_the_leaf_downstream_at_the_waters_own_speed():
	var velocity := LeafWaterDrift.velocity_px_s(
		Vector2.RIGHT, 0.6, Vector2.ZERO, 0.0, PackedVector2Array(), Vector2.ZERO
	)
	assert_eq(velocity, Vector2.RIGHT * RiverFlowShader.surface_px_per_s(0.6))


func test_zero_current_speed_with_no_wind_or_waders_gives_zero_velocity():
	var velocity := LeafWaterDrift.velocity_px_s(
		Vector2.RIGHT, 0.0, Vector2.ZERO, 0.0, PackedVector2Array(), Vector2.ZERO
	)
	assert_eq(velocity, Vector2.ZERO)


func test_current_direction_is_respected_not_just_its_speed():
	var velocity := LeafWaterDrift.velocity_px_s(
		Vector2.DOWN, 0.6, Vector2.ZERO, 0.0, PackedVector2Array(), Vector2.ZERO
	)
	assert_eq(velocity, Vector2.DOWN * RiverFlowShader.surface_px_per_s(0.6))


# -- wind: damped, and clearly secondary to the current ----------------------

func test_a_full_gale_never_outweighs_the_same_frame_current():
	var current_speed := 0.6
	var velocity := LeafWaterDrift.velocity_px_s(
		Vector2.RIGHT, current_speed, Vector2.RIGHT, 1.0, PackedVector2Array(), Vector2.ZERO
	)
	var current_only := RiverFlowShader.surface_px_per_s(current_speed)
	# Wind adds on top (same direction here), but by less than the current
	# contributed alone -- "less affected by wind" means secondary, not zero.
	assert_gt(velocity.x, current_only)
	assert_lt(velocity.x - current_only, current_only)


func test_wind_at_zero_strength_contributes_nothing():
	var with_zero_wind := LeafWaterDrift.velocity_px_s(
		Vector2.RIGHT, 0.6, Vector2.UP, 0.0, PackedVector2Array(), Vector2.ZERO
	)
	var current_only := RiverFlowShader.surface_px_per_s(0.6)
	assert_eq(with_zero_wind, Vector2.RIGHT * current_only)


func test_wind_push_is_exactly_the_damping_fraction_of_the_local_current_speed():
	var current_speed := 0.6
	var full_gale_along_current := LeafWaterDrift.velocity_px_s(
		Vector2.RIGHT, current_speed, Vector2.RIGHT, 1.0, PackedVector2Array(), Vector2.ZERO
	)
	var current_only := RiverFlowShader.surface_px_per_s(current_speed)
	var wind_contribution := full_gale_along_current.x - current_only
	assert_almost_eq(wind_contribution, current_only * LeafWaterDrift.WATER_WIND_DAMPING, 0.001)


func test_wind_can_partially_oppose_the_current():
	var current_speed := 0.6
	var opposed := LeafWaterDrift.velocity_px_s(
		Vector2.RIGHT, current_speed, Vector2.LEFT, 1.0, PackedVector2Array(), Vector2.ZERO
	)
	var current_only := RiverFlowShader.surface_px_per_s(current_speed)
	assert_lt(opposed.x, current_only)
	assert_gt(opposed.x, 0.0, "even a full gale upstream must not overpower the current -- see WATER_WIND_DAMPING")


# -- turbulence: nearby waders/fish push a floating leaf sideways -----------

func test_no_waders_means_no_turbulence():
	var push := LeafWaterDrift.turbulence_velocity_px_s(Vector2.ZERO, PackedVector2Array(), Vector2.RIGHT)
	assert_eq(push, Vector2.ZERO)


func test_a_wader_directly_on_the_stagnation_line_pushes_the_leaf_sideways():
	var wader_position := Vector2(0.0, 0.0)
	var leaf_position := Vector2(0.0, 5.0)  # lateral offset only, no along-flow component
	var push := LeafWaterDrift.turbulence_velocity_px_s(
		leaf_position, PackedVector2Array([wader_position]), Vector2.RIGHT
	)
	assert_gt(push.length(), 0.0, "a leaf right beside a wader should feel real turbulence")


func test_a_wader_far_outside_the_reach_has_no_effect():
	var wader_position := Vector2(0.0, 0.0)
	var leaf_position := Vector2(0.0, RiverFlowShader.WADER_REACH_PX * 10.0)
	var push := LeafWaterDrift.turbulence_velocity_px_s(
		leaf_position, PackedVector2Array([wader_position]), Vector2.RIGHT
	)
	assert_eq(push, Vector2.ZERO)


func test_turbulence_from_two_waders_on_opposite_sides_partially_cancels():
	var leaf_position := Vector2.ZERO
	var one_sided := LeafWaterDrift.turbulence_velocity_px_s(
		leaf_position, PackedVector2Array([Vector2(0.0, 5.0)]), Vector2.RIGHT
	)
	var both_sides := LeafWaterDrift.turbulence_velocity_px_s(
		leaf_position, PackedVector2Array([Vector2(0.0, 5.0), Vector2(0.0, -5.0)]), Vector2.RIGHT
	)
	assert_lt(both_sides.length(), one_sided.length())


func test_zero_flow_direction_yields_no_turbulence_rather_than_dividing_by_zero():
	var push := LeafWaterDrift.turbulence_velocity_px_s(
		Vector2.ZERO, PackedVector2Array([Vector2(1.0, 1.0)]), Vector2.ZERO
	)
	assert_eq(push, Vector2.ZERO)


func test_turbulence_matches_the_rivers_own_wader_obstacle_math_directly():
	# The whole point: a leaf's wobble near a wader must visually agree with
	# how the current-line art already bends there (see this file's own doc
	# comment) -- so this pins the reuse itself, not just "some nonzero push".
	var flow_dir := Vector2.RIGHT
	var perp := Vector2(-flow_dir.y, flow_dir.x)
	var wader_position := Vector2(20.0, 20.0)
	var leaf_position := Vector2(25.0, 25.0)
	var offset := leaf_position - wader_position
	var expected_shift := RiverFlowShader.obstacle_lateral_shift_px(
		offset, perp, RiverFlowShader.WADER_RADIUS_PX, RiverFlowShader.WADER_REACH_PX, RiverFlowShader.WADER_WAKE_TRAIL
	)
	var push := LeafWaterDrift.turbulence_velocity_px_s(
		leaf_position, PackedVector2Array([wader_position]), flow_dir
	)
	assert_eq(push, perp * expected_shift)


func test_velocity_px_s_includes_turbulence_from_waders_too():
	var wader_position := Vector2(5.0, 0.0)
	var leaf_position := Vector2(5.0, 5.0)
	var velocity := LeafWaterDrift.velocity_px_s(
		Vector2.RIGHT, 0.6, Vector2.ZERO, 0.0, PackedVector2Array([wader_position]), leaf_position
	)
	var current_only := Vector2.RIGHT * RiverFlowShader.surface_px_per_s(0.6)
	assert_ne(velocity, current_only, "a nearby wader should perturb the pure-current velocity")
