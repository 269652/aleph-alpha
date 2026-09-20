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
const SettlementCharter = preload("res://src/emergence/settlement_charter.gd")
const SettlementTier = preload("res://src/emergence/settlement_tier.gd")

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


# -- a works that feeds people scales with the people -----------------------
#
# Asked directly: *"when population rises and there's not enough food they
# need to build more Farmhouses; Fishers or Hunters"*.
#
# _is_petitionable refuses anything already standing, which is right for a
# charter (one hall; a second entitles nobody) and wrong for a works: one
# farmhouse feeds the households one farmer can feed, so a village of forty
# stayed hungry with the remedy standing in plain sight.

const SettlementFoodDemand = preload("res://src/emergence/settlement_food_demand.gd")


## A village big enough to need several farmers, short of food, with one
## farmhouse already up.
func _hungry_village(households: int, present: Array, extras: Dictionary = {}) -> Dictionary:
	var state := {
		"estate_counts": {"kossaet": households},
		"household_count": households,
		"housed_count": households,
		"present_building_ids": present,
		"satisfaction": {VillageEstates.FOOD_KIND_TOKEN: 0.2},
	}
	for key in extras:
		state[key] = extras[key]
	return state


## The size that really asks for more than one producer, searched rather
## than guessed -- the same discipline the staffing test uses.
func _households_needing(producers: int) -> int:
	for size in range(2, 2000):
		if SettlementFoodDemand.producers_needed(size) >= producers:
			return size
	fail_test("no village size needs %d producers" % producers)
	return 0


## With husbandmen in it, who are the class a farmstead is worked by. A
## village of pure cottagers cannot staff a SECOND farm -- the first is
## raised under the charter exemption, and rising off it is what produces
## the field hands the next one needs. That ordering is the ladder working,
## not a gap.
func test_a_village_short_of_food_raises_a_second_farmhouse():
	var households := _households_needing(2)
	var state := _hungry_village(households, ["farmhouse"], {
		"estate_counts": {"kossaet": households - 2, "bauer": 2},
		"building_counts": {"farmhouse": 1},
	})
	assert_eq(VillageAssembly.next_building(state), "farmhouse")


## And a village with nobody who could work one does not vote for a second
## farmstead it would leave standing empty -- the same rule that has always
## kept a village from voting for a forge it has no smith for.
func test_a_village_of_cottagers_alone_does_not_vote_for_a_farm_it_cannot_work():
	var households := _households_needing(2)
	var state := _hungry_village(households, ["farmhouse"], {
		"building_counts": {"farmhouse": 1},
	})
	assert_ne(VillageAssembly.next_building(state), "farmhouse")


func test_a_village_with_a_farmhouse_for_every_farmer_it_needs_stops_asking():
	var households := _households_needing(2)
	var enough := SettlementFoodDemand.producers_needed(households)
	var state := _hungry_village(households, ["farmhouse"], {
		"building_counts": {"farmhouse": enough},
	})
	assert_ne(
		VillageAssembly.next_building(state), "farmhouse",
		"a village with a farmstead per farmer asks for something else, or nothing"
	)


## A charter does NOT scale: one hall entitles everybody in the village, and
## a second would entitle nobody.
func test_a_charter_is_still_only_ever_raised_once():
	var households := _households_needing(3)
	var state := _hungry_village(households, ["city_hall"], {
		"building_counts": {"city_hall": 1},
	})
	assert_ne(VillageAssembly.next_building(state), "city_hall")


## Counts nobody has supplied read as "one of each that stands", so every
## caller that has not been taught to count is exactly as it was.
func test_a_caller_that_counts_nothing_behaves_as_it_always_did():
	var households := _households_needing(2)
	assert_ne(
		VillageAssembly.next_building(_hungry_village(households, ["farmhouse"])),
		"farmhouse",
		"without counts a standing farmhouse is still one that stands"
	)


# -- and the land decides which works ---------------------------------------


