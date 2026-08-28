extends RefCounted

## The emergence Market's missing SOURCE: what a settlement gathers, what it
## eats, and what is left over to store.
##
## -- the hole this fills --
##
## A writer audit of the persisted emergence Market finds exactly three
## writers, and READING them is enough to see the problem: Market.produce
## consumes a recipe's inputs from its own stock and adds that recipe's
## output back to the same stock, and the two halves of a regional trade
## debit the supplier and credit the receiver. Every one of them MOVES
## stock; not one CREATES any, so an empty market stays empty forever.
## MEASURED over 40 steps of a real eight-household settlement covering all
## eight occupations: stock {}, production_succeeded 0, production_failed 8,
## capacity 0.
##
## Everything built on that ledger was therefore dead, not merely quiet:
## SettlementState.carrying_capacity was permanently 0, so a settlement
## could never grow offscreen and -- because nothing could be eaten out of
## an empty granary either -- never decline offscreen; RegionalTrade.
## has_surplus could never be true anywhere, so no caravan could ever depart
## and no caravan could ever be raided; SettlementTier's specialization
## needs production SUCCESSES, which need inputs; and every household asked
## for its full recipe at maximum urgency forever, because Quest's need is
## `count - stock_of(item)` against a stock that was always zero.
##
## Villagers really do gather (NpcEconomy._gather credits a Wallet and adds
## to the LIVE VillageMarket). That production simply never reached the
## settlement-scale ledger the simulation reasons about. This module is the
## rule that connects them.
##
## -- the model, and what each half is anchored to --
##
## A settlement's assessment period (EarthChunkManager.step_settlements, one
## pass per SETTLEMENT_STEP_INTERVAL) gathers, eats, and banks the rest:
##
##     banked = gathered - eaten,   eaten = households x FOOD_PER_HOUSEHOLD
##
## Neither side is a new number.
##
## EATEN is SettlementState.FOOD_PER_HOUSEHOLD, whose own doc comment
## already calls it "how much food one household draws down per assessment"
## -- and a settlement step IS one assessment. Nothing in this codebase had
## ever actually drawn it down; the constant existed only as a divisor
## inside carrying_capacity. Applying it is what finally makes capacity mean
## what it says: `stock / FOOD_PER_HOUSEHOLD` is how many households the
## granary can carry through an assessment, and now the settlement really
## does spend that much each assessment. Note what that does and does not
## change about SettlementState.status_for: the classification is still a
## statement about a LEVEL (capacity against the census, inside its own
## STABLE_BAND), not about this assessment's flow -- a settlement with a
## deep granary draining slowly still reads GROWING for a long while. What
## changes is that the level is now the running total of past surplus
## instead of a constant zero, so it can rise and fall at all.
##
## GATHERED is NpcProduction.yield_per_second, integrated over the elapsed
## time (see gathered_over) -- literally the same call NpcEconomy._gather
## makes every frame for a loaded villager, against the same three real
## regional numbers (vegetation density, herbivore headcount, fish
## headcount). An offscreen villager therefore gathers at exactly the rate
## an onscreen one does, because it is one rule and not two.
##
## The UNIT is shared and pinned (see test_the_gathered_unit_the_market_unit
## _and_the_meal_are_the_same_unit): NpcProduction.FOOD_UNIT, VillageMarket.
## FOOD_UNITS_PER_MEAL and one whole integer unit of emergence Market stock
## are all the same thing, and SettlementFood already counts village stock
## in exactly those whole meals. Without that the arithmetic above would be
## adding three different currencies.
##
## CONSIDERED AND REJECTED as the split rate: VillageWages' own derived
## share. It is a real, derived rate, but it splits GOLD between a producing
## household and the village purse -- a redistribution among villagers, not
## a division between what is consumed and what is stored. Borrowing it here
## would give one number two unrelated meanings. FOOD_PER_HOUSEHOLD is the
## constant that is already about exactly this question.
##
## SAID PLAINLY: what is derived here is that consumption is FOOD_PER_
## HOUSEHOLD per household per assessment and production is NpcProduction's
## rate. That surplus is stored *in full* -- no spoilage, no fraction held
## back -- is a modelling decision, not a measurement. It is the simplest
## conserving rule (nothing is created or destroyed between the two sides),
## and a loss term would be a number with nothing behind it.
##
## Pure static module, no Node/store/scene dependency -- arguments in,
## values out, the granary itself owned by whoever persists the settlement.
## Same shape as SettlementState, SettlementFood and VillageWages.

