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
## For the real top speed the rail's thickness is derived from.
const Taming = preload("res://src/gameplay/taming.gd")
const VillageCropChoice = preload("res://src/gameplay/village_crop_choice.gd")
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

## Asked directly, with a field of unrecognisable purple plants in shot:
## *"i don't even know what the purple crops are it plants.. atm it should
## plant only wheat which grows and gets harvested properly"*. The purple was
## the herbalist's herb, and it was dying overnight exactly as the wheat was
## (see FarmPlot.MIN_WATER_GRACE_SECONDS).
##
## That narrowing is WITHDRAWN. It was the right answer to "the crop dies
## before it ripens" and the wrong one to keep once the night bug was
## fixed: reported next was *"they have 0 Herbs even though there are 3 farm
## houses"*, because the one table entry that had put herbs in the ground
## was the one it removed.
##
## This table is now the TRADITIONAL crop -- what an occupation reaches for,
## which VillageCropChoice uses to break a tie and as its fallback where
## there is no reading to go on. What actually goes in the ground is the
## village's own worst-supplied need (docs/concept/village_farms.md, "What a
## field sows follows the village's need").
func test_each_farming_occupation_has_its_own_traditional_crop():
	assert_eq(VillageFarm.crop_for("farmer"), "wheat")
	assert_eq(
		VillageFarm.crop_for("herbalist"), "herb",
		"the herbalist reaches for herbs again -- the crop the report was about"
	)


## Every traditional crop has to be one a field can really sow, or the
## fallback would put something unsowable in the ground.
func test_every_traditional_crop_is_really_sowable():
	assert_gt(VillageFarm.CROP_BY_OCCUPATION.size(), 0, "the premise: somebody farms")
	for occupation in VillageFarm.CROP_BY_OCCUPATION:
		assert_true(
			VillageCropChoice.sowable_crops().has(VillageFarm.CROP_BY_OCCUPATION[occupation]),
			"%s's own crop is not sowable" % occupation
		)


## And the herbalist still farms at all -- the narrowing is what is sown,
## never whether they have a field.
func test_the_herbalist_still_has_a_field_of_their_own():
	assert_ne(VillageFarm.crop_for("herbalist"), "")


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
	# The bed's own real window, not growth_time's share of it: a bed's
	# tolerance has a floor of one night now (FarmPlot.MIN_WATER_GRACE_
	# SECONDS), and the margin is half of whatever that bed really has.
	var margin: float = plot.grace_seconds() * VillageFarm.WATER_BEFORE_WITHER_FRACTION
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
	var tile_id: String = VillageFarm.fence_tile_for("corner_nw")
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


## A corner knows BOTH sides it caps. The side wall was the first half: that
## wall is drawn on its own inner edge, and a post that did not know the side
## would sit half a tile off it. The run is the second, and was missing --
## reported with all three visible corners crossed out, "the fences still
## aren't optimal": with only a side, a corner post had no line to stop on
## and was drawn as a whole tile of vertical rail, so the frame overshot by
## a tile at every corner.
func test_a_corner_knows_both_the_sides_it_caps():
	var beds := _every_rect_cell(Rect2i(4, 4, 3, 2))
	assert_eq(VillageFarm.fence_facing(Vector2i(3, 3), beds), "corner_nw", "north-west")
	assert_eq(VillageFarm.fence_facing(Vector2i(3, 6), beds), "corner_sw", "south-west")
	assert_eq(VillageFarm.fence_facing(Vector2i(7, 3), beds), "corner_ne", "north-east")
	assert_eq(VillageFarm.fence_facing(Vector2i(7, 6), beds), "corner_se", "south-east")


