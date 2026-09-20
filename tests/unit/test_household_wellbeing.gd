extends GutTest

## HouseholdWellbeing: docs/concept/village_growth.md mechanism 4 -- a
## household's four needs, its happiness and its productivity, DERIVED from
## real state at the moment they are asked for rather than stored anywhere.
## Pure and static; every input is a number the simulation already keeps.

const HouseholdWellbeing = preload("res://src/emergence/household_wellbeing.gd")
const VillageGrowth = preload("res://src/emergence/village_growth.gd")
const VillageMarket = preload("res://src/world/village_market.gd")


## A fed, housed, paid household in a village with its whole ladder up.
func _thriving() -> Dictionary:
	return {
		"hunger": 0.0,
		"food_per_household": HouseholdWellbeing.FOOD_STOCK_PER_HOUSEHOLD_TARGET,
		"house_capacity": 3, "household_size": 1,
		"wallet_balance": VillageMarket.VILLAGE_LOCAL_FOOD_PRICE * HouseholdWellbeing.INCOME_MEALS_FOR_FULL,
		"meal_price": VillageMarket.VILLAGE_LOCAL_FOOD_PRICE,
		"ladder_share": 1.0,
		"employment": 1.0,
	}


func test_a_thriving_household_meets_every_need_and_is_fully_happy():
	var out: Dictionary = HouseholdWellbeing.assess(_thriving())
	for need in HouseholdWellbeing.NEED_IDS:
		assert_almost_eq(float(out["needs"][need]), 1.0, 0.001, "%s should be fully met" % need)
	assert_almost_eq(float(out["happiness"]), 1.0, 0.001)
	assert_almost_eq(float(out["productivity"]), 1.0, 0.001)


func test_every_need_and_score_always_lands_inside_the_unit_range():
	var extremes: Array = [
		{},
		{"hunger": 5.0, "food_per_household": -3.0, "house_capacity": -1, "household_size": 0,
		 "wallet_balance": -99, "meal_price": 0, "ladder_share": 7.0},
		_thriving(),
	]
	for state in extremes:
		var out: Dictionary = HouseholdWellbeing.assess(state)
		for need in HouseholdWellbeing.NEED_IDS:
			var value: float = out["needs"][need]
			assert_between(value, 0.0, 1.0, "%s out of range for %s" % [need, str(state)])
		assert_between(float(out["happiness"]), 0.0, 1.0)
		assert_between(float(out["productivity"]), 0.0, 1.0)


func test_an_empty_state_reads_as_destitute_not_as_a_crash():
	var out: Dictionary = HouseholdWellbeing.assess({})
	assert_eq(out["needs"].size(), HouseholdWellbeing.NEED_IDS.size())
	assert_lt(float(out["happiness"]), 0.5, "nothing known is nothing met")


# -- food: the resident's own belly AND the village larder -----------------

func test_hunger_and_an_empty_larder_each_cut_the_food_need():
	var fed: Dictionary = HouseholdWellbeing.assess(_thriving())
	var starving: Dictionary = _thriving()
	starving["hunger"] = 1.0
	var empty_larder: Dictionary = _thriving()
	empty_larder["food_per_household"] = 0.0
	assert_lt(float(HouseholdWellbeing.assess(starving)["needs"]["food"]), float(fed["needs"]["food"]))
	assert_lt(float(HouseholdWellbeing.assess(empty_larder)["needs"]["food"]), float(fed["needs"]["food"]))


func test_a_fed_villager_in_an_empty_village_is_still_not_fully_fed():
	# The larder half is real: a full belly today with nothing in store is
	# not the same as a full belly with a winter's food behind it.
	var state: Dictionary = _thriving()
	state["food_per_household"] = 0.0
	assert_lt(float(HouseholdWellbeing.assess(state)["needs"]["food"]), 1.0)
	assert_gt(float(HouseholdWellbeing.assess(state)["needs"]["food"]), 0.0)


# -- shelter: a roof first, elbow room after ------------------------------

func test_a_homeless_household_has_no_shelter_at_all():
	var state: Dictionary = _thriving()
	state["house_capacity"] = 0
	assert_eq(float(HouseholdWellbeing.assess(state)["needs"]["shelter"]), 0.0)


