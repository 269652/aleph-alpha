extends GutTest

## VillageGrowth: docs/concept/village_growth.md mechanism 2 -- the ONE
## building a village owes itself next, given how many households it has,
## how many of them are housed, and what already stands. Pure, static, no
## state of its own; it names the target and nothing else (whether the
## village can actually afford or staff the build stays
## SettlementSpareCapacity's and SettlementConstruction's job, exactly as
## for the city hall today).

const VillageGrowth = preload("res://src/emergence/village_growth.gd")
const BuildingCatalog = preload("res://src/gameplay/building_catalog.gd")


func test_a_village_with_nobody_in_it_owes_itself_nothing():
	assert_eq(VillageGrowth.next_building(0, 0, []), "")


## Shelter before adornment: a household without a roof outranks every
## civic and production rung, however entitled the village is to them.
func test_an_unhoused_household_outranks_every_other_rung():
	var next: String = VillageGrowth.next_building(9, 4, ["sawmill", "city_hall", "farmhouse"])
	assert_true(BuildingCatalog.BUILDING_IDS.has(next), "a homeless household gets a house, not a brewery")


func test_a_fully_housed_village_moves_on_to_the_ladder():
	var next: String = VillageGrowth.next_building(3, 3, [])
	assert_false(BuildingCatalog.BUILDING_IDS.has(next), "nobody is homeless -- build the works")


## The sawmill is rung one because timber is the input every later rung is
## made of: even a village of one owes itself one.
func test_the_very_first_rung_is_the_sawmill():
	assert_eq(VillageGrowth.next_building(1, 1, []), "sawmill")


## The hall's threshold is CivicBuildDecision's own, unchanged -- one
## number, not a second copy that could drift from it.
func test_the_city_halls_threshold_is_the_civic_decisions_own():
	var CivicBuildDecision = load("res://src/emergence/civic_build_decision.gd")
	assert_eq(
		VillageGrowth.min_households_for("city_hall"), CivicBuildDecision.CITY_HALL_MIN_HOUSEHOLDS
	)


func test_the_ladder_is_walked_in_order_as_the_village_grows():
	var standing: Array = []
	var raised: Array = []
	# Up past the ladder's own top rung, read off the ladder rather than
	# typed in, so re-spacing the rungs cannot silently stop this walk short
	# of one of them and go on passing.
	var top: int = VillageGrowth.min_households_for(
		VillageGrowth.LADDER_BUILDING_IDS[VillageGrowth.LADDER_BUILDING_IDS.size() - 1]
	)
	for households in range(1, top + 2):
		var next: String = VillageGrowth.next_building(households, households, standing)
		while next != "" and not standing.has(next):
			standing.append(next)
			raised.append(next)
			next = VillageGrowth.next_building(households, households, standing)
	# No warehouse: a village is FOUNDED with its store standing, so the
	# ladder never owes one (docs/concept/village_warehouse.md). It used to
	# sit between city_hall and farmhouse here.
	assert_eq(raised, ["sawmill", "city_hall", "farmhouse", "blacksmith", "brewery"])


func test_a_rung_whose_threshold_is_not_met_is_never_named():
	# Two households: the sawmill is owed, the hall (3) is not.
	assert_eq(VillageGrowth.next_building(2, 2, ["sawmill"]), "")


func test_a_rung_already_standing_is_never_named_again():
	assert_eq(VillageGrowth.next_building(3, 3, ["sawmill", "city_hall"]), "", "one seat per village")


func test_a_village_with_everything_its_size_entitles_it_to_owes_nothing():
	assert_eq(
		VillageGrowth.next_building(20, 20, ["sawmill", "city_hall", "warehouse", "farmhouse", "blacksmith", "brewery"]),
		""
	)


## A bigger village is entitled to strictly more -- the honest thing to
## pin, rather than any one "correct" population per rung.
func test_every_rung_is_entitled_to_at_a_larger_size_than_the_one_before_it():
	var previous := 0
	for building_id in VillageGrowth.LADDER_BUILDING_IDS:
		var threshold: int = VillageGrowth.min_households_for(building_id)
		assert_gt(threshold, 0, "%s needs a real threshold" % building_id)
		assert_gte(threshold, previous, "%s must not be entitled earlier than the rung before it" % building_id)
		previous = threshold
	assert_gt(previous, VillageGrowth.min_households_for(VillageGrowth.LADDER_BUILDING_IDS[0]), "the ladder really climbs")


func test_every_rung_is_a_real_catalog_building_nobody_lives_in():
	for building_id in VillageGrowth.LADDER_BUILDING_IDS:
		assert_true(BuildingCatalog.has_building(building_id), "%s must be real" % building_id)
		assert_eq(BuildingCatalog.capacity_of(building_id), 0, "%s is not a home" % building_id)


func test_an_unknown_building_has_no_threshold():
	assert_eq(VillageGrowth.min_households_for("moon_base"), 0)


# -- how many rungs stand: the community need's own real input -------------

func test_standing_rungs_counts_only_real_ladder_buildings():
	assert_eq(VillageGrowth.standing_rungs(["sawmill", "house_small", "city_hall", "sagewerk"]), 2)
	assert_eq(VillageGrowth.standing_rungs([]), 0)


func test_the_ladder_share_runs_from_nothing_to_everything():
	assert_eq(VillageGrowth.ladder_share([]), 0.0)
	assert_eq(VillageGrowth.ladder_share(VillageGrowth.LADDER_BUILDING_IDS), 1.0)
	assert_almost_eq(
		VillageGrowth.ladder_share(["sawmill", "city_hall", "city_hall"]),
		2.0 / float(VillageGrowth.LADDER_BUILDING_IDS.size()), 0.001
	)


