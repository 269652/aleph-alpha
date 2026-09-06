extends GutTest

## Biases an ant scout's own ambient wander heading toward a LOCALLY-sensed
## pheromone trail, when one exists -- real chemotaxis-style trail
## following (a scout sensing a gradient exactly where it currently stands),
## never omniscient knowledge of where a good source was previously found
## (see docs/concept/soil_fauna.md's "Scouting: real search, not omniscient
## dispatch"). Mirrors ThreatAvoidantWander's own shape exactly: a pure
## post-process on an already-computed candidate heading, so
## AmbientFlyerMovement itself (the shared, already hard-won wander
## primitive several OTHER species depend on) never needs touching for
## this one extra, ant-specific need.

const AntScoutWander = preload("res://src/gameplay/ant_scout_wander.gd")


func test_returns_the_wander_heading_unchanged_with_no_gradient():
	var wander := Vector2.RIGHT
	assert_eq(AntScoutWander.biased_heading(wander, Vector2.ZERO), wander)


func test_biases_toward_the_gradient_when_one_exists():
	var wander := Vector2.RIGHT
	var gradient := Vector2.UP
	var biased := AntScoutWander.biased_heading(wander, gradient)
	# Genuinely bent toward the gradient, not left untouched and not
	# replaced outright -- a real bias, not a hard override.
	assert_gt(biased.dot(gradient), wander.dot(gradient), "should turn measurably toward the sensed trail")
	assert_lt(biased.dot(gradient), gradient.dot(gradient), "should not simply BECOME the gradient direction")


func test_result_is_always_unit_length_with_a_gradient():
	var biased := AntScoutWander.biased_heading(Vector2(1, 1).normalized(), Vector2(0, -1))
	assert_almost_eq(biased.length(), 1.0, 0.0001)


func test_result_is_unit_length_even_when_wander_and_gradient_nearly_cancel():
	var biased := AntScoutWander.biased_heading(Vector2.RIGHT, Vector2.LEFT)
	assert_almost_eq(biased.length(), 1.0, 0.0001)


## Pinned, not an eyeballed literal buried in logic (see CLAUDE.md's own
## "tuned values must be tested" rule) -- a real, named design knob for how
## strongly a sensed trail overrides plain exploration once ANY trail is
## sensed at all. See the constant's own doc comment for the real-world
## framing (this is chemotaxis strength, not distance-scored recruitment).
func test_trail_bias_is_pinned():
	assert_eq(AntScoutWander.TRAIL_BIAS, 0.7)
