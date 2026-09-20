extends GutTest

## What ground a building's own footprint paints -- see docs/concept/
## building.md, "The ground a building stands on, and the kerb round its
## plot". Reported live with a screenshot: "the background of the houses
## 2x2 should be variable; if the city hall is placed on the plaza it
## should have cobblestone background so it looks seamless".
##
## A building is an OVERLAY standing on whatever ground it was raised on
## (TerrainRenderer.BUILDING_OVERLAY_TILE_IDS) -- except for the one thing
## an overlay cannot answer: placement LIFTS the paving it covers, so a
## hall on the village square would show the grassland that square was
## paved over. So a building reads its own KERB, the ring of cells
## immediately around its footprint: more than PAVED_KERB_SHARE of that
## ring paved means it stands ON the square and paints that paving;
## anything less is "", no ground of its own, and it stays an overlay.
##
## The rule itself is pure (a list of tile ids in, one tile id out) and is
## tested here against BOTH made-up rings and the real geometry a real
## village lays down, so a change to the plaza or to the street pitch that
## moved the hall off its own square fails here rather than on screen.

const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")
const VillageLayout = preload("res://src/world/village_layout.gd")
const BuildingCatalog = preload("res://src/gameplay/building_catalog.gd")

const CHUNK_SIZE := 32


func _ring(paved: int, open_ground: int) -> Array:
	var ids: Array = []
	for i in paved:
		ids.append(TerrainRenderer.ROAD_TILE_ID)
	for i in open_ground:
		ids.append("")
	return ids


# -- the rule ----------------------------------------------------------------

func test_a_plot_ringed_by_paving_stands_on_that_paving():
	assert_eq(
		TerrainRenderer.building_ground_tile_for("city_hall", _ring(12, 0)), TerrainRenderer.ROAD_TILE_ID,
		"a building whose every neighbour is the square's own paving is part of the square"
	)


func test_a_plot_on_open_ground_keeps_no_ground_of_its_own():
	assert_eq(
		TerrainRenderer.building_ground_tile_for("city_hall", _ring(2, 10)), "",
		"a house with nothing but its doorstep paved shows the grass it was raised on"
	)


## Exactly half is not MORE than half -- pinned so the boundary is a
## decision rather than whatever the comparison happens to do.
func test_a_kerb_exactly_half_paved_is_not_enough_to_pave_the_plot():
	assert_eq(TerrainRenderer.building_ground_tile_for("city_hall", _ring(6, 6)), "")
	assert_eq(TerrainRenderer.building_ground_tile_for("city_hall", _ring(7, 5)), TerrainRenderer.ROAD_TILE_ID)


## A building at the chunk's own edge has neighbours nobody can read. The
## answer is the overlay it already was, not a crash and not paving
## conjured out of nothing.
func test_a_plot_with_no_readable_kerb_at_all_paints_no_ground():
	assert_eq(TerrainRenderer.building_ground_tile_for("city_hall", []), "")


## Only the LAID Road tier counts (docs/concept/infrastructure.md). A
## trail is ground worn by walking, and a building standing in worn ground
## stands in worn ground -- a path scuffed past a plot must not promote it
## to cobbles.
func test_a_trail_worn_past_a_plot_is_not_paving():
	var trails: Array = []
	for i in 12:
		trails.append(TerrainRenderer.TRAIL_TILE_ID)
	assert_eq(TerrainRenderer.building_ground_tile_for("city_hall", trails), "")


# -- the same rule against a real village's own geometry ---------------------

func _always_buildable(_cell: Vector2i) -> bool:
	return true


func _never_occupied(_cell: Vector2i) -> bool:
	return false


## The ring of cells immediately around `origin`'s footprint, as tile ids,
## read out of the paving a real layout laid.
func _kerb_ids_for(origin: Vector2i, footprint: Vector2i, road_cells: Dictionary) -> Array:
	var ids: Array = []
	var plot := Rect2i(origin, footprint)
	for y in range(origin.y - 1, origin.y + footprint.y + 1):
		for x in range(origin.x - 1, origin.x + footprint.x + 1):
			var cell := Vector2i(x, y)
			if plot.has_point(cell):
				continue
			if cell.x < 0 or cell.y < 0 or cell.x >= CHUNK_SIZE or cell.y >= CHUNK_SIZE:
				continue
			ids.append(TerrainRenderer.ROAD_TILE_ID if road_cells.has(cell) else "")
	return ids


