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