const SettlementState = preload("res://src/emergence/settlement_state.gd")
const NpcProduction = preload("res://src/world/npc_production.gd")
const ItemCatalog = preload("res://src/gameplay/item_catalog.gd")

## The one real item category a settlement can eat -- ItemCatalog's own
## `kind`, the same category SettlementState.food_stock and SettlementFood
## already filter on, rather than a second hand-maintained list of food ids.
## A granary also holds what the settlement PRODUCED (Market.produce crafts
## its recipe output into this same stock), and nobody eats a pickaxe.
const FOOD_KIND := "food"


## A stand-in for the live world's three regional-resource accessors,
## holding one region's numbers as plain values.
##
## Exists so that an UNLOADED settlement's production can be computed
## through NpcProduction.yield_per_second itself rather than through a
## second copy of its rate and its occupation -> resource mapping. The
## caller fills it with whatever that region really holds; EarthChunkManager
## fills it with the equilibrium EcosystemSimulation.add_region would seed
## the region at the instant its chunk loads, which is that simulation's own
## definition of what an unvisited region contains ("the world is assumed to
## already contain a mature ecosystem").
##
## Position-independent on purpose: these are per-CHUNK aggregates in
## EcosystemSimulation, and one settlement sits in one chunk, so every
## pixel_position inside it reads the same three numbers anyway.
class SeededRegion:
	extends RefCounted

	var vegetation_density := 0.0
	var herbivore_population := 0.0
	var fish_population := 0.0

	func vegetation_density_near(_pixel_position: Vector2) -> float:
		return vegetation_density

	func herbivore_population_near(_pixel_position: Vector2) -> float:
		return herbivore_population

	func fish_population_near(_pixel_position: Vector2) -> float:
		return fish_population


## What a settlement of `household_count` households eats in one assessment
## -- SettlementState's own per-household draw, finally drawn. An empty or
## nonsensical census eats nothing rather than going negative, the same
## clamp VillageWages.deposit already applies to nonsense input.
static func subsistence_draw(household_count: int) -> int:
	return maxi(household_count, 0) * SettlementState.FOOD_PER_HOUSEHOLD


## Whether any of these households has an occupation that gathers food at
## all -- i.e. whether gathered_over could return anything for them, asked
## WITHOUT needing a region. The caller's region reading may itself be
## expensive to obtain (EarthChunkManager generates a chunk for it), and a
## settlement of eight blacksmiths never needs one.
static func has_producer(occupations: Array) -> bool:
	var production := NpcProduction.new()
	for occupation in occupations:
		if production.is_producer(str(occupation)):
			return true
	return false


## item_id -> float food gathered by these households over `seconds`, one
## entry per real producer item.
##
## `occupations` is one entry per household (the founder's occupation, ""
## and non-producers included and skipped), and `region` is anything
## exposing the three world accessors NpcProduction reads -- a SeededRegion,
## or the live EarthChunkManager itself. The rate and the occupation ->
## item/resource mapping both come from NpcProduction, so this function owns
## no economics of its own: it is that module's per-second yield times
## elapsed time, summed over the households that have one.
static func gathered_over(occupations: Array, region, seconds: float) -> Dictionary:
	var production := NpcProduction.new()
	var elapsed := maxf(seconds, 0.0)
	var gathered: Dictionary = {}
	for occupation in occupations:
		var item_id := production.item_id_for(str(occupation))
		if item_id == "":
			continue
		var amount := production.yield_per_second(str(occupation), region, Vector2.ZERO) * elapsed
		if amount <= 0.0:
			continue
		gathered[item_id] = float(gathered.get(item_id, 0.0)) + amount
	return gathered


