extends GutTest

## RoomDetector: which cells are enclosed by walls, i.e. indoors (see
## docs/concept/building.md#what-enterable-means-in-a-top-down-game).
##
## This is the mechanism that makes a building a BUILDING rather than
## scenery. A 3D game gets enclosure for free from geometry; a top-down grid
## has to compute it -- a region is indoors when it cannot reach the outside
## world by orthogonal steps through non-enclosing cells.

const RoomDetector = preload("res://src/gameplay/room_detector.gd")

var detector: RoomDetector


func before_each():
	detector = RoomDetector.new()


## A 5x5 ring of walls around a 3x3 floor interior, with an optional door
## punched into the top wall.
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


func test_a_walled_hut_encloses_its_interior():
	var rooms := detector.find_rooms(_hut(false))
	assert_eq(rooms.size(), 1, "the hut should be one room")
	assert_eq(rooms[0].size(), 9, "the 3x3 interior should all be indoors")


## The defining case: a doorway must NOT leak. A door encloses for the
## purposes of "is this a building" while still being walkable, which is
## what lets the player walk in without the house ceasing to be a house.
func test_a_door_does_not_break_the_enclosure():
	var rooms := detector.find_rooms(_hut(true))
	assert_eq(rooms.size(), 1, "a hut with a door is still enclosed")
	assert_eq(rooms[0].size(), 9)


## A hole in the wall DOES break it -- otherwise "enclosed" would mean
## nothing.
func test_a_gap_in_the_wall_leaves_the_interior_outdoors():
	var grid := _hut(false)
	grid.erase(Vector2i(2, 0))  # knock a wall out
	assert_eq(detector.find_rooms(grid).size(), 0, "a hut open to the world is not a room")


## A walled ring with no floor is a fence, not a house.
func test_an_empty_walled_ring_is_not_a_room():
	var grid := {}
	for x in range(0, 5):
		for y in range(0, 5):
			if x == 0 or y == 0 or x == 4 or y == 4:
				grid[Vector2i(x, y)] = "wood_wall"
	assert_eq(detector.find_rooms(grid).size(), 0, "no floor means no room")


func test_is_indoors_reports_membership_of_a_room():
	var grid := _hut(true)
	assert_true(detector.is_indoors(Vector2i(2, 2), grid), "the middle of the hut is indoors")
	assert_false(detector.is_indoors(Vector2i(2, 6), grid), "outside the hut is not indoors")
	assert_false(detector.is_indoors(Vector2i(0, 0), grid), "a wall cell is not itself indoors")


func test_two_separate_huts_are_two_rooms():
	var grid := _hut(true)
	for cell in _hut(true):
		grid[cell + Vector2i(10, 0)] = _hut(true)[cell]
	var rooms := detector.find_rooms(grid)
	assert_eq(rooms.size(), 2, "two huts should be two distinct rooms")


func test_an_empty_world_has_no_rooms():
	assert_eq(detector.find_rooms({}).size(), 0)


## Enclosure must be decided by the structure, not by how far the search
## happens to wander -- a big open floor slab with no walls is outdoors.
func test_a_large_open_floor_is_not_a_room():
	var grid := {}
	for x in range(0, 8):
		for y in range(0, 8):
			grid[Vector2i(x, y)] = "wood_floor"
	assert_eq(detector.find_rooms(grid).size(), 0, "floor without walls is a patio, not a room")


func test_results_are_deterministic():
	var grid := _hut(true)
	assert_eq(detector.find_rooms(grid), detector.find_rooms(grid))
