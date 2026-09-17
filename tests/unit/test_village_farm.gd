extends GutTest

## VillageFarm: the pure rule set behind a village's own farms (see
## docs/concept/village_farms.md). Decides WHICH ground a farmhouse owns,
## WHAT its worker grows there and WHAT to do next on it; NpcMarker owns
## the world effect, the same split HuntableQuarry already draws.
##
## Reported in play: "every tile of wheat planted adjacent to a farm house
## may be tied to a farm house (so you can build multiple farms)". The
## ownership rule below is that sentence: geometry, total, deterministic,
## and nothing persisted -- two farmhouses in one village each work their
## own ground and no tile is ever worked twice.

const VillageFarm = preload("res://src/gameplay/village_farm.gd")
const BuildingCatalog = preload("res://src/gameplay/building_catalog.gd")
const ItemCatalog = preload("res://src/gameplay/item_catalog.gd")
const FarmPlot = preload("res://src/gameplay/farm_plot.gd")


func _growing_plot(time_since_watered: float) -> FarmPlot:
	var plot := FarmPlot.new()
	plot.plant("wheat", 1)
	plot.time_since_watered = time_since_watered
	return plot


func _plot_in_state(state: String) -> FarmPlot:
	var plot := FarmPlot.new()
	plot.plant("wheat", 1)
	plot.state = state
	return plot


# -- the building ----------------------------------------------------------

func test_the_farmhouse_is_the_catalogs_own_production_building():
	assert_true(
		BuildingCatalog.PRODUCTION_BUILDING_IDS.has(VillageFarm.FARM_BUILDING_ID),
		"a farmhouse the catalog does not know is a farmhouse nothing can place"
	)
	assert_ne(BuildingCatalog.footprint_of(VillageFarm.FARM_BUILDING_ID), Vector2i.ZERO)


# -- the field -------------------------------------------------------------

func test_the_field_is_the_ring_of_tiles_around_the_farmhouse():
	var origin := Vector2i(10, 10)
	var footprint := BuildingCatalog.footprint_of(VillageFarm.FARM_BUILDING_ID)
	var cells: Array = VillageFarm.field_cells(origin, VillageFarm.FARM_BUILDING_ID)
	# Measured off the catalog, never written down: the rectangle one tile
	# out on every side, minus the ground the building itself stands on.
	var expected := (footprint.x + 2) * (footprint.y + 2) - footprint.x * footprint.y
	assert_eq(cells.size(), expected, "the field ring is derived from the catalog footprint")


func test_no_field_cell_stands_under_the_farmhouse():
	var origin := Vector2i(4, 7)
	var under: Dictionary = {}
	for cell in BuildingCatalog.footprint_cells(VillageFarm.FARM_BUILDING_ID, origin):
		under[cell] = true
	for cell in VillageFarm.field_cells(origin, VillageFarm.FARM_BUILDING_ID):
		assert_false(under.has(cell), "%s is under the farmhouse, not beside it" % str(cell))


func test_every_field_cell_touches_the_farmhouse():
	var origin := Vector2i(0, 0)
	var footprint := BuildingCatalog.footprint_of(VillageFarm.FARM_BUILDING_ID)
	for cell in VillageFarm.field_cells(origin, VillageFarm.FARM_BUILDING_ID):
		var dx: int = maxi(origin.x - cell.x, cell.x - (origin.x + footprint.x - 1))
		var dy: int = maxi(origin.y - cell.y, cell.y - (origin.y + footprint.y - 1))
		assert_eq(maxi(maxi(dx, 0), maxi(dy, 0)), 1, "%s does not touch the farmhouse" % str(cell))


func test_the_field_has_no_duplicate_cells():
	var seen: Dictionary = {}
	for cell in VillageFarm.field_cells(Vector2i(3, 3), VillageFarm.FARM_BUILDING_ID):
		assert_false(seen.has(cell), "%s listed twice" % str(cell))
		seen[cell] = true


