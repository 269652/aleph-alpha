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

## Asked for directly: "The space the farmhouse utilizes should be
## maximized and capped to 10 tiles ... the fields be placed sideways and
## downwards of it". So the field is a DIRECTED region, not a ring: a
## village house fronts the street with its door south, and the ground
## north of a farmhouse is the next row of buildings.
func test_the_field_offers_more_ground_than_one_farmhouse_will_work():
	var cells: Array = VillageFarm.field_cells(Vector2i(10, 10), VillageFarm.FARM_BUILDING_ID)
	assert_gt(
		cells.size(), VillageFarm.MAX_WORKED_CELLS,
		"the caller filters for water and paving, so there must be more offered than kept"
	)


## The earlier ask was a CAP -- "maximized and capped to 10 tiles" -- and
## the later one names the shape inside it: "The fence should enclose a 2x3
## or 3x2 area". Six respects the cap and is where the measured yield table
## peaks, so both asks and the measurement agree.
func test_the_field_is_the_rectangle_that_was_asked_for_and_inside_the_old_cap():
	assert_eq(VillageFarm.MAX_WORKED_CELLS, 6, "a 3x2 or 2x3 area")
	assert_lte(VillageFarm.MAX_WORKED_CELLS, 10, "and still inside the cap asked for earlier")


func test_the_field_can_always_offer_a_full_cap_on_open_ground():
	var cells: Array = VillageFarm.field_cells(Vector2i(20, 20), VillageFarm.FARM_BUILDING_ID)
	assert_gte(
		cells.size(), VillageFarm.MAX_WORKED_CELLS,
		"a reach too short to offer the cap would cap the field below its own cap"
	)


func test_the_field_is_offered_nearest_the_farmhouse_first():
	var origin := Vector2i(10, 10)
	var footprint := BuildingCatalog.footprint_of(VillageFarm.FARM_BUILDING_ID)
	var cells: Array = VillageFarm.field_cells(origin, VillageFarm.FARM_BUILDING_ID)
	var previous := 0
	for cell in cells:
		var dx: int = maxi(maxi(origin.x - cell.x, cell.x - (origin.x + footprint.x - 1)), 0)
		var dy: int = maxi(maxi(origin.y - cell.y, cell.y - (origin.y + footprint.y - 1)), 0)
		var reach: int = maxi(dx, dy)
		assert_gte(reach, previous, "%s is nearer than a cell already offered" % str(cell))
		previous = reach


func test_no_field_cell_stands_under_the_farmhouse():
	var origin := Vector2i(4, 7)
	var under: Dictionary = {}
	for cell in BuildingCatalog.footprint_cells(VillageFarm.FARM_BUILDING_ID, origin):
		under[cell] = true
	for cell in VillageFarm.field_cells(origin, VillageFarm.FARM_BUILDING_ID):
		assert_false(under.has(cell), "%s is under the farmhouse, not beside it" % str(cell))


func test_the_field_lies_to_the_sides_and_below_never_above():
	var origin := Vector2i(0, 0)
	var footprint := BuildingCatalog.footprint_of(VillageFarm.FARM_BUILDING_ID)
	var below := 0
	var beside := 0
	for cell in VillageFarm.field_cells(origin, VillageFarm.FARM_BUILDING_ID):
		assert_gte(
			cell.y, origin.y,
			"%s is north of the farmhouse, where the next row of buildings goes" % str(cell)
		)
		var dx: int = maxi(maxi(origin.x - cell.x, cell.x - (origin.x + footprint.x - 1)), 0)
		var dy: int = maxi(maxi(origin.y - cell.y, cell.y - (origin.y + footprint.y - 1)), 0)
		assert_lte(maxi(dx, dy), VillageFarm.FIELD_REACH_TILES, "%s is out of reach" % str(cell))
		if cell.y >= origin.y + footprint.y:
			below += 1
		if cell.x < origin.x or cell.x >= origin.x + footprint.x:
			beside += 1
	assert_gt(below, 0, "downwards")
	assert_gt(beside, 0, "and sideways")


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
		# (no other farmhouse here, so every offered cell is really its own)
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
	var under: Dictionary = {}
	for origin in origins:
		for cell in BuildingCatalog.footprint_cells(VillageFarm.FARM_BUILDING_ID, origin):
			under[cell] = true
	var claimed: Dictionary = {}
	for origin in origins:
		for cell in VillageFarm.field_cells(origin, VillageFarm.FARM_BUILDING_ID):
			if under.has(cell):
				continue  # the other farmhouse stands here -- it is not field
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
	var far := Vector2i(10 + footprint.x + 6, 10)
	# A cell hugging `near`'s own west side: in `near`'s field only.
	var cell := Vector2i(9, 10)
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