## And its direction really points at the beds it corners, on both axes --
## the same pin the straight runs already have, which is what stops the two
## halves of the name drifting apart from the geometry.
func test_a_corners_direction_points_diagonally_at_the_beds():
	var beds := _every_rect_cell(Rect2i(4, 4, 3, 2))
	for corner in [Vector2i(3, 3), Vector2i(7, 3), Vector2i(3, 6), Vector2i(7, 6)]:
		var tile_id: String = VillageFarm.fence_tile_for(VillageFarm.fence_facing(corner, beds))
		var inner: Vector2i = VillageFarm.fence_inner_direction(tile_id)
		assert_ne(inner.x, 0, "%s has no side" % str(corner))
		assert_ne(inner.y, 0, "%s has no run" % str(corner))
		assert_true(
			beds.has(corner + inner),
			"%s's own diagonal must land on the bed it corners, not past it" % str(corner)
		)


func test_every_corner_post_has_a_rail_tile_of_its_own():
	var seen: Array = []
	for facing in ["corner_nw", "corner_ne", "corner_sw", "corner_se"]:
		var tile_id: String = VillageFarm.fence_tile_for(facing)
		assert_ne(tile_id, "", facing)
		assert_false(seen.has(tile_id), "%s reuses another corner's tile" % facing)
		assert_true(VillageFarm.is_fence_tile(tile_id))
		seen.append(tile_id)


## A rail a village raised under the two-id scheme is still a rail: it keeps
## its art and stays out of the ground cover, because the id is the only
## thing stored about it and an unrecognised one would paint bare earth on
## ground somebody has already walked past.
func test_a_corner_from_the_older_scheme_still_reads_as_a_rail():
	for tile_id in VillageFarm.LEGACY_FENCE_TILE_IDS:
		assert_true(VillageFarm.is_fence_tile(tile_id), tile_id)
		assert_true(VillageFarm.is_fence_corner_tile(tile_id), tile_id)
		assert_ne(
			VillageFarm.fence_inner_direction(tile_id), Vector2i.ZERO,
			"%s still has to know which side it caps, or its art goes nowhere" % tile_id
		)


## And nothing raises one any more.
func test_no_corner_the_rule_set_names_is_a_legacy_one():
	var beds := _every_rect_cell(Rect2i(4, 4, 3, 2))
	for cell in VillageFarm.fence_cells(beds, Vector2i(20, 20), VillageFarm.FARM_BUILDING_ID):
		var tile_id: String = VillageFarm.fence_tile_for(VillageFarm.fence_facing(cell, beds))
		assert_false(
			VillageFarm.LEGACY_FENCE_TILE_IDS.has(tile_id),
			"%s was raised as %s, which nothing should raise" % [str(cell), tile_id]
		)


## The claim docs/progress.md's own honest-gap row makes about the merged
## rule, pinned rather than asserted: with the field a rectangle
## (FIELD_SHAPES) and its diagonal cells real corner posts, an animal can
## walk the whole ring without ever being turned back -- which is what
## "treat the rest of the tile as street" asked for -- while every way INTO
## the crop stays shut.
func test_the_ring_of_a_rectangular_field_is_walkable_all_the_way_round():
	var beds: Array = []
	for y in range(4, 6):
		for x in range(4, 7):
			beds.append(Vector2i(x, y))  # a real 3x2 field
	var rails: Dictionary = {}
	for cell in VillageFarm.fence_cells(beds, Vector2i(20, 20), VillageFarm.FARM_BUILDING_ID):
		rails[cell] = VillageFarm.fence_tile_for(VillageFarm.fence_facing(cell, beds))
	assert_gt(rails.size(), 8, "precondition: a real ring round a 3x2 field")
	for cell in rails:
		for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			if not rails.has(cell + step):
				continue  # not a step along the ring
			assert_false(
				VillageFarm.rails_block_step(rails[cell], rails[cell + step], step),
				"the ring turns an animal back at %s -> %s" % [str(cell), str(cell + step)]
			)


