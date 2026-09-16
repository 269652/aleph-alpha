extends RefCounted

## docs/concept/traveling_merchants.md: the outside world arriving on foot.
##
## A village's gold used to come from nowhere -- NpcProduction.YIELD_TO_
## GOLD_RATE conjures a coin per food unit gathered, whether or not anyone
## ever buys it, which is why a village's wealth never meant anything. A
## traveling merchant is the faucet that replaces it: he arrives, buys
## goods that genuinely exist in the settlement's own market, removes them
## from it, and pays real gold into the settlement purse.
##
## Pure and static, the same shape VillageImmigration/SettlementGathering
## already use: numbers in, numbers out, no world and no state. The caller
## moves the goods and the gold (see EarthChunkManager).

const SagewerkProduction = preload("res://src/world/sagewerk_production.gd")
const ConstructionCatchup = preload("res://src/world/construction_catchup.gd")

## What a village makes and a merchant can carry away. Everything here is a
## real output of a producer occupation (NpcProduction), of butchering, or
## of the sawmill's own chain -- nothing the village cannot make, and
## nothing it makes that he refuses.
const BUY_LIST: Array[String] = ["beam", "plank", "hide", "wood", "fish", "meat", "fruit"]

## The base timber unit every sawn price is derived from, and the cheapest
## thing on the list.
const LOG_PRICE := 1

## Farm-gate prices, in whole gold per unit.
##
## This project refuses to invent item values -- Shop's own comment says
## "CATALOG is the only place in the game an item has a price at all, and
## paying for anything else would mean inventing a number with nothing
## behind it". So none of these are invented; each is derived from a real
## relationship the game already models, and each is pinned by a test
## against that relationship rather than asserted as a magic number:
##
## - `plank` is a log, sawn: worth more than the raw timber it came from.
## - `beam` is LOG_COST_PER_BEAM / LOG_COST_PER_PLANK times a plank --
##   the sawmill's OWN conversion rate (3 logs to a Balken, 1 to a Planke),
##   so sawn timber is worth exactly what its logs were worth.
## - raw food sits UNDER VillageMarket.VILLAGE_LOCAL_FOOD_PRICE (what a
##   villager pays for a meal of it) and under Shop.CATALOG's prepared
##   cooked_meat: preparing food is what adds the value, and the merchant's
##   margin is his reason to walk the circuit at all.
## - `hide` is a by-product that keeps and travels, so it is worth more
##   than food that spoils and less than worked timber.
const FARM_GATE_PRICES := {
	"beam": LOG_PRICE * 2 * int(SagewerkProduction.LOG_COST_PER_BEAM / SagewerkProduction.LOG_COST_PER_PLANK),
	"plank": LOG_PRICE * 2,
	"hide": LOG_PRICE * 2,
	"wood": LOG_PRICE,
	"fish": LOG_PRICE,
	"meat": LOG_PRICE,
	"fruit": LOG_PRICE,
}

## How much a merchant can carry away in one visit, in whole units. Finite
## on purpose: it is what stops a village that hoarded for a season from
## turning it into one enormous windfall, and what makes a second visit
## worth waiting for.
const CART_CAPACITY := 20

## Visits per day to a village with something, anything, worth buying.
const VISITS_PER_DAY := 0.4
## How much a full surplus adds to that draw, as a multiple.
const SURPLUS_DRAW := 1.5
## How many sellable units count as a full surplus -- more than one cart,
## so a village has to be genuinely piling goods up to pull him early.
const SURPLUS_FOR_FULL_DRAW := float(CART_CAPACITY) * 2.0


## What `item_id` fetches at the farm gate; 0 for anything he does not deal
## in, which is a real answer rather than a stub (see FARM_GATE_PRICES).
static func price_of(item_id: String) -> int:
	return int(FARM_GATE_PRICES.get(item_id, 0))


## How many whole units of sellable goods a settlement is holding -- what
## decides both whether a merchant comes at all and how soon.
static func sellable_units(stock: Dictionary) -> int:
	var total := 0
	for item_id in BUY_LIST:
		total += int(floor(float(stock.get(item_id, 0.0))))
	return total


## `{"arrived": bool, "carry": the fraction of a visit still owed}`.
##
## Gated on there being something to buy: no sellable stock means no visit,
## and the carry is kept rather than lost, so a village that finally lands
## a catch is not also made to wait out a fresh clock.
static func arrivals(seconds: float, stock: Dictionary, carry: float) -> Dictionary:
	if seconds <= 0.0 or sellable_units(stock) <= 0:
		return {"arrived": false, "carry": carry}

	var surplus := clampf(float(sellable_units(stock)) / SURPLUS_FOR_FULL_DRAW, 0.0, 1.0)
	var draw := VISITS_PER_DAY * (1.0 + SURPLUS_DRAW * surplus)
	var accrued := carry + draw * (seconds / ConstructionCatchup.SECONDS_PER_DAY)
	if accrued < 1.0:
		return {"arrived": false, "carry": accrued}
	# One visit at a time, whatever has accrued: a merchant who is overdue
	# turns up once, he does not arrive three times in one afternoon.
	return {"arrived": true, "carry": accrued - floor(accrued)}


## What this merchant takes and what he pays for it:
## `{"bought": {item_id -> whole units}, "paid": gold}`. Never mutates the
## stock it is shown -- the caller moves the goods and the gold, so a sale
## that cannot be completed for any reason has changed nothing.
##
## The cart fills with the DEAREST goods first (price, then item id, so the
## outcome is deterministic rather than dependent on Dictionary order): a
## merchant with room for twenty units takes the beams over the fish.
static func purchase(stock: Dictionary) -> Dictionary:
	var order: Array = []
	for item_id in BUY_LIST:
		var available := int(floor(float(stock.get(item_id, 0.0))))
		if available > 0:
			order.append([-price_of(item_id), item_id, available])
	order.sort()

	var bought := {}
	var paid := 0
	var room := CART_CAPACITY
	for entry in order:
		if room <= 0:
			break
		var item_id: String = entry[1]
		var units: int = mini(int(entry[2]), room)
		bought[item_id] = units
		paid += units * price_of(item_id)
		room -= units
	return {"bought": bought, "paid": paid}
