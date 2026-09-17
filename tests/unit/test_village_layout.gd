extends GutTest

## VillageLayout: an Anno-style road-frontage layout (docs/concept/
## building.md "Buildings are entities; interiors are scenes", pillar 5)
## instead of the old ring -- a spine street with buildings on its north
## side, doors facing south onto it (the doorstep IS a road cell), one-tile
## gaps between plots; a street that runs out of room opens a further one
## south of it. Pure and seeded, tested here with stub predicates.

const VillageLayout = preload("res://src/world/village_layout.gd")
const BuildingCatalog = preload("res://src/gameplay/building_catalog.gd")

const CHUNK_SIZE := 32

var layout: VillageLayout


func before_each():
	layout = VillageLayout.new()


func _always_buildable(_cell: Vector2i) -> bool:
	return true


func _never_buildable(_cell: Vector2i) -> bool:
	return false


func _never_occupied(_cell: Vector2i) -> bool:
	return false


func test_places_every_building_when_there_is_ample_room():
	var ids := ["house_small", "house_small", "house_medium"]
	var result := layout.layout(ids, CHUNK_SIZE, 1, _always_buildable, _never_occupied)
	assert_eq(result["plots"].size(), 3)
	var placed_ids := []
	for plot in result["plots"]:
		placed_ids.append(plot["building_id"])
	placed_ids.sort()
	var expected := ids.duplicate()
	expected.sort()
	assert_eq(placed_ids, expected)


## The doorstep IS a road cell -- what makes the plot actually FRONT the
## street rather than merely stand near it.
func test_every_plots_doorstep_is_a_road_cell():
	var ids := ["house_small", "house_medium"]
	var result := layout.layout(ids, CHUNK_SIZE, 2, _always_buildable, _never_occupied)
	var road_cells: Array = result["road_cells"]
	for plot in result["plots"]:
		assert_true(road_cells.has(plot["doorstep"]), "doorstep %s should be a road cell" % str(plot["doorstep"]))


## Every plot's own door faces the road south of it -- computed from
## BuildingCatalog directly, not re-derived, so this pins that layout
## actually uses the catalog's own door convention.
func test_every_plots_doorstep_equals_its_origin_plus_the_catalogs_doorstep():
	var ids := ["house_medium"]
	var result := layout.layout(ids, CHUNK_SIZE, 3, _always_buildable, _never_occupied)
	assert_eq(result["plots"].size(), 1)
	var plot: Dictionary = result["plots"][0]
	assert_eq(plot["doorstep"], plot["origin"] + BuildingCatalog.doorstep_of(plot["building_id"]))
	assert_eq(plot["facing"], Vector2i(0, 1), "faces south, onto the road")


## Every plot reports which ORIGINAL building_ids index it came from -- the
## caller (VillageRenderer, mapping plots back to the npc that ordered
## each one) cannot assume placed plots are a plain prefix of the request:
## a building that fits nowhere is skipped without shifting the indices of
## the ones behind it.
func test_every_plot_reports_its_original_building_ids_index():
	var ids := ["house_small", "house_medium", "house_large"]
	var result := layout.layout(ids, CHUNK_SIZE, 13, _always_buildable, _never_occupied)
	assert_eq(result["plots"].size(), 3)
	var seen_indices := []
	for plot in result["plots"]:
		assert_eq(ids[plot["building_index"]], plot["building_id"])
		seen_indices.append(plot["building_index"])
	seen_indices.sort()
	assert_eq(seen_indices, [0, 1, 2])


## The actual case building_index exists for: a building that can never
## fit anywhere (every 3rd column is occupied -- never 4 contiguous free
## columns for house_large, but plenty of 2-wide gaps for house_small)
## must not stop LATER, smaller buildings from still being tried and
## placed with their own real index intact.
## REVISED: this used to occupy every third COLUMN, which shreds the spine
## into two-cell runs -- and a village now builds on one unbroken run of
## street (see the connectivity section at the end of this file), so that
## world can no longer host a village at all and stopped expressing what
## this test is about. The intent is unchanged and now stated more
## directly: house_large is 4x3 and house_small 2x2, so occupying the one
## row only the taller building needs makes the large one genuinely
## unplaceable while leaving the small one a clear, connected street.
func test_an_unplaceable_building_does_not_block_later_ones_from_their_own_index():
	var third_row_north: int = CHUNK_SIZE / 2 - 3
	var is_occupied := func(cell: Vector2i) -> bool: return cell.y == third_row_north
	var ids := ["house_large", "house_small"]
	var result := layout.layout(ids, CHUNK_SIZE, 14, _always_buildable, is_occupied)
	assert_eq(result["plots"].size(), 1)
	assert_eq(result["plots"][0]["building_index"], 1)
	assert_eq(result["plots"][0]["building_id"], "house_small")


func test_no_two_plots_footprints_ever_overlap():
	var ids := ["house_small", "house_small", "house_small", "house_medium", "house_large", "house_small"]
	var result := layout.layout(ids, CHUNK_SIZE, 4, _always_buildable, _never_occupied)
	var claimed := {}
	for plot in result["plots"]:
		for cell in BuildingCatalog.footprint_cells(plot["building_id"], plot["origin"]):
			assert_false(claimed.has(cell), "cell %s claimed twice" % str(cell))
			claimed[cell] = true


## At least a one-tile gap between adjacent plots on the same street --
## measured directly, not assumed: no two plots' footprints are even
## ORTHOGONALLY adjacent.
func test_adjacent_plots_on_the_same_street_keep_a_real_gap():
	var ids := ["house_small", "house_small", "house_small"]
	var result := layout.layout(ids, CHUNK_SIZE, 5, _always_buildable, _never_occupied)
	var plots: Array = result["plots"]
	for a in plots.size():
		for b in range(a + 1, plots.size()):
			if plots[a]["origin"].y != plots[b]["origin"].y:
				continue  # different streets
			var cells_a: Dictionary = {}
			for cell in BuildingCatalog.footprint_cells(plots[a]["building_id"], plots[a]["origin"]):
				cells_a[cell] = true
			for cell in BuildingCatalog.footprint_cells(plots[b]["building_id"], plots[b]["origin"]):
				for dx in range(-1, 2):
					for dy in range(-1, 2):
						assert_false(cells_a.has(cell + Vector2i(dx, dy)), "plots %d/%d touch or overlap" % [a, b])


