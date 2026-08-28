extends GutTest

const CreatureWander = preload("res://src/rendering/creature_wander.gd")

var wander: CreatureWander


func before_each():
	wander = CreatureWander.new()


func test_direction_is_a_unit_vector():
	var direction := wander.direction_at(Vector2.ZERO, Vector2.ZERO, 0.0, 42)
	assert_almost_eq(direction.length(), 1.0, 0.001)


func test_roam_direction_is_a_unit_vector():
	assert_almost_eq(wander.roam_direction(0.0, 42).length(), 1.0, 0.001)


func test_roam_direction_is_stable_within_a_change_interval_and_ignores_home():
	# Unlike direction_at, roam has no home bias -- it's a free exploration
	# heading, the same for any position within a given interval.
	var early := wander.roam_direction(0.1, 7)
	var late := wander.roam_direction(CreatureWander.DIRECTION_CHANGE_INTERVAL - 0.1, 7)
	assert_eq(early, late)


func test_roam_direction_changes_between_intervals():
	var first := wander.roam_direction(0.0, 7)
	var second := wander.roam_direction(CreatureWander.DIRECTION_CHANGE_INTERVAL * 3.0, 7)
	assert_ne(first, second)


func test_direction_is_deterministic_for_the_same_inputs():
	var first := wander.direction_at(Vector2(10, 10), Vector2(12, 8), 3.5, 7)
	var second := wander.direction_at(Vector2(10, 10), Vector2(12, 8), 3.5, 7)
	assert_eq(first, second)


func test_direction_changes_between_distinct_seeds():
	var a := wander.direction_at(Vector2.ZERO, Vector2.ZERO, 0.0, 1)
	var b := wander.direction_at(Vector2.ZERO, Vector2.ZERO, 0.0, 2)
	assert_ne(a, b)


func test_direction_is_stable_within_one_change_interval():
	var early := wander.direction_at(Vector2.ZERO, Vector2.ZERO, 0.1, 7)
	var late := wander.direction_at(Vector2.ZERO, Vector2.ZERO, CreatureWander.DIRECTION_CHANGE_INTERVAL - 0.1, 7)
	assert_eq(early, late)


func test_direction_biases_back_toward_home_once_far_enough_away():
	var home := Vector2.ZERO
	var far_away := Vector2(CreatureWander.WANDER_RADIUS * 3, 0)
	var direction := wander.direction_at(home, far_away, 0.0, 7)
	# Should point roughly back toward home (negative x), regardless of the
	# pseudo-random seed that would otherwise pick an arbitrary direction.
	assert_lt(direction.x, 0.0)


## Hard-switching from "roam freely" to "head straight home" the instant the
## creature crosses WANDER_RADIUS made the returned heading DISCONTINUOUS at
## that boundary: a creature sitting on it got a wildly different direction
## from one frame to the next as it stepped a fraction of a pixel back and
## forth across the line. Downstream that reads as a legged animal flipping
## its facing every few frames, since CreatureMarker flips immediately off
## the requested direction's own x sign (reported: "now it constantly flips
## back and forth"). The heading must instead ease from roam toward home as
## the creature drifts further out, so crossing the radius changes nothing
## abruptly.
func test_direction_is_continuous_across_the_home_radius_boundary():
	var home := Vector2.ZERO
	var inside := wander.direction_at(home, Vector2(CreatureWander.WANDER_RADIUS - 0.5, 0), 0.0, 7)
	var outside := wander.direction_at(home, Vector2(CreatureWander.WANDER_RADIUS + 0.5, 0), 0.0, 7)
	assert_gt(
		inside.dot(outside),
		0.9,
		"a hair either side of the radius should give nearly the same heading, not a hard reversal"
	)


## The other half of the same property: the ease has to actually complete,
## or a creature far from home would keep half-roaming outward forever. Full
## home pull is reached by HOME_PULL_FULL_RADIUS_FACTOR x the radius, which
## is what keeps the wander genuinely bounded (see
## test_step_position_never_strands_far_beyond_the_wander_radius).
func test_direction_points_fully_home_once_well_past_the_radius():
	var home := Vector2.ZERO
	var distance: float = CreatureWander.WANDER_RADIUS * CreatureWander.HOME_PULL_FULL_RADIUS_FACTOR
	var direction := wander.direction_at(home, Vector2(distance, 0), 0.0, 7)
	assert_almost_eq(direction.x, -1.0, 0.01, "should be heading straight home, with no roam left in it")


## direction_at takes an optional radius (default WANDER_RADIUS, so every
## existing caller above is unaffected) -- a juvenile creature passes a
## smaller one to stay tighter to home (see CreatureMarker/MammalGrowth).
## Omitting it must reproduce today's exact heading.
func test_direction_at_default_radius_matches_passing_wander_radius_explicitly():
	var home := Vector2.ZERO
	var current := Vector2(50, 0)
	var without_radius := wander.direction_at(home, current, 0.0, 7)
	var with_radius := wander.direction_at(home, current, 0.0, 7, CreatureWander.WANDER_RADIUS)
	assert_eq(without_radius, with_radius)