func test_the_field_is_the_same_field_every_time_it_is_asked_for():
	var a: Array = VillageFarm.field_cells(Vector2i(9, 2), VillageFarm.FARM_BUILDING_ID)
	var b: Array = VillageFarm.field_cells(Vector2i(9, 2), VillageFarm.FARM_BUILDING_ID)
	assert_eq(a, b, "nothing is persisted, so the rule must re-derive the same field")


func test_a_building_the_catalog_does_not_know_has_no_field():
	assert_eq(VillageFarm.field_cells(Vector2i(1, 1), "not_a_building"), [])


# -- who owns a tile -------------------------------------------------------

func test_a_lone_farmhouse_owns_every_cell_of_its_own_field():
	var origin := Vector2i(10, 10)
	for cell in VillageFarm.field_cells(origin, VillageFarm.FARM_BUILDING_ID):
		assert_eq(
			VillageFarm.owner_of(cell, [origin], VillageFarm.FARM_BUILDING_ID), origin,
			"%s lies beside the only farmhouse there is" % str(cell)
		)


func test_ground_nowhere_near_a_farmhouse_belongs_to_nobody():
	assert_null(VillageFarm.owner_of(Vector2i(40, 40), [Vector2i(10, 10)], VillageFarm.FARM_BUILDING_ID))


func test_ground_under_a_farmhouse_belongs_to_nobody():
	var origin := Vector2i(10, 10)
	assert_null(
		VillageFarm.owner_of(origin, [origin], VillageFarm.FARM_BUILDING_ID),
		"the farmhouse stands on it -- it is not field"
	)


func test_two_farmhouses_never_share_a_tile():
	# Close enough that their rings genuinely overlap.
	var footprint := BuildingCatalog.footprint_of(VillageFarm.FARM_BUILDING_ID)
	var west := Vector2i(10, 10)
	var east := Vector2i(10 + footprint.x + 1, 10)
	var origins := [west, east]
	var claimed: Dictionary = {}
	for origin in origins:
		for cell in VillageFarm.field_cells(origin, VillageFarm.FARM_BUILDING_ID):
			var owner = VillageFarm.owner_of(cell, origins, VillageFarm.FARM_BUILDING_ID)
			assert_not_null(owner, "%s lies beside a farmhouse and must belong to one" % str(cell))
			if claimed.has(cell):
				assert_eq(claimed[cell], owner, "%s answered to two owners" % str(cell))
			claimed[cell] = owner
	var shared := 0
	for cell in VillageFarm.field_cells(west, VillageFarm.FARM_BUILDING_ID):
		if VillageFarm.field_cells(east, VillageFarm.FARM_BUILDING_ID).has(cell):
			shared += 1
	assert_gt(shared, 0, "precondition: these two farmhouses really do contest some ground")


func test_the_nearer_farmhouse_takes_contested_ground():
	var footprint := BuildingCatalog.footprint_of(VillageFarm.FARM_BUILDING_ID)
	var near := Vector2i(10, 10)
	var far := Vector2i(10, 10 + footprint.y + 2)
	# A cell hugging `near`'s own north edge: adjacent to `near` only.
	var cell := Vector2i(10, 9)
	assert_eq(VillageFarm.owner_of(cell, [near, far], VillageFarm.FARM_BUILDING_ID), near)
	assert_eq(VillageFarm.owner_of(cell, [far, near], VillageFarm.FARM_BUILDING_ID), near,
		"the answer cannot depend on what order the farmhouses were listed in")


func test_ownership_is_decided_the_same_way_every_time():
	var footprint := BuildingCatalog.footprint_of(VillageFarm.FARM_BUILDING_ID)
	var a := Vector2i(10, 10)
	var b := Vector2i(10 + footprint.x + 1, 10)
	for cell in VillageFarm.field_cells(a, VillageFarm.FARM_BUILDING_ID):
		assert_eq(
			VillageFarm.owner_of(cell, [a, b], VillageFarm.FARM_BUILDING_ID),
			VillageFarm.owner_of(cell, [b, a], VillageFarm.FARM_BUILDING_ID),
			"%s must not change hands when the list is reordered" % str(cell)
		)


# -- what grows there ------------------------------------------------------

