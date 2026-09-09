extends GutTest

## FootstepGait: real per-step footfall detection -- alternates left/right
## exactly like a real walking gait, driven by ACTUAL distance travelled
## (not a fixed per-frame or per-tile-entry event, unlike PathScarring/
## SnowTrail's own tile-entry debounce). Reported live: "real footstep
## prints with left/right footprints spaced apart". Mirrors
## CreatureMarker._gait_distance's own "accumulate real travelled distance,
## threshold it" shape, generalized from an animation-frame index into a
## discrete, real world event: "plant a foot here, alternate which one."

const FootstepGait = preload("res://src/gameplay/footstep_gait.gd")
const GroundSlide = preload("res://src/gameplay/ground_slide.gd")

var gait: FootstepGait


func before_each():
	gait = FootstepGait.new()


func test_no_step_before_the_stride_length_is_covered():
	assert_eq(gait.step_if_due(FootstepGait.STRIDE_LENGTH_PX * 0.5), "")


func test_a_step_fires_once_the_stride_length_is_covered():
	var side := gait.step_if_due(FootstepGait.STRIDE_LENGTH_PX)
	assert_true(side == "left" or side == "right", "a real step should fire exactly at the stride length")


## A real gait alternates every single step -- never the same foot twice
## in a row.
func test_steps_alternate_left_and_right():
	var first := gait.step_if_due(FootstepGait.STRIDE_LENGTH_PX)
	var second := gait.step_if_due(FootstepGait.STRIDE_LENGTH_PX)
	assert_ne(first, second)
	assert_true(first == "left" or first == "right")
	assert_true(second == "left" or second == "right")


func test_a_third_step_returns_to_the_first_foot():
	var first := gait.step_if_due(FootstepGait.STRIDE_LENGTH_PX)
	gait.step_if_due(FootstepGait.STRIDE_LENGTH_PX)
	var third := gait.step_if_due(FootstepGait.STRIDE_LENGTH_PX)
	assert_eq(third, first)


## The remainder carries forward rather than resetting to zero -- covering
## the stride length across several small calls (matching how this is
## actually driven, once per physics frame with a small per-frame delta)
## must fire a step at the same total distance as one big call would.
func test_the_remainder_carries_forward_across_many_small_calls():
	var half := FootstepGait.STRIDE_LENGTH_PX / 2.0
	assert_eq(gait.step_if_due(half), "")
	var side := gait.step_if_due(half)
	assert_true(side == "left" or side == "right")


## Real, grounded human-scale measurement (see GroundSlide.PX_PER_METER),
## not an eyeballed pixel count -- pinned per CLAUDE.md's own "tuned
## values must be tested" rule.
func test_stride_length_is_derived_from_a_real_meter_measurement_not_eyeballed():
	var expected := FootstepGait.STRIDE_LENGTH_METERS * GroundSlide.PX_PER_METER
	assert_almost_eq(FootstepGait.STRIDE_LENGTH_PX, expected, 0.01)


# -- placement: a perpendicular offset from the walked line, spaced apart
# like a real gait's stance width -----------------------------------------

func test_left_and_right_offsets_are_on_opposite_sides_of_the_heading():
	var heading := Vector2(1, 0)
	var left_offset := FootstepGait.print_offset(heading, "left")
	var right_offset := FootstepGait.print_offset(heading, "right")
	assert_almost_eq(left_offset.x, -right_offset.x, 0.01)
	assert_almost_eq(left_offset.y, -right_offset.y, 0.01)


func test_offsets_are_perpendicular_to_the_heading_not_along_it():
	var heading := Vector2(1, 0)
	var offset := FootstepGait.print_offset(heading, "left")
	assert_almost_eq(offset.x, 0.0, 0.01, "moving straight along +x should offset sideways in y, not forward")
	assert_gt(absf(offset.y), 0.0)


func test_stance_width_is_derived_from_a_real_meter_measurement_not_eyeballed():
	var expected := FootstepGait.STANCE_WIDTH_METERS * GroundSlide.PX_PER_METER
	assert_almost_eq(FootstepGait.STANCE_WIDTH_PX, expected, 0.01)