## And the other half of the same claim: no cell of that ring faces beds on
## two orthogonal sides, which is the case one facing per rail could not
## close.
func test_no_rail_of_a_rectangular_field_has_to_close_two_sides_at_once():
	var beds: Array = []
	for y in range(4, 6):
		for x in range(4, 7):
			beds.append(Vector2i(x, y))
	var bed_set: Dictionary = {}
	for bed in beds:
		bed_set[bed] = true
	for cell in VillageFarm.fence_cells(beds, Vector2i(20, 20), VillageFarm.FARM_BUILDING_ID):
		var orthogonal := 0
		for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			if bed_set.has(cell + step):
				orthogonal += 1
		assert_lt(orthogonal, 2, "%s faces beds on %d sides and can only close one" % [str(cell), orthogonal])


# -- watering is measured against the bed's REAL window ----------------------
#
# A bed's drought tolerance gained a floor of one night (FarmPlot.
# MIN_WATER_GRACE_SECONDS) after a real village was measured losing thirteen
# of eighteen beds to the dark. The farmer's own "water it before it wilts"
# threshold has to be read off the same window, or the two describe different
# beds: computed from growth_time alone it fires at a quarter of the growth
# time, which for a fast crop is a fraction of the real window and sends the
# farmer back to soak ground that is in no danger.


func test_a_bed_is_watered_at_half_of_its_own_real_grace_window():
	var plot := FarmPlot.new()
	plot.plant("wheat", 7)
	plot.time_since_watered = plot.grace_seconds() * VillageFarm.WATER_BEFORE_WITHER_FRACTION - 0.01
	assert_eq(VillageFarm.action_for(plot), "", "not thirsty yet")
	plot.time_since_watered = plot.grace_seconds() * VillageFarm.WATER_BEFORE_WITHER_FRACTION + 0.01
	assert_eq(VillageFarm.action_for(plot), "water")


## And the margin is real: a bed the farmer is sent to water is always still
## alive when they get there, for every seed.
func test_the_watering_call_always_comes_before_the_bed_dies():
	for seed_value in range(1, 40):
		var plot := FarmPlot.new()
		plot.plant("wheat", seed_value)
		plot.time_since_watered = plot.grace_seconds() * VillageFarm.WATER_BEFORE_WITHER_FRACTION + 0.01
		assert_eq(VillageFarm.action_for(plot), "water", "seed %d" % seed_value)
		assert_false(plot.is_withered(), "seed %d was already dead when it was called thirsty" % seed_value)


# -- a field is sown before it is re-sown -----------------------------------
#
# Reported live with the field in shot: *"the NPC only sows 4 / 6 tiles"*.
#
# Measured before changing anything (tools/probe_village_farming.gd): every
# field in the sample had exactly 6 cells, five of them worked and cycling
# normally, and the SIXTH -- the last in the field's own order -- reported
# "no marker, never tilled" after a full 600-second work block. Both farmers
# in the village, the same bed each time.
#
# next_action scans from index 0 and returns the first plot wanting the
# highest-priority kind. Ground nobody has tilled asks to be planted, and so
# does a bed that was sown, ripened and harvested -- so once the earlier beds
# start cycling, one of them is always an earlier "plant" than the ground at
# the end, and the last bed is never broken at all. A farmer sows the FIELD.


func test_ground_never_broken_is_sown_before_a_bed_that_has_already_carried_a_crop():
	var harvested := _plot_in_state("empty")
	assert_eq(
		VillageFarm.next_action([harvested, null]), 1,
		"a bed that has already given a crop was re-sown while bare ground sat unbroken"
	)


## ...whichever end of the field it sits at -- this is about which bed, not
## about scan order.
func test_the_unbroken_ground_wins_from_either_end_of_the_field():
	assert_eq(VillageFarm.next_action([null, _plot_in_state("empty")]), 0)
	assert_eq(VillageFarm.next_action([_plot_in_state("empty"), null]), 1)


