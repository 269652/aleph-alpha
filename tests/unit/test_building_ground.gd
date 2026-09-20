extends GutTest

## What ground a building's own footprint paints -- see docs/concept/
## building.md, "The ground a building stands on, and the kerb round its
## plot". Reported live with a screenshot: "the background of the houses
## 2x2 should be variable; if the city hall is placed on the plaza it
## should have cobblestone background so it looks seamless".
##
## A building stands on the ground its own KERB is made of: the ring of
## cells immediately around the footprint. More than PAVED_KERB_SHARE of
## that ring paved means the footprint is paved too; anything less is the
## trodden earth yard it always was.
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
		TerrainRenderer.building_ground_tile_for(_ring(12, 0)), TerrainRenderer.ROAD_TILE_ID,
		"a building whose every neighbour is the square's own paving is part of the square"
	)


func test_a_plot_on_open_ground_keeps_its_own_worn_earth_yard():
	assert_eq(
		TerrainRenderer.building_ground_tile_for(_ring(2, 10)), TerrainRenderer.EARTH_TILE_ID,
		"a house with nothing but its doorstep paved stands in its own yard"
	)


## Exactly half is not MORE than half -- pinned so the boundary is a
## decision rather than whatever the comparison happens to do.
func test_a_kerb_exactly_half_paved_is_not_enough_to_pave_the_plot():
	assert_eq(TerrainRenderer.building_ground_tile_for(_ring(6, 6)), TerrainRenderer.EARTH_TILE_ID)
	assert_eq(TerrainRenderer.building_ground_tile_for(_ring(7, 5)), TerrainRenderer.ROAD_TILE_ID)


## A building at the chunk's own edge has neighbours nobody can read. The
## answer is its yard, not a crash and not paving conjured out of nothing.
func test_a_plot_with_no_readable_kerb_at_all_stands_on_earth():
	assert_eq(TerrainRenderer.building_ground_tile_for([]), TerrainRenderer.EARTH_TILE_ID)


## Only the LAID Road tier counts (docs/concept/infrastructure.md). A
## trail is ground worn by walking, which is what the yard already is --
## a path scuffed across a plot must not promote it to cobbles.
func test_a_trail_worn_past_a_plot_is_not_paving():
	var trails: Array = []
	for i in 12:
		trails.append(TerrainRenderer.TRAIL_TILE_ID)
	assert_eq(TerrainRenderer.building_ground_tile_for(trails), TerrainRenderer.EARTH_TILE_ID)


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
			TerrainRenderer.building_ground_tile_for(kerb), TerrainRenderer.ROAD_TILE_ID,
			"seed %d: the hall's own square should reach under the hall" % seed_value
		)


## The other half of "variable": an ordinary street plot is NOT promoted
## to cobbles just because its door opens onto a road.
func test_a_real_street_house_keeps_its_own_earth_yard():
	var checked := 0
	for seed_value in [1, 2, 3, 17]:
		var village := _real_village(seed_value)
		for plot in village["plots"]:
			var footprint := BuildingCatalog.footprint_of(plot["building_id"])
			var kerb := _kerb_ids_for(plot["origin"], footprint, village["paved"])
			assert_eq(
				TerrainRenderer.building_ground_tile_for(kerb), TerrainRenderer.EARTH_TILE_ID,
				"seed %d: the house at %s fronts a street, it does not stand on one" % [seed_value, plot["origin"]]
			)
			checked += 1
	assert_gt(checked, 0, "precondition: there are real house plots to check")
