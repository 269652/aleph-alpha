extends GutTest

## VillageAssembly: docs/concept/village_estates.md mechanism 5 -- what the
## village VOTES to build next, replacing village_growth.md's fixed ladder
## order with an estate-weighted petition.
##
## The thing a headcount ladder can never do: two villages of the same size
## with different estate mixes build visibly different towns, because each
## estate petitions for what IT is short of, and a burgher's voice in the
## assembly carries further than a cottager's.
##
## The vote rule in one line: a household short of something petitions for
## the works that would supply it; a household with nothing to complain of
## petitions for the charter that would let it rise.

const VillageAssembly = preload("res://src/emergence/village_assembly.gd")
const VillageEstates = preload("res://src/emergence/village_estates.gd")
const VillageGrowth = preload("res://src/emergence/village_growth.gd")
const EstateAscension = preload("res://src/emergence/estate_ascension.gd")
const BuildingCatalog = preload("res://src/gameplay/building_catalog.gd")

const FOOD := VillageEstates.FOOD_KIND_TOKEN
const FUEL := VillageEstates.FUEL_ITEM_ID

const PROVIDED := {}  # nothing short: every good reads as fully supplied


func _petition(overrides: Dictionary) -> String:
	var state := {
		"estate_counts": {"kossaet": 4},
		"household_count": 4,
		"housed_count": 4,
		"present_building_ids": [],
		"satisfaction": {},
	}
	state.merge(overrides, true)
	return VillageAssembly.next_building(state)


func _fully_supplied(estate_counts: Dictionary) -> Dictionary:
	var satisfaction := {}
	for estate in estate_counts:
		for good in VillageEstates.basket_goods(estate):
			satisfaction[good] = 1.0
	return satisfaction


# -- shelter first, unchanged ---------------------------------------------

func test_an_unhoused_household_outvotes_every_petition():
	var next := _petition({"housed_count": 1, "satisfaction": {FUEL: 0.0}})
	assert_true(BuildingCatalog.BUILDING_IDS.has(next), "a homeless village built works instead")


## And it closes village_growth.md's own named gap -- "a growth house is
## always the small one". The house a village raises is the house the
## waiting household's own ESTATE lives in, so a burgher who lost their
## roof is not rehoused in a cottage.
func test_the_house_raised_is_the_waiting_households_own_estates_house():
	var next := _petition({
		"estate_counts": {"buerger": 1},
		"household_count": 1,
		"housed_count": 0,
		"waiting_estate": "buerger",
	})
	assert_eq(next, VillageEstates.house_id_for("buerger"))


func test_with_no_waiting_estate_named_the_house_is_the_founding_one():
	var next := _petition({"household_count": 4, "housed_count": 3})
	assert_eq(next, VillageEstates.house_id_for(VillageEstates.STARTING_ESTATE))


# -- a household short of something petitions for the works ---------------

func test_a_village_short_of_fuel_petitions_for_the_sawmill():
	assert_eq(_petition({"satisfaction": {FOOD: 1.0, FUEL: 0.0}}), "sawmill")


func test_a_village_short_of_food_petitions_for_the_farm():
	assert_eq(_petition({"satisfaction": {FOOD: 0.0, FUEL: 1.0}}), "farmhouse")


## Worst first: a village short of both asks for what it is shortest of.
func test_a_village_petitions_for_its_WORST_shortage_not_merely_a_shortage():
	assert_eq(_petition({"satisfaction": {FOOD: 0.9, FUEL: 0.1}}), "sawmill")
	assert_eq(_petition({"satisfaction": {FOOD: 0.1, FUEL: 0.9}}), "farmhouse")


## Burghers want beer, and only a brewery makes it. The village has to
## hold the hands and the trade to work one, which a real village at this
## stage does -- a town of nothing but burghers genuinely cannot open a
## brewhouse, and does not vote for one it would leave cold.
func test_burghers_short_of_beer_petition_for_the_brewery():
	var estate_counts := {"kossaet": 2, "handwerker": 2, "buerger": 3}
	var satisfaction := _fully_supplied(estate_counts)
	satisfaction["beer"] = 0.0
	assert_eq(
		_petition({
			"estate_counts": estate_counts,
			"household_count": 7,
			"housed_count": 7,
			"present_building_ids": ["farmhouse", "sawmill", "city_hall"],
			"satisfaction": satisfaction,
		}),
		"brewery"
	)