func test_the_farmer_grows_wheat_and_the_herbalist_grows_herbs():
	assert_eq(VillageFarm.crop_for("farmer"), "wheat")
	assert_eq(VillageFarm.crop_for("herbalist"), "herb")


func test_every_other_occupation_has_no_field():
	for occupation in ["hunter", "fisher", "merchant", "guard", "nurse", "blacksmith", ""]:
		assert_eq(VillageFarm.crop_for(occupation), "", "%s does not farm" % occupation)


func test_every_crop_a_village_grows_is_a_real_item():
	for occupation in VillageFarm.CROP_BY_OCCUPATION:
		var crop_id: String = VillageFarm.CROP_BY_OCCUPATION[occupation]
		assert_true(
			ItemCatalog.new().has(crop_id),
			"%s grows %s, which nothing can hold, stock or sell" % [occupation, crop_id]
		)


# -- what to do next -------------------------------------------------------

func test_untilled_ground_is_planted():
	assert_eq(VillageFarm.action_for(null), "plant")


func test_a_ready_plot_is_harvested_an_empty_or_withered_one_planted():
	assert_eq(VillageFarm.action_for(_plot_in_state("ready")), "harvest")
	assert_eq(VillageFarm.action_for(_plot_in_state("empty")), "plant")
	assert_eq(VillageFarm.action_for(_plot_in_state("withered")), "plant")


func test_a_freshly_watered_growing_plot_needs_nothing():
	assert_eq(VillageFarm.action_for(_growing_plot(0.0)), "")


func test_a_growing_plot_is_watered_once_it_has_used_up_its_margin():
	var plot := _growing_plot(0.0)
	var margin: float = (
		plot.growth_time * FarmPlot.WATER_GRACE_FRACTION * VillageFarm.WATER_BEFORE_WITHER_FRACTION
	)
	plot.time_since_watered = margin - 0.01
	assert_eq(VillageFarm.action_for(plot), "", "still inside its own margin")
	plot.time_since_watered = margin
	assert_eq(VillageFarm.action_for(plot), "water", "a real farmer waters ahead of visible wilting")


func test_harvest_beats_planting_beats_watering():
	var plots: Array = [_growing_plot(9999.0), _plot_in_state("empty"), _plot_in_state("ready")]
	assert_eq(VillageFarm.next_action(plots), 2, "getting real value off the field wins")
	plots[2] = _growing_plot(0.0)
	assert_eq(VillageFarm.next_action(plots), 1, "starting the next cycle beats routine tending")
	plots[1] = _growing_plot(0.0)
	assert_eq(VillageFarm.next_action(plots), 0, "and the thirstiest plot is what is left")


func test_nothing_to_do_on_a_field_that_needs_nothing():
	assert_eq(VillageFarm.next_action([_growing_plot(0.0), _growing_plot(0.0)]), -1)


func test_an_empty_field_asks_for_nothing():
	assert_eq(VillageFarm.next_action([]), -1)


## MIN_FIELD_CELLS is not a fresh guess -- it is the already-measured plot
## count one farmer can keep watered (see VillageFarm's own doc comment).
## Pinned here rather than preloaded there so the pure rule set keeps no
## rendering dependency (CLAUDE.md: tuned values are tested functions or
## test-pinned constants).
func test_the_smallest_worthwhile_field_is_what_one_farmer_can_already_tend():
	var FarmerMarker = load("res://src/rendering/farmer_marker.gd")
	assert_eq(VillageFarm.MIN_FIELD_CELLS, FarmerMarker.PLOT_COUNT)
	assert_lte(
		VillageFarm.MIN_FIELD_CELLS,
		VillageFarm.field_cells(Vector2i.ZERO, VillageFarm.FARM_BUILDING_ID).size(),
		"a field ring that could never meet its own minimum would refuse every site"
	)


## The two share one watering margin rather than two copies of it.
func test_the_placeable_farms_worker_waters_on_the_same_margin():
	var FarmerMarker = load("res://src/rendering/farmer_marker.gd")
	assert_eq(FarmerMarker.WATER_BEFORE_WITHER_FRACTION, VillageFarm.WATER_BEFORE_WITHER_FRACTION)
