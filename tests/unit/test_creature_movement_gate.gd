extends GutTest

## CreatureMovementGate: decides where a creature is ALLOWED to step before
## it steps there, rather than moving first and reacting afterwards.
##
## Reported: "when it's stuck between player and blocked by a tree it still
## flips erratically... same when blocked by a stone. Make it so that all
## animals first check if moving is going to be blocked by a tree or by
## entering flee radius and only actually execute the move if it's clear. If
## it doesn't have anywhere to go, it should just stay in idle mode without
## walk animation or flips."
##
## Pure vector math over plain data (positions + radii), no nodes -- the
## caller gathers the real trees/stones/threats and applies the result.

const CreatureMovementGate = preload("res://src/gameplay/creature_movement_gate.gd")

const STEP := 10.0
const KEEP_OUT := 80.0


func _blocker(at: Vector2, radius: float = 12.0) -> Dictionary:
	return {"position": at, "radius": radius}


func test_an_unobstructed_direction_is_returned_unchanged():
	var heading := CreatureMovementGate.clear_direction(
		Vector2.ZERO, Vector2.RIGHT, STEP, [], [], KEEP_OUT
	)
	assert_almost_eq(heading.x, 1.0, 0.001)
	assert_almost_eq(heading.y, 0.0, 0.001)


func test_a_zero_desired_direction_yields_no_movement():
	var heading := CreatureMovementGate.clear_direction(
		Vector2.ZERO, Vector2.ZERO, STEP, [], [], KEEP_OUT
	)
	assert_eq(heading, Vector2.ZERO)


## The whole point: a blocker dead ahead must produce a DIFFERENT heading
## that is itself clear -- not the blocked one, and not a dead stop while
## somewhere sensible remains open.
## The blocker's radius has to be SMALLER than its distance, or the creature
## starts out already inside it and the escape-hatch rule in _is_clear
## (below) legitimately applies instead -- which is a different scenario, not
## this one.
func test_it_steers_around_a_blocker_dead_ahead_instead_of_into_it():
	var blockers := [_blocker(Vector2(STEP, 0.0), 6.0)]

	var heading := CreatureMovementGate.clear_direction(
		Vector2.ZERO, Vector2.RIGHT, STEP, blockers, [], KEEP_OUT
	)

	assert_ne(heading, Vector2.ZERO, "there is plenty of open ground; it should not give up")
	var destination := heading * STEP
	assert_gt(
		destination.distance_to(blockers[0]["position"]),
		blockers[0]["radius"],
		"the chosen step must actually clear the blocker"
	)


## Boxed in on every side -- the creature has genuinely nowhere to go, and
## must say so (Vector2.ZERO) rather than picking a blocked direction anyway.
## The caller reads this as "stand idle", which is what stops the erratic
## flipping when wedged between the player and a tree.
func test_it_reports_no_clear_direction_when_completely_enclosed():
	var blockers: Array = []
	for i in 16:
		var angle := TAU * float(i) / 16.0
		blockers.append(_blocker(Vector2.RIGHT.rotated(angle) * STEP, 14.0))

	var heading := CreatureMovementGate.clear_direction(
		Vector2.ZERO, Vector2.RIGHT, STEP, blockers, [], KEEP_OUT
	)

	assert_eq(heading, Vector2.ZERO, "nowhere to go should mean stand still, not shove into a blocker")


## "or by entering flee radius": a step that would carry the creature closer
## to a threat it is trying to keep away from is refused the same as one into
## a tree -- this is the check that stops it walking into its own flee range
## and bouncing back out again.
func test_it_refuses_a_step_that_closes_on_a_threat_inside_the_keep_out_radius():
	var threat := Vector2(KEEP_OUT + STEP * 0.5, 0.0)  # just outside; one step would breach

	var heading := CreatureMovementGate.clear_direction(
		Vector2.ZERO, Vector2.RIGHT, STEP, [], [threat], KEEP_OUT
	)

	assert_ne(heading, Vector2.ZERO)
	assert_lt(
		(heading * STEP).distance_to(threat) - Vector2.ZERO.distance_to(threat),
		0.001,
		"the chosen step must not close the gap to the threat"
	)
	assert_false(heading.is_equal_approx(Vector2.RIGHT), "straight at the threat should have been rejected")


## A creature the player has simply walked up to is ALREADY inside the
## keep-out radius. Refusing every step then would freeze it against the
## player -- the rule is "don't get closer", not "never be close", so
## retreating and sidestepping both stay available.
func test_a_creature_already_inside_the_keep_out_radius_can_still_move_away():
	var threat := Vector2(20.0, 0.0)  # well inside KEEP_OUT

	var heading := CreatureMovementGate.clear_direction(
		Vector2.ZERO, Vector2.LEFT, STEP, [], [threat], KEEP_OUT
	)

	assert_almost_eq(heading.x, -1.0, 0.001, "retreating from a threat already on top of it must be allowed")


