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


## Windows are now phase-shifted per seed (see _phase_offset -- fixing
## "all birds on the screen reverse direction at the exact same time"
## means no two seeds' windows can both start at exactly elapsed_time=0
## any more), so this scans forward for a real boundary crossing instead
## of assuming one sits at exactly direction_change_interval. Same claim
## as before: stable within one window, just measured from wherever this
## seed's own window actually starts.
func test_direction_is_stable_within_one_change_interval():
	var seed_value := 7
	var first := flyer.direction_at(Vector2.ZERO, Vector2.ZERO, 0.0, seed_value)
	var boundary := 0.0
	var t := 0.0
	while t < flyer.direction_change_interval * 2.0:
		t += 0.01
		if flyer.direction_at(Vector2.ZERO, Vector2.ZERO, t, seed_value) != first:
			boundary = t
			break
	assert_gt(boundary, 0.0, "precondition: a boundary crossing should exist within two intervals")
	var early := flyer.direction_at(Vector2.ZERO, Vector2.ZERO, boundary + 0.05, seed_value)
	var late := flyer.direction_at(
		Vector2.ZERO, Vector2.ZERO, boundary + flyer.direction_change_interval - 0.05, seed_value
	)
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


# -- parked on the containment boundary: glide, don't jitter ------------------
#
# Reported live: "some birds still stall and jitter on a fixed spot."
# Measured: a bird sat 5.55 simulated seconds inside a 3px circle, at
# distance 70.04 from a home with radius 70 -- exactly ON the containment
# boundary.
#
# Cause: containment strips the whole OUTWARD component of `roam`. When roam
# points almost exactly outward (roam.dot(outward) == +1.00 measured), what
# is left is float residue -- length 0.002 -- and normalising residue turns
# numerical noise into a heading. Consecutive frames came back
# (+0.17, -0.99) then (-0.18, +0.98): a full 180-degree reversal every
# frame, which is a bird vibrating on the spot rather than flying.
#
# The pre-existing `< 0.001` fallback was written for EXACT cancellation and
# so never fired for the near-cancellation that actually happens.

## The exact measured state from the live reproduction.
const _JITTER_HOME := Vector2(500, 500)
const _JITTER_POSITION := Vector2(431, 488)
const _JITTER_TIME := 11.5
const _JITTER_SEED := 11


func test_a_flyer_on_its_boundary_does_not_reverse_heading_every_frame():
	var movement := AmbientFlyerMovement.new(34.0, 70.0, 1.4)
	var step := 1.0 / 60.0
	var previous := movement.direction_at(_JITTER_HOME, _JITTER_POSITION, _JITTER_TIME, _JITTER_SEED)
	var position := _JITTER_POSITION
	var elapsed := _JITTER_TIME
	for _i in 12:
		position = movement.step_position(_JITTER_HOME, position, elapsed, step, _JITTER_SEED)
		elapsed += step
		var heading := movement.direction_at(_JITTER_HOME, position, elapsed, _JITTER_SEED)
		assert_gt(
			heading.dot(previous), 0.0,
			"heading reversed between consecutive frames -- that is a flyer vibrating in place"
		)
		previous = heading


## The behavioural claim, not just the per-frame one: a flyer that starts on
## its boundary must actually GO somewhere over a few seconds. Path length
## alone is not enough -- a jittering bird still travels ~100px of path while
## netting almost no displacement -- so this measures how far it gets from
## its start.
##
## Measured as the FARTHEST distance from the start reached AT ANY POINT
## during the window, not the final distance at the window's end. A
## contained flyer now commits to one rotational direction for TURN_SIGN_
## INTERVALS roam intervals at a time (see that constant's own doc comment
## -- fixing "robins still cycle between two points" means a flyer can no
## longer luck into a fresh, better-displacing turn sign every 1.4s the way
## it used to), and a flyer travelling a genuine arc around its boundary can
## end a fixed window back near where it started -- measured directly, one
## seed's END-of-window displacement was 0.89px despite having swept most
## of the way around its territory in between, which a naive "final
## distance" check reads as indistinguishable from a true stall. "How far
## did it get, at its farthest" is not fooled by that: a real stall never
## gets far at any point, while genuine circular travel does, whether or
## not it later swings back near home.
func test_a_flyer_starting_on_its_boundary_actually_travels():
	var movement := AmbientFlyerMovement.new(34.0, 70.0, 1.4)
	var step := 1.0 / 60.0
	var commitment_seconds: float = AmbientFlyerMovement.TURN_SIGN_INTERVALS * movement.direction_change_interval
	var steps := int((commitment_seconds + 3.0) / step)
	for seed_value in range(16):
		var position := _JITTER_POSITION
		var elapsed := _JITTER_TIME
		var max_distance := 0.0
		for _i in steps:
			position = movement.step_position(_JITTER_HOME, position, elapsed, step, seed_value)
			elapsed += step
			max_distance = maxf(max_distance, _JITTER_POSITION.distance_to(position))
		assert_gt(
			max_distance, 20.0,
			"seed %d never got far from its start -- it is stalled on the boundary" % seed_value
		)


