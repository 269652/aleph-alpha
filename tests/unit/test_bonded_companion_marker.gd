extends GutTest

## BondedCompanionMarker: a netted flyer bonded via Beastmaster's
## `menagerie` keystone (see docs/concept/taming.md's "A bond, not an
## order: the Kinship path"). Deliberately lighter than CreatureMarker: no
## trust/order/struggle state, just a loose follow using the same
## CreatureMovementGate obstacle-avoidance a led animal already gets.

const BondedCompanionMarker = preload("res://src/rendering/bonded_companion_marker.gd")


class StubWorld:
	extends RefCounted
	var blockers: Array = []
	func solid_obstacles_near(_p: Vector2, _r: float) -> Array:
		return blockers


var marker: BondedCompanionMarker


func before_each():
	marker = BondedCompanionMarker.new()
	marker.species = "monarch"
	marker.wander_seed = 5
	add_child_autofree(marker)


func test_a_fresh_companion_starts_where_it_is_placed():
	marker.position = Vector2(40, 40)
	assert_eq(marker.position, Vector2(40, 40))


func test_it_walks_toward_its_follow_target():
	marker.setup(StubWorld.new(), 16)
	marker.position = Vector2.ZERO
	marker.follow_target = Vector2(200, 0)
	var start_distance := marker.position.distance_to(marker.follow_target)
	marker.step(1.0 / 60.0)
	assert_lt(
		marker.position.distance_to(marker.follow_target), start_distance,
		"a step toward the target should close the distance"
	)


## Close enough already: it should not keep endlessly micro-adjusting on
## top of the exact point (the same "held at rope length" idea a led
## animal's rope anchor uses).
func test_it_stops_once_within_arrival_radius():
	marker.setup(StubWorld.new(), 16)
	marker.position = Vector2.ZERO
	marker.follow_target = Vector2(BondedCompanionMarker.ARRIVAL_RADIUS * 0.5, 0)
	marker.step(1.0 / 60.0)
	assert_eq(marker.position, Vector2.ZERO)


## Deliberately slower than the player's own base pace (80.0, see
## Player.BASE_SPEED) -- "loosely trails" (taming.md's own wording) would
## read as glued to the player at an equal or faster speed.
func test_follow_speed_is_slower_than_the_players_own_base_speed():
	const Player = preload("res://scenes/player.gd")
	assert_lt(BondedCompanionMarker.FOLLOW_SPEED, Player.BASE_SPEED)


## Reuses CreatureMovementGate: walks around a blocker rather than straight
## through it, the same "walks around a tree" behaviour a led animal gets.
func test_it_steps_around_a_blocker_directly_in_its_path():
	var world := StubWorld.new()
	world.blockers = [{"position": Vector2(50, 0), "radius": 20.0}]
	marker.setup(world, 16)
	marker.position = Vector2.ZERO
	marker.follow_target = Vector2(200, 0)
	for _i in 30:
		marker.step(1.0 / 60.0)
	assert_gt(
		marker.position.distance_to(Vector2(50, 0)), 20.0,
		"it should have detoured around the blocker rather than walking into it"
	)


func test_a_companion_with_no_world_still_walks_straight_at_its_target():
	marker.position = Vector2.ZERO
	marker.follow_target = Vector2(100, 0)
	marker.step(1.0 / 60.0)
	assert_gt(marker.position.x, 0.0, "no world set should not leave it stuck")