## Harvest, then SAVE what is already growing, then break new ground.
##
## The order used to be harvest > plant > water, and measuring a real work
## block showed what that costs: a field of any size usually has an empty
## or withered bed somewhere, so the farmer planted instead of watering,
## every bed died on the vine, and the whole block went into replanting
## ground that died again. A 3-tile field yielded ZERO wheat that way.
##
## A bed already sown is work already done. Watering it costs one trip;
## losing it costs the whole cycle.
func test_harvest_beats_saving_a_bed_which_beats_breaking_new_ground():
	var plots: Array = [_plot_in_state("empty"), _growing_plot(9999.0), _plot_in_state("ready")]
	assert_eq(VillageFarm.next_action(plots), 2, "getting real value off the field wins")
	plots[2] = _growing_plot(0.0)
	assert_eq(VillageFarm.next_action(plots), 1, "a bed about to die beats an empty one")
	plots[1] = _growing_plot(0.0)
	assert_eq(VillageFarm.next_action(plots), 0, "and with nothing dying, break new ground")


## A farmer standing in their own field always has something to do. With
## nothing ripe, nothing dying and nothing bare, they tend the THIRSTIEST
## bed -- which is what keeps a field alive at all.
##
## Measured, and this is why: with the farmer idling between thresholds, a
## three-tile field over a real work block ran 108 replants, 72 waterings
## and ZERO harvests. Beds died faster than the circuit came back round,
## and once they were out of step the watering that comes with each visit
## could not help either -- a withered bed cannot be watered.
func test_a_farmer_with_nothing_urgent_tends_the_thirstiest_bed():
	var fresh := _growing_plot(0.0)
	var thirsty := _growing_plot(fresh.growth_time * FarmPlot.WATER_GRACE_FRACTION * 0.3)
	assert_eq(VillageFarm.next_action([fresh, thirsty]), 1)
	assert_eq(VillageFarm.next_action([thirsty, fresh]), 0)


func test_an_empty_field_asks_for_nothing_at_all():
	assert_eq(VillageFarm.next_action([]), -1)


func test_a_field_of_nothing_but_ready_beds_still_harvests_first():
	assert_eq(VillageFarm.next_action([_growing_plot(0.0), _plot_in_state("ready")]), 1)


func test_an_empty_field_asks_for_nothing():
	assert_eq(VillageFarm.next_action([]), -1)


## The field is never SMALLER than the plot count one farmer is already
## known to keep watered (FarmerMarker.PLOT_COUNT -- the one number in this
## codebase measured against that). A village farmhouse hands its villager
## a whole rectangle or nothing at all, so this is the floor that rectangle
## has to clear. Pinned here rather than preloaded there so the pure rule
## set keeps no rendering dependency (CLAUDE.md: tuned values are tested
## functions or test-pinned constants).
func test_a_field_is_never_smaller_than_what_one_farmer_can_already_tend():
	var FarmerMarker = load("res://src/rendering/farmer_marker.gd")
	for shape in VillageFarm.FIELD_SHAPES:
		assert_gte(
			(shape as Vector2i).x * (shape as Vector2i).y, FarmerMarker.PLOT_COUNT,
			"%s is less ground than one farmer already tends by hand" % str(shape)
		)


## The two share one watering margin rather than two copies of it.
func test_the_placeable_farms_worker_waters_on_the_same_margin():
	var FarmerMarker = load("res://src/rendering/farmer_marker.gd")
	assert_eq(FarmerMarker.WATER_BEFORE_WITHER_FRACTION, VillageFarm.WATER_BEFORE_WITHER_FRACTION)


