extends GutTest

## What a builder fetches from the village store, and how many trips the
## project's own reservation is really worth (docs/concept/building.md,
## "And he carries the material"). Asked for directly: *"the builders
## should carry materials to the site"*.
##
## The load is READ off the project rather than authored: a building that
## costs more material is more trips, because that is what the building
## costs. This is the pure half of that -- ConstructionWorkerMarker walks
## the legs, this decides what is in his arms on each one.

const ConstructionHaul = preload("res://src/gameplay/construction_haul.gd")
const BuildingCatalog = preload("res://src/gameplay/building_catalog.gd")


func test_the_load_is_drawn_from_what_the_project_really_reserved():
	var load_out := ConstructionHaul.next_load({"wood": 12.0}, {})
	assert_eq(load_out.get("item_id", ""), "wood", "he carries the timber the cottage is made of")
	assert_almost_eq(float(load_out.get("count", 0.0)), float(ConstructionHaul.CARRY_LOAD), 0.001)


func test_the_heaviest_outstanding_item_goes_first():
	var load_out := ConstructionHaul.next_load({"wood": 4.0, "stone": 9.0}, {})
	assert_eq(load_out.get("item_id", ""), "stone", "the bulk of the pile moves first")


## Already-delivered material is off the list, so a second trip is not the
## first one over again.
func test_what_is_already_on_site_is_not_fetched_twice():
	var load_out := ConstructionHaul.next_load({"wood": 20.0, "stone": 10.0}, {"wood": 18.0})
	assert_eq(load_out.get("item_id", ""), "stone", "eighteen of the twenty are already standing there")


func test_the_last_trip_carries_only_the_remainder():
	var load_out := ConstructionHaul.next_load({"wood": 12.0}, {"wood": 10.0})
	assert_almost_eq(float(load_out.get("count", 0.0)), 2.0, 0.001, "he does not carry air to round up")


func test_a_finished_haul_is_no_load_at_all():
	assert_eq(ConstructionHaul.next_load({"wood": 12.0}, {"wood": 12.0}), {}, "everything is on site")


## A project with nothing reserved -- a planned site, a ledger row restored
## without material -- has nothing to carry, which is a real answer rather
## than an error: the builder simply works his plot (see the marker's own
## test_a_builder_with_nothing_to_fetch_never_leaves_the_site).
func test_an_unreserved_project_has_nothing_to_carry():
	assert_eq(ConstructionHaul.next_load({}, {}), {})
	assert_eq(ConstructionHaul.trips_required({}), 0)


## Determinism, the same reason every other seeded thing in this project is
## pinned: two equal piles must not pick a different first load run to run,
## or one builder would fetch differently on every reload.
func test_two_equal_piles_break_the_tie_the_same_way_every_time():
	var first := ConstructionHaul.next_load({"stone": 6.0, "wood": 6.0}, {})
	for i in 8:
		assert_eq(ConstructionHaul.next_load({"wood": 6.0, "stone": 6.0}, {}), first)


# -- calibration: CARRY_LOAD against what buildings really cost ------------
#
# The size of a load is not a number somebody liked: it is what makes a
# real cottage a handful of trips. One trip would mean the material
# teleports with a walk attached; fifty would mean the builder never lifts
# a mallet. Pinned against the REAL catalog costs, so a rebalance of what a
# cottage costs is caught here rather than silently changing how a village
# looks.


func _trips_for(building_id: String) -> int:
	var cost: Dictionary = BuildingCatalog.cost_of(building_id)
	var reserved := {}
	for item_id in cost:
		reserved[item_id] = float(cost[item_id])
	return ConstructionHaul.trips_required(reserved)


func test_a_real_cottage_is_a_handful_of_trips():
	var trips := _trips_for("house_small")
	assert_between(trips, 2, 8, "a cottage took %d trips" % trips)


func test_a_hall_costs_more_trips_than_a_cottage():
	assert_gt(
		_trips_for("city_hall"), _trips_for("house_small"),
		"a building that costs more material is more journeys, because that is what it costs"
	)


func test_the_trips_really_empty_the_pile():
	var reserved := {"wood": 20.0, "stone": 10.0}
	var delivered := {}
	var trips := 0
	while true:
		var load_out := ConstructionHaul.next_load(reserved, delivered)
		if load_out.is_empty():
			break
		trips += 1
		assert_lt(trips, 100, "the haul must terminate")
		var item_id: String = load_out["item_id"]
		delivered[item_id] = float(delivered.get(item_id, 0.0)) + float(load_out["count"])
	assert_eq(trips, ConstructionHaul.trips_required(reserved), "trips_required counts the real round")
	assert_almost_eq(float(delivered.get("wood", 0.0)), 20.0, 0.001)
	assert_almost_eq(float(delivered.get("stone", 0.0)), 10.0, 0.001)