func test_print_offset_falls_back_to_a_stable_direction_for_a_zero_heading():
	# A player who hasn't actually established a heading yet (e.g. spawned
	# standing still) must not crash or produce NaN/garbage.
	var offset := FootstepGait.print_offset(Vector2.ZERO, "left")
	assert_false(is_nan(offset.x))
	assert_false(is_nan(offset.y))


# -- step_at: the SAME per-walker state, but now owning its own last-known -
# -- position and teleport detection internally too -- makes ONE ----------
# -- FootstepGait instance the WHOLE per-walker footstep record (see this -
# -- file's own header doc comment: "one FootstepGait per walker"),  ------
# -- rather than needing a second, external position tracker the way ------
# -- EarthChunkManager used to keep alongside its own _player_footstep_ ---
# -- gait. Lets a CreatureMarker own a single lazily-built FootstepGait ---
# -- the same way it already owns a lazily-built Metabolism for mass. -----

const TELEPORT_GAP_PX := 200.0


func test_step_at_the_first_call_establishes_a_baseline_and_places_no_step():
	assert_eq(gait.step_at(Vector2.ZERO, TELEPORT_GAP_PX), "")


## Mirrors test_earth_chunk_manager_footprints.gd's own "+ 1.0" margin on
## every stride-length position delta below -- distance here is computed
## via a real Vector2.distance_to() (a sqrt), which does not bit-exactly
## invert squaring the way passing STRIDE_LENGTH_PX straight into
## step_if_due (see that function's own tests above) does -- landing
## exactly ON the boundary can round a hair under it, the real reason
## every position-based test below clears the stride by a real margin
## instead of stopping exactly at it.
func test_step_at_fires_once_the_stride_length_is_covered():
	gait.step_at(Vector2.ZERO, TELEPORT_GAP_PX)
	var side := gait.step_at(Vector2(FootstepGait.STRIDE_LENGTH_PX + 1.0, 0), TELEPORT_GAP_PX)
	assert_true(side == "left" or side == "right")


func test_step_at_alternates_left_and_right_across_real_calls():
	gait.step_at(Vector2.ZERO, TELEPORT_GAP_PX)
	var first := gait.step_at(Vector2(FootstepGait.STRIDE_LENGTH_PX + 1.0, 0), TELEPORT_GAP_PX)
	var second := gait.step_at(Vector2(FootstepGait.STRIDE_LENGTH_PX * 2.0 + 2.0, 0), TELEPORT_GAP_PX)
	assert_ne(first, second)


func test_step_at_treats_a_huge_jump_as_a_teleport_not_a_stride():
	gait.step_at(Vector2.ZERO, TELEPORT_GAP_PX)
	var side := gait.step_at(Vector2(TELEPORT_GAP_PX + 50.0, 0), TELEPORT_GAP_PX)
	assert_eq(side, "", "a teleport must not fire a stray step bridging the gap")


## Mirrors EarthChunkManager.record_footstep's own pre-refactor behavior
## exactly (a teleport used to replace the whole _player_footstep_gait
## object with FootstepGait.new()) -- the next real step after a teleport
## should read as a fresh gait's own first step, not an alternation
## carried over from before the jump.
func test_step_at_resets_the_stride_alternation_after_a_teleport():
	gait.step_at(Vector2.ZERO, TELEPORT_GAP_PX)
	gait.step_at(Vector2(FootstepGait.STRIDE_LENGTH_PX + 1.0, 0), TELEPORT_GAP_PX)  # a real step -> consumes "left"
	var jump_target := Vector2(FootstepGait.STRIDE_LENGTH_PX + TELEPORT_GAP_PX + 50.0, 0)
	gait.step_at(jump_target, TELEPORT_GAP_PX)  # the teleport itself
	var after_teleport := gait.step_at(
		jump_target + Vector2(FootstepGait.STRIDE_LENGTH_PX + 1.0, 0), TELEPORT_GAP_PX
	)
	assert_eq(after_teleport, "left", "a teleport should restart the alternation, matching a fresh FootstepGait")


func test_step_at_before_any_call_never_crashes_on_a_huge_position():
	assert_eq(gait.step_at(Vector2(999999999, 999999999), TELEPORT_GAP_PX), "")