# -- the warehouse left the ladder ------------------------------------------
#
# See docs/concept/village_warehouse.md. Every village is founded with a
# store already standing (VillageLayout.warehouse_plot, raised by
# VillageRenderer), so it is not something a village grows into.
#
# The rung is REMOVED rather than lowered to one household. A threshold that
# is always met is a gate that lies to the next reader, and worse: the rung
# would be satisfied before the ladder is ever consulted, so next_building
# would keep naming a target the village already has -- exactly the bug
# present_building_ids exists to prevent.


func test_the_warehouse_is_not_a_rung_a_village_climbs():
	assert_false(
		VillageGrowth.LADDER_BUILDING_IDS.has("warehouse"),
		"a village is founded with its store, so the ladder must not owe it one"
	)
	assert_eq(
		VillageGrowth.min_households_for("warehouse"),
		0,
		"not a rung means no threshold, not a threshold of one"
	)


## Whatever the village's size, and whatever it already has standing, the
## ladder never asks for a warehouse -- swept across the whole range the
## thresholds span rather than at one convenient number.
func test_no_village_of_any_size_is_ever_owed_a_warehouse():
	for households in range(1, 13):
		var owed := VillageGrowth.next_building(households, households, [])
		assert_ne(owed, "warehouse", "a village of %d households was owed one" % households)


# -- the ladder is spaced in founding rosters -------------------------------
# Asked directly: *"increase the village sizes from 5 houses to 10 initial
# and then it should grow by itself; adding new houses new trades"*. The
# second half is the constraint on the first: if every rung's threshold sits
# at or below the founding roster, a village is founded already owing itself
# the whole ladder and there is nothing left to grow into. The ladder was
# spaced against a roster of five; the roster is ten now, so the ladder is
# spaced against ten.

const SettlementGenerator = preload("res://src/world/settlement_generator.gd")


## A village is founded able to feed and govern itself -- the rungs it needs
## to live are its from the start.
func test_a_founded_village_is_entitled_to_the_rungs_it_needs_to_live():
	for building_id in ["sawmill", "city_hall", "farmhouse"]:
		assert_lte(
			VillageGrowth.min_households_for(building_id), SettlementGenerator.POPULATION,
			"%s is what a village needs to live, not something it grows into" % building_id
		)


## And the specialists are what it grows into. A threshold already met at
## founding is a gate that lies to the next reader -- the same reasoning
## that took the warehouse off this ladder entirely.
func test_a_founded_village_still_has_trades_to_grow_into():
	var founding := SettlementGenerator.POPULATION
	for building_id in ["blacksmith", "brewery"]:
		assert_gt(
			VillageGrowth.min_households_for(building_id), founding,
			"%s must be something a village grows into, not something it is founded with" % building_id
		)
	var standing: Array = ["sawmill", "city_hall", "warehouse", "farmhouse"]
	assert_eq(
		VillageGrowth.next_building(founding, founding, standing), "",
		"a freshly founded village owes itself nothing more until it grows"
	)


# -- a village keeps a roof standing empty for the next arrival -------------
#
# The other half of "NPCs should only move in when a new unoccupied house
# exists for them" (see test_village_immigration.gd). Once arrivals need a
# REAL empty house, something has to build one -- and priority 1 only ever
# fires for a household that is already here with nowhere to live. A village
# whose people are all housed would otherwise owe itself nothing, build
# nothing, and so never have the spare roof an arrival needs: it would stop
# growing for good the moment it caught up with itself.
#
# So the lowest rung of the ladder is a house for nobody in particular. It
# sits BELOW the civic and production rungs on purpose -- a village finishes
# what it already owes itself before it makes room for strangers -- and
# above nothing at all.


func _every_rung() -> Array:
	var built: Array = []
	for building_id in VillageGrowth.LADDER_BUILDING_IDS:
		built.append(building_id)
	return built


func test_a_village_with_every_rung_standing_and_no_spare_roof_builds_a_house():
	assert_eq(
		VillageGrowth.next_building(10, 10, _every_rung(), 0),
		BuildingCatalog.BUILDING_IDS[0],
		"a village with nowhere for anyone to move into builds somewhere"
	)


func test_a_village_that_already_has_a_spare_roof_owes_itself_nothing_more():
	assert_eq(
		VillageGrowth.next_building(10, 10, _every_rung(), 1), "",
		"an empty house already stands -- building a second is hoarding, not growth"
	)


## Below the rungs, not above them: a village owed a sawmill builds the
## sawmill first, and makes room for newcomers after.
func test_the_rungs_a_village_is_owed_still_come_before_room_for_strangers():
	var nothing_built: Array = []
	assert_eq(
		VillageGrowth.next_building(50, 50, nothing_built, 0),
		VillageGrowth.LADDER_BUILDING_IDS[0],
		"a village with no sawmill builds the sawmill before a spare cottage"
	)


## And above nothing: a household with no roof of its own still outranks
## everything, which is what lets a village that has already overfilled
## itself dig out rather than stall.
func test_a_household_with_no_roof_still_outranks_the_spare_one():
	assert_eq(
		VillageGrowth.next_building(21, 10, _every_rung(), 0),
		BuildingCatalog.BUILDING_IDS[0]
	)


## A caller that does not know its spare capacity gets exactly the ladder it
## always got -- the new rung stays silent rather than making every such
## caller build houses for ever.
func test_a_caller_that_does_not_pass_spare_capacity_gets_the_old_ladder():
	assert_eq(VillageGrowth.next_building(10, 10, _every_rung()), "")