func test_a_building_that_fits_nowhere_is_simply_absent_from_plots():
	var result := layout.layout(["house_small"], CHUNK_SIZE, 6, _never_buildable, _never_occupied)
	assert_true(result["plots"].is_empty())


func test_unbuildable_land_does_not_stall_placing_the_rest():
	var half_buildable := func(cell: Vector2i) -> bool: return cell.x < CHUNK_SIZE / 2
	var ids := ["house_small", "house_small", "house_small", "house_small"]
	var result := layout.layout(ids, CHUNK_SIZE, 7, half_buildable, _never_occupied)
	assert_gt(result["plots"].size(), 0, "at least the buildable half should hold some houses")
	for plot in result["plots"]:
		for cell in BuildingCatalog.footprint_cells(plot["building_id"], plot["origin"]):
			assert_true(half_buildable.call(cell), str(cell))


## Already-occupied ground (another village's own earlier placement, a
## river the buildability predicate alone wouldn't catch) is refused the
## same as unbuildable ground.
func test_occupied_ground_is_refused_even_if_buildable():
	var occupied := {Vector2i(10, 15): true}
	var is_occupied := func(cell: Vector2i) -> bool: return occupied.has(cell)
	var result := layout.layout(["house_small"], CHUNK_SIZE, 8, _always_buildable, is_occupied)
	for plot in result["plots"]:
		for cell in BuildingCatalog.footprint_cells(plot["building_id"], plot["origin"]):
			assert_false(occupied.has(cell))


## More buildings than one street can hold opens a second street further
## south, not stacked or overlapping the first.
func test_a_full_street_opens_a_second_one_further_south():
	var ids: Array = []
	for i in 20:
		ids.append("house_small")
	var result := layout.layout(ids, CHUNK_SIZE, 9, _always_buildable, _never_occupied)
	var street_ys := {}
	for plot in result["plots"]:
		street_ys[plot["origin"].y] = true
	assert_gt(street_ys.size(), 1, "20 houses should not all fit on one street")


func test_every_cell_used_stays_inside_the_chunk():
	var ids: Array = []
	for i in 12:
		ids.append("house_medium")
	var result := layout.layout(ids, CHUNK_SIZE, 10, _always_buildable, _never_occupied)
	for plot in result["plots"]:
		for cell in BuildingCatalog.footprint_cells(plot["building_id"], plot["origin"]):
			assert_true(cell.x >= 0 and cell.y >= 0 and cell.x < CHUNK_SIZE and cell.y < CHUNK_SIZE, str(cell))
	for cell in result["road_cells"]:
		assert_true(cell.x >= 0 and cell.y >= 0 and cell.x < CHUNK_SIZE and cell.y < CHUNK_SIZE, str(cell))


func test_layout_is_deterministic():
	var ids := ["house_small", "house_medium", "house_large", "house_small"]
	var a := layout.layout(ids, CHUNK_SIZE, 42, _always_buildable, _never_occupied)
	var b := layout.layout(ids, CHUNK_SIZE, 42, _always_buildable, _never_occupied)
	assert_eq(a, b)


func test_an_unknown_building_id_is_skipped_not_fatal():
	var ids := ["not_a_real_building", "house_small"]
	var result := layout.layout(ids, CHUNK_SIZE, 11, _always_buildable, _never_occupied)
	assert_eq(result["plots"].size(), 1)
	assert_eq(result["plots"][0]["building_id"], "house_small")


func test_empty_building_list_returns_empty_layout():
	var result := layout.layout([], CHUNK_SIZE, 12, _always_buildable, _never_occupied)
	assert_true(result["plots"].is_empty())
	assert_true(result["road_cells"].is_empty())


# -- layout v2: plaza, civic plot, gate, landmarks on the square, side streets
#
# docs/concept/building.md pillar 5 ("Villages are laid out, not scattered")
# made true end to end: the main street's middle is a paved plaza with the
# civic plot (the City Hall's reserved site, see civic_construction.md), the
# well and the stall ON it and a gate at the street's end; a second street,
# when one opens, is tied back to the plaza by side streets. All of it is a
# pure, seeded function of the chunk, so an older village's plaza can be
# re-derived on reload without persisting anything (VillageLayout.skeleton).

func _cells_of(rect: Rect2i) -> Array:
	var out: Array = []
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			out.append(Vector2i(x, y))
	return out


func test_seed_for_is_the_renderers_own_layout_seed_formula():
	assert_eq(VillageLayout.seed_for(Vector2i(3, -4)), hash("3_-4_village_layout"))


func test_skeleton_is_deterministic_and_puts_the_main_street_through_the_chunks_middle():
	var a: Dictionary = VillageLayout.skeleton(CHUNK_SIZE, 42)
	var b: Dictionary = VillageLayout.skeleton(CHUNK_SIZE, 42)
	assert_eq(a, b)
	assert_eq(a["street_y"], CHUNK_SIZE / 2)
	assert_lt(a["street_x0"], a["street_x1"])


func test_a_villages_plaza_is_a_paved_square_straddling_the_main_street():
	var result := layout.layout(["house_small", "house_medium"], CHUNK_SIZE, 3, _always_buildable, _never_occupied)
	var plaza: Rect2i = result["plaza"]
	assert_gt(plaza.size.x * plaza.size.y, 0, "a village on ample ground always gets its plaza")
	var road_cells: Array = result["road_cells"]
	for cell in _cells_of(plaza):
		assert_true(road_cells.has(cell), "plaza cell %s must be paved" % str(cell))
	var street_y: int = VillageLayout.skeleton(CHUNK_SIZE, 3)["street_y"]
	assert_true(plaza.position.y <= street_y and street_y < plaza.end.y, "the plaza straddles the street")


func test_the_civic_plot_sits_on_the_plaza_and_fronts_the_main_street():
	var result := layout.layout(["house_small"], CHUNK_SIZE, 3, _always_buildable, _never_occupied)
	var civic: Dictionary = result["civic_plot"]
	assert_eq(civic["building_id"], VillageLayout.CIVIC_BUILDING_ID)
	var plaza: Rect2i = result["plaza"]
	for cell in BuildingCatalog.footprint_cells(civic["building_id"], civic["origin"]):
		assert_true(plaza.has_point(cell), "civic footprint cell %s must lie on the plaza" % str(cell))
	var street_y: int = VillageLayout.skeleton(CHUNK_SIZE, 3)["street_y"]
	assert_eq(civic["doorstep"], civic["origin"] + BuildingCatalog.doorstep_of(civic["building_id"]))
	assert_eq(civic["doorstep"].y, street_y, "the hall's door opens onto the main street")
	assert_true((result["road_cells"] as Array).has(civic["doorstep"]))