func _real_village(seed_value: int) -> Dictionary:
	var ids := ["house_small", "house_medium", "house_small", "house_large"]
	var result := VillageLayout.new().layout(ids, CHUNK_SIZE, seed_value, _always_buildable, _never_occupied)
	var road_cells := {}
	for cell in result["road_cells"]:
		road_cells[cell] = true
	result["paved"] = road_cells
	return result


## The hall's plot IS the square's north half, so the square is what
## surrounds it -- measured at 12 of 18 kerb cells paved (67%) in all
## three real settlements tools/probe_building_ground.gd sampled.
func test_the_town_hall_on_a_real_villages_square_stands_on_the_square():
	for seed_value in [1, 2, 3, 17]:
		var village := _real_village(seed_value)
		var civic: Dictionary = village["civic_plot"]
		assert_false(civic.is_empty(), "precondition: seed %d lays a square" % seed_value)
		var origin: Vector2i = civic["origin"]
		var footprint := BuildingCatalog.footprint_of(civic["building_id"])
		var kerb := _kerb_ids_for(origin, footprint, village["paved"])
		assert_eq(
			TerrainRenderer.building_ground_tile_for(civic["building_id"], kerb), TerrainRenderer.ROAD_TILE_ID,
			"seed %d: the hall's own square should reach under the hall" % seed_value
		)


## The other half of "variable": an ordinary street plot is NOT promoted
## to cobbles just because its door opens onto a road -- it keeps showing
## the ground it was raised on.
func test_a_real_street_house_keeps_showing_the_ground_it_was_raised_on():
	var checked := 0
	for seed_value in [1, 2, 3, 17]:
		var village := _real_village(seed_value)
		for plot in village["plots"]:
			var footprint := BuildingCatalog.footprint_of(plot["building_id"])
			var kerb := _kerb_ids_for(plot["origin"], footprint, village["paved"])
			assert_eq(
				TerrainRenderer.building_ground_tile_for(plot["building_id"], kerb), "",
				"seed %d: the house at %s fronts a street, it does not stand on one" % [seed_value, plot["origin"]]
			)
			checked += 1
	assert_gt(checked, 0, "precondition: there are real house plots to check")


# -- only a building raised ON paving is cobbled to its walls ---------------
#
# Reported with three farmhouses in shot, each on its own grey pad: *"make
# the farm houses ground grass instead of cobblestone... only buildings
# placed on pavement like the city hall should get the pavement bg ... the
# farmhouses should be placed on grass / forest biomes without pavement
# under it"*.
#
# The kerb share alone cannot answer it, and the measurement that set it
# says why. When PAVED_KERB_SHARE was chosen, tools/probe_building_ground.gd
# measured "an ordinary house/farmhouse/sawmill plot runs 7-43%" against a
# hall's 67%. Re-run on three real settlements near lat 48.6 lon 12.7 after
# the square stopped being abandoned at founding:
#
#     farmhouse   origin=(13, 19) 3x2  kerb 14/14 paved (100%)  plaza=false
#     farmhouse   origin=(20, 19) 3x2  kerb 11/14 paved ( 79%)  plaza=false
#     house_small origin=(17, 19) 2x2  kerb 10/12 paved ( 83%)  plaza=false
#     city_hall   origin=(14, 13) 4x3  kerb 12/18 paved ( 67%)  plaza=true
#
# Ten buildings across those three villages painted cobbles while standing
# on open ground, and the worst offenders beat the hall. A plot wedged
# between the square's south rows and the second street is ringed by paving
# on every side while standing on none of it, so no threshold can separate
# the two -- the hall's own 67% is BELOW the farmhouse's 100%.
#
# What really separates them is not local geometry at all: it is which
# buildings a village ever raises on its own paving. Exactly one does. The
# civic plot IS the paved square (EarthChunkManager._civic_plot_origin_for
# refuses a plot whose every footprint cell is not already a road tile),
# while every other placement path refuses a modified footprint outright.
# So the rule asks both: a building that stands on laid paving by design,
# AND a kerb that says the paving is really there.