func test_a_roof_is_most_of_shelter_and_spare_room_is_the_rest():
	var snug: Dictionary = _thriving()
	snug["house_capacity"] = 1
	snug["household_size"] = 1
	var roomy: Dictionary = _thriving()
	roomy["house_capacity"] = 3
	roomy["household_size"] = 1
	var snug_shelter: float = HouseholdWellbeing.assess(snug)["needs"]["shelter"]
	assert_gte(snug_shelter, HouseholdWellbeing.SHELTER_ROOF_SHARE, "a roof that fits is most of the way there")
	assert_lt(snug_shelter, float(HouseholdWellbeing.assess(roomy)["needs"]["shelter"]), "spare room is the rest")


func test_an_overcrowded_house_scores_below_a_bare_roof():
	var crowded: Dictionary = _thriving()
	crowded["house_capacity"] = 1
	crowded["household_size"] = 4
	assert_lt(float(HouseholdWellbeing.assess(crowded)["needs"]["shelter"]), HouseholdWellbeing.SHELTER_ROOF_SHARE)


# -- income and community --------------------------------------------------

func test_income_is_the_purse_measured_in_meals():
	var broke: Dictionary = _thriving()
	broke["wallet_balance"] = 0
	assert_eq(float(HouseholdWellbeing.assess(broke)["needs"]["income"]), 0.0)
	var half: Dictionary = _thriving()
	half["wallet_balance"] = int(VillageMarket.VILLAGE_LOCAL_FOOD_PRICE * HouseholdWellbeing.INCOME_MEALS_FOR_FULL / 2)
	assert_almost_eq(float(HouseholdWellbeing.assess(half)["needs"]["income"]), 0.5, 0.05)


func test_community_is_exactly_how_much_of_the_ladder_stands():
	var bare: Dictionary = _thriving()
	bare["ladder_share"] = VillageGrowth.ladder_share([])
	assert_eq(float(HouseholdWellbeing.assess(bare)["needs"]["community"]), 0.0)
	# Derived from the ladder itself, not a hand-copied list of rungs: this
	# used to name ["sawmill", "city_hall", "warehouse"] as "half", and
	# stopped being half the moment the warehouse left the ladder (it is
	# raised at founding now -- docs/concept/village_warehouse.md), leaving
	# the test asserting 0.5 against a real 0.4.
	var half_the_rungs: Array = VillageGrowth.LADDER_BUILDING_IDS.slice(
		0, VillageGrowth.LADDER_BUILDING_IDS.size() / 2
	)
	var halfway: Dictionary = _thriving()
	halfway["ladder_share"] = VillageGrowth.ladder_share(half_the_rungs)
	assert_almost_eq(
		float(HouseholdWellbeing.assess(halfway)["needs"]["community"]),
		float(half_the_rungs.size()) / float(VillageGrowth.LADDER_BUILDING_IDS.size()), 0.001
	)


# -- happiness: weighted, food heaviest ------------------------------------

func test_the_need_weights_are_a_real_distribution_over_every_need():
	var total := 0.0
	for need in HouseholdWellbeing.NEED_IDS:
		var weight: float = HouseholdWellbeing.NEED_WEIGHTS[need]
		assert_gt(weight, 0.0, "%s must actually count" % need)
		total += weight
	assert_almost_eq(total, 1.0, 0.001)


## Pinned by the ORDER it produces, not by the weights themselves: going
## hungry must cost a household more happiness than lacking a brewery.
func test_losing_food_costs_more_happiness_than_losing_community():
	var no_food: Dictionary = _thriving()
	no_food["hunger"] = 1.0
	no_food["food_per_household"] = 0.0
	var no_community: Dictionary = _thriving()
	no_community["ladder_share"] = 0.0
	assert_lt(
		float(HouseholdWellbeing.assess(no_food)["happiness"]),
		float(HouseholdWellbeing.assess(no_community)["happiness"])
	)


func test_losing_shelter_costs_more_happiness_than_losing_income():
	var homeless: Dictionary = _thriving()
	homeless["house_capacity"] = 0
	var broke: Dictionary = _thriving()
	broke["wallet_balance"] = 0
	assert_lt(
		float(HouseholdWellbeing.assess(homeless)["happiness"]),
		float(HouseholdWellbeing.assess(broke)["happiness"])
	)


# -- productivity: happiness, with hunger as a hard drag -------------------