## One assessment of the granary: bank what was gathered, eat what the
## households need, and report the net change to the settlement's stock.
##
## Returns {"stock_delta": item_id -> int change to apply to the emergence
## Market, "carry": item_id -> float sub-unit remainder to pass back in next
## time}. Only non-zero deltas appear, so a settlement with nothing to say
## returns an empty delta and its ledger is left untouched -- which is what
## lets EarthChunkManager's change-guards stay quiet for a settlement
## nothing is happening to.
##
## `gathered` is this assessment's catch (see gathered_over), `carry` the
## previous call's returned remainder, `granary_stock` the settlement's
## current emergence Market stock, `household_count` its census.
##
## Gathering and eating resolve against ONE pool: this assessment's catch is
## available to eat this assessment, so a village that gathers exactly what
## it needs never has to have banked it first. And the drawdown is floored
## at empty -- a settlement can eat its granary bare, but a hungrier
## settlement than that goes hungry rather than driving the ledger negative.
## How much hungrier is genuinely not recorded anywhere: a village 1 short
## and a village 100 short both end the assessment at zero, and this module
## keeps no debt. What survives is the level, not the depth of the
## shortfall, which is all SettlementState.carrying_capacity reads anyway.
static func catchup(
	gathered: Dictionary, carry: Dictionary, granary_stock: Dictionary,
	household_count: int, catalog = null
) -> Dictionary:
	var item_catalog = catalog if catalog != null else ItemCatalog.new()

	# Whole units bank; the sub-unit remainder is carried rather than
	# truncated away (a slow trickle must not round to nothing forever) --
	# the same carry-until-it-crosses-a-whole-unit idiom NpcEconomy.
	# _accumulated_yield and VillageWages' fractional purse already run on.
	var next_carry: Dictionary = {}
	var banked: Dictionary = {}
	for item_id in carry:
		next_carry[str(item_id)] = float(carry[item_id])
	for item_id in gathered:
		next_carry[str(item_id)] = float(next_carry.get(item_id, 0.0)) + float(gathered[item_id])
	for item_id in next_carry:
		var whole := floori(float(next_carry[item_id]))
		if whole <= 0:
			continue
		banked[item_id] = whole
		next_carry[item_id] = float(next_carry[item_id]) - float(whole)

	# Sorted rather than iteration order: this drives a PERSISTED ledger, and
	# a Dictionary restored from disk need not iterate the way the one that
	# wrote it did.
	var food_ids: Array = []
	for item_id in granary_stock:
		if item_catalog.kind_of(str(item_id)) == FOOD_KIND:
			food_ids.append(str(item_id))
	for item_id in banked:
		if not food_ids.has(item_id) and item_catalog.kind_of(item_id) == FOOD_KIND:
			food_ids.append(item_id)
	food_ids.sort()

	var remaining := subsistence_draw(household_count)
	var stock_delta: Dictionary = {}
	for item_id in banked:
		stock_delta[item_id] = int(banked[item_id])
	for item_id in food_ids:
		if remaining <= 0:
			break
		var available := int(granary_stock.get(item_id, 0)) + int(banked.get(item_id, 0))
		if available <= 0:
			continue
		var eaten := mini(available, remaining)
		remaining -= eaten
		stock_delta[item_id] = int(stock_delta.get(item_id, 0)) - eaten

	for item_id in stock_delta.keys():
		if int(stock_delta[item_id]) == 0:
			stock_delta.erase(item_id)

	return {"stock_delta": stock_delta, "carry": next_carry}