func test_no_plot_footprint_ever_overlaps_a_road_cell_plaza_included():
	var ids: Array = []
	for i in 14:
		ids.append("house_small" if i % 3 else "house_large")
	var result := layout.layout(ids, CHUNK_SIZE, 4, _always_buildable, _never_occupied)
	var road := {}
	for cell in result["road_cells"]:
		road[cell] = true
	assert_gt(result["plots"].size(), 0, "precondition")
	for plot in result["plots"]:
		for cell in BuildingCatalog.footprint_cells(plot["building_id"], plot["origin"]):
			assert_false(road.has(cell), "footprint cell %s stands on a road/plaza cell" % str(cell))


func test_the_gate_stands_on_the_main_street_at_its_end_and_no_doorstep_shares_it():
	var result := layout.layout(["house_small", "house_small", "house_medium"], CHUNK_SIZE, 5, _always_buildable, _never_occupied)
	var gate: Vector2i = result["landmarks"]["gate"]
	var skeleton: Dictionary = VillageLayout.skeleton(CHUNK_SIZE, 5)
	assert_eq(gate.y, skeleton["street_y"])
	assert_eq(gate.x, skeleton["street_x0"], "the gate marks where the street enters the village")
	assert_true((result["road_cells"] as Array).has(gate))
	for plot in result["plots"]:
		assert_ne(plot["doorstep"], gate, "a house must not open onto the gate itself")


func test_the_well_and_the_stall_stand_on_the_plaza_clear_of_the_civic_plot():
	var result := layout.layout(["house_small"], CHUNK_SIZE, 6, _always_buildable, _never_occupied)
	var plaza: Rect2i = result["plaza"]
	var civic: Dictionary = result["civic_plot"]
	var civic_cells: Array = BuildingCatalog.footprint_cells(civic["building_id"], civic["origin"])
	for landmark in ["well", "stall"]:
		var cell: Vector2i = result["landmarks"][landmark]
		assert_true(plaza.has_point(cell), "%s must stand on the plaza" % landmark)
		assert_false(civic_cells.has(cell), "%s must not stand where the hall will rise" % landmark)
		assert_ne(cell, civic["doorstep"], "%s must not block the hall's door" % landmark)
	assert_ne(result["landmarks"]["well"], result["landmarks"]["stall"])


func test_the_main_street_is_paved_along_its_whole_buildable_length():
	var result := layout.layout(["house_small"], CHUNK_SIZE, 7, _always_buildable, _never_occupied)
	var skeleton: Dictionary = VillageLayout.skeleton(CHUNK_SIZE, 7)
	var road_cells: Array = result["road_cells"]
	for x in range(skeleton["street_x0"], skeleton["street_x1"] + 1):
		assert_true(road_cells.has(Vector2i(x, skeleton["street_y"])), "street cell x=%d must be paved" % x)


## Superseded in part: the square SLIDES now (see plaza_x0_for), so ground
## blocked where it was designed no longer means no square at all -- it
## means the square moves. What still has to hold, and is the real
## invariant, is that the village is still a village: houses placed, and
## nothing paved on ground it was told it cannot use.
func test_a_blocked_square_site_moves_the_square_and_still_houses_people():
	var skeleton: Dictionary = VillageLayout.skeleton(CHUNK_SIZE, 8)
	var plaza_site: Rect2i = skeleton["plaza"]
	var not_on_the_square := func(cell: Vector2i) -> bool: return not plaza_site.has_point(cell)
	var result := layout.layout(["house_small", "house_small"], CHUNK_SIZE, 8, not_on_the_square, _never_occupied)
	assert_gt(result["plots"].size(), 0, "houses still line the street")
	for cell in result["road_cells"]:
		assert_true(not_on_the_square.call(cell), "nothing paved on unbuildable ground (%s)" % str(cell))
	var plaza: Rect2i = result["plaza"]
	if plaza.has_area():
		for y in range(plaza.position.y, plaza.end.y):
			for x in range(plaza.position.x, plaza.end.x):
				assert_true(
					not_on_the_square.call(Vector2i(x, y)),
					"the square moved onto ground it was told it cannot use"
				)


func test_side_streets_tie_a_second_street_back_to_the_plaza():
	var ids: Array = []
	for i in 20:
		ids.append("house_small")
	var result := layout.layout(ids, CHUNK_SIZE, 9, _always_buildable, _never_occupied)
	var street_ys := {}
	for plot in result["plots"]:
		street_ys[plot["doorstep"].y] = true
	assert_gt(street_ys.size(), 1, "precondition: 20 houses open a second street")
	var plaza: Rect2i = result["plaza"]
	var ys: Array = street_ys.keys()
	ys.sort()
	var second_street_y: int = ys[1]  # the side streets reach the SECOND street, whatever opens beyond it
	var road_cells: Array = result["road_cells"]
	for x in [plaza.position.x, plaza.end.x - 1]:
		for y in range(plaza.end.y, second_street_y + 1):
			assert_true(road_cells.has(Vector2i(x, y)), "side street cell %s must be paved" % str(Vector2i(x, y)))


func test_a_village_that_fits_on_one_street_lays_no_side_streets():
	var result := layout.layout(["house_small", "house_small"], CHUNK_SIZE, 10, _always_buildable, _never_occupied)
	var plaza: Rect2i = result["plaza"]
	var road_cells: Array = result["road_cells"]
	for cell in road_cells:
		assert_true(
			cell.y <= plaza.end.y - 1,
			"nothing paved south of the plaza when no second street opened (%s)" % str(cell)
		)


# -- the industry plot: a sawmill at the forest, joined by a real road spur
#
# docs/concept/village_growth.md mechanism 1. A sawmill stands at the
# timber, not on the village square -- and a real track is laid to it,
# because a building the village cannot walk to is not part of the village.
# Pure and seeded like the rest of this module: stub predicates only.

