extends GutTest

## Walking up to a wireframe and raising it -- yourself, or by paying
## somebody (see PlanRaising, docs/concept/planner_mode.md). Asked
## directly: "when leaving the plan mode he can go to one of the wireframes
## and hire an NPC to build it or build it himself".
##
## Pure: positions and inventories are passed in, so no Player, no
## NpcMarker, no chunk.

const PlanRaising = preload("res://src/gameplay/plan_raising.gd")
const BuildPlan = preload("res://src/world/build_plan.gd")
const BuildPlanLedger = preload("res://src/world/build_plan_ledger.gd")
const BuildingCatalog = preload("res://src/gameplay/building_catalog.gd")
const HiringGate = preload("res://src/world/hiring_gate.gd")

var ledger: BuildPlanLedger


func before_each():
	ledger = BuildPlanLedger.new()


func _anywhere(_cell: Vector2i) -> bool:
	return true


# -- standing in front of one ----------------------------------------------

func test_the_wireframe_you_are_standing_on_is_the_one_offered():
	ledger.plan(Vector2i.ZERO, Vector2i(4, 4), "house_small", 0.0, _anywhere)
	var found = PlanRaising.plan_within_reach(ledger, Vector2i(4, 4), 32)
	assert_not_null(found)
	assert_eq(found.blueprint_id, "house_small")


## Reach is generous enough to stand BESIDE a wireframe rather than
## demanding you stand inside its footprint -- you cannot stand inside a
## finished house, and the prompt should not require it of a planned one.
func test_standing_beside_a_wireframe_is_close_enough():
	ledger.plan(Vector2i.ZERO, Vector2i(4, 4), "house_small", 0.0, _anywhere)
	assert_not_null(
		PlanRaising.plan_within_reach(ledger, Vector2i(4, 4) - Vector2i(PlanRaising.REACH_TILES, 0), 32),
		"exactly at the reach limit still counts"
	)


func test_a_wireframe_across_the_map_is_not_offered():
	ledger.plan(Vector2i.ZERO, Vector2i(4, 4), "house_small", 0.0, _anywhere)
	assert_null(PlanRaising.plan_within_reach(ledger, Vector2i(40, 40), 32))


func test_nothing_planned_means_nothing_offered():
	assert_null(PlanRaising.plan_within_reach(ledger, Vector2i.ZERO, 32))


# -- building it yourself --------------------------------------------------

## Pillar 1 pays out here: the cost that planning did NOT charge is charged
## now, and it is the building's own real catalog cost, not a second
## number invented for the planner.
func test_building_it_yourself_needs_the_buildings_own_real_cost():
	var cost := BuildingCatalog.cost_of("house_small")
	assert_false(cost.is_empty(), "the premise: a house really costs something")
	assert_true(PlanRaising.can_build_yourself("house_small", cost))
	assert_false(PlanRaising.can_build_yourself("house_small", {}), "empty hands build nothing")


func test_what_you_are_short_of_is_named_so_the_prompt_can_say_it():
	var cost := BuildingCatalog.cost_of("house_small")
	var missing: Dictionary = PlanRaising.missing_materials("house_small", {})
	assert_eq(missing.size(), cost.size(), "everything is missing when you carry nothing")
	for item_id in cost:
		assert_eq(missing.get(item_id, 0), cost[item_id], item_id)


func test_carrying_more_than_enough_leaves_nothing_missing():
	var plenty := {}
	for item_id in BuildingCatalog.cost_of("house_small"):
		plenty[item_id] = 9999
	assert_true(PlanRaising.can_build_yourself("house_small", plenty))
	assert_eq(PlanRaising.missing_materials("house_small", plenty), {})


## Pavement is not a BuildingCatalog entry, so it has no catalog cost --
## and it must not therefore read as "free to raise but impossible to
## afford". It is buildable by hand, like the earth tile the player
## already places.
func test_pavement_can_always_be_laid_by_hand():
	assert_true(PlanRaising.can_build_yourself(BuildPlan.PAVEMENT_BLUEPRINT_ID, {}))


# -- hiring somebody -------------------------------------------------------

## Hiring an NPC to build is an ongoing wage relationship like any other in
## this game, so it goes through the SAME HiringGate rather than a second,
## softer rule invented for construction.
func test_hiring_uses_the_same_gate_every_other_wage_relationship_uses():
	var trusted := 1.0
	var wage := 10.0
	assert_eq(
		PlanRaising.can_hire_builder(trusted, wage, 1.0),
		HiringGate.can_hire(trusted, wage, 1.0),
		"no second, softer rule for construction"
	)


func test_an_untrusting_npc_will_not_be_hired_however_good_the_wage():
	assert_false(PlanRaising.can_hire_builder(0.0, 9999.0, 1.0))


func test_a_trusted_npc_still_refuses_an_insulting_wage():
	assert_false(PlanRaising.can_hire_builder(1.0, 0.0, 5.0))


# -- the two ways are the same construction --------------------------------

## Pillar 5: build-it-yourself and hire-somebody are the same construction,
## paid for differently. Both must name the same site and the same
## blueprint, or they are two features that happen to look alike.
func test_both_ways_raise_the_same_site_and_blueprint():
	ledger.plan(Vector2i(1, 1), Vector2i(2, 3), "sawmill", 0.0, _anywhere)
	var plan = ledger.plans()[0]
	var mine := PlanRaising.raising_request(plan, PlanRaising.Labour.PLAYER)
	var theirs := PlanRaising.raising_request(plan, PlanRaising.Labour.HIRED)
	assert_eq(mine.chunk_coord, theirs.chunk_coord)
	assert_eq(mine.origin, theirs.origin)
	assert_eq(mine.blueprint_id, theirs.blueprint_id)
	assert_ne(mine.labour, theirs.labour, "only who supplies the hours differs")