# -- only as much ground as one villager can keep ---------------------------

func test_the_worked_field_is_capped_at_what_one_villager_can_keep():
	var origin := Vector2i(10, 10)
	var ring: Array = VillageFarm.field_cells(origin, VillageFarm.FARM_BUILDING_ID)
	assert_gt(ring.size(), VillageFarm.MAX_WORKED_CELLS, "precondition: the ring is bigger than the cap")
	var worked: Array = VillageFarm.nearest_cells(
		ring, origin, VillageFarm.FARM_BUILDING_ID, VillageFarm.MAX_WORKED_CELLS
	)
	assert_eq(worked.size(), VillageFarm.MAX_WORKED_CELLS)
	for cell in worked:
		assert_true(ring.has(cell), "%s is not even part of this farmhouse's ring" % str(cell))


func test_the_cells_kept_are_the_ones_nearest_the_farmhouse():
	var origin := Vector2i(10, 10)
	var footprint := BuildingCatalog.footprint_of(VillageFarm.FARM_BUILDING_ID)
	var centre := Vector2(origin) + Vector2(footprint) * 0.5
	var ring: Array = VillageFarm.field_cells(origin, VillageFarm.FARM_BUILDING_ID)
	var worked: Array = VillageFarm.nearest_cells(
		ring, origin, VillageFarm.FARM_BUILDING_ID, VillageFarm.MAX_WORKED_CELLS
	)
	var furthest_kept := 0.0
	for cell in worked:
		furthest_kept = maxf(furthest_kept, (Vector2(cell) + Vector2(0.5, 0.5)).distance_to(centre))
	for cell in ring:
		if worked.has(cell):
			continue
		assert_gte(
			(Vector2(cell) + Vector2(0.5, 0.5)).distance_to(centre), furthest_kept - 0.0001,
			"%s was dropped although it lies closer than a cell that was kept" % str(cell)
		)


func test_the_same_farmhouse_keeps_the_same_cells_every_time():
	var origin := Vector2i(7, 4)
	var ring: Array = VillageFarm.field_cells(origin, VillageFarm.FARM_BUILDING_ID)
	assert_eq(
		VillageFarm.nearest_cells(ring, origin, VillageFarm.FARM_BUILDING_ID, 4),
		VillageFarm.nearest_cells(ring, origin, VillageFarm.FARM_BUILDING_ID, 4)
	)


func test_asking_for_no_cells_or_an_unknown_building_gives_none():
	var ring: Array = VillageFarm.field_cells(Vector2i.ZERO, VillageFarm.FARM_BUILDING_ID)
	assert_eq(VillageFarm.nearest_cells(ring, Vector2i.ZERO, VillageFarm.FARM_BUILDING_ID, 0), [])
	assert_eq(VillageFarm.nearest_cells(ring, Vector2i.ZERO, "not_a_building", 4), [])


# -- the fence around the beds ---------------------------------------------
#
# Asked for directly, with the field circled in a screenshot: "the farmhouse
# should build a fence around the bed so no animals enter". See
# docs/concept/village_farms.md, "The fence around the beds".


func test_a_single_bed_is_ringed_by_all_eight_neighbours():
	var origin := Vector2i(20, 20)  # far from the beds, so nothing is dropped as footprint
	var fence: Array = VillageFarm.fence_cells(
		[Vector2i(4, 4)], origin, VillageFarm.FARM_BUILDING_ID
	)
	var expected: Array = []
	for dy in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			if dx == 0 and dy == 0:
				continue
			expected.append(Vector2i(4 + dx, 4 + dy))
	expected.sort()
	var got: Array = fence.duplicate()
	got.sort()
	assert_eq(got, expected, "a fence goes round a bed on the diagonal too, or its corners are open")


func test_no_rail_ever_stands_on_a_bed_the_villager_works():
	var origin := Vector2i(6, 5)
	var worked: Array = VillageFarm.nearest_cells(
		VillageFarm.field_cells(origin, VillageFarm.FARM_BUILDING_ID), origin,
		VillageFarm.FARM_BUILDING_ID, VillageFarm.MAX_WORKED_CELLS
	)
	assert_gt(worked.size(), 0, "precondition: a real field")
	for cell in VillageFarm.fence_cells(worked, origin, VillageFarm.FARM_BUILDING_ID):
		assert_false(worked.has(cell), "a rail through %s is a rail through the crop" % str(cell))


