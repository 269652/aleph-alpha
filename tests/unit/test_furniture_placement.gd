extends GutTest

## FurniturePlacement: may this furniture piece go on this cell (see
## docs/concept/housing.md's "Interior furniture" section). Pure logic over
## two grids, the same "player's build cursor and the village generator ask
## the same question of the same code" shape BuildingPlacement already
## establishes for the ground layer -- here, real interior floor only via
## RoomDetector, not a second "is this a house" heuristic.

const FurniturePlacement = preload("res://src/gameplay/furniture_placement.gd")

var placement: FurniturePlacement

## Vector2i cell -> piece_id, same shape BuildingPlacement's own grid uses.
var ground_grid: Dictionary
## Vector2i cell -> furniture piece_id -- its own layer, mirroring
## Chunk.roof_modifications' own "sits on top of the floor, needs its own
## dict" reasoning.
var furniture_grid: Dictionary


func before_each():
	placement = FurniturePlacement.new()
	ground_grid = _hut(true)
	furniture_grid = {}


## A 5x5 ring of walls around a 3x3 floor interior, with a door in the top
## wall -- the exact fixture test_room_detector.gd already establishes for
## the same reason: a small, real, enclosed room to test against.
func _hut(with_door: bool) -> Dictionary:
	var grid := {}
	for x in range(0, 5):
		for y in range(0, 5):
			var edge := x == 0 or y == 0 or x == 4 or y == 4
			if edge:
				grid[Vector2i(x, y)] = "wood_wall"
			else:
				grid[Vector2i(x, y)] = "wood_floor"
	if with_door:
		grid[Vector2i(2, 0)] = "wood_door"
	return grid


func test_furniture_may_be_placed_on_real_interior_floor():
	assert_true(placement.can_place("wood_chair", Vector2i(2, 2), ground_grid, furniture_grid))


## The rule this whole module exists for: a floor tile that is not actually
## enclosed by walls is not "inside a house" -- furnishing it would let a
## table sit on a slab in the open wilderness.
func test_furniture_may_not_be_placed_on_an_unenclosed_floor():
	var open_floor := {Vector2i(50, 50): "wood_floor"}
	assert_false(placement.can_place("wood_chair", Vector2i(50, 50), open_floor, {}))


func test_furniture_may_not_be_placed_on_a_wall():
	assert_false(placement.can_place("wood_chair", Vector2i(0, 2), ground_grid, furniture_grid))


func test_furniture_may_not_be_placed_on_a_door():
	assert_false(placement.can_place("wood_chair", Vector2i(2, 0), ground_grid, furniture_grid))


func test_furniture_may_not_be_placed_where_no_ground_piece_exists_at_all():
	assert_false(placement.can_place("wood_chair", Vector2i(99, 99), ground_grid, furniture_grid))


## One furniture piece per cell -- the same "one thing per layer" rule
## every other modification dict in this codebase already enforces.
func test_furniture_may_not_stack_on_another_furniture_piece():
	furniture_grid[Vector2i(2, 2)] = "wood_rug"
	assert_false(placement.can_place("wood_chair", Vector2i(2, 2), ground_grid, furniture_grid))


## Two DIFFERENT furniture pieces can share a room (a rug under a table) as
## long as they are on DIFFERENT cells -- only same-cell stacking is refused.
func test_two_furniture_pieces_may_share_a_room_on_different_cells():
	furniture_grid[Vector2i(1, 1)] = "wood_rug"
	assert_true(placement.can_place("wood_chair", Vector2i(2, 2), ground_grid, furniture_grid))


func test_an_unknown_piece_is_refused():
	assert_false(placement.can_place("not_a_real_piece", Vector2i(2, 2), ground_grid, furniture_grid))


## A real structural piece (not furniture-category) is refused here too --
## this module places furniture, not walls; BuildingPlacement stays the
## one place that decides those.
func test_a_non_furniture_piece_is_refused():
	assert_false(placement.can_place("wood_wall", Vector2i(2, 2), ground_grid, furniture_grid))


func test_refusal_reason_explains_each_real_failure():
	assert_eq(placement.refusal_reason("wood_chair", Vector2i(2, 2), ground_grid, furniture_grid), "")
	assert_ne(placement.refusal_reason("not_a_real_piece", Vector2i(2, 2), ground_grid, furniture_grid), "")
	assert_ne(placement.refusal_reason("wood_wall", Vector2i(2, 2), ground_grid, furniture_grid), "")
	assert_ne(placement.refusal_reason("wood_chair", Vector2i(0, 2), ground_grid, furniture_grid), "")
	assert_ne(placement.refusal_reason("wood_chair", Vector2i(50, 50), {}, {}), "")
	furniture_grid[Vector2i(2, 2)] = "wood_rug"
	assert_ne(placement.refusal_reason("wood_chair", Vector2i(2, 2), ground_grid, furniture_grid), "")