## A fisher's works is their own house, beside which they dig their pond.
## Raising a farmhouse in a fishing village is a building nobody there will
## work, so the honest answer is to petition for nothing on that count.
##
## Asked with the kossaet CHARTER already standing, which is the farmhouse
## too (EstateAscension._CHARTERS_BY_ESTATE: you cannot be a husbandman
## where there is no plough-land worked). That path is a real and separate
## reason to raise one -- a fishing village that wants husbandmen does need
## a farm -- and this test is about the FOOD remedy, not about that.
func test_a_fishing_village_short_of_food_does_not_raise_a_farmhouse():
	var households := _households_needing(2)
	var enough := SettlementFoodDemand.producers_needed(households)
	var state := _hungry_village(households, ["farmhouse"], {
		"building_counts": {"farmhouse": 1},
		"food_trade": "fisher",
	})
	assert_gt(enough, 1, "precondition: a farming village this size would want another")
	assert_ne(
		VillageAssembly.next_building(state), "farmhouse",
		"a fishing village raises no second farmstead to feed itself"
	)


func test_a_farming_village_still_raises_its_farmhouse():
	var households := _households_needing(2)
	var state := _hungry_village(households, [], {
		"building_counts": {},
		"food_trade": "farmer",
	})
	assert_eq(VillageAssembly.next_building(state), "farmhouse")


## A herbalist's physic garden is worked off the farmstead's own field, so
## their land raises the same building a farmer's does.
func test_a_herbalists_land_raises_the_same_farmstead():
	var households := _households_needing(2)
	var state := _hungry_village(households, [], {
		"building_counts": {},
		"food_trade": "herbalist",
	})
	assert_eq(VillageAssembly.next_building(state), "farmhouse")


## No trade named is farming -- the fallback the food model itself keeps,
## because a farmer can raise a farmhouse anywhere a village can build.
func test_no_land_named_falls_back_to_farming():
	var households := _households_needing(2)
	var state := _hungry_village(households, [], {"building_counts": {}})
	assert_eq(VillageAssembly.next_building(state), "farmhouse")
	assert_eq(SettlementFoodDemand.FALLBACK_TRADE, "farmer", "and that is the model's own fallback")


# -- the village reads the same charter the player does -------------------

## docs/concept/settlement_charter.md mechanism 4. A hamlet must not spend
## years saving timber for a hall it would be refused -- and a village that
## could quietly raise through its own ledger what a player standing on its
## square is refused would make the charter a lie.
func test_a_hamlet_never_petitions_for_a_building_its_charter_forbids():
	var estate_counts := {"buerger": 6}
	var satisfaction := _fully_supplied(estate_counts)
	for good in satisfaction:
		satisfaction[good] = 0.0
	for _i in 30:
		var next := _petition({
			"estate_counts": estate_counts,
			"household_count": 6,
			"housed_count": 6,
			"present_building_ids": [],
			"satisfaction": satisfaction,
			"tier": SettlementTier.HAMLET,
		})
		assert_true(
			SettlementCharter.allows(next, SettlementTier.HAMLET),
			"a hamlet petitioned for %s, which it may not raise" % next
		)


## A settlement whose tier nobody told us is treated as the LOWEST, so the
## assembly errs toward refusing rather than toward letting a hamlet build
## a mage guild because a caller forgot an argument.
func test_a_village_whose_tier_is_unknown_is_treated_as_the_lowest():
	var estate_counts := {"kossaet": 4}
	var next := _petition({
		"estate_counts": estate_counts,
		"household_count": 4,
		"housed_count": 4,
		"present_building_ids": [],
		"satisfaction": _fully_supplied(estate_counts),
	})
	assert_true(SettlementCharter.allows(next, SettlementTier.HAMLET))


