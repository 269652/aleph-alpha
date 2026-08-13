extends GutTest

## BuildingPlacement: may this piece go on this cell (see
## docs/concept/building.md#placement-rules). Pure logic over a grid, so the
## player's build cursor and the village generator ask it the same question.

const BuildingPlacement = preload("res://src/gameplay/building_placement.gd")

var placement: BuildingPlacement

## A grid is Dictionary: Vector2i cell -> piece_id.
var grid: Dictionary


func before_each():
	placement = BuildingPlacement.new()
	grid = {}


## Ground is buildable unless it's water; a caller supplies this so the
## rules never need to know about biomes.
func _buildable(_cell: Vector2i) -> bool:
	return true


func _not_buildable(_cell: Vector2i) -> bool:
	return false


func test_a_floor_may_be_placed_on_open_buildable_ground():
	assert_true(placement.can_place("wood_floor", Vector2i(0, 0), grid, _buildable))


func test_a_floor_may_not_be_placed_on_water_or_other_unbuildable_ground():
	assert_false(placement.can_place("wood_floor", Vector2i(0, 0), grid, _not_buildable))


func test_nothing_may_be_placed_where_a_piece_already_stands():
	grid[Vector2i(0, 0)] = "wood_floor"
	assert_false(placement.can_place("wood_wall", Vector2i(0, 0), grid, _buildable))
	assert_false(placement.can_place("wood_floor", Vector2i(0, 0), grid, _buildable))


## Walls belong to a building, not to open wilderness -- so a wall needs a
## floor under it or beside it.
func test_a_wall_needs_a_floor_on_or_beside_its_cell():
	assert_false(
		placement.can_place("wood_wall", Vector2i(5, 5), grid, _buildable),
		"a wall in empty wilderness should be refused"
	)
	grid[Vector2i(5, 6)] = "wood_floor"
	assert_true(
		placement.can_place("wood_wall", Vector2i(5, 5), grid, _buildable),
		"a wall beside a floor belongs to that building"
	)


func test_doors_and_windows_follow_the_same_rule_as_walls():
	assert_false(placement.can_place("wood_door", Vector2i(2, 2), grid, _buildable))
	assert_false(placement.can_place("wood_window", Vector2i(2, 2), grid, _buildable))
	grid[Vector2i(2, 3)] = "wood_floor"
	assert_true(placement.can_place("wood_door", Vector2i(2, 2), grid, _buildable))
	assert_true(placement.can_place("wood_window", Vector2i(2, 2), grid, _buildable))


## A roof covers a room, so it needs floor beneath it -- a roof floating
## over open ground is nonsense.
func test_a_roof_needs_a_floor_beneath_it():
	assert_false(placement.can_place("wood_roof", Vector2i(1, 1), grid, _buildable))
	grid[Vector2i(1, 1)] = "wood_floor"
	# The floor occupies the cell, but a roof sits ABOVE the room rather than
	# on its plane, so it is the one piece allowed to share a cell with a floor.
	assert_true(placement.can_place("wood_roof", Vector2i(1, 1), grid, _buildable))


func test_a_roof_may_not_share_a_cell_with_another_roof():
	grid[Vector2i(1, 1)] = "wood_floor"
	var roofs := {Vector2i(1, 1): "wood_roof"}
	assert_false(placement.can_place("wood_roof", Vector2i(1, 1), grid, _buildable, roofs))


func test_an_unknown_piece_is_never_placeable():
	assert_false(placement.can_place("not_a_piece", Vector2i(0, 0), grid, _buildable))


## Removal returns the piece's materials, mirroring the existing
## build/destroy loop.
func test_removing_a_piece_refunds_its_cost():
	assert_eq(placement.refund_for("wood_wall"), {"wood": 2})
	assert_eq(placement.refund_for("not_a_piece"), {})


## The cursor needs to explain a refusal, not just refuse.
func test_refusal_gives_a_reason():
	assert_ne(placement.refusal_reason("wood_wall", Vector2i(9, 9), grid, _buildable), "")
	grid[Vector2i(9, 9)] = "wood_floor"
	assert_eq(
		placement.refusal_reason("wood_wall", Vector2i(9, 10), grid, _buildable), "",
		"a legal placement should have no refusal reason"
	)
