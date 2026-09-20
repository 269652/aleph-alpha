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
const NpcProduction = preload("res://src/world/npc_production.gd")
const VillageFarm = preload("res://src/gameplay/village_farm.gd")
const SettlementGathering = preload("res://src/emergence/settlement_gathering.gd")
const HuntableQuarry = preload("res://src/gameplay/huntable_quarry.gd")

## The raw timber a woodcutter fells. Not in any producer map -- it comes
## off a tree (ChoppableTree) -- and it is what the sawmill's whole chain
## is priced from (CraftingRecipeBook's log_to_balken/log_to_planke).
const RAW_TIMBER := "log"

## The base unit every other price is derived from: one raw log at the farm
## gate, the cheapest thing a village can sell.
const LOG_PRICE := 1

## What a merchant pays for goods that have had WORK put into them or that
## KEEP and travel -- the doc's own grounding, *"Hide, salted meat, dried
## fish and sawn timber keep and are worth carrying"*.
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
## - `hide` is a by-product that keeps and travels, so it is worth more
##   than food that spoils and less than worked timber.
##
## Everything NOT here is raw produce and prices at LOG_PRICE, which is the
## rule the old hand-written table already followed without saying so --
## wood, fish, meat and fruit were every one of them LOG_PRICE. Stating it
## means a new crop needs no new number, and raw food still sits UNDER
## VillageMarket.VILLAGE_LOCAL_FOOD_PRICE (what a villager pays for a meal
## of it) and under Shop.CATALOG's prepared cooked_meat: preparing food is
## what adds the value, and the merchant's margin is his reason to walk the
## circuit at all.
const KEEPING_GOOD_PRICES := {
	"beam": LOG_PRICE * 2 * int(SagewerkProduction.LOG_COST_PER_BEAM / SagewerkProduction.LOG_COST_PER_PLANK),
	"plank": LOG_PRICE * 2,
	HuntableQuarry.HIDE_ITEM_ID: LOG_PRICE * 2,
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


## Everything a village's own producers really put into its stock, read off
## the producers' OWN maps rather than named again here.
##
## This is the whole fix. The buy list used to be a hand-written const, and
## a village kept growing past it: a herbalist's crop, a farmer's wheat,
## gathered stone and plant fibre all arrived after it was written and none
## was ever added to it. Measured (tools/probe_village_purse.gd) on a real
## village after 1200 simulated seconds, ONE of the nine ids it was holding
## was sellable and all ten of those units were reserved for its own next
## house -- so both purses read 0.0 gold and 8 of 8 villagers were broke. A
## merchant is the ONLY faucet gold has (see the doc's "the merchant is the
## ONLY faucet"), so a village that makes nothing he buys has no income at
## all, ever.
##
## A second list of the same facts can only ever drift from the first. This
## one cannot: add an occupation, a crop or a gathered material and it is
## sellable the same day it exists.
static func village_produce() -> Array[String]:
	var ids: Array[String] = Array([], TYPE_STRING, "", null)
	for occupation in NpcProduction.PRODUCER_ITEM_BY_OCCUPATION:
		var item_id := String(NpcProduction.PRODUCER_ITEM_BY_OCCUPATION[occupation])
		if item_id != "" and not ids.has(item_id):
			ids.append(item_id)
	for occupation in VillageFarm.CROP_BY_OCCUPATION:
		var crop_id := String(VillageFarm.CROP_BY_OCCUPATION[occupation])
		if crop_id != "" and not ids.has(crop_id):
			ids.append(crop_id)
	for gathered_id in SettlementGathering.gathered_item_ids():
		if not ids.has(gathered_id):
			ids.append(gathered_id)
	return ids


## Computed once: the walk above touches four maps, and this is read inside
## every price lookup.
static var _buy_list_cache: Array[String] = Array([], TYPE_STRING, "", null)


## What a village makes and a merchant can carry away: everything its
## producers make, the raw timber it fells, and the worked goods and
## by-products it makes from those.
##
## Sorted so the order is deterministic rather than dependent on Dictionary
## iteration -- `purchase` below fills the cart by price and then by id.
static func buy_list() -> Array[String]:
	if not _buy_list_cache.is_empty():
		return _buy_list_cache
	var ids := village_produce()
	if not ids.has(RAW_TIMBER):
		ids.append(RAW_TIMBER)
	for item_id in KEEPING_GOOD_PRICES:
		var worked_id := String(item_id)
		if not ids.has(worked_id):
			ids.append(worked_id)
	ids.sort()
	_buy_list_cache = ids
	return _buy_list_cache


## What `item_id` fetches at the farm gate; 0 for anything he does not deal
## in, which is a real answer rather than a stub. Goods that keep have their
## own derived price; everything else a village makes is raw produce at the
## base unit (see KEEPING_GOOD_PRICES).
static func price_of(item_id: String) -> int:
	if KEEPING_GOOD_PRICES.has(item_id):
		return int(KEEPING_GOOD_PRICES[item_id])
	if buy_list().has(item_id):
		return LOG_PRICE
	return 0


## How many whole units of sellable goods a settlement is holding -- what
## decides both whether a merchant comes at all and how soon.
static func sellable_units(stock: Dictionary, reserved: Dictionary = {}) -> int:
	var total := 0
	for item_id in buy_list():
		total += _surplus_of(stock, reserved, item_id)
	return total


## What is really for sale of `item_id`: whole units held, less whatever the
## village is saving for. Never negative -- a village short of what it needs
## has no surplus, it does not owe the merchant units.
static func _surplus_of(stock: Dictionary, reserved: Dictionary, item_id: String) -> int:
	var held := int(floor(float(stock.get(item_id, 0.0))))
	return maxi(held - int(reserved.get(item_id, 0)), 0)


## `{"arrived": bool, "carry": the fraction of a visit still owed}`.
##
## Gated on there being something to buy: no sellable stock means no visit,
## and the carry is kept rather than lost, so a village that finally lands
## a catch is not also made to wait out a fresh clock.
## `reserved` is what the village is SAVING FOR -- item_id -> whole units
## its own next building really needs (see this doc's "Mercantile
## surplus, not stock"). Stock up to the reserve is not surplus and is
## neither sold nor counted toward a visit being worth the walk.
static func arrivals(
	seconds: float, stock: Dictionary, carry: float, reserved: Dictionary = {}
) -> Dictionary:
	if seconds <= 0.0 or sellable_units(stock, reserved) <= 0:
		return {"arrived": false, "carry": carry}

	var surplus := clampf(float(sellable_units(stock, reserved)) / SURPLUS_FOR_FULL_DRAW, 0.0, 1.0)
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
## `reserved` holds back what the village's own next building needs, item_id
## -> whole units. A merchant buys a village's SURPLUS; he does not buy the
## timber it cut for its own next house. Measured before this rule
## (tools/probe_village_growth.gd): a real village's stone climbed steadily
## to 37 while its wood never once got past 2, because SettlementGathering
## is the only thing that puts wood into a settlement's market and `wood` is
## on the buy list -- so a village that grew from 10 households to 31 built
## not one house for any of them.
static func purchase(stock: Dictionary, reserved: Dictionary = {}) -> Dictionary:
	var order: Array = []
	for item_id in buy_list():
		var available := _surplus_of(stock, reserved, item_id)
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