## Only among beds asking for the same thing. A ripe crop still comes first:
## breaking new ground while wheat rots on the stalk is how a field yields
## nothing, which is the failure the priority order exists for.
func test_unbroken_ground_still_waits_for_a_ripe_crop_and_a_dying_bed():
	assert_eq(
		VillageFarm.next_action([null, _plot_in_state("ready")]), 1,
		"harvest still beats breaking new ground"
	)
	assert_eq(
		VillageFarm.next_action([null, _growing_plot(9999.0)]), 1,
		"saving a dying bed still beats breaking new ground"
	)


## The whole field really does get broken, not just the first bed of it:
## every cell of a fresh field is planted before any of them is planted
## twice.
func test_every_bed_of_a_fresh_field_is_broken_before_any_is_re_sown():
	var plots: Array = [null, null, null, null, null, null]
	for round in plots.size():
		var index: int = VillageFarm.next_action(plots)
		assert_gte(index, 0, "a field with bare ground in it always has work")
		assert_null(plots[index], "bed %d was worked twice before the field was sown" % index)
		# What tilling it does: the bed exists now, bare and waiting.
		plots[index] = _plot_in_state("empty")
	for plot in plots:
		assert_not_null(plot, "a bed was left unbroken after a full pass of the field")


# -- the rail's own hitbox ---------------------------------------------------
#
# Reported live and carried for several rounds: the player walks straight
# through fences. Every other walker already respects them -- rails_block_step
# is an ask-before-you-step rule, and markers are Sprite2Ds that ask. The
# PLAYER is a real CharacterBody2D, and nothing in the world was ever there
# for it to collide with, because a rail is not a BuildingPiece and so got no
# StaticBody2D.
#
# It cannot simply be made a solid tile: a rail stands on the INNER EDGE of
# its cell and the rest of that cell is street you may walk (see
# rails_block_step). So the collider is an edge, not a tile.


func test_a_rail_puts_its_collider_on_the_edge_it_closes():
	for facing in ["north", "south", "east", "west"]:
		var tile_id := VillageFarm.fence_tile_for(facing)
		assert_eq(
			VillageFarm.fence_collider_normal(tile_id),
			VillageFarm.fence_inner_direction(tile_id),
			"%s: the collider sits on the same edge rails_block_step shuts" % facing
		)


## A CORNER post gets none, and this is the load-bearing case. Its inner
## direction is DIAGONAL, so an edge collider would have to lie on one of its
## two cardinal sides -- and both of those are the runs it caps. Walling
## either one shuts the ring itself, which is the exact opposite of "treat
## the rest of the tile as street" and what _rail_stops_step already refuses.
## The diagonal it does block is closed by the two neighbouring runs' own
## colliders meeting at the shared corner.
func test_a_corner_post_gets_no_collider_so_the_ring_stays_walkable():
	for facing in VillageFarm.FENCE_TILE_IDS:
		var tile_id: String = VillageFarm.FENCE_TILE_IDS[facing]
		if not VillageFarm.is_fence_corner_tile(tile_id):
			continue
		assert_eq(
			VillageFarm.fence_collider_normal(tile_id), Vector2i.ZERO,
			"%s: a corner may not wall the runs it caps" % facing
		)


func test_ordinary_ground_gets_no_collider():
	assert_eq(VillageFarm.fence_collider_normal(""), Vector2i.ZERO)
	assert_eq(VillageFarm.fence_collider_normal("road"), Vector2i.ZERO)


# -- the shape of that edge --------------------------------------------------

## A real measured wood height for a horizontal rail, in tile-local pixels on
## a 16px tile -- see the table under "a horizontal rail is blocked at the
## BOTTOM of its wood" below, which is where it comes from and what it means.
const _FENCE_H := 10.9


func _rail_rect(facing: String) -> Rect2:
	return VillageFarm.fence_collider_rect(
		VillageFarm.fence_tile_for(facing), 16.0,
		VillageFarm.FENCE_COLLIDER_THICKNESS_PX, _FENCE_H
	)


func test_the_collider_lies_inside_its_own_tile():
	for facing in ["north", "south", "east", "west"]:
		var rect := _rail_rect(facing)
		assert_gte(rect.position.x, 0.0, facing)
		assert_gte(rect.position.y, 0.0, facing)
		assert_lte(rect.end.x, 16.0, facing)
		assert_lte(rect.end.y, 16.0, facing)


