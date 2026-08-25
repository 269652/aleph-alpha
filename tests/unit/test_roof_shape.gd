extends GutTest

## RoofShape (docs/concept/building.md "How a house reads from above"): the
## pure per-cell classifier that turns a building's flat set of roof cells
## into a PITCHED roof -- a ridge along the long axis, slopes falling away
## from it, and an outward edge mask for the building's silhouette.
##
## Pure over the cell set exactly like TerrainRenderer.dominant_blend_for/
## corner_direction_for are pure over neighbour biomes: no atlas, no image,
## no TileMapLayer, so the geometry can be pinned without baking anything.

const RoofShape = preload("res://src/rendering/roof_shape.gd")


## A rectangular block of roof cells, as the Dictionary-as-set every caller
## passes (cell -> anything; only the keys matter).
func _rect(origin: Vector2i, size: Vector2i) -> Dictionary:
	var cells := {}
	for y in size.y:
		for x in size.x:
			cells[origin + Vector2i(x, y)] = true
	return cells


# -- ridge orientation --------------------------------------------------------
#
# Real rafters span the SHORTER direction, so the ridge beam they lean
# against runs along the longer one. A wide house has a left-right ridge; a
# tall one has an up-down ridge.

func test_a_wide_roof_puts_its_ridge_along_the_horizontal_axis():
	assert_true(RoofShape.ridge_is_horizontal(_rect(Vector2i.ZERO, Vector2i(7, 3))))


func test_a_tall_roof_puts_its_ridge_along_the_vertical_axis():
	assert_false(RoofShape.ridge_is_horizontal(_rect(Vector2i.ZERO, Vector2i(3, 7))))


## A square has no longer axis -- it must still pick one deterministically
## rather than flickering between two equally-valid answers.
func test_a_square_roof_picks_a_stable_ridge_orientation():
	var square := _rect(Vector2i.ZERO, Vector2i(5, 5))
	assert_eq(RoofShape.ridge_is_horizontal(square), RoofShape.ridge_is_horizontal(square))


# -- shade bands: brightest at the ridge, falling to the eaves ----------------

func test_every_shade_band_is_within_the_declared_range():
	var cells := _rect(Vector2i.ZERO, Vector2i(9, 6))
	var classified := RoofShape.classify_all(cells)
	for cell in classified:
		var band: int = classified[cell].band
		assert_between(band, 0, RoofShape.TOTAL_SHADE_BANDS - 1, "cell %s" % cell)


## The whole point of a pitch: a cell ON the ridge must be brighter than one
## down at the eave of the same slope. Without this the roof is a flat
## texture, which is what made it read as a brick patio.
func test_a_ridge_cell_is_brighter_than_an_eave_cell_on_the_same_slope():
	# 9 wide x 7 tall -> horizontal ridge on row 3, lit slope above it.
	var cells := _rect(Vector2i.ZERO, Vector2i(9, 7))
	var classified := RoofShape.classify_all(cells)
	var ridge_band: int = classified[Vector2i(4, 3)].band
	var eave_band: int = classified[Vector2i(4, 0)].band
	assert_lt(ridge_band, eave_band, "lower band index means brighter; the ridge must be the brighter one")


## Light comes from the upper-left throughout this project (see
## ProceduralBuildingPieceSprite's own rim convention and docs/art/
## ai_sprite_prompts.md's shared style preamble), so the slope facing UP is
## lit and the one facing DOWN is shaded -- at the SAME distance from the
## ridge, the up-facing cell must be the brighter of the two.
func test_the_up_facing_slope_is_brighter_than_the_down_facing_one():
	var cells := _rect(Vector2i.ZERO, Vector2i(9, 7))
	var classified := RoofShape.classify_all(cells)
	var above: int = classified[Vector2i(4, 2)].band
	var below: int = classified[Vector2i(4, 4)].band
	assert_lt(above, below, "the up-facing slope catches the light")


## Brightness must fall MONOTONICALLY from ridge to eave down one slope --
## a non-monotonic ramp reads as banding/noise rather than as a surface
## turning away from the light.
func test_brightness_falls_monotonically_from_ridge_to_eave():
	var cells := _rect(Vector2i.ZERO, Vector2i(11, 9))
	var classified := RoofShape.classify_all(cells)
	var previous := -1
	# Row 4 is the ridge; walk UP the lit slope toward the eave at row 0.
	for y in range(4, -1, -1):
		var band: int = classified[Vector2i(5, y)].band
		assert_gte(band, previous, "row %d" % y)
		previous = band


## A vertical ridge must behave identically with the axes swapped -- the
## classifier can't be accidentally hardcoded to one orientation.
func test_a_tall_roof_shades_across_its_own_pitch_axis():
	var cells := _rect(Vector2i.ZERO, Vector2i(7, 11))
	var classified := RoofShape.classify_all(cells)
	var ridge_band: int = classified[Vector2i(3, 5)].band
	var eave_band: int = classified[Vector2i(0, 5)].band
	assert_lt(ridge_band, eave_band, "a vertical ridge pitches across x, not y")