func test_a_desperate_household_still_works_just_badly():
	var starving: Dictionary = _thriving()
	starving["hunger"] = 1.0
	var productivity: float = HouseholdWellbeing.assess(starving)["productivity"]
	assert_almost_eq(productivity, HouseholdWellbeing.MIN_PRODUCTIVITY, 0.001)
	assert_gt(productivity, 0.0, "a desperate household still works")


func test_hunger_drags_productivity_below_happiness():
	var hungry: Dictionary = _thriving()
	hungry["hunger"] = 0.5
	var out: Dictionary = HouseholdWellbeing.assess(hungry)
	assert_lt(float(out["productivity"]), float(out["happiness"]), "a hungry household works below its mood")


func test_productivity_rises_with_happiness_when_hunger_is_equal():
	var poor: Dictionary = _thriving()
	poor["ladder_share"] = 0.0
	poor["wallet_balance"] = 0
	assert_lt(
		float(HouseholdWellbeing.assess(poor)["productivity"]),
		float(HouseholdWellbeing.assess(_thriving())["productivity"])
	)


# -- the settlement's own mean, the number gathering is scaled by ----------

func test_the_mean_productivity_of_no_households_is_neutral_not_zero():
	assert_eq(HouseholdWellbeing.mean_productivity([]), 1.0, "an empty settlement must not be penalised")


func test_the_mean_productivity_is_the_real_average():
	var thriving: Dictionary = HouseholdWellbeing.assess(_thriving())
	var starving_state: Dictionary = _thriving()
	starving_state["hunger"] = 1.0
	var starving: Dictionary = HouseholdWellbeing.assess(starving_state)
	assert_almost_eq(
		HouseholdWellbeing.mean_productivity([thriving, starving]),
		(float(thriving["productivity"]) + float(starving["productivity"])) / 2.0, 0.001
	)


# -- work: the labour pyramid, felt from the household's side -------------

## docs/concept/village_estates.md mechanism 4 reaches wellbeing. The
## pyramid already said what share of a building's POSTS are filled; this
## is the other half of the same two numbers -- what share of the PEOPLE
## have one -- and it is the half a household actually feels.
func test_work_is_one_of_the_needs():
	assert_true(HouseholdWellbeing.NEED_IDS.has("work"))


func test_a_household_with_a_post_has_its_work_need_met():
	assert_almost_eq(float(HouseholdWellbeing.assess(_thriving())["needs"]["work"]), 1.0, 0.001)


func test_an_idle_household_has_no_work_at_all():
	var idle: Dictionary = _thriving()
	idle["employment"] = 0.0
	assert_almost_eq(float(HouseholdWellbeing.assess(idle)["needs"]["work"]), 0.0, 0.001)


func test_half_a_chance_of_a_post_is_half_the_need():
	var half: Dictionary = _thriving()
	half["employment"] = 0.5
	assert_almost_eq(float(HouseholdWellbeing.assess(half)["needs"]["work"]), 0.5, 0.001)


## Idleness really costs a village something: an idle household is
## unhappier, and therefore builds slower, than an employed one.
func test_an_idle_village_is_unhappier_and_builds_slower():
	var idle: Dictionary = _thriving()
	idle["employment"] = 0.0
	var employed: Dictionary = HouseholdWellbeing.assess(_thriving())
	var out: Dictionary = HouseholdWellbeing.assess(idle)
	assert_lt(float(out["happiness"]), float(employed["happiness"]))
	assert_lt(float(out["productivity"]), float(employed["productivity"]))


## **Not a destitute default, and deliberately so.** Every other need reads
## a missing input as its worst case, because a household nobody has
## established anything about really is badly off. Employment is different:
## it is read off the BUILDINGS a settlement has, and a caller that could
## not look at them has not discovered idleness, it has discovered nothing.
## A destitute default here would have every village in the world nobody is
## standing in read as wholly unemployed -- the same trap
## `house_capacity`'s own unloaded fallback already avoids.
func test_a_household_whose_employment_was_never_read_is_not_called_idle():
	var unread: Dictionary = _thriving()
	unread.erase("employment")
	assert_almost_eq(
		float(HouseholdWellbeing.assess(unread)["needs"]["work"]),
		1.0,
		0.001,
		"a household nobody asked about was reported out of work"
	)


