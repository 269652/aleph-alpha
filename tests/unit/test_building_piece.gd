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


# -- real statics: load-bearing / support capacity (see
# docs/concept/timber_construction.md#real-statics-a-support-graph-over-the-
# piece-grid) -- "every CATEGORY_WALL piece is load-bearing with some support
# capacity; CATEGORY_FLOOR/ROOF/DOOR/WINDOW pieces are not load-bearing
# themselves", generalizing pillar 1's "a Balken is load-bearing, a Planke is
# not" to every material tier, not just the timber one.

## Regression: every existing piece's category/material/encloses/walkable/
## durability/cost must be completely unaffected by the new field -- this
## test locks in the exact same assertions test_building_piece.gd already
## made above, now for every single piece id in one pass, so a future
## statics change can never silently corrupt placement/enclosure behavior.
func test_existing_piece_fields_are_unaffected_by_the_new_statics_field():
	for piece_id in BuildingPiece.PIECE_IDS:
		var expected_category := BuildingPiece.category_of(piece_id)
		var expected_material := BuildingPiece.material_of(piece_id)
		var expected_encloses := BuildingPiece.encloses(piece_id)
		var expected_walkable := BuildingPiece.is_walkable(piece_id)
		var expected_durability := BuildingPiece.durability_of(piece_id)
		var expected_cost := BuildingPiece.cost_of(piece_id)
		# Reading the new field must not have mutated anything above.
		BuildingPiece.is_load_bearing(piece_id)
		BuildingPiece.support_capacity_of(piece_id)
		assert_eq(BuildingPiece.category_of(piece_id), expected_category, piece_id)
		assert_eq(BuildingPiece.material_of(piece_id), expected_material, piece_id)
		assert_eq(BuildingPiece.encloses(piece_id), expected_encloses, piece_id)
		assert_eq(BuildingPiece.is_walkable(piece_id), expected_walkable, piece_id)
		assert_eq(BuildingPiece.durability_of(piece_id), expected_durability, piece_id)
		assert_eq(BuildingPiece.cost_of(piece_id), expected_cost, piece_id)


## Every CATEGORY_WALL piece, and only CATEGORY_WALL pieces, are load-bearing
## -- checked for every real piece id (not just the timber tier) since this
## generalizes across all three material tiers.
func test_every_wall_piece_is_load_bearing_and_nothing_else_is():
	for piece_id in BuildingPiece.PIECE_IDS:
		var expected := BuildingPiece.category_of(piece_id) == BuildingPiece.CATEGORY_WALL
		assert_eq(
			BuildingPiece.is_load_bearing(piece_id), expected,
			"%s load-bearing should match whether it's a wall" % piece_id
		)


## A load-bearing piece must carry positive support capacity; a non-load-
## bearing one must carry none -- the "flag or support-capacity number" the
## concept doc describes are the same field here, not two.
func test_support_capacity_is_positive_for_walls_and_zero_otherwise():
	for piece_id in BuildingPiece.PIECE_IDS:
		var capacity := BuildingPiece.support_capacity_of(piece_id)
		if BuildingPiece.is_load_bearing(piece_id):
			assert_gt(capacity, 0.0, "%s is load-bearing, it should carry real support capacity" % piece_id)
		else:
			assert_eq(capacity, 0.0, "%s is not load-bearing, it should carry none" % piece_id)


## Support capacity mirrors durability's own already-tuned wood < timber <
## stone progression (reusing an existing tested number rather than
## inventing a fresh one) -- real per-material span capacity stays future
## work per the concept doc's own "ships first as a simpler fixed span/
## support-count approximation" note.
func test_wall_support_capacity_matches_the_wood_timber_stone_progression():
	assert_gt(BuildingPiece.support_capacity_of("timber_wall"), BuildingPiece.support_capacity_of("wood_wall"))
	assert_gt(BuildingPiece.support_capacity_of("stone_wall"), BuildingPiece.support_capacity_of("timber_wall"))
	for wall_id in ["wood_wall", "stone_wall", "timber_wall"]:
		assert_eq(
			BuildingPiece.support_capacity_of(wall_id), BuildingPiece.durability_of(wall_id),
			"%s's support capacity should reuse its own already-tuned durability number" % wall_id
		)


func test_unknown_piece_is_not_load_bearing_and_carries_no_capacity():
	assert_false(BuildingPiece.is_load_bearing("mystery"), "an unknown id must never silently carry load")
	assert_eq(BuildingPiece.support_capacity_of("mystery"), 0.0)


# -- the stone dam (docs/concept/rivers.md) ----------------------------------
#
# A player-built check dam is a real BuildingPiece rather than a "placeable"
# structure, deliberately: a piece already gets collision, atlas
# registration, persistence in chunk.modifications, boulder-respawn
# suppression, participation in the connected-structure flood fill, and
# material drop-back on collapse -- every one of which a dam wants, and none
# of which a placeable gets.

func test_the_stone_dam_is_a_real_piece():
	assert_true(BuildingPiece.has_piece("stone_dam"))
	assert_true(BuildingPiece.PIECE_IDS.has("stone_dam"))


func test_the_stone_dam_is_its_own_category():
	assert_eq(BuildingPiece.category_of("stone_dam"), BuildingPiece.CATEGORY_DAM)


## A dam is a barrier: you cannot walk through it, and it stops the
## enclosure flood fill exactly as a wall does.
func test_the_stone_dam_blocks_movement_and_encloses():
	assert_false(BuildingPiece.is_walkable("stone_dam"))
	assert_true(BuildingPiece.encloses("stone_dam"))


## It costs the stone the player can actually GET from the world: `rock` is
## what picking up a pebble and smashing a boulder both yield, whereas
## `stone` is the MINED output and would gate dams behind a pickaxe.
func test_the_stone_dam_costs_gatherable_rock_not_mined_stone():
	var cost := BuildingPiece.cost_of("stone_dam")
	assert_true(cost.has("rock"), "a dam should be buildable from gathered rock")
	assert_false(cost.has("stone"), "a dam should not require mined stone")
	assert_gt(cost["rock"], 0)


## Stone durability, matching the other stone pieces' tier -- a dam is
## dry-stacked rock, and its real failure mode is hydraulic (see
## DamImpoundment.failure_depth_m), not something that should also make it
## unusually fragile to hits.
func test_the_stone_dam_is_as_durable_as_other_stone_work():
	assert_eq(BuildingPiece.material_of("stone_dam"), BuildingPiece.MATERIAL_STONE)
	assert_gt(BuildingPiece.durability_of("stone_dam"), 0.0)


## It holds back water, not a roof. Keeping it out of the span solver means
## BuildingStatics never treats a dam run as an unsupported cantilever and
## collapses it for a reason that has nothing to do with dams.
func test_the_stone_dam_is_not_load_bearing():
	assert_false(BuildingPiece.is_load_bearing("stone_dam"))