## And the charter never blocks the ladder itself: a village that wants a
## sawmill still gets one, whatever its tier.
func test_the_charter_never_blocks_a_village_from_climbing():
	var estate_counts := {"kossaet": 4}
	var satisfaction := _fully_supplied(estate_counts)
	satisfaction[FUEL] = 0.0
	assert_eq(
		_petition({
			"estate_counts": estate_counts,
			"household_count": 4,
			"housed_count": 4,
			"present_building_ids": [],
			"satisfaction": satisfaction,
			"tier": SettlementTier.HAMLET,
		}),
		"sawmill"
	)


# -- the civic petition: a city builds its own institutions ---------------

## docs/concept/settlement_charter.md. An estate with nothing to complain
## of and no charter left to earn is the top of the village, and what the
## top of a village asks for is the institutions its standing finally
## entitles the place to. Without this a city that earned its charter would
## sit there never raising anything with it, and the player's own hand
## would be the only way a mage guild ever appeared.
func test_a_city_whose_people_want_for_nothing_petitions_for_its_institutions():
	var estate_counts := {"buerger": 6}
	assert_eq(
		_petition({
			"estate_counts": estate_counts,
			"household_count": 6,
			"housed_count": 6,
			"present_building_ids": VillageGrowth.LADDER_BUILDING_IDS,
			"satisfaction": _fully_supplied(estate_counts),
			"tier": SettlementTier.CITY,
		}),
		"trade_hall",
		"a city with everything asked for nothing"
	)


## In charter order, cheapest entitlement first: the town's hall before the
## city's guild, so a place builds up rather than straight to the top.
func test_a_city_raises_what_it_was_entitled_to_first_before_what_it_just_earned():
	var estate_counts := {"buerger": 6}
	assert_eq(
		_petition({
			"estate_counts": estate_counts,
			"household_count": 6,
			"housed_count": 6,
			"present_building_ids": VillageGrowth.LADDER_BUILDING_IDS + ["trade_hall"],
			"satisfaction": _fully_supplied(estate_counts),
			"tier": SettlementTier.CITY,
		}),
		"mage_guild"
	)


## A town asks for its hall and never for the guild -- it is not a city,
## and the charter is the whole reason the player has an errand.
func test_a_town_with_everything_still_never_asks_for_a_mage_guild():
	var estate_counts := {"buerger": 6}
	var present: Array = VillageGrowth.LADDER_BUILDING_IDS + ["trade_hall"]
	assert_eq(
		_petition({
			"estate_counts": estate_counts,
			"household_count": 6,
			"housed_count": 6,
			"present_building_ids": present,
			"satisfaction": _fully_supplied(estate_counts),
			"tier": SettlementTier.TOWN,
		}),
		"",
		"a town asked for a building only a city may raise"
	)


## And a place that has everything its charter entitles it to really does
## want for nothing.
func test_a_city_holding_every_entitlement_petitions_for_nothing():
	var estate_counts := {"buerger": 6}
	assert_eq(
		_petition({
			"estate_counts": estate_counts,
			"household_count": 6,
			"housed_count": 6,
			"present_building_ids": (
				VillageGrowth.LADDER_BUILDING_IDS + BuildingCatalog.CHARTERED_BUILDING_IDS
			),
			"satisfaction": _fully_supplied(estate_counts),
			"tier": SettlementTier.CITY,
		}),
		""
	)


## A SHORTAGE still outranks an institution: hungry people before halls.
func test_a_shortage_still_outranks_an_institution():
	var estate_counts := {"kossaet": 2, "buerger": 4}
	var satisfaction := _fully_supplied(estate_counts)
	satisfaction[FUEL] = 0.0
	assert_eq(
		_petition({
			"estate_counts": estate_counts,
			"household_count": 6,
			"housed_count": 6,
			"present_building_ids": ["farmhouse", "city_hall", "blacksmith", "brewery"],
			"satisfaction": satisfaction,
			"tier": SettlementTier.CITY,
		}),
		"sawmill",
		"a city built a hall while its people were cold"
	)


