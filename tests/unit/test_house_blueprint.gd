extends GutTest

## HouseBlueprint: a seed and a footprint become a list of building pieces
## (see docs/concept/building.md#one-system-two-builders).
##
## This is what makes an NPC village house a REAL house: the settlement
## generator stamps blueprints made of the same pieces the player places by
## hand, so anything true of a player's house is true of a villager's.

const HouseBlueprint = preload("res://src/gameplay/house_blueprint.gd")
const BuildingPiece = preload("res://src/gameplay/building_piece.gd")
const RoomDetector = preload("res://src/gameplay/room_detector.gd")

var blueprint: HouseBlueprint


func before_each():
	blueprint = HouseBlueprint.new()


func test_a_house_fills_its_footprint():
	var pieces := blueprint.build(Vector2i(6, 5), 1)
	for cell in pieces:
		assert_between(cell.x, 0, 5)
		assert_between(cell.y, 0, 4)


## The whole point: a generated house must actually enclose a room, exactly
## as a hand-built one does. If this fails, village houses are scenery.
func test_a_generated_house_encloses_a_real_room():
	var rooms := RoomDetector.new().find_rooms(blueprint.build(Vector2i(7, 6), 3))
	assert_eq(rooms.size(), 1, "a house should enclose exactly one room")
	assert_gt(rooms[0].size(), 0)


func test_every_house_has_exactly_one_door():
	for seed_value in 12:
		var pieces := blueprint.build(Vector2i(6, 5), seed_value)
		var doors := 0
		for cell in pieces:
			if BuildingPiece.category_of(pieces[cell]) == BuildingPiece.CATEGORY_DOOR:
				doors += 1
		assert_eq(doors, 1, "seed %d should give exactly one way in" % seed_value)


func test_a_house_has_walls_floors_and_a_door():
	var pieces := blueprint.build(Vector2i(6, 5), 2)
	var categories := {}
	for cell in pieces:
		categories[BuildingPiece.category_of(pieces[cell])] = true
	for category in [
		BuildingPiece.CATEGORY_FLOOR, BuildingPiece.CATEGORY_WALL, BuildingPiece.CATEGORY_DOOR
	]:
		assert_true(categories.has(category), "a house needs %s pieces" % category)


## Different seeds give visibly different houses -- a village of identical
## huts is the problem the settlement art already had once.
func test_different_seeds_place_the_door_differently():
	var doors := {}
	for seed_value in 20:
		var pieces := blueprint.build(Vector2i(7, 6), seed_value)
		for cell in pieces:
			if BuildingPiece.category_of(pieces[cell]) == BuildingPiece.CATEGORY_DOOR:
				doors[cell] = true
	assert_gt(doors.size(), 1, "houses should not all have their door in the same place")


func test_material_follows_the_requested_tier():
	var stone := blueprint.build(Vector2i(6, 5), 1, BuildingPiece.MATERIAL_STONE)
	for cell in stone:
		assert_eq(BuildingPiece.material_of(stone[cell]), BuildingPiece.MATERIAL_STONE)


func test_a_footprint_too_small_for_an_interior_builds_nothing():
	assert_eq(blueprint.build(Vector2i(2, 2), 1).size(), 0, "there is no room inside a 2x2")


func test_is_deterministic():
	assert_eq(blueprint.build(Vector2i(6, 5), 9), blueprint.build(Vector2i(6, 5), 9))


## Roofs come back on their own layer, since they sit above the room rather
## than on its plane (see BuildingPlacement).
func test_roofs_cover_the_interior_on_their_own_layer():
	var roofs := blueprint.build_roofs(Vector2i(6, 5), 1)
	assert_gt(roofs.size(), 0, "a house should be roofed")
	for cell in roofs:
		assert_eq(BuildingPiece.category_of(roofs[cell]), BuildingPiece.CATEGORY_ROOF)
