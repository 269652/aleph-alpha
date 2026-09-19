extends RefCounted

## docs/concept/village_growth.md mechanism 4: a household's five needs, its
## happiness and its productivity.
##
## **Derived, never stored** (that doc's pillar 5). Every input below is a
## number the simulation already keeps for its own reasons -- the
## resident's hunger from NpcNeeds, the settlement's food stock from
## VillageMarket/SettlementFood, the purse from the household's own Wallet,
## the roof from BuildingCatalog.capacity_of, the civic amenity from
## VillageGrowth.ladder_share over what actually stands. Nothing here is
## persisted and nothing here is a second copy of state, so the readout can
## never drift from the simulation: it IS the simulation, read.
##
## Pure and static, the same shape SettlementSpareCapacity/SettlementTier
## already use. Every `state` key is optional and every missing one reads as
## its destitute default -- a caller holding partial information gets an
## honest bad score rather than a crash, which is the right answer for a
## household nobody has established anything about yet.
##
## `state` keys:
##   hunger               [0,1], the resident's own NpcNeeds.hunger (0 fed)
##   food_per_household   the settlement's food stock divided by households
##   house_capacity       BuildingCatalog.capacity_of their house; 0 homeless
##   household_size       how many people the household actually holds
##   wallet_balance       real gold in the household's own Wallet
##   meal_price           VillageMarket.VILLAGE_LOCAL_FOOD_PRICE
##   ladder_share         VillageGrowth.ladder_share of what stands here
##   employment           [0,1], VillageLabor.employment_for_estate for this
##                        household's own estate -- OMIT it rather than
##                        guessing when the settlement's buildings could not
##                        be read (see WORK_UNREAD_DEFAULT)
##
## Every tuned value below is pinned by test_household_wellbeing.gd against
## the ORDERING it produces (going hungry costs more happiness than lacking
## a brewery; a hungry household works below its own mood), never asserted
## as a magic number, per this project's no-manual-tuning rule.

## The five needs, in the order a readout should show them -- most
## fundamental first, which is also weight order (see NEED_WEIGHTS).
const NEED_IDS: Array[String] = ["food", "shelter", "work", "income", "community"]

## How much settlement food stock PER HOUSEHOLD reads as a full larder.
## Deliberately several meals' worth rather than one: a village with
## exactly one meal per household in store is one bad day from hunger, and
## should not read as "food need fully met".
const FOOD_STOCK_PER_HOUSEHOLD_TARGET := 4.0
## How the food need splits between the resident's own belly right now and
## the village's larder behind it. A full belly today with nothing in store
## is genuinely not the same as a full belly with a winter's food behind
## it, so neither half alone can satisfy the need.
const FOOD_BELLY_SHARE := 0.5

## How much of shelter is simply HAVING a roof that fits. A roof is most of
## it; elbow room is the rest.
const SHELTER_ROOF_SHARE := 0.7
## How much spare capacity beyond the household's own size reads as full
## elbow room -- a large house (3) holding a single villager clears it.
const SHELTER_SPARE_CAPACITY_FOR_FULL := 2.0

## How many meals' worth of gold in hand reads as a comfortable purse.
const INCOME_MEALS_FOR_FULL := 10

## What a household whose employment NOBODY READ counts as.
##
## Deliberately the opposite of every other need's destitute default, and
## the exception is the point. The other inputs describe the household
## itself, so a missing one really is bad news. Employment is read off the
## BUILDINGS its settlement has, and a caller that could not look at them
## has not discovered idleness -- it has discovered nothing. A destitute
## default here would have every village in the world nobody is standing in
## read as wholly out of work, which is the same trap the unloaded
## `house_capacity` fallback already avoids (see EarthChunkManager.
## _household_wellbeing_for_settlement's own note).
##
## "Not read" is a MISSING key. A reading that is present is taken at face
## value and clamped, however silly.
const WORK_UNREAD_DEFAULT := 1.0

## Weights over NEED_IDS, summing to 1, strictly descending in that array's
## own order -- pinned by the ordering it produces, not by these numbers.
##
## `work` sits between shelter and income because that is where the
## ORDERING puts it: losing your trade costs more than losing your savings,
## since the trade is what produced the savings, and less than losing the
## roof over your head.
const NEED_WEIGHTS := {
	"food": 0.35, "shelter": 0.25, "work": 0.18, "income": 0.12, "community": 0.10,
}

## What a wholly desperate household still manages. Never zero: a starving
## household still works, just badly, and a zero here would silently stall
## every settlement mechanism productivity scales.
const MIN_PRODUCTIVITY := 0.25


