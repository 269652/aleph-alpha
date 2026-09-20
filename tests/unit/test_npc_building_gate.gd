extends GutTest

## NpcBuildingGate: where an NPC may actually step, given the buildings in
## its way (see docs/concept/npc.md "Walls are solid to a villager too").
##
## Reported live: "NPCs walk straight through houses, ignoring the hitbox".
## The hitbox is real -- EarthChunkManager._spawn_building_node gives every
## building a StaticBody2D, which is what stops the PLAYER -- but an
## NpcMarker is a plain Sprite2D that assigns `position` directly, so no
## physics body is ever consulted on its behalf. This gate is the ask-first
## check that gives a villager the same walls, the same shape
## CreatureMovementGate already uses for trees and stones: pure math over
## plain data, no nodes, caller supplies the facts.

const NpcBuildingGate = preload("res://src/gameplay/npc_building_gate.gd")

const TILE := 16


## A blocked-tile predicate covering one 2x2 building at tiles (2,2)-(3,3).
func _house() -> Callable:
	return func(tile: Vector2i) -> bool:
		return tile.x >= 2 and tile.x <= 3 and tile.y >= 2 and tile.y <= 3


func _centre_of(tile: Vector2i) -> Vector2:
	return Vector2(tile.x * TILE + TILE * 0.5, tile.y * TILE + TILE * 0.5)


# -- the ordinary case: nothing in the way ---------------------------------

func test_a_clear_step_is_taken_in_full():
	var from := _centre_of(Vector2i(0, 0))
	var desired := _centre_of(Vector2i(1, 0))
	assert_eq(NpcBuildingGate.resolve_step(from, desired, TILE, _house()), desired)


func test_the_gate_is_pure():
	var from := _centre_of(Vector2i(0, 0))
	var desired := _centre_of(Vector2i(1, 0))
	assert_eq(
		NpcBuildingGate.resolve_step(from, desired, TILE, _house()),
		NpcBuildingGate.resolve_step(from, desired, TILE, _house())
	)


# -- the reported bug ------------------------------------------------------

func test_a_step_into_a_house_is_refused():
	var from := _centre_of(Vector2i(1, 2))
	var desired := _centre_of(Vector2i(2, 2))  # straight into the wall
	assert_eq(
		NpcBuildingGate.resolve_step(from, desired, TILE, _house()), from,
		"the villager walked into the house"
	)


func test_no_reachable_step_ever_ends_inside_a_house():
	# The property that actually matters, swept rather than sampled: from
	# every tile around the house, a step in any of the eight directions
	# must never land the villager inside it.
	var blocked := _house()
	for from_tile_y in range(0, 6):
		for from_tile_x in range(0, 6):
			var from_tile := Vector2i(from_tile_x, from_tile_y)
			if blocked.call(from_tile):
				continue  # starting inside is its own case, below
			for dy in [-1, 0, 1]:
				for dx in [-1, 0, 1]:
					var from := _centre_of(from_tile)
					var desired := _centre_of(from_tile + Vector2i(dx, dy))
					var landed: Vector2 = NpcBuildingGate.resolve_step(from, desired, TILE, blocked)
					var landed_tile := Vector2i(floori(landed.x / TILE), floori(landed.y / TILE))
					assert_false(
						blocked.call(landed_tile),
						"stepping %s from %s landed inside the house at %s" % [
							Vector2i(dx, dy), from_tile, landed_tile
						]
					)


# -- sliding: a wall must not freeze a villager ----------------------------

func test_a_diagonal_step_slides_along_the_wall_instead_of_stopping():
	# Walking diagonally into a wall is the commonest case by far. Refusing
	# outright would pin villagers against their own houses; sliding keeps
	# them moving along it, which is what a person does.
	var from := _centre_of(Vector2i(1, 1))
	var desired := _centre_of(Vector2i(2, 2))  # corner of the house
	var landed: Vector2 = NpcBuildingGate.resolve_step(from, desired, TILE, _house())
	assert_ne(landed, from, "the villager froze against the corner instead of sliding")
	var landed_tile := Vector2i(floori(landed.x / TILE), floori(landed.y / TILE))
	assert_false(_house().call(landed_tile))


func test_sliding_keeps_whichever_axis_is_actually_free():
	# Walking down the house's left wall: the diagonal target (2,3) is
	# inside it, and so is the X-only slide to (2,2) -- only the Y-only
	# slide to (1,3) is free, so that is the one that must be taken. The
	# first draft of this test picked a start tile where the X slide WAS
	# free and then asserted the Y one, which measured nothing about
	# preference and everything about my own arithmetic.
	var from := _centre_of(Vector2i(1, 2))
	var desired := _centre_of(Vector2i(2, 3))
	var landed: Vector2 = NpcBuildingGate.resolve_step(from, desired, TILE, _house())
	assert_almost_eq(landed.y, desired.y, 0.001, "the free axis was given up too")
	assert_almost_eq(landed.x, from.x, 0.001, "the blocked axis was taken anyway")