## A shortage whose remedy already stands is not petitioned for again --
## the works exist and the shortage is a supply problem, not a building one.
func test_a_shortage_whose_works_already_stand_does_not_re_petition_for_them():
	assert_ne(_petition({"present_building_ids": ["sawmill"], "satisfaction": {FUEL: 0.0}}), "sawmill")


# -- a household with nothing to complain of petitions to rise ------------

func test_a_fully_supplied_village_petitions_for_the_charter_that_lets_it_rise():
	var estate_counts := {"kossaet": 5}
	assert_eq(
		_petition({
			"estate_counts": estate_counts,
			"household_count": 5,
			"housed_count": 5,
			"satisfaction": _fully_supplied(estate_counts),
		}),
		EstateAscension.charter_building_ids_for("kossaet")[0]
	)


## The bootstrap, and it is load-bearing: a charter building is exempt from
## the staffing gate. A village with no burghers cannot staff a civic seat
## and must build one anyway -- the seat is what CREATES the estate that
## keeps it. Without this exemption the ladder deadlocks at every rung.
func test_a_village_with_nobody_to_staff_a_civic_seat_still_petitions_for_one():
	var estate_counts := {"handwerker": 4}
	assert_eq(
		_petition({
			"estate_counts": estate_counts,
			"household_count": 4,
			"housed_count": 4,
			"present_building_ids": ["farmhouse", "sawmill"],
			"satisfaction": _fully_supplied(estate_counts),
		}),
		"city_hall"
	)


## A works nobody could put a single body in is never petitioned for: a
## village with no craftsmen does not vote to build a forge it would then
## leave cold.
func test_a_village_never_petitions_for_works_it_could_not_staff():
	var estate_counts := {"bauer": 6}
	var satisfaction := _fully_supplied(estate_counts)
	satisfaction["bread"] = 0.0
	var next := _petition({
		"estate_counts": estate_counts,
		"household_count": 6,
		"housed_count": 6,
		"present_building_ids": ["farmhouse", "city_hall"],
		"satisfaction": satisfaction,
	})
	assert_ne(next, "blacksmith", "a village of farmers voted for a forge nobody can work")


func test_a_village_that_has_everything_and_can_rise_no_further_petitions_for_nothing():
	var estate_counts := {"buerger": 3}
	assert_eq(
		_petition({
			"estate_counts": estate_counts,
			"household_count": 3,
			"housed_count": 3,
			"present_building_ids": VillageGrowth.LADDER_BUILDING_IDS,
			"satisfaction": _fully_supplied(estate_counts),
		}),
		""
	)


# -- weight: an estate assembly is not one household, one vote ------------

## Historically true and mechanically the point: a burgher's voice in the
## assembly carried further than a cottager's.
func test_a_higher_estate_carries_strictly_more_weight_in_the_assembly():
	var previous := -1.0
	for estate in VillageEstates.ESTATE_IDS:
		var weight: float = VillageAssembly.ESTATE_VOTE_WEIGHT[estate]
		assert_true(weight > previous, "%s is worth no more than the rung below" % estate)
		previous = weight


## Everyone is a little short of firewood; the burghers are out of beer
## entirely. Three burghers outvote five other households, and the village
## builds the brewery rather than the mill. This is the mechanism's whole
## claim: the same headcount, a different mix, a different town.
func _divided_village(cottagers: int) -> Dictionary:
	var estate_counts := {"kossaet": cottagers, "handwerker": 1, "buerger": 3}
	var satisfaction := _fully_supplied(estate_counts)
	satisfaction[FUEL] = 0.3  # short, and everyone feels it
	satisfaction["beer"] = 0.0  # the burghers' own, and shorter still
	return {
		"estate_counts": estate_counts,
		"household_count": cottagers + 4,
		"housed_count": cottagers + 4,
		"present_building_ids": ["farmhouse", "city_hall", "blacksmith"],
		"satisfaction": satisfaction,
	}


func test_a_few_burghers_outvote_more_cottagers():
	assert_eq(
		_petition(_divided_village(4)),
		"brewery",
		"the cottagers' sawmill won a vote the burghers should have carried"
	)