func test_no_rail_ever_stands_on_the_farmhouse_itself():
	var origin := Vector2i(6, 5)
	var worked: Array = VillageFarm.nearest_cells(
		VillageFarm.field_cells(origin, VillageFarm.FARM_BUILDING_ID), origin,
		VillageFarm.FARM_BUILDING_ID, VillageFarm.MAX_WORKED_CELLS
	)
	var footprint: Array = BuildingCatalog.footprint_cells(VillageFarm.FARM_BUILDING_ID, origin)
	for cell in VillageFarm.fence_cells(worked, origin, VillageFarm.FARM_BUILDING_ID):
		assert_false(
			footprint.has(cell),
			"%s is the farmhouse's own wall -- the building closes that side, not a rail" % str(cell)
		)


## A block of beds is fenced round the OUTSIDE only: a 2x2 block has twelve
## cells touching it, and not one rail stands between two beds.
func test_a_block_of_beds_is_fenced_round_the_outside_only():
	var beds: Array = [Vector2i(4, 4), Vector2i(5, 4), Vector2i(4, 5), Vector2i(5, 5)]
	var fence: Array = VillageFarm.fence_cells(beds, Vector2i(20, 20), VillageFarm.FARM_BUILDING_ID)
	assert_eq(fence.size(), 12, "a 2x2 block of beds has exactly twelve cells touching it")
	for cell in fence:
		assert_false(beds.has(cell), "%s is a bed, not a fence line" % str(cell))


func test_a_farmhouse_with_no_beds_raises_no_fence():
	assert_eq(VillageFarm.fence_cells([], Vector2i(6, 5), VillageFarm.FARM_BUILDING_ID), [])
	assert_eq(VillageFarm.fence_cells([Vector2i(4, 4)], Vector2i(6, 5), "not_a_building"), [])


func test_the_same_field_fences_the_same_ring_every_time():
	var origin := Vector2i(6, 5)
	var worked: Array = VillageFarm.nearest_cells(
		VillageFarm.field_cells(origin, VillageFarm.FARM_BUILDING_ID), origin,
		VillageFarm.FARM_BUILDING_ID, VillageFarm.MAX_WORKED_CELLS
	)
	assert_eq(
		VillageFarm.fence_cells(worked, origin, VillageFarm.FARM_BUILDING_ID),
		VillageFarm.fence_cells(worked, origin, VillageFarm.FARM_BUILDING_ID)
	)


## Every rail knows which side of the field it stands on, so the sheet's own
## four orientation columns can be drawn (docs/concept/village_farms.md).
func test_every_rail_faces_away_from_the_field_it_encloses():
	var beds: Array = [Vector2i(4, 4)]
	var facings: Dictionary = {}
	for cell in VillageFarm.fence_cells(beds, Vector2i(20, 20), VillageFarm.FARM_BUILDING_ID):
		facings[cell] = VillageFarm.fence_facing(cell, beds)
	assert_eq(facings[Vector2i(4, 3)], "north", "a rail above the bed closes its north side")
	assert_eq(facings[Vector2i(4, 5)], "south")
	assert_eq(facings[Vector2i(5, 4)], "east")
	assert_eq(facings[Vector2i(3, 4)], "west")


## A rail's TILE ID carries which way it faces, so the sheet's own four
## orientation columns survive a reload with nothing else persisted
## (docs/concept/village_farms.md's art contract).
func test_every_facing_has_its_own_rail_tile():
	var ids: Array = []
	for facing in ["north", "south", "east", "west"]:
		var tile_id: String = VillageFarm.fence_tile_for(facing)
		assert_ne(tile_id, "", "%s must have a rail of its own" % facing)
		assert_false(ids.has(tile_id), "%s reuses another facing's tile" % facing)
		assert_true(VillageFarm.is_fence_tile(tile_id), "%s must read back as a rail" % tile_id)
		ids.append(tile_id)


