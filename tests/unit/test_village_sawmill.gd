extends GutTest

## VillageSawmill: the pure rule set behind a village's own sawmill (see
## docs/concept/village_timber.md) -- which building it is, whose trade it
## is, how far a lumberjack ranges for timber, and what wants doing next.
##
## The sibling of VillageFarm, deliberately the same shape: this decides
## WHAT, LumberjackBehavior decides WHEN, and NpcMarker owns the world
## effect. Every number here is grounded in SagewerkProduction's own already-
## measured costs rather than invented a second time.

const VillageSawmill = preload("res://src/gameplay/village_sawmill.gd")
const SagewerkProduction = preload("res://src/world/sagewerk_production.gd")
const BuildingCatalog = preload("res://src/gameplay/building_catalog.gd")
const NpcIdentity = preload("res://src/world/npc_identity.gd")


func test_the_sawmill_is_the_catalogs_own_building():
	assert_ne(
		BuildingCatalog.footprint_of(VillageSawmill.SAWMILL_BUILDING_ID), Vector2i.ZERO,
		"the village sawmill is a real catalog building, never a second id"
	)


func test_the_trade_that_works_it_is_a_real_village_trade():
	assert_true(NpcIdentity.OCCUPATIONS.has(VillageSawmill.OCCUPATION))


func test_only_a_lumberjack_works_a_sawmill():
	assert_true(VillageSawmill.works_timber("lumberjack"))
	for occupation in ["farmer", "herbalist", "hunter", "merchant", "nurse"]:
		assert_false(VillageSawmill.works_timber(occupation), occupation)
	assert_false(VillageSawmill.works_timber(""))


# -- what the mill wants doing next ----------------------------------------


func test_an_empty_mill_wants_timber():
	assert_eq(VillageSawmill.next_action(0), VillageSawmill.FELL)


func test_a_mill_with_enough_logs_squares_a_beam():
	assert_eq(
		VillageSawmill.next_action(int(SagewerkProduction.LOG_COST_PER_BEAM)),
		VillageSawmill.SHAPE
	)


## Short of a beam's worth, the answer is still "go and fell": a lumberjack
## who stood at the mill waiting for logs nobody was fetching would be a
## sawmill that stops the moment it runs down.
func test_a_mill_short_of_a_beams_worth_sends_the_sawyer_back_out():
	assert_eq(
		VillageSawmill.next_action(int(SagewerkProduction.LOG_COST_PER_BEAM) - 1),
		VillageSawmill.FELL
	)


## The threshold is SagewerkProduction's own cost, not a second number that
## could drift from it.
func test_the_beam_threshold_is_the_sawmills_own_measured_cost():
	var cost := int(SagewerkProduction.LOG_COST_PER_BEAM)
	assert_eq(VillageSawmill.LOGS_PER_BEAM, cost)
	for stock in range(0, cost):
		assert_eq(VillageSawmill.next_action(stock), VillageSawmill.FELL, "stock %d" % stock)
	assert_eq(VillageSawmill.next_action(cost), VillageSawmill.SHAPE)


# -- how far a village fells -----------------------------------------------


## A village fells its own wood rather than stripping the map, so the range
## is a walk from the mill -- and it has to be at least as far as the mill
## itself was sited from timber, or a sawmill could be raised beside trees
## its own sawyer is not allowed to reach.
func test_a_lumberjack_ranges_at_least_as_far_as_the_mill_was_sited_for():
	var VillageLayout = load("res://src/world/village_layout.gd")
	assert_gte(
		VillageSawmill.TIMBER_REACH_TILES, int(VillageLayout.INDUSTRY_FOREST_REACH_TILES),
		"a mill sited beside timber must be able to reach that timber"
	)


func test_a_tree_within_range_is_workable_and_one_beyond_it_is_not():
	var mill := Vector2(0, 0)
	var reach := float(VillageSawmill.TIMBER_REACH_TILES) * 16.0
	assert_true(VillageSawmill.is_in_range(mill, Vector2(reach - 1.0, 0.0), 16))
	assert_false(VillageSawmill.is_in_range(mill, Vector2(reach + 1.0, 0.0), 16))