## Nonsense is still clamped -- "not read" is a MISSING key, never a silly
## number.
func test_an_absurd_employment_reading_is_still_clamped():
	var absurd: Dictionary = _thriving()
	absurd["employment"] = 7.0
	assert_almost_eq(float(HouseholdWellbeing.assess(absurd)["needs"]["work"]), 1.0, 0.001)
	absurd["employment"] = -3.0
	assert_almost_eq(float(HouseholdWellbeing.assess(absurd)["needs"]["work"]), 0.0, 0.001)


# -- and where work sits among the rest ------------------------------------

## Pinned as an ordering, like every other weight here: losing your trade
## costs a household more than losing its savings, because the trade is
## what produced the savings; and it costs less than losing the roof.
func test_losing_work_costs_more_happiness_than_losing_income():
	var idle: Dictionary = _thriving()
	idle["employment"] = 0.0
	var broke: Dictionary = _thriving()
	broke["wallet_balance"] = 0
	assert_lt(
		float(HouseholdWellbeing.assess(idle)["happiness"]),
		float(HouseholdWellbeing.assess(broke)["happiness"])
	)


func test_losing_shelter_costs_more_happiness_than_losing_work():
	var homeless: Dictionary = _thriving()
	homeless["house_capacity"] = 0
	var idle: Dictionary = _thriving()
	idle["employment"] = 0.0
	assert_lt(
		float(HouseholdWellbeing.assess(homeless)["happiness"]),
		float(HouseholdWellbeing.assess(idle)["happiness"])
	)


## The whole weight order, in one place, so a re-weighting cannot silently
## reshuffle it: food, shelter, work, income, community.
func test_the_needs_are_weighted_in_their_own_listed_order():
	var previous := 1.1
	for need_id in HouseholdWellbeing.NEED_IDS:
		var weight: float = HouseholdWellbeing.NEED_WEIGHTS[need_id]
		assert_lt(weight, previous, "%s is weighted at or above the need before it" % need_id)
		previous = weight


# -- a full larder is the minimum stock, per household ---------------------
#
# docs/concept/village_economy_balance.md mechanism 4. The target was 4.0:
# one assessment's draw, from when the draw was 4. The draw is a measured
# 1.2 now and the target was never revisited, so "full larder" meant three
# and a third assessments of food for no reason anybody could state -- and
# a village the card said fed 25 of 10 read its households at 60%.

const SettlementSurplus = preload("res://src/emergence/settlement_surplus.gd")
const SettlementState = preload("res://src/emergence/settlement_state.gd")
const MerchantVisit = preload("res://src/emergence/merchant_visit.gd")


## A household reads its larder as full with a DAY's meals in store: the
## measured draw over the assessments in the day the village lives on --
## the same sixty seconds its schedule, its ecosystem step, its settlement
## step and its cart all run on. The card's own "feeds N of M" line reads
## the same draw, so a village that feeds all its households with a day in
## hand reads 100% here too.
##
## Deliberately NOT the cart's whole cover (the minimum stock, 2.5 days):
## measured with the target at that (tools/probe_village_economy.gd), a
## village holding a day or two of food read its households below the
## subsistence floor and lost four of ten to the estate ladder's exodus
## while every belly in it was full.
func test_a_full_larder_is_a_lived_day_of_the_measured_draw():
	assert_almost_eq(
		HouseholdWellbeing.FOOD_STOCK_PER_HOUSEHOLD_TARGET,
		SettlementState.FOOD_PER_HOUSEHOLD * MerchantVisit.SECONDS_PER_DAY / SettlementState.ASSESSMENT_SECONDS,
		0.0001
	)


## And a village that keeps its minimum stock reads full, with more than a
## day in hand -- the two horizons agree in the direction that matters.
func test_a_village_at_its_minimum_stock_reads_full():
	for households in [1, 4, 10, 37]:
		var per_household := float(SettlementSurplus.minimum_stock_for(households)) / float(households)
		assert_true(
			per_household >= HouseholdWellbeing.FOOD_STOCK_PER_HOUSEHOLD_TARGET,
			"%d households at their minimum stock read short" % households
		)


## And it is several meals, not one: a household with one meal in store is
## one bad day from hunger and must not read as fully fed.
func test_a_full_larder_is_several_meals():
	assert_gt(HouseholdWellbeing.FOOD_STOCK_PER_HOUSEHOLD_TARGET, VillageMarket.FOOD_UNITS_PER_MEAL * 2.0)
