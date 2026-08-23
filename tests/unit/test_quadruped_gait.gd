extends GutTest

## QuadrupedGait: two-bone (hip + knee) walk-cycle pose driving
## ProceduralAnimalSprite's legs (see docs/concept/pixel_art_engine.md).
##
## Animals used to "walk" by shifting the leg-shaped PIXELS of one static
## image sideways -- there was no joint to move, which is why a horse never
## read as walking like a horse. This is pure trig, testable without an
## Image: the hip swings forward/back through the gait cycle, the knee bends
## only during the forward (lifted) half of the swing, and diagonal leg
## pairs move together the way a real quadruped's do.

const QuadrupedGait = preload("res://src/rendering/quadruped_gait.gd")


## sin(0) and sin(pi) are both zero, so every leg -- whichever diagonal pair
## it's in -- passes through neutral (straight down) at the start of the
## cycle. That's the pose a static/non-animated context should render.
func test_every_leg_is_neutral_at_the_start_of_the_cycle():
	for leg in QuadrupedGait.LEG_PHASE:
		assert_almost_eq(QuadrupedGait.hip_angle(leg, 0.0), 0.0, 0.01, leg)


## Diagonal pairs (front-left+back-right, front-right+back-left) must move
## TOGETHER -- the walk/trot pattern real quadrupeds use, not four legs in
## lockstep or a random assortment.
func test_diagonal_leg_pairs_share_a_phase():
	for phase in [0.1, 0.4, 0.77]:
		assert_almost_eq(
			QuadrupedGait.hip_angle("front_left", phase), QuadrupedGait.hip_angle("back_right", phase), 0.001
		)
		assert_almost_eq(
			QuadrupedGait.hip_angle("front_right", phase), QuadrupedGait.hip_angle("back_left", phase), 0.001
		)


## ...and the two diagonal pairs must be OPPOSITE each other, or all four
## legs still move as one lockstepped block.
func test_the_two_diagonal_pairs_are_out_of_phase():
	for phase in [0.05, 0.3, 0.6, 0.9]:
		var pair_a := QuadrupedGait.hip_angle("front_left", phase)
		var pair_b := QuadrupedGait.hip_angle("front_right", phase)
		assert_almost_eq(pair_a, -pair_b, 0.001, "opposite diagonal pairs should swing oppositely")


func test_hip_swing_stays_within_stride_amplitude():
	for leg in QuadrupedGait.LEG_PHASE:
		for i in 20:
			var phase := float(i) / 20.0
			assert_between(
				QuadrupedGait.hip_angle(leg, phase), -QuadrupedGait.STRIDE_AMPLITUDE, QuadrupedGait.STRIDE_AMPLITUDE
			)


## A planted/trailing leg (bearing weight, pushing back) must stay straight --
## bending it too would read as limping on every step, not walking.
func test_the_knee_stays_straight_while_planted_and_pushing_back():
	assert_almost_eq(QuadrupedGait.knee_bend("front_left", 0.75), 0.0, 0.01)


## The knee only bends during the forward swing, when the foot is lifted
## clear of the ground -- otherwise it would drag through the floor.
func test_the_knee_bends_during_the_forward_swing():
	assert_gt(QuadrupedGait.knee_bend("front_left", 0.25), 0.0)


func test_knee_bend_is_never_negative():
	for i in 20:
		assert_gte(QuadrupedGait.knee_bend("back_right", float(i) / 20.0), 0.0)


func test_the_cycle_wraps_seamlessly():
	assert_almost_eq(QuadrupedGait.hip_angle("front_left", 0.0), QuadrupedGait.hip_angle("front_left", 1.0), 0.001)


func test_gait_is_deterministic():
	assert_eq(QuadrupedGait.hip_angle("back_left", 0.33), QuadrupedGait.hip_angle("back_left", 0.33))


func test_an_unknown_leg_name_does_not_crash():
	assert_eq(QuadrupedGait.hip_angle("tail", 0.5), QuadrupedGait.hip_angle("front_left", 0.5))