## `{"needs": {need_id -> [0,1]}, "happiness": [0,1], "productivity": [0,1]}`.
static func assess(state: Dictionary) -> Dictionary:
	var needs := {
		"food": _food_need(state),
		"shelter": _shelter_need(state),
		"work": _work_need(state),
		"income": _income_need(state),
		"community": clampf(float(state.get("ladder_share", 0.0)), 0.0, 1.0),
	}

	var happiness := 0.0
	for need_id in NEED_IDS:
		happiness += float(needs[need_id]) * float(NEED_WEIGHTS[need_id])
	happiness = clampf(happiness, 0.0, 1.0)

	# Hunger drags productivity below mood outright: a household with a
	# beautiful town and an empty stomach does not work well, and no amount
	# of civic amenity compensates for it.
	var hunger := clampf(float(state.get("hunger", 1.0)), 0.0, 1.0)
	var productivity := MIN_PRODUCTIVITY + (1.0 - MIN_PRODUCTIVITY) * happiness * (1.0 - hunger)

	return {"needs": needs, "happiness": happiness, "productivity": clampf(productivity, 0.0, 1.0)}


## Half the resident's own fullness, half the village's larder (see
## FOOD_BELLY_SHARE). A missing hunger reads as desperate and a missing
## stock reads as empty -- the destitute default.
static func _food_need(state: Dictionary) -> float:
	var belly := 1.0 - clampf(float(state.get("hunger", 1.0)), 0.0, 1.0)
	var larder := clampf(
		float(state.get("food_per_household", 0.0)) / FOOD_STOCK_PER_HOUSEHOLD_TARGET, 0.0, 1.0
	)
	return clampf(belly * FOOD_BELLY_SHARE + larder * (1.0 - FOOD_BELLY_SHARE), 0.0, 1.0)


## 0 for a homeless household. An OVERCROWDED one gets a fraction of the
## roof share (a bed in a house too small is better than no house, and
## worse than a house that fits); an adequate one gets the whole roof share
## plus whatever spare capacity it has room to enjoy.
static func _shelter_need(state: Dictionary) -> float:
	var capacity := maxi(int(state.get("house_capacity", 0)), 0)
	if capacity <= 0:
		return 0.0
	var size := maxi(int(state.get("household_size", 1)), 1)
	if capacity < size:
		return clampf(SHELTER_ROOF_SHARE * float(capacity) / float(size), 0.0, 1.0)
	var spare := float(capacity - size) / SHELTER_SPARE_CAPACITY_FOR_FULL
	return clampf(SHELTER_ROOF_SHARE + (1.0 - SHELTER_ROOF_SHARE) * clampf(spare, 0.0, 1.0), 0.0, 1.0)


## docs/concept/village_estates.md mechanism 4, felt from the household's
## side. `VillageLabor.employment_for` already says what share of the
## PEOPLE of a labour class have a post -- the dual of the fulfilment a
## building reads -- and this is the household's own class's share of it.
##
## A village with no works has idle cottagers and knows it; one that
## promoted every cottager into a husbandman has idle husbandmen and a
## saw pit nobody can run. Either way the idleness now costs real
## happiness, and through it real productivity, which is what makes the
## pyramid something a village feels rather than a number it carries.
static func _work_need(state: Dictionary) -> float:
	if not state.has("employment"):
		return WORK_UNREAD_DEFAULT
	return clampf(float(state["employment"]), 0.0, 1.0)


## The purse measured in meals it could actually buy. A meal price of zero
## or less (an unpriced market) reads as "money buys nothing here", so a
## purse cannot rescue a household in a village with nothing to sell.
static func _income_need(state: Dictionary) -> float:
	var meal_price := float(state.get("meal_price", 0))
	if meal_price <= 0.0:
		return 0.0
	var meals := float(state.get("wallet_balance", 0)) / meal_price
	return clampf(meals / float(INCOME_MEALS_FOR_FULL), 0.0, 1.0)


## The mean productivity of a settlement's own assessed households -- the
## number SettlementGathering's rate is scaled by, closing docs/concept/
## village_growth.md's loop (buildings raise happiness, happiness raises
## productivity, productivity raises the material that raises buildings).
##
## An EMPTY list is 1.0, deliberately neutral rather than 0.0: "nobody
## lives here to be unhappy" must never read as "everyone here is
## miserable", which would have every unpopulated caller silently
## multiplying its own rate to the floor.
static func mean_productivity(assessments: Array) -> float:
	if assessments.is_empty():
		return 1.0
	var total := 0.0
	for assessment in assessments:
		total += float(assessment.get("productivity", MIN_PRODUCTIVITY))
	return total / float(assessments.size())