# -- room is made first, and moved into after -----------------------------
#
# village_growth.md says this already, and has since 2026-09-20: *"a
# village whose people are all housed would owe itself nothing, build
# nothing, and never have the roof an arrival needs -- it would stop
# growing for good the moment it caught up with itself. So next_building
# gains a lowest rung: a house for nobody in particular, when
# spare_house_capacity <= 0."*
#
# That rung was added to VillageGrowth.next_building. The live decision
# does not go through it: EarthChunkManager._apply_village_growth_decision
# asks next_building_for_settlement, which asks THIS function, and this
# function had no such rung and was never handed the capacity to test it.
# The documented fix was unreachable from the path the village uses.
#
# Measured (tools/probe_village_growth_gate.gd) on a real village over a
# 1200-second watch, every ladder rung it was entitled to already standing:
#
#     seconds  house housed  room  food/hh  ladder
#         300     10     10     0     2.30    0.60
#         600     10     10     0     2.30    0.60
#         900     10     10     0     2.10    0.60
#        1050     10     10     0     2.30    0.60
#
# Food comfortably over FED_THRESHOLD (2.0) the whole way, and `room` zero
# at every single sample. The village was fed, content, and sealed.

const _SETTLED := {"kossaet": 4}


## Everyone housed, nothing to complain of, and no spare roof: the village
## owes itself a house.
func test_a_village_with_no_spare_roof_owes_itself_a_house():
	var next := _petition({
		"estate_counts": _SETTLED,
		"satisfaction": _fully_supplied(_SETTLED),
		"present_building_ids": VillageGrowth.LADDER_BUILDING_IDS.duplicate(),
		"spare_house_capacity": 0,
	})
	assert_true(
		BuildingCatalog.BUILDING_IDS.has(next),
		"a village that caught up with itself must still make room: got '%s'" % next
	)


## ...and a village that already HAS a spare roof does not keep building
## them. One empty house is room; two is a habit.
func test_a_village_with_a_spare_roof_owes_nothing():
	var next := _petition({
		"estate_counts": _SETTLED,
		"satisfaction": _fully_supplied(_SETTLED),
		"present_building_ids": VillageGrowth.LADDER_BUILDING_IDS.duplicate(),
		"spare_house_capacity": 1,
	})
	assert_eq(next, "", "an empty house already stands; nothing is owed")


## The house for nobody in particular is the STARTING estate's, because
## that is the estate a newcomer arrives as (VillageEstates.STARTING_ESTATE
## -- admit_household forms exactly one).
func test_the_room_made_is_the_house_a_newcomer_would_live_in():
	var next := _petition({
		"estate_counts": {"buerger": 4},
		"satisfaction": _fully_supplied({"buerger": 4}),
		"present_building_ids": VillageGrowth.LADDER_BUILDING_IDS.duplicate(),
		"spare_house_capacity": 0,
	})
	assert_eq(
		next, VillageEstates.house_id_for(VillageEstates.STARTING_ESTATE),
		"a stranger arrives a cottager, whatever the burghers here live in"
	)


## And it sits BELOW every petition, exactly as village_growth.md rules: a
## village finishes what it already owes itself before it makes room for
## strangers.
func test_a_real_petition_still_outranks_making_room():
	var next := _petition({
		"estate_counts": _SETTLED,
		"satisfaction": {FUEL: 0.0},
		"spare_house_capacity": 0,
	})
	assert_false(
		BuildingCatalog.BUILDING_IDS.has(next),
		"a cold village builds the works that warms it before a spare roof: got '%s'" % next
	)


## A caller that does not know its spare capacity gets exactly the
## behaviour it always got -- the same default VillageGrowth.next_building
## already keeps, so nothing that never learned this parameter starts
## building houses.
func test_a_caller_that_does_not_know_its_capacity_is_unchanged():
	var next := _petition({
		"estate_counts": _SETTLED,
		"satisfaction": _fully_supplied(_SETTLED),
		"present_building_ids": VillageGrowth.LADDER_BUILDING_IDS.duplicate(),
	})
	assert_eq(next, "", "absent capacity reads as 'there is already room'")