func test_a_facing_nobody_drew_has_no_rail():
	assert_eq(VillageFarm.fence_tile_for(""), "")
	assert_eq(VillageFarm.fence_tile_for("up"), "")
	assert_false(VillageFarm.is_fence_tile("road"))
	assert_false(VillageFarm.is_fence_tile(""))


# -- the field is a compact rectangle, and its fence a closed frame --------
#
# Reported in play with the broken ring circled in a screenshot: "The
# fencing system does not yet work... The fence should enclose a 2x3 or 3x2
# area ... also the side walls of the fence should be moved outwards and
# corner pieces added so it doesn't look that broken". See
# docs/concept/village_farms.md, "The fence around the beds".


func _every_rect_cell(rect: Rect2i) -> Array:
	var cells: Array = []
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			cells.append(Vector2i(x, y))
	return cells


func test_the_shapes_a_field_may_take_are_the_two_that_were_asked_for():
	assert_eq(VillageFarm.FIELD_SHAPES.size(), 2)
	assert_true(VillageFarm.FIELD_SHAPES.has(Vector2i(3, 2)), "3x2")
	assert_true(VillageFarm.FIELD_SHAPES.has(Vector2i(2, 3)), "2x3")


## Six beds -- and not a fresh guess: it is what the yield table already
## peaked at (see MAX_WORKED_CELLS's own measured numbers).
func test_a_field_is_six_beds_however_it_is_turned():
	for shape in VillageFarm.FIELD_SHAPES:
		assert_eq((shape as Vector2i).x * (shape as Vector2i).y, VillageFarm.MAX_WORKED_CELLS)


func test_a_farmhouse_on_open_ground_really_gets_a_rectangle():
	var origin := Vector2i(10, 10)
	var rect = VillageFarm.field_rect(
		origin, VillageFarm.FARM_BUILDING_ID, func(_cell: Vector2i) -> bool: return true
	)
	assert_not_null(rect, "open ground must fit a field")
	assert_true(
		VillageFarm.FIELD_SHAPES.has((rect as Rect2i).size),
		"%s is not one of the shapes that were asked for" % str((rect as Rect2i).size)
	)


## Never north: a village house fronts the street with its door south, so
## the ground above a farmhouse is the next row of buildings.
func test_a_field_never_reaches_north_of_the_farmhouse():
	var origin := Vector2i(10, 10)
	var rect: Rect2i = VillageFarm.field_rect(
		origin, VillageFarm.FARM_BUILDING_ID, func(_cell: Vector2i) -> bool: return true
	)
	assert_gte(rect.position.y, origin.y, "the field starts no higher than the farmhouse itself")


func test_a_field_never_lies_under_the_farmhouse():
	var origin := Vector2i(10, 10)
	var rect: Rect2i = VillageFarm.field_rect(
		origin, VillageFarm.FARM_BUILDING_ID, func(_cell: Vector2i) -> bool: return true
	)
	var footprint: Array = BuildingCatalog.footprint_cells(VillageFarm.FARM_BUILDING_ID, origin)
	for cell in _every_rect_cell(rect):
		assert_false(footprint.has(cell), "%s is the farmhouse itself" % str(cell))


## Every cell of the rectangle must be workable -- a field with a rock or a
## river in the middle of it is not the rectangle that was asked for.
func test_a_rectangle_is_only_offered_where_every_one_of_its_cells_is_free():
	var origin := Vector2i(10, 10)
	var blocked := Vector2i(11, 13)
	var rect = VillageFarm.field_rect(
		origin, VillageFarm.FARM_BUILDING_ID,
		func(cell: Vector2i) -> bool: return cell != blocked
	)
	assert_not_null(rect, "there is still room elsewhere for a field")
	assert_false(_every_rect_cell(rect).has(blocked), "the field was laid over blocked ground")


func test_ground_that_fits_no_rectangle_at_all_gets_no_field():
	assert_null(VillageFarm.field_rect(
		Vector2i(10, 10), VillageFarm.FARM_BUILDING_ID,
		func(_cell: Vector2i) -> bool: return false
	))
	assert_null(VillageFarm.field_rect(
		Vector2i(10, 10), "not_a_building", func(_cell: Vector2i) -> bool: return true
	))