# -- edge mask: the building's silhouette, not a per-tile rim -----------------
#
# The reported "randomly placed panels" look came from every tile drawing
# its own rim. A rim belongs only where the cell actually borders something
# outside its own building.

func test_an_interior_cell_has_no_outward_edges():
	var cells := _rect(Vector2i.ZERO, Vector2i(5, 5))
	var classified := RoofShape.classify_all(cells)
	assert_eq(classified[Vector2i(2, 2)].mask, 0, "a fully surrounded cell must draw no rim at all")


func test_a_top_left_corner_cell_reports_exactly_its_two_open_sides():
	var cells := _rect(Vector2i.ZERO, Vector2i(5, 5))
	var classified := RoofShape.classify_all(cells)
	assert_eq(classified[Vector2i(0, 0)].mask, RoofShape.EDGE_NORTH | RoofShape.EDGE_WEST)


func test_a_bottom_right_corner_cell_reports_exactly_its_two_open_sides():
	var cells := _rect(Vector2i.ZERO, Vector2i(5, 5))
	var classified := RoofShape.classify_all(cells)
	assert_eq(classified[Vector2i(4, 4)].mask, RoofShape.EDGE_SOUTH | RoofShape.EDGE_EAST)


func test_a_straight_top_run_reports_only_its_north_side():
	var cells := _rect(Vector2i.ZERO, Vector2i(5, 5))
	var classified := RoofShape.classify_all(cells)
	assert_eq(classified[Vector2i(2, 0)].mask, RoofShape.EDGE_NORTH)


func test_every_mask_is_a_four_bit_value():
	var cells := _rect(Vector2i.ZERO, Vector2i(6, 4))
	var classified := RoofShape.classify_all(cells)
	for cell in classified:
		assert_between(classified[cell].mask, 0, 15, "cell %s" % cell)


# -- separate buildings are separate roofs ------------------------------------
#
# A chunk's roof_modifications holds EVERY house in that chunk at once. Two
# neighbouring houses must each get their own ridge from their OWN footprint
# -- treating the chunk's whole roof set as one bounding box would run a
# single ridge across the gap between two unrelated buildings.

func test_two_separate_buildings_are_classified_independently():
	var cells := _rect(Vector2i.ZERO, Vector2i(3, 9))
	cells.merge(_rect(Vector2i(20, 0), Vector2i(9, 3)))
	var classified := RoofShape.classify_all(cells)
	# The tall one pitches across x; the wide one pitches across y. If they
	# shared a bounding box neither would.
	assert_lt(
		classified[Vector2i(1, 4)].band, classified[Vector2i(0, 4)].band,
		"the tall building must pitch across its own short axis"
	)
	assert_lt(
		classified[Vector2i(24, 1)].band, classified[Vector2i(24, 0)].band,
		"the wide building must pitch across its own short axis"
	)


## Two houses one tile apart must not have their edge masks bleed together:
## the facing sides of each are still that building's own outer boundary.
func test_adjacent_but_separate_buildings_keep_their_own_silhouettes():
	var cells := _rect(Vector2i.ZERO, Vector2i(3, 3))
	cells.merge(_rect(Vector2i(5, 0), Vector2i(3, 3)))
	var classified := RoofShape.classify_all(cells)
	assert_true(
		(classified[Vector2i(2, 1)].mask & RoofShape.EDGE_EAST) != 0,
		"the left building's right side is still an outer edge"
	)
	assert_true(
		(classified[Vector2i(5, 1)].mask & RoofShape.EDGE_WEST) != 0,
		"the right building's left side is still an outer edge"
	)


## Cells that DO touch across the component boundary belong to one building
## by definition -- orthogonal adjacency is what "same building" means here,
## the same connectivity RoomDetector's own flood fill uses.
func test_touching_cells_are_one_building_not_two():
	var cells := _rect(Vector2i.ZERO, Vector2i(4, 3))
	cells.merge(_rect(Vector2i(4, 0), Vector2i(4, 3)))
	var classified := RoofShape.classify_all(cells)
	assert_eq(classified[Vector2i(3, 1)].mask & RoofShape.EDGE_EAST, 0, "these two halves are one 8-wide building")


# -- L-shaped and irregular footprints ---------------------------------------

func test_an_l_shaped_roof_classifies_every_one_of_its_cells():
	var cells := _rect(Vector2i.ZERO, Vector2i(6, 3))
	cells.merge(_rect(Vector2i.ZERO, Vector2i(3, 6)))
	var classified := RoofShape.classify_all(cells)
	assert_eq(classified.size(), cells.size(), "no cell may be left unclassified")


func test_the_inner_corner_of_an_l_shape_is_not_treated_as_an_outer_edge():
	var cells := _rect(Vector2i.ZERO, Vector2i(6, 3))
	cells.merge(_rect(Vector2i.ZERO, Vector2i(3, 6)))
	var classified := RoofShape.classify_all(cells)
	# (2,2) has roof on all four sides within the L -- nothing outward.
	assert_eq(classified[Vector2i(2, 2)].mask, 0)


# -- degenerate inputs --------------------------------------------------------

func test_an_empty_roof_classifies_to_nothing_rather_than_crashing():
	assert_eq(RoofShape.classify_all({}).size(), 0)