## Property test (not a literal): step_position accumulated over many steps
## with a SMALLER supplied radius should keep the creature bounded within
## roughly that smaller radius, not the default WANDER_RADIUS -- proving the
## radius argument actually changes the containment distance rather than
## just being accepted and ignored.
func test_a_smaller_supplied_radius_keeps_step_position_bounded_tighter_to_home():
	var home := Vector2.ZERO
	var current := Vector2.ZERO
	var elapsed := 0.0
	var small_radius := CreatureWander.WANDER_RADIUS * 0.25
	for i in 200:
		current = wander.step_position(home, current, elapsed, 0.5, 7, small_radius)
		elapsed += 0.5
	assert_lt(
		current.distance_to(home), small_radius * 2.0,
		"a smaller radius should bound wandering to roughly itself, not the default WANDER_RADIUS"
	)


func test_step_position_moves_by_speed_times_delta():
	var home := Vector2.ZERO
	var current := Vector2.ZERO
	var next := wander.step_position(home, current, 0.0, 1.0, 7)
	assert_almost_eq(next.distance_to(current), CreatureWander.WANDER_SPEED, 0.001)


# -- per-instance radius/speed override --------------------------------------
#
# WANDER_RADIUS/WANDER_SPEED used to be read directly as module consts
# everywhere in this file, with no way for one caller to get a different
# scale than every other -- fine for creatures/real-world fish, all sized
# against the same open world, but wrong for the character preview
# diorama's own tiny pond (real WANDER_RADIUS, 40 units, comfortably
# exceeds the whole pond). Reported live: the diorama drove its fish with
# its OWN separate point-to-point movement instead of this real "swims like
# in the real game" algorithm at all, and it showed ("fish don't swim like
# in the real game"). wander_radius/wander_speed are instance fields
# DEFAULTING to the module consts -- every existing caller (CreatureMarker,
# FishMarker with a live water world) is completely unaffected unless it
# explicitly opts in to a different scale.

func test_wander_radius_defaults_to_the_module_constant():
	assert_eq(wander.wander_radius, CreatureWander.WANDER_RADIUS)


func test_wander_speed_defaults_to_the_module_constant():
	assert_eq(wander.wander_speed, CreatureWander.WANDER_SPEED)


func test_direction_at_honors_an_overridden_wander_radius():
	wander.wander_radius = 5.0
	var home := Vector2.ZERO
	# Well past the SMALL overridden radius but well inside the real-world
	# default -- only picks up the pull-home behavior if the override is
	# actually being read.
	var far_for_the_small_radius := Vector2(20.0, 0)
	var direction := wander.direction_at(home, far_for_the_small_radius, 0.0, 7)
	assert_lt(direction.x, 0.0, "should already be pulling home at 4x the overridden radius")


func test_step_position_honors_an_overridden_wander_speed():
	wander.wander_speed = 1.0
	var home := Vector2.ZERO
	var next := wander.step_position(home, home, 0.0, 1.0, 7)
	assert_almost_eq(next.distance_to(home), 1.0, 0.001)


func test_step_position_never_strands_far_beyond_the_wander_radius():
	var home := Vector2.ZERO
	var current := Vector2.ZERO
	var elapsed := 0.0
	for i in 200:
		current = wander.step_position(home, current, elapsed, 0.5, 7)
		elapsed += 0.5
	# The home-bias should keep it roughly bounded, not drifting away forever.
	assert_lt(current.distance_to(home), CreatureWander.WANDER_RADIUS * 2.0)


# -- is_pausing: grazing pauses within ordinary wander ------------------------
#
# Continuous, never-resting drift reads as mechanical (reported: "it doesn't
# look like natural wandering or foraging") -- real animals stop, look
# around, and graze between short walks. Some direction-change intervals are
# therefore PAUSES: the creature stands idle for that interval instead of
# picking a heading. Deterministic per (seed, interval), like every other
# wander decision, so the same creature pauses at the same moments on
# revisit.

func test_is_pausing_is_deterministic_for_the_same_seed_and_time():
	assert_eq(wander.is_pausing(3.7, 42), wander.is_pausing(3.7, 42))


func test_is_pausing_is_stable_within_one_direction_change_interval():
	var early := wander.is_pausing(0.1, 7)
	var late := wander.is_pausing(CreatureWander.DIRECTION_CHANGE_INTERVAL - 0.1, 7)
	assert_eq(early, late, "a pause covers a whole interval, not a flickering sub-window")


## PAUSE_FRACTION is a tested constant, not an eyeballed comment: across many
## intervals the realized pause share must actually track it.
func test_roughly_the_pause_fraction_of_intervals_are_pauses():
	var pauses := 0
	var total := 400
	for i in total:
		if wander.is_pausing((float(i) + 0.5) * CreatureWander.DIRECTION_CHANGE_INTERVAL, 11):
			pauses += 1
	var share := float(pauses) / float(total)
	assert_between(share, CreatureWander.PAUSE_FRACTION - 0.1, CreatureWander.PAUSE_FRACTION + 0.1)