## And enough cottagers DO outvote the burghers -- weight is a thumb on the
## scale, never a veto.
func test_enough_cottagers_outvote_the_burghers_after_all():
	assert_eq(_petition(_divided_village(40)), "sawmill")


# -- determinism and the fallback -----------------------------------------

## A tie breaks on the growth ladder's own order, so the assembly is
## deterministic and a village with no strong opinion still behaves exactly
## as village_growth.md's ladder already does.
func test_a_tied_vote_breaks_on_the_growth_ladders_own_order():
	var estate_counts := {"kossaet": 2, "bauer": 2}
	var satisfaction := _fully_supplied(estate_counts)
	satisfaction[FOOD] = 0.0
	satisfaction[FUEL] = 0.0
	var next := _petition({
		"estate_counts": estate_counts,
		"household_count": 4,
		"housed_count": 4,
		"satisfaction": satisfaction,
	})
	assert_true(VillageGrowth.LADDER_BUILDING_IDS.has(next))


func test_the_same_village_always_votes_the_same_way():
	var estate_counts := {"kossaet": 3, "bauer": 3, "handwerker": 3}
	var satisfaction := _fully_supplied(estate_counts)
	satisfaction[FOOD] = 0.2
	satisfaction[FUEL] = 0.2
	var state := {
		"estate_counts": estate_counts,
		"household_count": 9,
		"housed_count": 9,
		"present_building_ids": ["city_hall"],
		"satisfaction": satisfaction,
	}
	var first := _petition(state)
	for _i in 20:
		assert_eq(_petition(state), first, "the assembly changed its mind on identical input")


## A village nobody has established anything about falls back to the ladder
## rather than to nothing, so the assembly can never make a village build
## LESS than it did before this existed.
func test_a_village_with_no_estate_census_at_all_falls_back_to_the_ladder():
	assert_eq(
		_petition({"estate_counts": {}, "household_count": 4, "housed_count": 4}),
		VillageGrowth.next_building(4, 4, [])
	)


## A village whose people are known but whose supply has never been
## ASSESSED has not abstained -- nobody asked it. Without this it silently
## petitions for nothing, and a village that has never been stepped builds
## nothing at all, which would make the assembly a regression on the plain
## ladder rather than a layer over it.
func test_a_village_nobody_has_assessed_yet_falls_back_to_the_ladder():
	assert_eq(
		_petition({
			"estate_counts": {"kossaet": 4},
			"household_count": 4,
			"housed_count": 4,
			"present_building_ids": ["farmhouse"],
			"satisfaction": {},
		}),
		VillageGrowth.next_building(4, 4, ["farmhouse"])
	)


## And once a reading HAS been taken, the fallback is gone: a village that
## really wants nothing really builds nothing.
func test_an_assessed_village_that_wants_nothing_builds_nothing():
	var estate_counts := {"buerger": 3}
	assert_eq(
		_petition({
			"estate_counts": estate_counts,
			"household_count": 3,
			"housed_count": 3,
			"present_building_ids": VillageGrowth.LADDER_BUILDING_IDS,
			"satisfaction": _fully_supplied(estate_counts),
		}),
		""
	)


func test_an_empty_village_owes_itself_nothing():
	assert_eq(_petition({"estate_counts": {}, "household_count": 0, "housed_count": 0}), "")


## The assembly only ever names something the growth ladder or the house
## catalog really knows how to raise.
func test_every_answer_is_a_building_the_village_can_actually_build():
	var estate_counts := {"kossaet": 2, "bauer": 2, "handwerker": 2, "buerger": 2}
	for shortage in [FOOD, FUEL, "bread", "beer", "herb", "candle", "hide", "honey"]:
		var satisfaction := _fully_supplied(estate_counts)
		satisfaction[shortage] = 0.0
		var next := _petition({
			"estate_counts": estate_counts,
			"household_count": 8,
			"housed_count": 8,
			"satisfaction": satisfaction,
		})
		assert_true(
			next == "" or VillageGrowth.LADDER_BUILDING_IDS.has(next) or BuildingCatalog.BUILDING_IDS.has(next),
			"a shortage of %s produced %s, which nothing builds" % [shortage, next]
		)
