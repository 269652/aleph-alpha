extends GutTest

## Pure idle-flight motion for butterflies/songbirds (see
## docs/concept/ecosystem_dynamics.md's Species roster -- "ambient flyers").
## Same shape as CreatureWander's direction_at/step_position, but
## per-instance-configurable (speed/radius/interval) instead of fixed
## constants, so butterflies (flutter: fast interval, small radius, slow
## speed) and songbirds (glide: slower interval, larger radius, faster
## speed) share one tested algorithm instead of two near-duplicate ones.

const AmbientFlyerMovement = preload("res://src/rendering/ambient_flyer_movement.gd")

var flyer: AmbientFlyerMovement


func before_each():
	flyer = AmbientFlyerMovement.new(20.0, 40.0, 1.0)


func test_direction_is_a_unit_vector():
	var direction := flyer.direction_at(Vector2.ZERO, Vector2.ZERO, 0.0, 42)
	assert_almost_eq(direction.length(), 1.0, 0.001)


func test_direction_is_deterministic_for_the_same_inputs():
	var first := flyer.direction_at(Vector2(10, 10), Vector2(12, 8), 3.5, 7)
	var second := flyer.direction_at(Vector2(10, 10), Vector2(12, 8), 3.5, 7)
	assert_eq(first, second)


func test_direction_changes_between_distinct_seeds():
	var a := flyer.direction_at(Vector2.ZERO, Vector2.ZERO, 0.0, 1)
	var b := flyer.direction_at(Vector2.ZERO, Vector2.ZERO, 0.0, 2)
	assert_ne(a, b)


func test_direction_is_stable_within_one_change_interval():
	var early := flyer.direction_at(Vector2.ZERO, Vector2.ZERO, 0.1, 7)
	var late := flyer.direction_at(Vector2.ZERO, Vector2.ZERO, flyer.direction_change_interval - 0.1, 7)
	assert_eq(early, late)


func test_direction_biases_back_toward_home_once_far_enough_away():
	var home := Vector2.ZERO
	var far_away := Vector2(flyer.radius * 3, 0)
	var direction := flyer.direction_at(home, far_away, 0.0, 7)
	assert_lt(direction.x, 0.0)


func test_step_position_moves_by_speed_times_delta():
	var home := Vector2.ZERO
	var current := Vector2.ZERO
	var next := flyer.step_position(home, current, 0.0, 1.0, 7)
	assert_almost_eq(next.distance_to(current), flyer.speed, 0.001)


func test_step_position_never_strands_far_beyond_the_radius():
	var home := Vector2.ZERO
	var current := Vector2.ZERO
	var elapsed := 0.0
	for i in 200:
		current = flyer.step_position(home, current, elapsed, 0.5, 7)
		elapsed += 0.5
	assert_lt(current.distance_to(home), flyer.radius * 2.0)


## The actual point of making this configurable: two differently-tuned
## instances (butterfly-flutter vs songbird-glide) produce different motion
## from the identical inputs.
func test_different_instances_move_at_their_own_configured_speed():
	var butterfly := AmbientFlyerMovement.new(10.0, 20.0, 0.4)
	var songbird := AmbientFlyerMovement.new(30.0, 70.0, 2.0)
	var butterfly_next := butterfly.step_position(Vector2.ZERO, Vector2.ZERO, 0.0, 1.0, 7)
	var songbird_next := songbird.step_position(Vector2.ZERO, Vector2.ZERO, 0.0, 1.0, 7)
	assert_almost_eq(butterfly_next.distance_to(Vector2.ZERO), 10.0, 0.001)
	assert_almost_eq(songbird_next.distance_to(Vector2.ZERO), 30.0, 0.001)


## The same continuity property CreatureWander.direction_at earned the hard
## way (see its doc comment): the old hard "past the radius? head straight
## home" switch is a frame-rate limit cycle for anything parked ON the
## boundary -- outward roam, snap home, back inside, outward roam again --
## which is exactly the erratic flicker reported for birds at obstacles
## ("Boars and Birds now also get stuck, flicker and flip erratically").
## A hair either side of the radius must give nearly the same heading.
func test_direction_is_continuous_across_the_home_radius_boundary():
	var home := Vector2.ZERO
	var inside := flyer.direction_at(home, Vector2(flyer.radius - 0.5, 0), 0.0, 7)
	var outside := flyer.direction_at(home, Vector2(flyer.radius + 0.5, 0), 0.0, 7)
	assert_gt(
		inside.dot(outside),
		0.9,
		"crossing the radius should not abruptly reverse the heading"
	)


## And the ease must complete: far past the radius the flyer heads straight
## home, so it still genuinely comes back rather than drifting off forever.
func test_direction_points_fully_home_once_well_past_the_radius():
	var home := Vector2.ZERO
	var far := flyer.radius * AmbientFlyerMovement.HOME_PULL_FULL_RADIUS_FACTOR
	var direction := flyer.direction_at(home, Vector2(far, 0), 0.0, 7)
	assert_almost_eq(direction.x, -1.0, 0.01)