## It spans the tile fully ACROSS the edge, so two rails side by side meet
## and leave no seam for a player to squeeze through.
func test_neighbouring_rails_meet_with_no_gap_between_them():
	for facing in ["north", "south"]:
		assert_eq(_rail_rect(facing).size.x, 16.0, "%s must span the full width" % facing)
	for facing in ["east", "west"]:
		assert_eq(_rail_rect(facing).size.y, 16.0, "%s must span the full height" % facing)


## The edge is named by the collider's NORMAL, not by the rail's facing --
## and the two are opposite, which is the point. A "north" rail stands on the
## north side of the FIELD, so the edge it closes is its own SOUTH one, the
## side the crop is on. Asserting it the other way round is what the first
## draft of this test did.
##
## A VERTICAL rail only. This used to assert all four facings, and that is
## exactly the bug reported as "the horizontal fences should have the hitbox
## at the bottom of the rail": a south rail's normal names the tile's TOP
## edge, its wood hangs down from there, and pinning the collider to the
## named edge therefore stopped the player at the rail's head. Where a
## horizontal rail stands is its wood's foot, asserted below.
func test_a_vertical_colliders_edge_is_the_one_its_normal_names():
	for facing in ["east", "west"]:
		var normal := VillageFarm.fence_collider_normal(VillageFarm.fence_tile_for(facing))
		var rect := _rail_rect(facing)
		if normal.x > 0:
			assert_almost_eq(rect.end.x, 16.0, 0.0001, facing)
		else:
			assert_almost_eq(rect.position.x, 0.0, 0.0001, facing)


## ...and that opposition is itself worth pinning, because it is the thing a
## reader gets wrong: the rail closes the side the crop is on.
func test_a_rails_collider_faces_the_crop_not_the_street():
	assert_eq(
		VillageFarm.fence_collider_normal(VillageFarm.fence_tile_for("north")),
		Vector2i(0, 1), "a rail on the field's north side closes its southern edge"
	)
	assert_eq(
		VillageFarm.fence_collider_normal(VillageFarm.fence_tile_for("west")),
		Vector2i(1, 0), "a rail on the field's west side closes its eastern edge"
	)


func test_a_tile_with_no_rail_has_no_rect_at_all():
	assert_eq(
		VillageFarm.fence_collider_rect(
			"", 16.0, VillageFarm.FENCE_COLLIDER_THICKNESS_PX, _FENCE_H
		).size,
		Vector2.ZERO
	)


# -- and why the thickness is the number it is -------------------------------

## Thick enough that the FASTEST thing the player can be -- mounted on a
## maximum-fitness horse, Taming.MOUNTED_SPEED * MAX_FITNESS_SPEED_MULTIPLIER
## = 180 px/s -- cannot cross it inside one 60Hz physics tick (3.0 px), so
## the rail holds even if a step is ever resolved without sweeping.
func test_the_rail_is_thicker_than_the_fastest_single_step_across_it():
	var top_speed := Taming.MOUNTED_SPEED * Taming.MAX_FITNESS_SPEED_MULTIPLIER
	assert_gte(VillageFarm.FENCE_COLLIDER_THICKNESS_PX, top_speed / 60.0)


## ...and thin enough to still be a LINE on one edge rather than a wall
## filling the cell, which is the whole distinction the ring depends on.
func test_the_rail_is_still_a_line_and_not_a_wall():
	assert_lte(VillageFarm.FENCE_COLLIDER_THICKNESS_PX, 16.0 / 4.0)


