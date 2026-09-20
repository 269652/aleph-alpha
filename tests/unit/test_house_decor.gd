extends GutTest

## HouseDecor (docs/concept/housing.md's "Occupation-themed decor" section) --
## the resolution to that doc's own "theme matching" Open Question, for the
## one real per-NPC signal this codebase already models: occupation identity.
## Deliberately NOT wealth-tiered -- see house_decor.gd's own file doc
## comment on why (VillageWages' own economy is deliberately neutral between
## producer and non-producer occupations).

const HouseDecor = preload("res://src/gameplay/house_decor.gd")
const NpcIdentity = preload("res://src/world/npc_identity.gd")
const BuildingPiece = preload("res://src/gameplay/building_piece.gd")


func test_every_real_occupation_has_a_furniture_set():
	for occupation in NpcIdentity.OCCUPATIONS:
		var set := HouseDecor.furniture_set_for(occupation)
		assert_false(set.is_empty(), occupation)


func test_every_piece_in_every_set_is_a_real_furniture_piece():
	for occupation in NpcIdentity.OCCUPATIONS:
		for piece_id in HouseDecor.furniture_set_for(occupation):
			assert_true(BuildingPiece.has_piece(piece_id), "%s: %s" % [occupation, piece_id])
			assert_eq(
				BuildingPiece.category_of(piece_id), BuildingPiece.CATEGORY_FURNITURE,
				"%s: %s" % [occupation, piece_id]
			)


func test_no_set_repeats_the_same_piece_twice():
	for occupation in NpcIdentity.OCCUPATIONS:
		var set := HouseDecor.furniture_set_for(occupation)
		var seen := {}
		for piece_id in set:
			assert_false(seen.has(piece_id), "%s repeats %s" % [occupation, piece_id])
			seen[piece_id] = true


## The couch is the one piece meant for a visitor to sit on (docs/concept/
## housing.md) -- reserved for the two occupations whose real work routinely
## brings other people to them (NpcIdentity.WORK_LOCATION_BY_OCCUPATION: a
## merchant's stall has customers, a nurse's well has patients), not hunter/
## guard/blacksmith's solitary or barracks-simple work.
func test_the_couch_goes_only_to_occupations_whose_work_involves_visitors():
	assert_true(HouseDecor.furniture_set_for("merchant").has("couch"))
	assert_true(HouseDecor.furniture_set_for("nurse").has("couch"))
	for occupation in ["guard", "hunter", "blacksmith", "farmer", "fisher", "herbalist"]:
		assert_false(HouseDecor.furniture_set_for(occupation).has("couch"), occupation)


## A herbalist's own real recipe (OccupationProduction) is butterfly_net --
## a specimen-collecting, knowledge-keeping trade, mirrored here by the one
## piece meant for keeping things: the bookshelf.
func test_the_herbalist_gets_a_bookshelf():
	assert_true(HouseDecor.furniture_set_for("herbalist").has("wood_bookshelf"))


func test_an_unrecognized_occupation_still_gets_a_real_non_empty_baseline():
	var set := HouseDecor.furniture_set_for("not_a_real_occupation")
	assert_false(set.is_empty())
	for piece_id in set:
		assert_true(BuildingPiece.has_piece(piece_id))


# -- a mage guild furnishes like a guild (docs/concept/mage_guild.md) -------
#
# The hall's shape is shared with the City Hall and the warehouse; what
# makes one READ as a mage guild is the same per-occupation slot
# resolution that already makes a smith's cottage differ from a farmer's.

const MageMaster = preload("res://src/gameplay/mage_master.gd")


func test_a_mage_works_at_a_bench_rather_than_out_of_a_crate():
	assert_eq(HouseDecor.piece_for_slot("W", MageMaster.OCCUPATION), "workbench")


func test_a_mage_keeps_books_rather_than_a_cupboard():
	assert_eq(HouseDecor.piece_for_slot("S", MageMaster.OCCUPATION), "wood_bookshelf")


func test_every_slot_a_hall_uses_resolves_for_a_mage():
	# A hall's whole slot vocabulary, minus the bed it deliberately has no
	# room for -- see InteriorTemplates._HALL_VARIANTS.
	for letter in ["T", "C", "R", "S", "P", "K", "W", "L"]:
		var piece: String = HouseDecor.piece_for_slot(letter, MageMaster.OCCUPATION)
		assert_true(BuildingPiece.has_piece(piece), "%s -> '%s'" % [letter, piece])
		assert_eq(BuildingPiece.category_of(piece), BuildingPiece.CATEGORY_FURNITURE, "%s" % letter)
