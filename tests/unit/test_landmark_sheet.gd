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
	assert_eq(LandmarkSheet.sheet_path_for("stall"), "res://assets/sprites/landmarks/stall.png")


func test_every_procedural_prop_has_somewhere_its_art_can_go():
	# Dropping the file in is the whole job -- nothing else has to change.
	for landmark_id in ProceduralLandmarkSprite.LANDMARK_IDS:
		assert_ne(LandmarkSheet.sheet_path_for(landmark_id), "", landmark_id)


func test_the_hunters_own_prop_is_covered_too():
	# hunting_ground has never had art of its own and falls back to the
	# well's sprite today -- a known cosmetic gap this closes the path for.
	assert_ne(LandmarkSheet.sheet_path_for("hunting_ground"), "")


## The well's art landed 2026-09-17; the rest of the props are still drawn
## from code, and that fallback is what this pins.
func test_a_prop_with_no_file_yet_reports_no_sheet():
	assert_false(
		LandmarkSheet.has_sheet("stall"),
		"no art has been supplied for the stall yet, so nothing overrides its sprite"
	)


func test_an_unknown_id_has_no_sheet_and_no_path():
	assert_eq(LandmarkSheet.sheet_path_for(""), "")
	assert_false(LandmarkSheet.has_sheet(""))


# -- variants, for a prop whose art is a grid ------------------------------


func test_a_plain_sheet_is_one_cell():
	assert_eq(LandmarkSheet.grid_of("stall"), Vector2i(1, 1))


func test_the_only_cell_of_a_plain_sheet_is_the_one_chosen():
	for seed_value in [0, 1, 7, 99, -4]:
		assert_eq(LandmarkSheet.variant_cell_for("stall", seed_value), Vector2i.ZERO)


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


# -- the well, whose art was delivered 2026-09-17 --------------------------
#
# Delivered into assets/sprites/buildings/ rather than assets/sprites/
# landmarks/, as a 5x5 grid of 25 wells with MAGENTA divider lines between
# the cells (measured, tools/probe_building_lifecycle_sheet.gd). All three
# of those differ from this module's own defaults, so all three are
# declared per id rather than assumed.

func test_the_well_has_real_art_now():
	assert_true(LandmarkSheet.has_sheet("well"), "the sheet was delivered -- it should be found")


func test_the_wells_art_is_read_from_where_it_was_actually_delivered():
	var path := LandmarkSheet.sheet_path_for("well")
	assert_eq(path, "res://assets/sprites/buildings/well.png")
	assert_true(FileAccess.file_exists(path), "and the file is really there")


func test_the_well_is_a_grid_of_twenty_five():
	assert_eq(LandmarkSheet.grid_of("well"), Vector2i(5, 5))


func test_every_one_of_the_twenty_five_wells_is_reachable():
	var seen: Dictionary = {}
	for seed_value in 4000:
		seen[LandmarkSheet.variant_cell_for("well", seed_value)] = true
	assert_eq(seen.size(), 25, "a well nobody's seed can reach is art nobody will ever see")


func test_a_well_keeps_the_same_look_across_reloads():
	for seed_value in [2, 88, 4242]:
		assert_eq(
			LandmarkSheet.variant_cell_for("well", seed_value),
			LandmarkSheet.variant_cell_for("well", seed_value)
		)


func test_the_wells_cells_are_cut_between_its_own_magenta_lines():
	var VariantSheetGrid = load("res://src/rendering/variant_sheet_grid.gd")
	var IllustratedStructureSprite = load("res://src/rendering/illustrated_structure_sprite.gd")
	var image := Image.load_from_file(LandmarkSheet.sheet_path_for("well"))
	assert_not_null(image, "precondition: the sheet loads")
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	var cell: Vector2i = LandmarkSheet.variant_cell_for("well", 11)
	var expected: Rect2i = VariantSheetGrid.divider_cell_rect(image, 5, 5, cell.y, cell.x)
	var frame: Image = LandmarkSheet.frame_image("well", 11, IllustratedStructureSprite.new())
	assert_not_null(frame, "the well's own art must actually come back")
	assert_eq(frame.get_size(), Vector2i(expected.size.x, expected.size.y))


func test_a_prop_with_no_declared_sheet_still_looks_in_the_landmarks_folder():
	for landmark_id in ProceduralLandmarkSprite.LANDMARK_IDS:
		if landmark_id == "well":
			continue
		assert_eq(
			LandmarkSheet.sheet_path_for(landmark_id),
			"res://assets/sprites/landmarks/%s.png" % landmark_id,
			"%s has no delivered art, so its door stays where it always was" % landmark_id
		)


func test_the_wells_own_background_is_keyed_out():
	var IllustratedStructureSprite = load("res://src/rendering/illustrated_structure_sprite.gd")
	var frame: Image = LandmarkSheet.frame_image("well", 11, IllustratedStructureSprite.new())
	assert_not_null(frame)
	var transparent := 0
	var opaque := 0
	for y in range(0, frame.get_height(), 3):
		for x in range(0, frame.get_width(), 3):
			if frame.get_pixel(x, y).a < 0.5:
				transparent += 1
			else:
				opaque += 1
	assert_gt(transparent, 0, "a well on an opaque black card would be a black card in the grass")
	assert_gt(opaque, 0, "and the well itself must still be there")


func test_no_magenta_divider_survives_into_a_wells_frame():
	var IllustratedStructureSprite = load("res://src/rendering/illustrated_structure_sprite.gd")
	for seed_value in [1, 2, 3, 4, 5]:
		var frame: Image = LandmarkSheet.frame_image("well", seed_value, IllustratedStructureSprite.new())
		for y in range(0, frame.get_height(), 2):
			for x in range(0, frame.get_width(), 2):
				var pixel := frame.get_pixel(x, y)
				if pixel.a < 0.5:
					continue
				assert_false(
					pixel.r >= 0.85 and pixel.b >= 0.85 and pixel.g <= 0.15,
					"a divider line survived into the frame at %d,%d" % [x, y]
				)