# -- a horizontal rail is blocked at the BOTTOM of its wood -----------------
#
# Reported live: "The horizontal fences should have the hitbox at the bottom
# of the rail ... so it should use fence height instead of thickness".
#
# Measured before changing anything. A horizontal rail's wood is anchored to
# the edge its inner direction names (IllustratedStructureSprite.
# footprint_offset), which puts it at OPPOSITE ends of the tile for the two
# facings:
#
#   north rail (inner 0,+1): wood y 5.5 .. 16.0   collider was 12..16  correct
#   south rail (inner 0,-1): wood y 0.0 .. 10.9   collider was  0..4   WRONG
#
# The south case blocked the player seven pixels north of the visible fence
# line, because the collider sat on the TILE edge while the wood hung down
# from it. A rail stands ON the ground at its own base, so the base is where
# it stops anything -- and finding that base needs the wood's HEIGHT, which
# is why fence_collider_rect now takes one.


func _rail_rect_with_height(facing: String) -> Rect2:
	return VillageFarm.fence_collider_rect(
		VillageFarm.fence_tile_for(facing), 16.0,
		VillageFarm.FENCE_COLLIDER_THICKNESS_PX, _FENCE_H
	)


## The wood of a south-facing rail hangs DOWN from the tile's top edge, so
## its base is at the wood's own height -- not at the tile edge.
func test_a_top_anchored_rail_is_blocked_at_the_foot_of_its_wood():
	var rect := _rail_rect_with_height("south")
	assert_almost_eq(
		rect.end.y, _FENCE_H, 0.0001,
		"the strip's far edge is the foot of the wood, not the top of the tile"
	)
	assert_almost_eq(rect.position.y, _FENCE_H - VillageFarm.FENCE_COLLIDER_THICKNESS_PX, 0.0001)


## The north-facing rail's wood already ends at the tile's bottom edge, so
## its collider must NOT move -- this half was right and has to stay right.
func test_a_bottom_anchored_rail_keeps_its_collider_on_the_tile_edge():
	var rect := _rail_rect_with_height("north")
	assert_almost_eq(rect.end.y, 16.0, 0.0001, "its wood really does end at the tile edge")


## Both horizontal facings end up blocking at their own wood's foot, which is
## the whole point -- stated as one property rather than two coordinates.
func test_both_horizontal_rails_block_at_their_own_foot():
	for facing in ["north", "south"]:
		var id := VillageFarm.fence_tile_for(facing)
		var inner := VillageFarm.fence_inner_direction(id)
		var foot := 16.0 if inner.y > 0 else _FENCE_H
		assert_almost_eq(_rail_rect_with_height(facing).end.y, foot, 0.0001, facing)


## A VERTICAL rail is untouched by this: its wood is anchored left or right,
## its foot is not a y coordinate at all, and the report was about horizontal
## fences only.
func test_a_vertical_rail_is_unchanged_by_the_wood_height():
	for facing in ["east", "west"]:
		var with_height := _rail_rect_with_height(facing)
		var without := VillageFarm.fence_collider_rect(
			VillageFarm.fence_tile_for(facing), 16.0,
			VillageFarm.FENCE_COLLIDER_THICKNESS_PX, 16.0
		)
		assert_eq(with_height, without, facing)


## The strip never leaves its own tile however odd the height it is handed --
## art that measures taller than the cell, or shorter than the strip is deep.
## Physics bodies are placed from this rect, so a foot outside the tile would
## put a rail in its NEIGHBOUR'S cell and wall a run that should be open.
func test_the_foot_is_clamped_into_the_tile_whatever_height_it_is_given():
	for height in [-4.0, 0.0, 1.0, 16.0, 40.0]:
		var rect := VillageFarm.fence_collider_rect(
			VillageFarm.fence_tile_for("south"), 16.0,
			VillageFarm.FENCE_COLLIDER_THICKNESS_PX, height
		)
		assert_gte(rect.position.y, 0.0, "height %s" % height)
		assert_lte(rect.end.y, 16.0, "height %s" % height)
		assert_almost_eq(
			rect.size.y, VillageFarm.FENCE_COLLIDER_THICKNESS_PX, 0.0001,
			"and stays a full rail thick rather than being squeezed, height %s" % height
		)