func test_a_villager_boxed_in_on_every_side_simply_stays_put():
	# Everything solid EXCEPT the cell they are standing on. Blocking that
	# one too would instead trip the walk-out rule below -- the two rules
	# genuinely interact, and a first draft of this test blocked every tile
	# including `from` and so asserted the opposite of what it meant.
	var standing := Vector2i(9, 9)
	var boxed_in := func(tile: Vector2i) -> bool: return tile != standing
	var from := _centre_of(standing)
	var desired := _centre_of(Vector2i(10, 9))
	assert_eq(NpcBuildingGate.resolve_step(from, desired, TILE, boxed_in), from)


# -- never trap anyone ------------------------------------------------------

func test_a_villager_already_inside_a_building_can_always_walk_out():
	# A house raised over a standing villager (or an older save that put one
	# there) must not imprison them forever: when the cell they are ON is
	# blocked, every step is allowed so they can leave.
	var from := _centre_of(Vector2i(2, 2))  # inside the house
	var desired := _centre_of(Vector2i(1, 2))  # out through the wall
	assert_eq(
		NpcBuildingGate.resolve_step(from, desired, TILE, _house()), desired,
		"a villager caught inside a building was trapped there"
	)


func test_a_null_predicate_lets_every_step_through():
	# Duck-typed fail-open, matching NpcMarker._is_in_water's own convention:
	# a marker with no world bound just walks as it always did.
	var from := _centre_of(Vector2i(1, 2))
	var desired := _centre_of(Vector2i(2, 2))
	assert_eq(NpcBuildingGate.resolve_step(from, desired, TILE, Callable()), desired)


func test_negative_coordinates_floor_correctly():
	# Villages exist west and north of the origin too; int truncation there
	# would round the wrong way and let a step slip inside a wall.
	var blocked := func(tile: Vector2i) -> bool: return tile == Vector2i(-2, -2)
	var from := Vector2(-3 * TILE + 1.0, -2 * TILE + 1.0)
	var desired := Vector2(-2 * TILE + 1.0, -2 * TILE + 1.0)
	assert_eq(NpcBuildingGate.resolve_step(from, desired, TILE, blocked), from)


# -- the thing this fix must not break -------------------------------------

const BuildingCatalog = preload("res://src/gameplay/building_catalog.gd")


## Every footprint cell of `building_id` placed at the origin, as the real
## blocked-tile predicate the gate will see in play.
func _real_building(building_id: String) -> Callable:
	var footprint: Vector2i = BuildingCatalog.footprint_of(building_id)
	return func(tile: Vector2i) -> bool:
		return (
			tile.x >= 0 and tile.x < footprint.x
			and tile.y >= 0 and tile.y < footprint.y
		)


func test_a_villager_can_still_reach_its_own_doorstep():
	# home_position IS the doorstep (VillageRenderer._build_npc), and the
	# whole schedule ends there -- so if blocking footprints also blocked
	# doorsteps, every villager in the game would be stranded outside their
	# own house forever. BuildingCatalog.doorstep_of puts it one row SOUTH
	# of the footprint for exactly this reason; this pins that the two
	# modules agree, against every real house the catalog knows.
	for building_id in BuildingCatalog.BUILDING_IDS:
		var blocked := _real_building(building_id)
		var doorstep: Vector2i = BuildingCatalog.doorstep_of(building_id)
		assert_false(
			blocked.call(doorstep),
			"%s's doorstep %s is inside its own footprint -- nobody could ever get home" % [
				building_id, doorstep
			]
		)
		# And the step onto it from further south is really allowed.
		var from := _centre_of(doorstep + Vector2i(0, 1))
		var desired := _centre_of(doorstep)
		assert_eq(
			NpcBuildingGate.resolve_step(from, desired, TILE, blocked), desired,
			"%s: a villager was refused its own doorstep" % building_id
		)


func test_the_door_itself_is_inside_the_footprint_and_stays_blocked():
	# The door cell is part of the building (doorstep_of is door_of + one
	# row south), so walking INTO the doorway is still refused -- entering
	# a house is a real transition (Player.enter_building), not a walk.
	for building_id in BuildingCatalog.BUILDING_IDS:
		var blocked := _real_building(building_id)
		assert_true(
			blocked.call(BuildingCatalog.door_of(building_id)),
			"%s's door is outside its own footprint" % building_id
		)
