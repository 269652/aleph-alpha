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
	var next: String = VillageGrowth.next_building(9, 4, ["sawmill", "city_hall", "warehouse"])
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
	for households in range(1, 12):
		var next: String = VillageGrowth.next_building(households, households, standing)
		while next != "" and not standing.has(next):
			standing.append(next)
			raised.append(next)
			next = VillageGrowth.next_building(households, households, standing)
	assert_eq(raised, ["sawmill", "city_hall", "warehouse", "farmhouse", "blacksmith", "brewery"])


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