const _SAWMILL := "sawmill"


## Forest filling the chunk's own southern band -- far enough from the
## street that a plot at its edge is genuinely outlying.
func _forest_in_the_south(cell: Vector2i) -> bool:
	return cell.y >= CHUNK_SIZE - 8


func _no_forest(_cell: Vector2i) -> bool:
	return false


## Buildable everywhere EXCEPT the forest itself -- the real rule
## (EarthChunkManager.is_buildable_ground_at refuses the forest biome).
func _buildable_outside_the_southern_forest(cell: Vector2i) -> bool:
	return not _forest_in_the_south(cell)


func test_no_forest_in_range_means_no_industry_plot():
	var plot: Dictionary = VillageLayout.industry_plot(
		_SAWMILL, CHUNK_SIZE, 31, _always_buildable, _no_forest, _never_occupied
	)
	assert_true(plot.is_empty(), "a village on open steppe honestly has no sawmill")


func test_the_industry_plot_stands_on_buildable_ground_beside_the_forest():
	var plot: Dictionary = VillageLayout.industry_plot(
		_SAWMILL, CHUNK_SIZE, 32, _buildable_outside_the_southern_forest, _forest_in_the_south, _never_occupied
	)
	assert_false(plot.is_empty(), "a village with forest in range raises its sawmill at it")
	assert_eq(plot["building_id"], _SAWMILL)
	var cells: Array = BuildingCatalog.footprint_cells(_SAWMILL, plot["origin"])
	var near_forest := false
	for cell in cells:
		assert_false(_forest_in_the_south(cell), "the mill itself never stands IN the forest")
		for dy in range(-VillageLayout.INDUSTRY_FOREST_REACH_TILES, VillageLayout.INDUSTRY_FOREST_REACH_TILES + 1):
			for dx in range(-VillageLayout.INDUSTRY_FOREST_REACH_TILES, VillageLayout.INDUSTRY_FOREST_REACH_TILES + 1):
				if _forest_in_the_south(cell + Vector2i(dx, dy)):
					near_forest = true
	assert_true(near_forest, "the mill must stand within reach of real forest")


func test_the_industry_plot_keeps_its_distance_from_the_square():
	var plot: Dictionary = VillageLayout.industry_plot(
		_SAWMILL, CHUNK_SIZE, 33, _buildable_outside_the_southern_forest, _forest_in_the_south, _never_occupied
	)
	assert_false(plot.is_empty(), "precondition")
	var plaza: Rect2i = VillageLayout.skeleton(CHUNK_SIZE, 33)["plaza"]
	var plaza_centre: Vector2i = plaza.position + plaza.size / 2
	var origin: Vector2i = plot["origin"]
	var distance: int = maxi(absi(origin.x - plaza_centre.x), absi(origin.y - plaza_centre.y))
	assert_gte(
		distance, VillageLayout.INDUSTRY_MIN_PLAZA_DISTANCE_TILES,
		"the works are outlying, not another plot on the square"
	)


## The whole point of the spur: the doorstep must actually reach the main
## street, walking only road. Verified by a real flood fill over the spur
## plus the street row, not by trusting the shape of the returned list.
func test_the_road_spur_connects_the_doorstep_to_the_main_street():
	var plot: Dictionary = VillageLayout.industry_plot(
		_SAWMILL, CHUNK_SIZE, 34, _buildable_outside_the_southern_forest, _forest_in_the_south, _never_occupied
	)
	assert_false(plot.is_empty(), "precondition")
	var bones: Dictionary = VillageLayout.skeleton(CHUNK_SIZE, 34)
	var street_y: int = bones["street_y"]

	var walkable := {}
	for cell in plot["road_spur"]:
		walkable[cell] = true
	for x in range(bones["street_x0"], bones["street_x1"] + 1):
		walkable[Vector2i(x, street_y)] = true

	var doorstep: Vector2i = plot["doorstep"]
	assert_true(walkable.has(doorstep), "the doorstep itself must be road")
	var seen := {doorstep: true}
	var frontier: Array = [doorstep]
	var reached_street := false
	while not frontier.is_empty():
		var cell: Vector2i = frontier.pop_back()
		if cell.y == street_y:
			reached_street = true
			break
		for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var next_cell: Vector2i = cell + step
			if walkable.has(next_cell) and not seen.has(next_cell):
				seen[next_cell] = true
				frontier.append(next_cell)
	assert_true(reached_street, "the spur must actually reach the street, walking only road")


## A spur must never be laid through the mill it serves.
func test_the_road_spur_never_runs_through_the_buildings_own_footprint():
	var plot: Dictionary = VillageLayout.industry_plot(
		_SAWMILL, CHUNK_SIZE, 35, _buildable_outside_the_southern_forest, _forest_in_the_south, _never_occupied
	)
	assert_false(plot.is_empty(), "precondition")
	var footprint := {}
	for cell in BuildingCatalog.footprint_cells(_SAWMILL, plot["origin"]):
		footprint[cell] = true
	for cell in plot["road_spur"]:
		assert_false(footprint.has(cell), "spur cell %s runs through the mill" % str(cell))


func test_an_unreachable_plot_is_refused_outright():
	# Forest in range but every cell occupied except the mill's own site --
	# no spur can be laid, so there is no plot at all rather than a mill
	# nobody can walk to.
	var plot: Dictionary = VillageLayout.industry_plot(
		_SAWMILL, CHUNK_SIZE, 36, _buildable_outside_the_southern_forest, _forest_in_the_south,
		func(cell: Vector2i) -> bool: return cell.y < CHUNK_SIZE - 12
	)
	assert_true(plot.is_empty(), "a mill the village cannot reach is not a mill")


func test_the_industry_plot_is_deterministic():
	var a: Dictionary = VillageLayout.industry_plot(
		_SAWMILL, CHUNK_SIZE, 37, _buildable_outside_the_southern_forest, _forest_in_the_south, _never_occupied
	)
	var b: Dictionary = VillageLayout.industry_plot(
		_SAWMILL, CHUNK_SIZE, 37, _buildable_outside_the_southern_forest, _forest_in_the_south, _never_occupied
	)
	assert_eq(a, b)