## The same escape hatch for blockers: a creature that has somehow ended up
## overlapping a tree must be able to walk out of it, not be pinned forever.
func test_a_creature_already_overlapping_a_blocker_can_still_move_clear():
	var blockers := [_blocker(Vector2(2.0, 0.0), 20.0)]  # origin is inside it

	var heading := CreatureMovementGate.clear_direction(
		Vector2.ZERO, Vector2.LEFT, STEP, blockers, [], KEEP_OUT
	)

	assert_almost_eq(heading.x, -1.0, 0.001, "moving away from an overlapping blocker must be allowed")


## Preference order matters: when the desired heading is clear it must be
## used as-is, and when it isn't, the replacement should be a modest turn
## rather than an arbitrary one -- a creature that veers 150 degrees off a
## perfectly good heading reads as panicking, not as walking around a tree.
func test_it_prefers_the_smallest_turn_that_clears():
	var blockers := [_blocker(Vector2(STEP, 0.0), 8.0)]

	var heading := CreatureMovementGate.clear_direction(
		Vector2.ZERO, Vector2.RIGHT, STEP, blockers, [], KEEP_OUT
	)

	assert_gt(heading.dot(Vector2.RIGHT), 0.0, "should still be heading broadly the way it wanted to go")


## A detour, once picked, must be STICKY: re-deriving it from scratch every
## frame let the chosen side alternate as the creature's position wobbled by
## sub-pixels, which read as flipping erratically right at the obstacle
## (reported: "walks into a tree and starts flipping erratically... walks
## into a stone and gets stuck"). When the desired heading is still blocked
## and the previously-chosen detour is still clear, the previous detour
## wins -- even when the fixed smallest-turn order would now pick the other
## side.
func test_a_previously_chosen_detour_is_kept_while_it_stays_clear():
	var blockers := [_blocker(Vector2(STEP, 0.0), 8.0)]
	var previous := Vector2.RIGHT.rotated(-PI / 3.0)  # the detour picked earlier

	var heading := CreatureMovementGate.clear_direction(
		Vector2.ZERO, Vector2.RIGHT, STEP, blockers, [], KEEP_OUT, previous
	)

	assert_almost_eq(heading.x, previous.x, 0.001, "should keep the committed detour, not re-litigate the side")
	assert_almost_eq(heading.y, previous.y, 0.001)


## Stickiness must not outlive its reason: the moment the DESIRED heading
## itself is clear again (the creature has passed the tree), the detour is
## dropped and it goes back to where it actually wanted to go.
func test_the_detour_is_dropped_once_the_desired_heading_clears():
	var previous := Vector2.RIGHT.rotated(-PI / 3.0)

	var heading := CreatureMovementGate.clear_direction(
		Vector2.ZERO, Vector2.RIGHT, STEP, [], [], KEEP_OUT, previous
	)

	assert_almost_eq(heading.x, 1.0, 0.001, "open ground ahead: resume the real intent, not the stale detour")


## When a detour is needed and clear options exist on BOTH horizontal sides,
## the one that keeps the creature's current facing must win, even at a
## wider turn -- a flip is the single most visible thing a creature can do,
## so a detour that requires one when a same-facing detour exists reads as
## erratic (reported: "if it gets blocked by a tree and changes direction it
## should not be allowed to instantly flip again"). Facing left here, with
## the desired heading (rightward) blocked dead ahead: the ±30° candidates
## both point rightward (a flip); a leftward option is clear -- it must be
## chosen despite being the wider turn. (A pure-vertical detour, x = 0, also
## preserves the facing -- the requirement is "no flip-REQUIRING rightward
## component", not "must point left".)
func test_a_detour_prefers_the_side_that_keeps_the_current_facing():
	var blockers := [_blocker(Vector2(STEP, 0.0), 6.0)]

	var heading := CreatureMovementGate.clear_direction(
		Vector2.ZERO, Vector2.RIGHT, STEP, blockers, [], KEEP_OUT, Vector2.ZERO, -1.0
	)

	assert_ne(heading, Vector2.ZERO)
	assert_lte(heading.x, 0.001, "no rightward (flip-requiring) component while facing left")


## No facing preference passed (0.0) keeps the plain smallest-turn order --
## serpents and any caller that doesn't track a binary facing lose nothing.
func test_no_facing_preference_keeps_the_smallest_turn():
	var blockers := [_blocker(Vector2(STEP, 0.0), 6.0)]

	var heading := CreatureMovementGate.clear_direction(
		Vector2.ZERO, Vector2.RIGHT, STEP, blockers, [], KEEP_OUT, Vector2.ZERO, 0.0
	)

	assert_gt(heading.dot(Vector2.RIGHT), 0.0)