func test_a_single_cell_roof_is_all_edges():
	var classified := RoofShape.classify_all({Vector2i(3, 3): true})
	assert_eq(classified[Vector2i(3, 3)].mask, 15, "a one-tile shed is boundary on every side")


## Compared field by field rather than dictionary-to-dictionary: this
## project targets Godot 4.7, where Dictionary equality is value-based, but
## a per-cell comparison says exactly WHICH cell drifted if this ever fails
## instead of just "the two dictionaries differ".
func test_classification_is_deterministic():
	var cells := _rect(Vector2i.ZERO, Vector2i(7, 5))
	var first := RoofShape.classify_all(cells)
	var second := RoofShape.classify_all(cells)
	assert_eq(first.size(), second.size())
	for cell in first:
		assert_eq(first[cell].band, second[cell].band, "band drifted at %s" % cell)
		assert_eq(first[cell].mask, second[cell].mask, "mask drifted at %s" % cell)


## A shallow roof must still have a LIT side. Distance from the ridge is
## counted in tiles rather than normalized to the roof's own depth,
## specifically because normalizing put both rows of a 3x3 hut's two-row
## pitch at maximum distance from their own ridge -- so the whole hut came
## out uniformly dark, with no lit slope at all.
func test_a_two_row_pitch_still_gets_a_lit_slope_and_a_shaded_one():
	var cells := _rect(Vector2i.ZERO, Vector2i(3, 2))
	var classified := RoofShape.classify_all(cells)
	assert_eq(classified[Vector2i(1, 0)].band, 0, "the upper row is the lit slope at full brightness")
	assert_eq(
		classified[Vector2i(1, 1)].band, RoofShape.FIRST_SHADED_BAND,
		"the lower row is the shaded slope at ITS brightest, not the darkest band available"
	)


## The same fact from the other end: a deep roof does not stretch its ramp
## to fit. Cells the same number of tiles from their ridge share a band
## whether the building is small or large, so two houses of different sizes
## sitting side by side read as the same kind of roof.
func test_pitch_shading_does_not_stretch_with_the_buildings_size():
	var small := RoofShape.classify_all(_rect(Vector2i.ZERO, Vector2i(9, 5)))
	var large := RoofShape.classify_all(_rect(Vector2i.ZERO, Vector2i(9, 9)))
	# One tile above the ridge in each: row 1 of 5-deep, row 3 of 9-deep.
	assert_eq(small[Vector2i(4, 1)].band, large[Vector2i(4, 3)].band)


# -- stepping inside lifts the roof off the whole room, walls included --------
#
# Roofs now cover a building's walls too, so hiding only the room's floor
# cells would leave the player standing in a floor bounded by roof, never
# able to see the room's own walls or the windows in them.

const BuildingPiece = preload("res://src/gameplay/building_piece.gd")


## A 3x3 house: wall ring, one floor cell in the middle.
func _tiny_house() -> Dictionary:
	var structure := {}
	for y in 3:
		for x in 3:
			var cell := Vector2i(x, y)
			structure[cell] = (
				"wood_floor" if cell == Vector2i(1, 1) else "wood_wall"
			)
	return structure


func test_revealing_a_room_also_reveals_the_walls_enclosing_it():
	var revealed := RoofShape.revealed_cells([Vector2i(1, 1)], _tiny_house())
	assert_eq(revealed.size(), 9, "the whole 3x3 house should be revealed, not just its one floor cell")


## The corners touch the room only diagonally, so a cardinal-only ring would
## leave four stray roof tiles pinned at the corners of an opened room.
func test_the_rooms_corner_walls_are_revealed_too():
	var revealed := RoofShape.revealed_cells([Vector2i(1, 1)], _tiny_house())
	for corner in [Vector2i(0, 0), Vector2i(2, 0), Vector2i(0, 2), Vector2i(2, 2)]:
		assert_true(revealed.has(corner), "corner %s stayed roofed" % corner)


## Only real building pieces come off. Standing in a house next to a
## campfire or a worn dirt path must not strip anything outside the
## building itself.
func test_non_building_modifications_next_to_a_room_are_not_revealed():
	var structure := _tiny_house()
	structure[Vector2i(3, 1)] = "campfire"
	structure[Vector2i(3, 0)] = "earth"
	var revealed := RoofShape.revealed_cells([Vector2i(1, 1)], structure)
	assert_false(revealed.has(Vector2i(3, 1)), "a campfire is not part of the house")
	assert_false(revealed.has(Vector2i(3, 0)), "a worn earth tile is not part of the house")


## A cell with nothing on it at all is likewise left alone -- open ground
## beside a house has no roof to lift.
func test_empty_ground_beside_a_room_is_not_revealed():
	var revealed := RoofShape.revealed_cells([Vector2i(1, 1)], _tiny_house())
	assert_false(revealed.has(Vector2i(-1, 1)))


## Standing outside reveals nothing, so the village keeps all its roofs.
func test_an_empty_room_reveals_nothing():
	assert_eq(RoofShape.revealed_cells([], _tiny_house()).size(), 0)
