extends GutTest

## Pure hip/knee gait-angle math (see src/rendering/leg_gait_cycle.gd) --
## replaces the old sin-BOB (a vertical offset, no joint at all) and
## FUSED_LEG_ROCK_AMPLITUDE (one whole-pair RIGID rotation, no knee) walk
## placeholders with a real, named, tested function of gait-cycle phase that
## produces a hip angle AND a knee angle (reported live: "add proper walk
## animation by morphing the leg sprites and include a knee joint animated
## motion").
##
## Phase convention (see the source file's own doc comment): phase=0 is the
## leg fully forward, about to plant (heel strike); stance (foot planted,
## sweeping back under the body) is phase in [0, PI]; swing (foot in the
## air, recovering forward) is phase in [PI, 2*PI].

const LegGaitCycle = preload("res://src/rendering/leg_gait_cycle.gd")

var gait: LegGaitCycle


func before_each():
	gait = LegGaitCycle.new()


# -- hip angle: a plain sine, full amplitude at the stance/swing boundary --

func test_hip_angle_is_maximally_forward_at_phase_zero():
	assert_almost_eq(gait.hip_angle(0.0), LegGaitCycle.HIP_SWING_AMPLITUDE, 0.0001)


func test_hip_angle_is_maximally_trailing_at_half_a_cycle():
	assert_almost_eq(gait.hip_angle(PI), -LegGaitCycle.HIP_SWING_AMPLITUDE, 0.0001)


func test_hip_angle_is_zero_a_quarter_cycle_in_either_direction():
	assert_almost_eq(gait.hip_angle(PI / 2.0), 0.0, 0.0001)
	assert_almost_eq(gait.hip_angle(3.0 * PI / 2.0), 0.0, 0.0001)


func test_hip_angle_repeats_every_full_cycle():
	assert_almost_eq(gait.hip_angle(0.4), gait.hip_angle(0.4 + 2.0 * PI), 0.0001)


# -- knee angle: rectified, flexion-only, peaking at mid-swing --------------

func test_knee_angle_is_never_negative_across_a_full_cycle():
	var phase := 0.0
	while phase < 2.0 * PI:
		assert_true(gait.knee_angle(phase) >= 0.0, "phase %.2f" % phase)
		phase += 0.1


func test_knee_stays_straight_through_stance():
	# Stance is phase in [0, PI] -- the planted leg should not be bending.
	for phase in [0.0, PI / 4.0, PI / 2.0, 3.0 * PI / 4.0, PI]:
		assert_almost_eq(gait.knee_angle(phase), 0.0, 0.0001, "phase %.2f" % phase)


func test_knee_bend_peaks_at_mid_swing():
	# Mid-swing (phase = 3*PI/2) is where the leg is vertical again but now
	# swinging forward through the air -- maximum ground clearance is needed
	# there, so this is the real peak, not an eyeballed one.
	assert_almost_eq(gait.knee_angle(3.0 * PI / 2.0), LegGaitCycle.KNEE_BEND_AMPLITUDE, 0.0001)


func test_knee_bend_is_partway_bent_between_stance_end_and_mid_swing():
	var bend := gait.knee_angle(PI + PI / 4.0)
	assert_true(bend > 0.0 and bend < LegGaitCycle.KNEE_BEND_AMPLITUDE)


func test_knee_angle_repeats_every_full_cycle():
	assert_almost_eq(gait.knee_angle(4.5), gait.knee_angle(4.5 + 2.0 * PI), 0.0001)