# -- the next free street plot: where a growth building actually goes ------
#
# docs/concept/village_growth.md mechanism 2: a village that owes itself a
# warehouse (or one more house for an arriving household) puts it on the
# next free frontage of its own street, not on a spiral-searched patch of
# wilderness.

func test_the_next_street_plot_fronts_the_street_with_its_doorstep_on_it():
	var plot: Dictionary = VillageLayout.next_street_plot(
		"warehouse", CHUNK_SIZE, 41, _always_buildable, _never_occupied
	)
	assert_false(plot.is_empty())
	var street_y: int = VillageLayout.skeleton(CHUNK_SIZE, 41)["street_y"]
	assert_eq(plot["doorstep"], plot["origin"] + BuildingCatalog.doorstep_of("warehouse"))
	assert_eq(plot["doorstep"].y, street_y, "a growth building fronts the main street")


## The plaza stays the plaza. Once paved it reads as OCCUPIED, and that
## must never be mistaken for "the square is free to build on".
func test_a_growth_building_never_lands_on_the_paved_plaza():
	var plaza: Rect2i = VillageLayout.skeleton(CHUNK_SIZE, 42)["plaza"]
	var paved := {}
	for cell in _cells_of(plaza):
		paved[cell] = true
	var plot: Dictionary = VillageLayout.next_street_plot(
		"warehouse", CHUNK_SIZE, 42, _always_buildable, func(cell: Vector2i) -> bool: return paved.has(cell)
	)
	assert_false(plot.is_empty(), "a paved square must not stop the village growing")
	for cell in BuildingCatalog.footprint_cells("warehouse", plot["origin"]) + [plot["doorstep"]]:
		assert_false(plaza.has_point(cell), "cell %s stands on the village square" % str(cell))


func test_the_next_street_plot_skips_ground_already_built_on():
	var first: Dictionary = VillageLayout.next_street_plot(
		"house_small", CHUNK_SIZE, 43, _always_buildable, _never_occupied
	)
	assert_false(first.is_empty(), "precondition")
	var taken := {}
	for cell in BuildingCatalog.footprint_cells("house_small", first["origin"]):
		taken[cell] = true
	var second: Dictionary = VillageLayout.next_street_plot(
		"house_small", CHUNK_SIZE, 43, _always_buildable, func(cell: Vector2i) -> bool: return taken.has(cell)
	)
	assert_false(second.is_empty())
	assert_ne(second["origin"], first["origin"], "the next household gets the NEXT plot, not the same one")


func test_no_street_plot_at_all_when_nothing_is_buildable():
	assert_true(
		VillageLayout.next_street_plot("warehouse", CHUNK_SIZE, 44, _never_buildable, _never_occupied).is_empty()
	)


# -- every house can be walked to (reported in play: "Not all houses are
# connected by streets.. this should be tested!") --------------------------
#
# The street is paved only where the ground allows it, so a river crossing
# it leaves two paved runs with no path between them. A house on the far
# run has a doorstep, and paving outside its door, and no way to reach the
# square -- which is what the report shows: separate islands of paving.
#
# The property is simple and worth pinning directly: from any one road
# cell, walking only on road cells (4-connected, the way anything on foot
# moves here), you can reach every other road cell AND every house's
# doorstep. A layout that cannot promise that has not laid a village, it
# has laid two.


## Every road cell reachable from `start` by 4-connected steps over road
## cells only.
func _reachable_road_cells(road_cells: Array, start: Vector2i) -> Dictionary:
	var roads := {}
	for cell in road_cells:
		roads[cell] = true
	var seen := {}
	var queue: Array = [start]
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_back()
		if seen.has(cell) or not roads.has(cell):
			continue
		seen[cell] = true
		for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var next: Vector2i = cell + step
			if roads.has(next) and not seen.has(next):
				queue.append(next)
	return seen


## A predicate that drowns one full column, the way a real river crossing a
## chunk does -- the exact shape that splits a street in two.
func _buildable_except_column(column: int) -> Callable:
	return func(cell: Vector2i) -> bool:
		return cell.x != column


func test_every_road_cell_is_reachable_from_every_other_on_open_ground():
	var result := layout.layout(
		["house_small", "house_small", "house_small", "house_small", "house_small"],
		CHUNK_SIZE, 1234, _always_buildable, _never_occupied
	)
	var roads: Array = result["road_cells"]
	assert_gt(roads.size(), 0, "precondition: something was paved")
	var reached := _reachable_road_cells(roads, roads[0])
	assert_eq(reached.size(), roads.size(), "the paving must be one network, not several islands")


func test_every_house_doorstep_is_reachable_from_the_paving():
	var result := layout.layout(
		["house_small", "house_small", "house_small", "house_small", "house_small"],
		CHUNK_SIZE, 4321, _always_buildable, _never_occupied
	)
	var roads: Array = result["road_cells"]
	var reached := _reachable_road_cells(roads, roads[0])
	for plot in result["plots"]:
		assert_true(
			reached.has(plot["doorstep"]),
			"a house whose door opens onto paving nobody can walk to is a house nobody can reach"
		)


func test_a_river_across_the_street_never_leaves_a_house_stranded():
	# The reported case: ground that is fine on both sides and impassable
	# down one column, so the street is paved in two runs.
	var result := layout.layout(
		["house_small", "house_small", "house_small", "house_small", "house_small"],
		CHUNK_SIZE, 99, _buildable_except_column(16), _never_occupied
	)
	var roads: Array = result["road_cells"]
	assert_gt(roads.size(), 0, "precondition: something was paved")
	var reached := _reachable_road_cells(roads, roads[0])
	assert_eq(
		reached.size(), roads.size(),
		"a village split by a river must pave one side only, not two disconnected halves"
	)
	for plot in result["plots"]:
		assert_true(reached.has(plot["doorstep"]), "every house placed must sit on the connected side")


func test_a_village_big_enough_for_a_second_street_is_still_one_network():
	# A further street south only connects through the side streets beside
	# the plaza, so a village that outgrows its spine is the other way this
	# can split.
	var many: Array = []
	for i in 12:
		many.append("house_small")
	var result := layout.layout(many, CHUNK_SIZE, 777, _always_buildable, _never_occupied)
	var roads: Array = result["road_cells"]
	assert_gt(result["plots"].size(), 5, "precondition: this village really did open a second street")
	var reached := _reachable_road_cells(roads, roads[0])
	assert_eq(reached.size(), roads.size(), "a second street must join the first, not float south of it")
	for plot in result["plots"]:
		assert_true(reached.has(plot["doorstep"]))


