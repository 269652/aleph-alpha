extends GutTest

## Where a village prop's real art lives, and what happens until it does.
##
## Asked for directly: the stands, wells, beds and workspot props are drawn
## from code (ProceduralLandmarkSprite) and look out of place beside the
## real pixel art the houses and the city hall now have. This is the same
## contract BuildingCatalog._VARIANT_SHEETS gives a building, pointed at
## props: a file at a known path takes over, and until that file exists the
## procedural sprite is drawn exactly as before.
##
## Deliberately ONE variant per sheet by default. A building's sheet is a
## 5x5 grid because 25 cottages make a street look unrepeated; asking for
## 25 drawings of a well to get a well is the wrong trade. An id that DOES
## get a variant grid declares it, and then draws from it seeded, the same
## way a house does.

const LandmarkSheet = preload("res://src/rendering/landmark_sheet.gd")
const ProceduralLandmarkSprite = preload("res://src/rendering/procedural_landmark_sprite.gd")


func test_a_props_sheet_has_a_predictable_path():
	assert_eq(LandmarkSheet.sheet_path_for("well"), "res://assets/sprites/landmarks/well.png")


func test_every_procedural_prop_has_somewhere_its_art_can_go():
	# Dropping the file in is the whole job -- nothing else has to change.
	for landmark_id in ProceduralLandmarkSprite.LANDMARK_IDS:
		assert_ne(LandmarkSheet.sheet_path_for(landmark_id), "", landmark_id)


func test_the_hunters_own_prop_is_covered_too():
	# hunting_ground has never had art of its own and falls back to the
	# well's sprite today -- a known cosmetic gap this closes the path for.
	assert_ne(LandmarkSheet.sheet_path_for("hunting_ground"), "")


func test_a_prop_with_no_file_yet_reports_no_sheet():
	assert_false(LandmarkSheet.has_sheet("well"), "no art has been supplied yet, so nothing overrides the sprite")


func test_an_unknown_id_has_no_sheet_and_no_path():
	assert_eq(LandmarkSheet.sheet_path_for(""), "")
	assert_false(LandmarkSheet.has_sheet(""))


# -- variants, for a prop whose art is a grid ------------------------------


func test_a_plain_sheet_is_one_cell():
	assert_eq(LandmarkSheet.grid_of("well"), Vector2i(1, 1))


func test_the_only_cell_of_a_plain_sheet_is_the_one_chosen():
	for seed_value in [0, 1, 7, 99, -4]:
		assert_eq(LandmarkSheet.variant_cell_for("well", seed_value), Vector2i.ZERO)


func test_a_declared_grid_spreads_its_seeds_over_every_cell():
	# Pinned against a declared grid rather than a real file, so this holds
	# before any art exists. Uses the same shape BuildingCatalog.
	# variant_cell_for does: independent hashes per axis, so the pair
	# covers the grid instead of walking its diagonal.
	var seen := {}
	for seed_value in 400:
		var cell: Vector2i = LandmarkSheet.variant_cell_for_grid(seed_value, Vector2i(3, 2))
		assert_true(cell.x >= 0 and cell.x < 3, "column in range")
		assert_true(cell.y >= 0 and cell.y < 2, "row in range")
		seen[cell] = true
	assert_eq(seen.size(), 6, "every cell of a 3x2 grid must be reachable")


func test_the_same_seed_always_picks_the_same_cell():
	var first: Vector2i = LandmarkSheet.variant_cell_for_grid(12345, Vector2i(5, 5))
	assert_eq(LandmarkSheet.variant_cell_for_grid(12345, Vector2i(5, 5)), first)