## Containment must still CONTAIN: the fix must not let a flyer whose roam
## points straight out simply leave. It should glide along the boundary, not
## escape past the home pull's full-strength radius.
func test_a_contained_flyer_still_does_not_escape_its_territory():
	var movement := AmbientFlyerMovement.new(34.0, 70.0, 1.4)
	var step := 1.0 / 60.0
	var limit: float = movement.radius * AmbientFlyerMovement.HOME_PULL_FULL_RADIUS_FACTOR
	for seed_value in range(16):
		var position := _JITTER_POSITION
		var elapsed := _JITTER_TIME
		for _i in 600:  # ten simulated seconds
			position = movement.step_position(_JITTER_HOME, position, elapsed, step, seed_value)
			elapsed += step
			assert_lte(
				position.distance_to(_JITTER_HOME), limit,
				"seed %d escaped its territory" % seed_value
			)


# -- individual, not synchronized; roaming, not shuttling between two points -

## Reported live, twice in one message: "robins still cycle between two
## points and interestingly all birds on the screen reverse direction at
## the exact same time... behaviour should be individual". Two separate,
## confirmed-by-measurement bugs (see tools/probe_bird_wander_sync.gd):
##
## 1. Every AmbientFlyerMarker starts its own _elapsed_time at 0.0 on
##    spawn, and _roam_direction/_turn_sign both derive interval_index
##    from elapsed_time ALONE, with no per-bird phase. Two birds spawned
##    together (an ordinary chunk load) therefore tick over
##    direction_change_interval boundaries on the EXACT SAME FRAME for the
##    rest of their lives, no matter how different their own seeds are --
##    only the CHOSEN heading differs, never the moment it changes. That
##    reads as a flock reversing in lockstep, not individuals.
## 2. _turn_sign re-rolls independently every single roam interval -- an
##    unbiased coin flip that on average reverses which way a CONTAINED
##    flyer circles its territory every other interval. That is far too
##    often for it to travel more than a short arc before turning back:
##    measured directly, a flyer run for 90 simulated seconds from the
##    boundary-jitter reproduction spent nearly all of it shuffling within
##    a narrow wedge, repeatedly revisiting near-identical points -- the
##    milder, longer-timescale sibling of the acute "stalled on the
##    boundary" bug above, and not caught by that bug's own 3-second/20px
##    travel test, which a shuffle this size still clears.

## Same jitter reproduction the boundary-stall tests above use, just for
## a much longer run.
func test_differently_seeded_flyers_change_heading_on_different_frames():
	var a := AmbientFlyerMovement.new(34.0, 70.0, 1.8)
	var b := AmbientFlyerMovement.new(34.0, 70.0, 1.8)
	var step := 1.0 / 60.0
	var pos_a := Vector2.ZERO
	var pos_b := Vector2.ZERO
	var dir_a := a.direction_at(Vector2.ZERO, pos_a, 0.0, 3)
	var dir_b := b.direction_at(Vector2.ZERO, pos_b, 0.0, 9)
	var elapsed := 0.0
	var flip_frame_a := -1
	var flip_frame_b := -1
	for i in 600:  # 10 simulated seconds -- several roam intervals at 1.8s
		var new_dir_a := a.direction_at(Vector2.ZERO, pos_a, elapsed, 3)
		var new_dir_b := b.direction_at(Vector2.ZERO, pos_b, elapsed, 9)
		if flip_frame_a < 0 and new_dir_a.dot(dir_a) < 0.5:
			flip_frame_a = i
		if flip_frame_b < 0 and new_dir_b.dot(dir_b) < 0.5:
			flip_frame_b = i
		dir_a = new_dir_a
		dir_b = new_dir_b
		pos_a = a.step_position(Vector2.ZERO, pos_a, elapsed, step, 3)
		pos_b = b.step_position(Vector2.ZERO, pos_b, elapsed, step, 9)
		elapsed += step
	assert_true(
		flip_frame_a >= 0 and flip_frame_b >= 0,
		"precondition: both flyers should change heading at least once in 10s"
	)
	assert_ne(
		flip_frame_a, flip_frame_b,
		"two differently-seeded flyers, both spawned at elapsed_time=0, changed heading on the exact same frame -- that is a synchronized flock, not individuals"
	)


## Wraparound-safe: tracks the UNWRAPPED cumulative angle around home frame
## to frame (the same wrapf-a-delta technique AmbientFlyerMovement._rotated_
## toward itself uses), so a flyer that happens to pass near the +-180
## degree seam is not mistaken for one that swept a huge arc, or vice versa.
func test_a_contained_flyer_ranges_over_a_wide_arc_not_just_two_points():
	var movement := AmbientFlyerMovement.new(34.0, 70.0, 1.8)
	var step := 1.0 / 60.0
	for seed_value in range(8):
		var position := _JITTER_POSITION
		var elapsed := _JITTER_TIME
		var previous_angle := (position - _JITTER_HOME).angle()
		var unwrapped := 0.0
		var min_unwrapped := 0.0
		var max_unwrapped := 0.0
		for _i in 5400:  # 90 simulated seconds
			position = movement.step_position(_JITTER_HOME, position, elapsed, step, seed_value)
			elapsed += step
			var angle := (position - _JITTER_HOME).angle()
			unwrapped += wrapf(angle - previous_angle, -PI, PI)
			previous_angle = angle
			min_unwrapped = minf(min_unwrapped, unwrapped)
			max_unwrapped = maxf(max_unwrapped, unwrapped)
		assert_gt(
			max_unwrapped - min_unwrapped, deg_to_rad(150.0),
			"seed %d only ever swept a narrow wedge around home in 90s -- reads as shuttling between two points, not roaming" % seed_value
		)