## Reported in play, twice, with a screenshot: a riverside village standing
## with three houses, no square and no hall, while five villagers lived
## there. A column of water through the chunk's own middle is exactly that
## shape -- it drowns the square (so `has_plaza` is false) AND splits the
## spine, leaving a run long enough for three houses and no more.
##
## A village with no square used to stop there: further streets were tied
## back to the spine ONLY by the two side streets beside the square, so
## without one there was nothing to hang them on and the loop broke. That
## is an honest rule about CONNECTIVITY, but the wrong conclusion -- the
## village still has a gate, and a lane from the gate reaches a further
## street just as well as a side street does.
func test_a_village_with_no_square_still_houses_everyone_it_arrived_with():
	var five := ["house_small", "house_small", "house_small", "house_small", "house_small"]
	# Water down the chunk's middle AND across the row the square's own
	# northern edge needs. The square can slide along the street (see
	# plaza_x0_for) but never off that row, so this village really has
	# nowhere to put one -- while a 2-deep house, standing on the two rows
	# directly north of the street, still fits perfectly well.
	var street_y: int = VillageLayout.skeleton(CHUNK_SIZE, 99)["street_y"]
	var no_square := func(cell: Vector2i) -> bool:
		return cell.x != CHUNK_SIZE / 2 and cell.y != street_y - VillageLayout.PLAZA_ROWS_NORTH
	var result := layout.layout(five, CHUNK_SIZE, 99, no_square, _never_occupied)
	var plaza: Rect2i = result["plaza"]
	assert_false(plaza.has_area(), "precondition: the water really does drown this village's square")
	assert_eq(
		result["plots"].size(), five.size(),
		"a village with no square must still house everyone who arrived with it"
	)
	var roads: Array = result["road_cells"]
	var reached := _reachable_road_cells(roads, result["plots"][0]["doorstep"])
	for plot in result["plots"]:
		assert_true(
			reached.has(plot["doorstep"]),
			"house at %s opens onto paving nobody can walk to" % str(plot["origin"])
		)
	assert_eq(reached.size(), roads.size(), "the paving must stay one network, not two islands")


# -- the square slides rather than drowns -----------------------------------
#
# Reported in play with a screenshot, twice: a riverside village with no
# square and no hall. The square was pinned to the chunk's exact middle, so
# a river through that middle meant no square at all -- and with no square
# there is no civic plot, and so no city hall, ever.
#
# The square is 8 tiles wide in a 32-tile chunk. There is real room beside
# the water; standing the square there is far more honest than standing
# nowhere. `is_dry` is deliberately a WATER test, not the general
# buildable/occupied pair: every caller must derive the SAME square, and
# water is the only input that never changes once the world is seeded --
# trees get felled, ground gets built on, rivers do not move.


func test_a_square_drowned_at_the_chunks_middle_slides_along_the_street():
	var bones: Dictionary = VillageLayout.skeleton(
		CHUNK_SIZE, 99, _buildable_except_column(CHUNK_SIZE / 2)
	)
	var plaza: Rect2i = bones["plaza"]
	assert_true(plaza.has_area(), "precondition: a square is still drawn")
	assert_true(
		plaza.end.x <= CHUNK_SIZE / 2 or plaza.position.x > CHUNK_SIZE / 2,
		"the square at %s still straddles the water at column %d" % [str(plaza), CHUNK_SIZE / 2]
	)


func test_the_civic_plot_and_landmarks_slide_with_the_square():
	var bones: Dictionary = VillageLayout.skeleton(
		CHUNK_SIZE, 99, _buildable_except_column(CHUNK_SIZE / 2)
	)
	var plaza: Rect2i = bones["plaza"]
	var civic_origin: Vector2i = bones["civic_plot"]["origin"]
	var footprint := BuildingCatalog.footprint_of(VillageLayout.CIVIC_BUILDING_ID)
	assert_gte(civic_origin.x, plaza.position.x, "the hall must stand on its own square")
	assert_lte(civic_origin.x + footprint.x, plaza.end.x, "the hall must stand on its own square")
	for landmark_id in ["well", "stall"]:
		var cell: Vector2i = bones["landmarks"][landmark_id]
		assert_true(
			plaza.has_point(cell),
			"%s at %s left the square behind at %s" % [landmark_id, str(cell), str(plaza)]
		)


func test_a_square_with_dry_ground_under_it_does_not_move():
	var centred: Dictionary = VillageLayout.skeleton(CHUNK_SIZE, 99)
	var checked: Dictionary = VillageLayout.skeleton(CHUNK_SIZE, 99, _always_buildable)
	assert_eq(checked["plaza"], centred["plaza"], "dry ground: the square keeps its designed place")
	assert_eq(checked["civic_plot"], centred["civic_plot"])
	assert_eq(checked["landmarks"], centred["landmarks"])


func test_the_slid_square_is_the_same_square_every_time_it_is_asked_for():
	var a: Dictionary = VillageLayout.skeleton(CHUNK_SIZE, 99, _buildable_except_column(CHUNK_SIZE / 2))
	var b: Dictionary = VillageLayout.skeleton(CHUNK_SIZE, 99, _buildable_except_column(CHUNK_SIZE / 2))
	assert_eq(a["plaza"], b["plaza"])
	assert_eq(a["civic_plot"], b["civic_plot"])
	assert_eq(a["landmarks"], b["landmarks"])


func test_a_village_with_nowhere_dry_for_a_square_keeps_its_designed_one_and_lays_none():
	var result := layout.layout(
		["house_small"], CHUNK_SIZE, 99, _never_buildable, _never_occupied
	)
	assert_true((result["plaza"] as Rect2i).size == Vector2i.ZERO, "no square is laid at all")
	assert_true((result["civic_plot"] as Dictionary).is_empty(), "and no civic plot with it")


func test_a_village_whose_middle_is_water_still_gets_a_square_and_a_civic_plot():
	var five := ["house_small", "house_small", "house_small", "house_small", "house_small"]
	var result := layout.layout(
		five, CHUNK_SIZE, 99, _buildable_except_column(CHUNK_SIZE / 2), _never_occupied
	)
	assert_true((result["plaza"] as Rect2i).has_area(), "a riverside village can still have its square")
	assert_false((result["civic_plot"] as Dictionary).is_empty(), "and therefore somewhere to put a hall")
	assert_eq(result["plots"].size(), five.size(), "and it still houses everyone")