# -- buildings (see docs/concept/navigation.md) -----------------------------
#
# Reported live: "fix creatures walking through houses too". Buildings were
# invisible to this gate for a structural reason, not a tuning one:
# EarthChunkManager.solid_obstacles_near -- the only thing it ever sees --
# walks _loaded_trees and _loaded_stones and has no building term at all.
#
# They arrive as a TILE PREDICATE rather than as circles in `blockers`.
# Circles over a rectangle either leave real diamond gaps at every
# four-tile corner or block past the wall, and either way cost
# O(footprint tiles) per candidate heading -- ~70 blockers against twelve
# headings per creature per tick in a village, the exact shape of cost
# solid_obstacles_near exists to escape.

const GATE_TILE := 16


## One 3x3 house occupying tiles (4,4)-(6,6).
func _house_tiles() -> Callable:
	return func(tile: Vector2i) -> bool:
		return tile.x >= 4 and tile.x <= 6 and tile.y >= 4 and tile.y <= 6


func _tile_centre(tile: Vector2i) -> Vector2:
	return Vector2(tile.x * GATE_TILE + GATE_TILE * 0.5, tile.y * GATE_TILE + GATE_TILE * 0.5)


func test_a_creature_will_not_step_into_a_house():
	# Standing just west of the wall, wanting to walk straight east into it.
	var origin := _tile_centre(Vector2i(3, 5))
	var heading: Vector2 = CreatureMovementGate.clear_direction(
		origin, Vector2.RIGHT, GATE_TILE, [], [], 0.0, Vector2.ZERO, 0.0,
		_house_tiles(), GATE_TILE
	)
	if heading == Vector2.ZERO:
		pass  # "nowhere to go" is an acceptable answer; walking in is not
	else:
		var landed := origin + heading * GATE_TILE
		var tile := Vector2i(floori(landed.x / GATE_TILE), floori(landed.y / GATE_TILE))
		assert_false(_house_tiles().call(tile), "the creature stepped into the house at %s" % tile)


func test_a_blocked_creature_turns_rather_than_stopping():
	# The whole point of this gate is that it finds a way round: with open
	# ground north and south of the wall, a creature facing it must get a
	# real heading back, not Vector2.ZERO.
	var origin := _tile_centre(Vector2i(3, 5))
	var heading: Vector2 = CreatureMovementGate.clear_direction(
		origin, Vector2.RIGHT, GATE_TILE, [], [], 0.0, Vector2.ZERO, 0.0,
		_house_tiles(), GATE_TILE
	)
	assert_ne(heading, Vector2.ZERO, "the creature froze at the wall instead of turning")


func test_no_candidate_heading_ever_lands_inside_a_house():
	# Swept rather than sampled: from every tile ringing the house, in
	# every direction, whatever heading comes back must be walkable.
	var blocked := _house_tiles()
	for y in range(2, 9):
		for x in range(2, 9):
			if blocked.call(Vector2i(x, y)):
				continue
			var origin := _tile_centre(Vector2i(x, y))
			for degrees in [0, 45, 90, 135, 180, 225, 270, 315]:
				var desired := Vector2.RIGHT.rotated(deg_to_rad(float(degrees)))
				var heading: Vector2 = CreatureMovementGate.clear_direction(
					origin, desired, GATE_TILE, [], [], 0.0, Vector2.ZERO, 0.0, blocked, GATE_TILE
				)
				if heading == Vector2.ZERO:
					continue
				var landed := origin + heading * GATE_TILE
				var tile := Vector2i(floori(landed.x / GATE_TILE), floori(landed.y / GATE_TILE))
				assert_false(
					blocked.call(tile),
					"from %s heading %d deg landed in the house at %s" % [
						Vector2i(x, y), degrees, tile
					]
				)


func test_a_creature_caught_inside_a_building_can_always_leave():
	# Same escape every other rule here keeps: a house raised over a
	# standing animal must not imprison it.
	var origin := _tile_centre(Vector2i(5, 5))  # dead centre of the house
	var heading: Vector2 = CreatureMovementGate.clear_direction(
		origin, Vector2.RIGHT, GATE_TILE, [], [], 0.0, Vector2.ZERO, 0.0,
		_house_tiles(), GATE_TILE
	)
	assert_ne(heading, Vector2.ZERO, "a creature caught inside a building was trapped there")


func test_without_a_tile_predicate_the_gate_behaves_exactly_as_before():
	# Every pre-existing 6- and 8-argument call site must be untouched.
	var origin := _tile_centre(Vector2i(3, 5))
	assert_eq(
		CreatureMovementGate.clear_direction(origin, Vector2.RIGHT, GATE_TILE, [], [], 0.0),
		Vector2.RIGHT
	)
	assert_eq(
		CreatureMovementGate.clear_direction(
			origin, Vector2.RIGHT, GATE_TILE, [], [], 0.0, Vector2.ZERO, 0.0, Callable(), 0
		),
		Vector2.RIGHT
	)
