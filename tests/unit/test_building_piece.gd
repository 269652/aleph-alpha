extends GutTest

## BuildingPiece: the catalog of structural pieces a house is assembled from
## (see docs/concept/building.md#pieces). Pure data -- placement rules live
## in BuildingPlacement, enclosure in RoomDetector.

const BuildingPiece = preload("res://src/gameplay/building_piece.gd")


func test_every_piece_id_resolves_to_a_definition():
	for piece_id in BuildingPiece.PIECE_IDS:
		assert_true(BuildingPiece.has_piece(piece_id), piece_id)


func test_an_unknown_id_is_not_a_piece():
	assert_false(BuildingPiece.has_piece("not_a_piece"))


func test_every_category_is_represented():
	var categories := {}
	for piece_id in BuildingPiece.PIECE_IDS:
		categories[BuildingPiece.category_of(piece_id)] = true
	for category in [
		BuildingPiece.CATEGORY_FLOOR, BuildingPiece.CATEGORY_WALL,
		BuildingPiece.CATEGORY_DOOR, BuildingPiece.CATEGORY_WINDOW,
		BuildingPiece.CATEGORY_ROOF,
	]:
		assert_true(categories.has(category), "no piece for category %s" % category)


## The distinction the whole system rests on: a door encloses a room but you
## can still walk through it. Without that, a house is either open to the
## world or a sealed box (see docs/concept/building.md).
func test_a_door_encloses_but_is_walkable():
	assert_true(BuildingPiece.encloses("wood_door"), "a door must enclose, or a house with a door isn't a house")
	assert_true(BuildingPiece.is_walkable("wood_door"), "a door must be walkable, or you could never get in")


func test_a_wall_encloses_and_blocks_movement():
	assert_true(BuildingPiece.encloses("wood_wall"))
	assert_false(BuildingPiece.is_walkable("wood_wall"))


func test_a_window_encloses_and_blocks_movement_like_a_wall():
	assert_true(BuildingPiece.encloses("wood_window"))
	assert_false(BuildingPiece.is_walkable("wood_window"))


func test_a_floor_is_walkable_and_does_not_enclose():
	assert_true(BuildingPiece.is_walkable("wood_floor"))
	assert_false(BuildingPiece.encloses("wood_floor"), "a floor must not block the enclosure flood fill")


## A roof sits above the room rather than on its plane, so it neither
## encloses nor obstructs.
func test_a_roof_neither_encloses_nor_blocks():
	assert_false(BuildingPiece.encloses("wood_roof"))
	assert_true(BuildingPiece.is_walkable("wood_roof"))


func test_pieces_cost_real_materials():
	for piece_id in BuildingPiece.PIECE_IDS:
		var cost := BuildingPiece.cost_of(piece_id)
		assert_false(cost.is_empty(), "%s should cost something to build" % piece_id)
		for item_id in cost:
			assert_gt(cost[item_id], 0, "%s cost for %s should be positive" % [piece_id, item_id])


## Materials are a progression along the existing gather -> craft -> smelt
## chain, so stone must be the tougher, dearer tier.
func test_stone_is_more_durable_and_costlier_than_wood():
	assert_gt(BuildingPiece.durability_of("stone_wall"), BuildingPiece.durability_of("wood_wall"))
	var wood_cost := BuildingPiece.cost_of("wood_wall")
	var stone_cost := BuildingPiece.cost_of("stone_wall")
	assert_true(wood_cost.has("wood"), "a wood wall should cost wood")
	assert_true(stone_cost.has("stone"), "a stone wall should cost stone")


func test_unknown_pieces_answer_safely_rather_than_crashing():
	assert_eq(BuildingPiece.category_of("mystery"), "")
	assert_false(BuildingPiece.encloses("mystery"))
	assert_true(BuildingPiece.is_walkable("mystery"), "unknown ids must not silently block the world")
	assert_eq(BuildingPiece.cost_of("mystery"), {})


# -- timber tier: real consumers for beam/plank (see
# docs/concept/timber_construction.md, docs/concept/woodworking.md's own
# "beam/plank have no consumers yet" gap) -- a real Anno-style upgrade path,
# wood tier then timber tier, sourced from a Sägewerk supply chain rather
# than the raw wood tier's plain gather-and-place. Pillar 1 of the timber
# doc: Balken (beam) is the load-bearing structural piece, Planke (plank)
# is not -- so the wall costs beam, the floor costs plank.

func test_timber_wall_costs_beam():
	assert_true(BuildingPiece.has_piece("timber_wall"))
	var cost := BuildingPiece.cost_of("timber_wall")
	assert_true(cost.has("beam"), "a timber wall is the load-bearing piece -- it should cost beam")
	assert_true(BuildingPiece.encloses("timber_wall"))
	assert_false(BuildingPiece.is_walkable("timber_wall"))


func test_timber_floor_costs_plank():
	assert_true(BuildingPiece.has_piece("timber_floor"))
	var cost := BuildingPiece.cost_of("timber_floor")
	assert_true(cost.has("plank"), "a timber floor is non-structural decking -- it should cost plank")
	assert_true(BuildingPiece.is_walkable("timber_floor"))
	assert_false(BuildingPiece.encloses("timber_floor"))


## The timber tier sits ABOVE plain wood (a real Sägewerk supply chain, not
## just gathered wood) but is not itself the stone tier.
func test_timber_wall_is_more_durable_than_a_plain_wood_wall():
	assert_gt(BuildingPiece.durability_of("timber_wall"), BuildingPiece.durability_of("wood_wall"))


func test_timber_pieces_are_included_in_piece_ids():
	assert_true(BuildingPiece.PIECE_IDS.has("timber_wall"))
	assert_true(BuildingPiece.PIECE_IDS.has("timber_floor"))