# -- a plot on the outskirts, when the street has no room left --------------
#
# Measured in the real world (chunk (661,139) near lat 49.8 lon 10.6): a
# village wedged against a river, three houses, and next_street_plot with no
# extra condition at all returns {} for a 3x2 farmhouse -- while SIXTY
# origins elsewhere in the same chunk fit one, every one of them with a full
# field ring around it. Reported in play as "no farmers".
#
# A farmstead does not need street frontage the way a house does. It needs
# open ground and a path home, which is exactly what industry_plot already
# gives the sawmill.


## The two rows a street plot's own footprint needs, taken on EVERY street
## the village could open -- a village whose frontage is genuinely full,
## while the ground north of its spine is still wide open.
func _all_frontage_taken(street_y: int) -> Callable:
	return func(cell: Vector2i) -> bool:
		if cell.y >= street_y:
			var into: int = (cell.y - street_y) % VillageLayout.STREET_PITCH_TILES
			return into == VillageLayout.STREET_PITCH_TILES - 1 or into == VillageLayout.STREET_PITCH_TILES - 2
		return street_y - cell.y <= 2


func test_an_outskirt_plot_is_found_where_no_street_frontage_is_left():
	var street_y: int = VillageLayout.skeleton(CHUNK_SIZE, 21)["street_y"]
	var occupied := _all_frontage_taken(street_y)
	assert_true(
		VillageLayout.next_street_plot(
			"farmhouse", CHUNK_SIZE, 21, _always_buildable, occupied
		).is_empty(),
		"precondition: this village really has no frontage left"
	)
	var plot: Dictionary = VillageLayout.outskirt_plot(
		"farmhouse", CHUNK_SIZE, 21, _always_buildable, occupied
	)
	assert_false(plot.is_empty(), "there is open ground here -- a farmstead can stand on it")
	assert_eq(plot["building_id"], "farmhouse")


func test_an_outskirt_plot_comes_with_a_real_path_back():
	var plot: Dictionary = VillageLayout.outskirt_plot(
		"farmhouse", CHUNK_SIZE, 22, _always_buildable, _never_occupied
	)
	assert_false(plot.is_empty())
	var spur: Array = plot["road_spur"]
	assert_gt(spur.size(), 0, "a farmstead nobody can walk to is not part of the village")
	assert_eq(spur[0], plot["doorstep"], "the path starts at the door")
	var street_y: int = VillageLayout.skeleton(CHUNK_SIZE, 22)["street_y"]
	var reaches_street := false
	for cell in spur:
		if (cell as Vector2i).y == street_y - 1 or (cell as Vector2i).y == street_y:
			reaches_street = true
	assert_true(reaches_street, "and ends at the street")


func test_an_outskirt_plot_honours_the_callers_own_condition():
	var refuses := func(_origin: Vector2i) -> bool: return false
	assert_true(
		VillageLayout.outskirt_plot(
			"farmhouse", CHUNK_SIZE, 23, _always_buildable, _never_occupied, refuses
		).is_empty(),
		"a site the caller refuses is not a site"
	)


func test_an_outskirt_plot_never_stands_on_the_square():
	var bones: Dictionary = VillageLayout.skeleton(CHUNK_SIZE, 24, _always_buildable)
	var plaza: Rect2i = bones["plaza"]
	var plot: Dictionary = VillageLayout.outskirt_plot(
		"farmhouse", CHUNK_SIZE, 24, _always_buildable, _never_occupied
	)
	assert_false(plot.is_empty())
	for cell in BuildingCatalog.footprint_cells("farmhouse", plot["origin"]):
		assert_false(plaza.has_point(cell), "%s is the market square" % str(cell))


func test_an_outskirt_plot_is_the_same_plot_every_time():
	var a: Dictionary = VillageLayout.outskirt_plot(
		"farmhouse", CHUNK_SIZE, 25, _always_buildable, _never_occupied
	)
	var b: Dictionary = VillageLayout.outskirt_plot(
		"farmhouse", CHUNK_SIZE, 25, _always_buildable, _never_occupied
	)
	assert_eq(a, b, "nothing is persisted, so the rule must re-derive the same plot")


func test_nowhere_buildable_means_no_outskirt_plot():
	assert_true(
		VillageLayout.outskirt_plot(
			"farmhouse", CHUNK_SIZE, 26, _never_buildable, _never_occupied
		).is_empty()
	)


# -- a narrow village keeps its square AND its houses ----------------------
#
# Measured on chunk (661,139) near lat 49.8 lon 10.6, reported three times
# ("no plaza, no city hall"). The square fits on DRY ground right where the
# street already runs -- two placements of it -- and was never laid, because
# the dry pocket is about nine tiles wide and the siting rule demanded a run
# wide enough for the square PLUS a house beside it. So the village took
# three houses and lost its square.
#
# That trade is the wrong way round. A house does not have to stand on the
# spine: a village that fills its spine opens a further street south and
# reaches it by the gate lane, which is exactly what that machinery is for.
# The square, on the other hand, can only ever straddle a street.


## Buildable in one narrow north-south band, just wide enough for a square.
func _only_a_narrow_band(from_x: int, width: int) -> Callable:
	return func(cell: Vector2i) -> bool:
		return cell.x >= from_x and cell.x < from_x + width


func test_a_village_whose_spine_only_fits_the_square_still_gets_one():
	var band := _only_a_narrow_band(4, VillageLayout.PLAZA_WIDTH_TILES + 1)
	var five := ["house_small", "house_small", "house_small", "house_small", "house_small"]
	var result := layout.layout(five, CHUNK_SIZE, 31, band, _never_occupied)
	assert_true(
		(result["plaza"] as Rect2i).has_area(),
		"the square fits on this street, so the village has one"
	)
	assert_false((result["civic_plot"] as Dictionary).is_empty(), "and somewhere to put a hall")


