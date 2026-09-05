extends GutTest

## Red-first spec for bottled_creature_wander.gd (docs/concept/capture_dsl.md's
## "Rendering a bottled catch"): a live creature's position/animation state
## confined to a small container, deliberately much simpler than
## AmbientFlyerMarker's open-world state machine (no courtship, no
## nectaring, no perched-bird logic -- nothing in a sealed bottle forages or
## courts). Two states only, alternating on a deterministic hash-seeded
## timer, the same "no RNG held anywhere" discipline every other
## per-individual timing in this codebase already holds to.

const BottledCreatureWander = preload("res://src/gameplay/bottled_creature_wander.gd")

const BOUNDS := Rect2(Vector2(-10, -10), Vector2(20, 20))


func test_position_always_stays_within_the_given_bounds():
	for t in range(0, 400):
		var elapsed := float(t) * 0.1
		var pos: Vector2 = BottledCreatureWander.position_in(BOUNDS, elapsed, 42)
		assert_true(BOUNDS.has_point(pos), "position %s escaped bounds %s at t=%f" % [pos, BOUNDS, elapsed])


func test_position_is_deterministic_for_the_same_inputs():
	var a: Vector2 = BottledCreatureWander.position_in(BOUNDS, 12.34, 7)
	var b: Vector2 = BottledCreatureWander.position_in(BOUNDS, 12.34, 7)
	assert_eq(a, b)


func test_different_seeds_eventually_diverge():
	var any_different := false
	for t in range(0, 100):
		var elapsed := float(t) * 0.3
		var a: Vector2 = BottledCreatureWander.position_in(BOUNDS, elapsed, 1)
		var b: Vector2 = BottledCreatureWander.position_in(BOUNDS, elapsed, 2)
		if a != b:
			any_different = true
	assert_true(any_different, "two different seeds should not trace the identical path")


func test_is_resting_is_sometimes_true_and_sometimes_false_over_time():
	var saw_resting := false
	var saw_flying := false
	for t in range(0, 400):
		var elapsed := float(t) * 0.1
		if BottledCreatureWander.is_resting(elapsed, 5):
			saw_resting = true
		else:
			saw_flying = true
	assert_true(saw_resting, "should rest sometimes")
	assert_true(saw_flying, "should fly sometimes")


## Position must not pop at a fly<->rest transition: sampled just before and
## just after any state change, the two positions should be nearly the same
## (see the module's own doc comment on why "to" of one leg equals "from" of
## the next).
func test_position_is_continuous_across_a_fly_rest_transition():
	var seed_value := 99
	var was_resting: bool = BottledCreatureWander.is_resting(0.0, seed_value)
	var previous_pos: Vector2 = BottledCreatureWander.position_in(BOUNDS, 0.0, seed_value)
	var step := 0.02
	var t := step
	while t < 60.0:
		var resting: bool = BottledCreatureWander.is_resting(t, seed_value)
		var pos: Vector2 = BottledCreatureWander.position_in(BOUNDS, t, seed_value)
		if resting != was_resting:
			assert_lt(
				previous_pos.distance_to(pos), 1.0,
				"position jumped %f at a state transition (t=%f)" % [previous_pos.distance_to(pos), t]
			)
		was_resting = resting
		previous_pos = pos
		t += step