func test_a_farmhouse_ringed_by_paving_still_stands_on_the_ground_it_was_raised_on():
	assert_eq(
		TerrainRenderer.building_ground_tile_for("farmhouse", _ring(14, 0)), "",
		"a farmhouse between the square and the next street is surrounded by paving, not standing on it"
	)


func test_a_street_house_ringed_by_paving_is_not_promoted_either():
	assert_eq(TerrainRenderer.building_ground_tile_for("house_small", _ring(12, 0)), "")
	assert_eq(TerrainRenderer.building_ground_tile_for("warehouse", _ring(16, 0)), "")
	assert_eq(TerrainRenderer.building_ground_tile_for("sawmill", _ring(14, 0)), "")


## ...and the hall still is, on the share its own square really gives it.
func test_the_hall_on_its_square_is_still_cobbled_to_its_walls():
	assert_eq(
		TerrainRenderer.building_ground_tile_for("city_hall", _ring(12, 6)), TerrainRenderer.ROAD_TILE_ID,
		"12 of 18 is what a real hall's square measures"
	)


## Both halves are needed: a hall raised somewhere there is no paving keeps
## the ground it was raised on, the same as anything else.
func test_a_hall_with_no_paving_round_it_keeps_its_own_ground():
	assert_eq(TerrainRenderer.building_ground_tile_for("city_hall", _ring(2, 16)), "")


## The one building on the list is the one VillageLayout reserves the paved
## civic plot for -- cross-pinned so the two can never drift apart.
func test_the_only_building_raised_on_paving_is_the_one_the_square_reserves_a_plot_for():
	assert_eq(
		BuildingCatalog.PAVED_PLOT_BUILDING_IDS, [VillageLayout.CIVIC_BUILDING_ID],
		"the square reserves its plot for one building; that is the one cobbled to its walls"
	)
	assert_true(BuildingCatalog.stands_on_laid_paving(VillageLayout.CIVIC_BUILDING_ID))
	assert_false(BuildingCatalog.stands_on_laid_paving("farmhouse"))
	assert_false(BuildingCatalog.stands_on_laid_paving(""))


## The exact rings the reported villages measured, as data
## (tools/probe_building_ground.gd, three real settlements near lat 48.6
## lon 12.7). Every one of these beat the threshold and painted cobbles;
## every one of them stands on open ground.
func test_the_rings_the_reported_villages_really_measured():
	var measured := [
		{"id": "farmhouse", "paved": 14, "total": 14},    # origin (13, 19)
		{"id": "farmhouse", "paved": 11, "total": 14},    # origin (20, 19)
		{"id": "house_small", "paved": 10, "total": 12},  # origin (13, 19)
		{"id": "house_small", "paved": 8, "total": 12},   # origin (15, 19)
		{"id": "house_small", "paved": 7, "total": 12},   # origin (10, 19)
	]
	for case in measured:
		var kerb := _ring(int(case["paved"]), int(case["total"]) - int(case["paved"]))
		assert_gt(
			float(case["paved"]), float(case["total"]) * TerrainRenderer.PAVED_KERB_SHARE,
			"precondition: %s at %d/%d really did beat the old threshold" % [
				case["id"], case["paved"], case["total"]
			]
		)
		assert_eq(
			TerrainRenderer.building_ground_tile_for(String(case["id"]), kerb), "",
			"%s ringed %d of %d paved stands on the ground it was raised on" % [
				case["id"], case["paved"], case["total"]
			]
		)


## ...and the hall measured in the same sweep still gets its cobbles.
func test_the_hall_the_same_sweep_measured_still_gets_its_cobbles():
	for paved in [12, 13]:  # 12/18 in two of the three villages, 13/18 in the third
		assert_eq(
			TerrainRenderer.building_ground_tile_for("city_hall", _ring(paved, 18 - paved)),
			TerrainRenderer.ROAD_TILE_ID,
			"the hall measured %d of 18 and stands on its own square" % paved
		)
