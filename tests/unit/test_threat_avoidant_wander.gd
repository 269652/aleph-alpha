extends GutTest

## ThreatAvoidantWander (see docs -- the geometric fix replacing a timer-based
## flee commit for "an animal wanders back toward a stationary threat and
## re-triggers fleeing forever").

const ThreatAvoidantWander = preload("res://src/gameplay/threat_avoidant_wander.gd")


func test_a_step_straight_toward_the_threat_is_cancelled_to_sideways():
	var biased := ThreatAvoidantWander.away_biased_step(Vector2(10, 0), Vector2(50, 0))
	assert_almost_eq(biased.x, 0.0, 0.01, "no component should remain toward the threat")
	assert_gt(biased.length(), 0.0, "must still move, not freeze")


func test_a_step_directly_away_is_unchanged():
	var away := Vector2(-10, 0)
	assert_eq(ThreatAvoidantWander.away_biased_step(away, Vector2(50, 0)), away)


## The core geometric claim: sideways motion (perpendicular to the threat
## axis) survives untouched -- an animal can skirt past a threat, not just
## retreat directly from it.
func test_a_purely_sideways_step_is_unchanged():
	var sideways := Vector2(0, 10)
	assert_eq(ThreatAvoidantWander.away_biased_step(sideways, Vector2(50, 0)), sideways)


## A diagonal step keeps its sideways part but loses the inward part.
func test_a_diagonal_step_keeps_only_its_sideways_component():
	var biased := ThreatAvoidantWander.away_biased_step(Vector2(10, 10), Vector2(50, 0))
	assert_lte(biased.x, 0.01, "the toward-threat component must be gone")
	assert_almost_eq(biased.y, 10.0, 0.01, "the sideways component must survive")


func test_no_threat_leaves_the_step_untouched():
	var step := Vector2(10, 5)
	assert_eq(ThreatAvoidantWander.away_biased_step(step, Vector2.ZERO), step)


## Never returns a dead-zero vector for a nonzero step -- an animal must
## still visibly move even when its wander target happens to be right on
## the threat's own position.
func test_a_step_aimed_dead_on_at_the_threat_still_produces_motion():
	var biased := ThreatAvoidantWander.away_biased_step(Vector2(10, 0), Vector2(30, 0))
	assert_gt(biased.length(), 0.0)


## THE point: bias never leaves a net closing velocity toward the threat.
func test_the_biased_step_never_gains_ground_toward_the_threat():
	var to_threat := Vector2(20, 40)
	for angle_degrees in range(0, 360, 15):
		var raw := Vector2.RIGHT.rotated(deg_to_rad(angle_degrees)) * 12.0
		var biased := ThreatAvoidantWander.away_biased_step(raw, to_threat)
		var closing := biased.dot(to_threat.normalized())
		assert_lte(closing, 0.01, "angle %d should never close distance" % angle_degrees)