func test_and_its_houses_go_on_a_further_street():
	var band := _only_a_narrow_band(4, VillageLayout.PLAZA_WIDTH_TILES + 1)
	var five := ["house_small", "house_small", "house_small", "house_small", "house_small"]
	var result := layout.layout(five, CHUNK_SIZE, 31, band, _never_occupied)
	assert_gt(
		result["plots"].size(), 0,
		"a square that leaves the village nowhere to live is not worth having"
	)
	var street_y: int = VillageLayout.skeleton(CHUNK_SIZE, 31)["street_y"]
	var below := 0
	for plot in result["plots"]:
		if (plot["origin"] as Vector2i).y > street_y:
			below += 1
	assert_gt(below, 0, "the houses the spine could not take went to a further street")
	var roads: Array = result["road_cells"]
	var reached := _reachable_road_cells(roads, result["plots"][0]["doorstep"])
	for plot in result["plots"]:
		assert_true(reached.has(plot["doorstep"]), "and every one of them is still reachable")


# -- the street's own jitter must not veto the square ----------------------
#
# Measured on chunk (661,139) near lat 49.8 lon 10.6, reported three times
# as "no plaza, no city hall". The only dry placements of an 8x6 square on
# that village's street row were at x=1 and x=2, and the search's western
# bound was max(_EDGE_MARGIN_TILES=2, street_x0). street_x0 is the spine's
# own SEED JITTER (_EDGE_MARGIN_TILES + 0..2, so villages don't all start
# at the identical column) -- and it happened to be 3 there, vetoing a
# square that sits perfectly well inside the chunk's own margin.
#
# A decorative jitter is not a reason a village cannot have a market
# square. The square is bounded by the chunk's edge margin, and the spine
# starts at whichever is further west -- so the street always reaches its
# own square.


func test_a_square_may_stand_at_the_chunks_own_margin():
	var band := func(cell: Vector2i) -> bool:
		return (
			cell.x >= VillageLayout._EDGE_MARGIN_TILES
			and cell.x < VillageLayout._EDGE_MARGIN_TILES + VillageLayout.PLAZA_WIDTH_TILES
		)
	var bones: Dictionary = VillageLayout.skeleton(CHUNK_SIZE, 41, band)
	assert_eq(
		(bones["plaza"] as Rect2i).position.x, VillageLayout._EDGE_MARGIN_TILES,
		"the square stands on the only dry ground there is"
	)


func test_the_street_always_reaches_its_own_square():
	for seed_value in [41, 42, 43, 44, 45]:
		var band := func(cell: Vector2i) -> bool:
			return (
			cell.x >= VillageLayout._EDGE_MARGIN_TILES
			and cell.x < VillageLayout._EDGE_MARGIN_TILES + VillageLayout.PLAZA_WIDTH_TILES
		)
		var bones: Dictionary = VillageLayout.skeleton(CHUNK_SIZE, seed_value, band)
		assert_lte(
			int(bones["street_x0"]), (bones["plaza"] as Rect2i).position.x,
			"a square the street stops short of is a square nobody walks to"
		)


func test_a_village_whose_only_dry_ground_is_at_the_margin_gets_its_square():
	var band := func(cell: Vector2i) -> bool:
		return (
			cell.x >= VillageLayout._EDGE_MARGIN_TILES
			and cell.x < VillageLayout._EDGE_MARGIN_TILES + VillageLayout.PLAZA_WIDTH_TILES
		)
	var five := ["house_small", "house_small", "house_small", "house_small", "house_small"]
	var result := layout.layout(five, CHUNK_SIZE, 41, band, _never_occupied)
	assert_true((result["plaza"] as Rect2i).has_area(), "a square, at last")
	assert_false((result["civic_plot"] as Dictionary).is_empty(), "and somewhere to put a hall")
	assert_gt(result["plots"].size(), 0, "and people still live there")


# -- houses move further out rather than being given up on ----------------
#
# Asked for directly: "the square wins; houses should just be moved further
# away connected by streets". A street that places nothing used to end the
# village outright, so a village whose near ground was water simply lost the
# houses it could have put two streets further out.
#
# The walk is bounded by the chunk either way (a further street only opens
# while it is inside the edge margin, and only when the gate lane reaching
# it is clear), so looking further costs nothing but iterations.


## Buildable everywhere except the rows a street's own plots would need,
## for the FIRST `blocked_streets` streets -- EXCEPT along the lane column,
## which has to stay walkable or the far ground is not reachable at all
## (and then the village should not settle there, which is a different
## rule).
func _near_streets_blocked(street_y: int, blocked_streets: int, lane_x: int) -> Callable:
	return func(cell: Vector2i) -> bool:
		if cell.x == lane_x:
			return true
		for i in blocked_streets:
			var street: int = street_y + i * VillageLayout.STREET_PITCH_TILES
			if cell.y == street - 1 or cell.y == street - 2:
				return false
		return true


func test_houses_go_two_streets_out_when_the_near_ones_cannot_take_them():
	var street_y: int = VillageLayout.skeleton(CHUNK_SIZE, 51)["street_y"]
	var five := ["house_small", "house_small", "house_small", "house_small", "house_small"]
	var result := layout.layout(
		five, CHUNK_SIZE, 51,
		_near_streets_blocked(street_y, 2, VillageLayout.skeleton(CHUNK_SIZE, 51)["street_x0"]),
		_never_occupied
	)
	assert_gt(result["plots"].size(), 0, "a village does not give up on the ground it can still use")
	var furthest := street_y
	for plot in result["plots"]:
		furthest = maxi(furthest, (plot["origin"] as Vector2i).y)
	assert_gt(
		furthest, street_y + VillageLayout.STREET_PITCH_TILES,
		"the houses went past the streets that could not take them"
	)


func test_and_every_one_of_them_is_still_connected():
	var street_y: int = VillageLayout.skeleton(CHUNK_SIZE, 51)["street_y"]
	var five := ["house_small", "house_small", "house_small", "house_small", "house_small"]
	var result := layout.layout(
		five, CHUNK_SIZE, 51,
		_near_streets_blocked(street_y, 2, VillageLayout.skeleton(CHUNK_SIZE, 51)["street_x0"]),
		_never_occupied
	)
	var roads: Array = result["road_cells"]
	var reached := _reachable_road_cells(roads, result["plots"][0]["doorstep"])
	for plot in result["plots"]:
		assert_true(
			reached.has(plot["doorstep"]),
			"a house at %s nobody can walk to" % str(plot["origin"])
		)