func test_the_same_farmhouse_lays_out_the_same_rectangle_every_time():
	var free := func(_cell: Vector2i) -> bool: return true
	assert_eq(
		VillageFarm.field_rect(Vector2i(7, 4), VillageFarm.FARM_BUILDING_ID, free),
		VillageFarm.field_rect(Vector2i(7, 4), VillageFarm.FARM_BUILDING_ID, free)
	)


# -- and the frame round it closes -----------------------------------------


func test_a_rectangles_fence_is_exactly_its_own_border():
	var beds := _every_rect_cell(Rect2i(4, 4, 3, 2))
	var fence: Array = VillageFarm.fence_cells(beds, Vector2i(20, 20), VillageFarm.FARM_BUILDING_ID)
	# A 3x2 block sits inside a 5x4 border: 5*4 - 3*2 = 14 cells.
	assert_eq(fence.size(), 14, "a 3x2 field has a fourteen-cell border round it")


func test_the_four_corners_of_a_frame_are_posts_not_lengths_of_rail():
	var beds := _every_rect_cell(Rect2i(4, 4, 3, 2))
	for corner in [Vector2i(3, 3), Vector2i(7, 3), Vector2i(3, 6), Vector2i(7, 6)]:
		assert_true(
			VillageFarm.fence_facing(corner, beds).begins_with("corner"),
			"%s caps two runs at once -- a rail drawn across it is the broken look" % str(corner)
		)


func test_a_corner_post_has_its_own_rail_tile():
	var tile_id: String = VillageFarm.fence_tile_for("corner_west")
	assert_ne(tile_id, "", "a corner needs a piece of its own")
	assert_true(VillageFarm.is_fence_tile(tile_id))


func test_each_wall_of_a_frame_faces_the_way_it_closes():
	var beds := _every_rect_cell(Rect2i(4, 4, 3, 2))
	assert_eq(VillageFarm.fence_facing(Vector2i(5, 3), beds), "north", "above the beds")
	assert_eq(VillageFarm.fence_facing(Vector2i(5, 6), beds), "south", "below the beds")
	assert_eq(VillageFarm.fence_facing(Vector2i(7, 4), beds), "east", "right of the beds")
	assert_eq(VillageFarm.fence_facing(Vector2i(3, 4), beds), "west", "left of the beds")


## Every cell of the border gets a real piece -- a frame with an unanswered
## cell in it is a frame with a hole in it.
func test_no_cell_of_a_frame_is_left_without_a_piece():
	var beds := _every_rect_cell(Rect2i(4, 4, 2, 3))
	for cell in VillageFarm.fence_cells(beds, Vector2i(20, 20), VillageFarm.FARM_BUILDING_ID):
		assert_ne(VillageFarm.fence_facing(cell, beds), "", "%s got no piece at all" % str(cell))


## A corner knows which SIDE of the field it caps, because the side wall it
## caps is drawn pushed out to that side and a post left on its own tile
## centre would sit half a tile inboard of the run it belongs to.
func test_a_corner_knows_which_side_of_the_field_it_caps():
	var beds := _every_rect_cell(Rect2i(4, 4, 3, 2))
	assert_eq(VillageFarm.fence_facing(Vector2i(3, 3), beds), "corner_west", "north-west")
	assert_eq(VillageFarm.fence_facing(Vector2i(3, 6), beds), "corner_west", "south-west")
	assert_eq(VillageFarm.fence_facing(Vector2i(7, 3), beds), "corner_east", "north-east")
	assert_eq(VillageFarm.fence_facing(Vector2i(7, 6), beds), "corner_east", "south-east")


func test_both_corner_posts_have_rail_tiles_of_their_own():
	var west: String = VillageFarm.fence_tile_for("corner_west")
	var east: String = VillageFarm.fence_tile_for("corner_east")
	assert_ne(west, "")
	assert_ne(east, "")
	assert_ne(west, east, "the two sides are pushed opposite ways, so they cannot share a tile")
	assert_true(VillageFarm.is_fence_tile(west))
	assert_true(VillageFarm.is_fence_tile(east))
