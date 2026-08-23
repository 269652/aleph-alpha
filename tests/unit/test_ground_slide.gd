extends GutTest

## Shared real kinematics for "how far does a stone slide after leaving the
## ground/hand at some velocity, under kinetic friction" -- used by BOTH Kick
## (a foot's delivered momentum) and the held-item throw (a deliberate arm
## throw), so both read the SAME real physical constants rather than
## duplicating gravity/friction independently.

const GroundSlide = preload("res://src/gameplay/ground_slide.gd")


func test_zero_velocity_travels_no_distance():
	assert_almost_eq(GroundSlide.distance_px(0.0, 100.0), 0.0, 0.001)


func test_negative_velocity_travels_no_distance():
	assert_almost_eq(GroundSlide.distance_px(-5.0, 100.0), 0.0, 0.001)


## Pins the exact real kinematics formula (d = v^2 / (2 * mu * g), the
## standard sliding-stopping-distance equation under constant kinetic
## friction) so the constants and the formula can't silently drift apart.
func test_distance_matches_the_kinematics_formula_below_the_cap():
	var velocity_mps := 2.0
	var distance_m := (velocity_mps * velocity_mps) / (2.0 * GroundSlide.GROUND_FRICTION_COEFFICIENT * GroundSlide.GRAVITY_MPS2)
	var expected_px := distance_m * GroundSlide.PX_PER_METER
	assert_almost_eq(GroundSlide.distance_px(velocity_mps, 10000.0), expected_px, 0.01)


func test_distance_never_exceeds_the_given_cap():
	assert_lte(GroundSlide.distance_px(1000.0, 50.0), 50.0)


func test_distance_never_negative():
	assert_gte(GroundSlide.distance_px(0.001, 50.0), 0.0)


func test_higher_velocity_travels_further_below_the_cap():
	assert_gt(GroundSlide.distance_px(3.0, 10000.0), GroundSlide.distance_px(1.0, 10000.0))
