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


func test_the_field_is_capped_at_ten_tiles():
	assert_eq(VillageFarm.MAX_WORKED_CELLS, 10, "asked for directly: capped to 10 tiles")


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


# -- a rail is a LINE on its own inner edge, not a solid tile --------------
#
# Asked for directly, with the two sides arrowed in a screenshot: "move the
# fences to the inner edge of the enclosure and treat the rest of the tile
# as street ... the brown squares should still be street when a fence is
# put". A rail cell is ordinary ground an animal may stand on and walk
# along; what it may not do is CROSS the edge the rails are actually drawn
# on. See docs/concept/village_farms.md, "The rail stands on the inner
# edge".


## Which of a rail cell's own four edges the rails are drawn on -- the edge
## facing the beds it encloses.
func test_every_rail_knows_which_of_its_own_edges_faces_the_beds():
	assert_eq(
		VillageFarm.fence_inner_direction(VillageFarm.fence_tile_for("north")), Vector2i(0, 1),
		"a rail closing the field's north side has its beds to the south"
	)
	assert_eq(VillageFarm.fence_inner_direction(VillageFarm.fence_tile_for("south")), Vector2i(0, -1))
	assert_eq(VillageFarm.fence_inner_direction(VillageFarm.fence_tile_for("east")), Vector2i(-1, 0))
	assert_eq(VillageFarm.fence_inner_direction(VillageFarm.fence_tile_for("west")), Vector2i(1, 0))


func test_anything_that_is_not_a_rail_has_no_inner_edge():
	assert_eq(VillageFarm.fence_inner_direction(""), Vector2i.ZERO)
	assert_eq(VillageFarm.fence_inner_direction("road"), Vector2i.ZERO)
	assert_eq(VillageFarm.fence_inner_direction("farmhouse"), Vector2i.ZERO)


## Not a second, independently-written table: the inner edge must be exactly
## the direction the bed really lies in from that rail, or the art stands on
## the wrong edge and the barrier closes the wrong side.
func test_the_inner_edge_really_points_at_the_bed_the_rail_encloses():
	var beds: Array = [Vector2i(4, 4)]
	for cell in [Vector2i(4, 3), Vector2i(4, 5), Vector2i(5, 4), Vector2i(3, 4)]:
		var tile_id: String = VillageFarm.fence_tile_for(VillageFarm.fence_facing(cell, beds))
		assert_eq(
			cell + VillageFarm.fence_inner_direction(tile_id), Vector2i(4, 4),
			"%s's inner edge must face the bed it encloses" % str(cell)
		)


## The rail stops a CROSSING, not an occupancy: an animal walking onto the
## ring is fine, an animal stepping over the rails is not.
func test_stepping_across_a_rails_inner_edge_is_blocked():
	var north: String = VillageFarm.fence_tile_for("north")
	assert_true(
		VillageFarm.rails_block_step(north, "", Vector2i(0, 1)),
		"south off a north rail is a step into the beds"
	)
	assert_true(
		VillageFarm.rails_block_step("", north, Vector2i(0, -1)),
		"north into a north rail is a step out of the beds"
	)
	var west: String = VillageFarm.fence_tile_for("west")
	assert_true(VillageFarm.rails_block_step(west, "", Vector2i(1, 0)), "east off a west rail")
	assert_true(VillageFarm.rails_block_step("", west, Vector2i(-1, 0)), "west into a west rail")


## The whole point of the change: the rest of the rail's tile is ordinary
## walkable ground.
func test_walking_onto_and_along_a_rail_is_never_blocked():
	var north: String = VillageFarm.fence_tile_for("north")
	assert_false(
		VillageFarm.rails_block_step(north, north, Vector2i(1, 0)),
		"an animal may walk the ring along its own run"
	)
	assert_false(
		VillageFarm.rails_block_step("", north, Vector2i(0, 1)),
		"walking ONTO a rail cell from outside is not crossing its rails"
	)
	assert_false(
		VillageFarm.rails_block_step(north, "", Vector2i(0, -1)),
		"stepping away from the beds is free"
	)
	assert_false(VillageFarm.rails_block_step("", "", Vector2i(0, 1)), "open ground blocks nothing")
	assert_false(VillageFarm.rails_block_step(north, north, Vector2i.ZERO), "standing still crosses nothing")


## A diagonal step crosses both of its own edges, so it is blocked whenever
## either component would be -- an animal must not slip round a corner of
## the ring that a cardinal step cannot pass.
func test_a_diagonal_step_over_a_rails_inner_edge_is_blocked_too():
	var west: String = VillageFarm.fence_tile_for("west")
	assert_true(
		VillageFarm.rails_block_step(west, "", Vector2i(1, 1)),
		"a diagonal whose east component still crosses the rails"
	)
	assert_false(
		VillageFarm.rails_block_step(west, "", Vector2i(-1, 1)),
		"a diagonal away from the rails is free"
	)


## The claim docs/concept/village_farms.md's own honest-gap row makes, pinned
## rather than eyeballed: a rail carries ONE facing, so it closes one of its
## own sides -- and on a rectangular field that is still enough at the
## corners, because fence_facing's vertical answer for a diagonal-only cell
## is always one of that diagonal's own two components.
func test_a_corner_of_a_rectangular_field_still_refuses_the_diagonal_into_the_crop():
	var beds: Array = [Vector2i(4, 4), Vector2i(5, 4), Vector2i(4, 5), Vector2i(5, 5)]
	var bed_set: Dictionary = {}
	for bed in beds:
		bed_set[bed] = true
	var rails: Dictionary = {}
	for cell in VillageFarm.fence_cells(beds, Vector2i(20, 20), VillageFarm.FARM_BUILDING_ID):
		rails[cell] = VillageFarm.fence_tile_for(VillageFarm.fence_facing(cell, beds))
	var corners := 0
	for cell in rails:
		var has_orthogonal_bed := false
		for side in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			if bed_set.has(cell + side):
				has_orthogonal_bed = true
		if has_orthogonal_bed:
			continue
		for diagonal in [Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]:
			if not bed_set.has(cell + diagonal):
				continue
			corners += 1
			assert_true(
				VillageFarm.rails_block_step(rails[cell], "", diagonal),
				"%s must still refuse the diagonal into the crop" % str(cell)
			)
	assert_eq(corners, 4, "a rectangular field has exactly four diagonal-only corner rails")
