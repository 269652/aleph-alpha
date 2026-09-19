extends RefCounted

## How many of a village's founders have to FEED it, and which trade the land
## feeds it with (see docs/concept/settlement_food_calibration.md).
##
## Deliberately NOT SettlementDemand, which is City Hall's own "compute
## demands" step over the recipe graph (npc_role_consensus.md) and has
## nothing to do with food. Two different questions; two different modules.
##
## Asked for directly: *"Make it driven by demand."* What that replaced was a
## hardcoded rule in SettlementGenerator -- "if nobody in this roster farms,
## make the LAST one a farmer" -- which gave every village exactly one food
## producer whatever its size and whatever it was standing on.
##
## It could only be written once both halves of the food model had been
## measured against each other, which is the whole of that concept doc:
## demand was overstated 3.33x against the villagers' own hunger clock, and
## the three trades' supply figures were four orders of magnitude apart
## because one invented rate was applied to a 0-1 density and to two
## headcounts alike. A roster rule built on those numbers would have staffed
## all-hunter villages inland and one-fisher villages beside water -- a
## plausible-looking rule whose behaviour came from an arithmetic error.
##
## Pure static module, no Node/store/scene dependency -- the same shape
## SettlementState, SettlementFood, SettlementGranary and VillageWages keep.

const SettlementState = preload("res://src/emergence/settlement_state.gd")
const SettlementGranary = preload("res://src/emergence/settlement_granary.gd")
const VillageFarm = preload("res://src/gameplay/village_farm.gd")
const NpcProduction = preload("res://src/world/npc_production.gd")

## The trades that really feed a village, and where each of them does it:
## a farmer and a herbalist work a field their own farmhouse owns
## (village_farms.md), a fisher works a pond they dug themselves
## (village_ponds.md).
##
## A HUNTER IS DELIBERATELY NOT ONE, and that is a measurement rather than a
## preference. Measured on real villages after this rule first landed
## (tools/probe_village_contents.gd): the village at (657,145) rolled a
## hunter and a fisher, was read as fed, and its farmhouse stood with nobody
## to work it. A hunter brings in about 0.02 food units an assessment
## against a draw of 6 -- a whole chunk supports roughly one deer, see the
## concept doc's own honest gap about HERBIVORES_PER_VEGETATION_UNIT.
## Counting one while sizing the roster against a FARMHOUSE's yield says a
## village is fed when it is not, and brings back the "No Farmhouses" report
## this whole line of work started from. Hunting stays a real occupation and
## a real way to eat; it is not what a village is founded on.
##
## An Array rather than a lookup because the ORDER is the tie-break in
## trade_for below: where two trades yield the same, the earlier one wins,
## and a village that farms is the one this game is about.
const FOOD_TRADES: Array[String] = ["farmer", "herbalist", "fisher"]

## The trade a village falls back on when its land says nothing -- barren
## ground, or no region to read at all. Farming, because a farmer can raise
## a farmhouse anywhere the village can build, while a fisher with no water
## and a hunter with no game have nothing to work.
const FALLBACK_TRADE := "farmer"


## What ONE food producer really brings a village, per settlement
## assessment.
##
## REAL WORK, not the ambient drip. Measured, the drip is about 0.22 food
## units per assessment on ordinary grassland against a draw of 6 for five
## households -- so no amount of foraging feeds a village, which is correct
## and is precisely why a village farms. A real worked field yields
## VillageFarm.FIELD_YIELD_PER_WORK_BLOCK over a work block, and that is the
## number a roster has to be sized against.
##
## The farmhouse stands for every food trade here. A fisher's pond and a
## hunter's range are real work too, and neither has a measured per-block
## yield of its own yet; using the one that HAS been measured, and saying so,
## beats inventing two more.
static func yield_per_producer_per_assessment() -> float:
	return (
		VillageFarm.FIELD_YIELD_PER_WORK_BLOCK / VillageFarm.WORK_BLOCK_SECONDS
		* SettlementState.ASSESSMENT_SECONDS
	)


## How many households one producer's real work feeds.
static func households_fed_per_producer() -> int:
	var per_household := SettlementState.FOOD_PER_HOUSEHOLD
	if per_household <= 0.0:
		return 0
	return int(floor(yield_per_producer_per_assessment() / per_household))


## How many food producers a village of `household_count` needs: its own
## subsistence draw over what one producer's real work brings in, rounded UP
## -- a village half a producer short is a village short.
##
## A village with nobody in it needs nobody to feed it, and a nonsensical
## census needs nobody either, the same clamp subsistence_draw already
## applies to one.
static func producers_needed(household_count: int) -> int:
	if household_count <= 0:
		return 0
	var per_producer := yield_per_producer_per_assessment()
	if per_producer <= 0.0:
		return 0
	return int(ceil(float(SettlementGranary.subsistence_draw(household_count)) / per_producer))


## Which food trade this land actually feeds a village with: whichever of
## FOOD_TRADES yields most here.
##
## Only meaningful because the three yields are finally the same kind of
## number (NpcProduction, and the concept doc's own measurement table). What
## it says on real chunks: land with real water is worked by a fisher, who
## digs and stocks a pond; ordinary grassland is farmed. A hunter never wins,
## and that is a measured finding rather than a rule written here -- a whole
## chunk supports about one deer, so hunting is a supplement and never a
## village's staple.
##
## `region` is anything exposing NpcProduction's three world accessors -- a
## SettlementGranary.SeededRegion, or the live world itself. Null, or land
## with nothing standing on it, falls back to farming rather than to a
## fisher with no water.
##
## KNOWN LIMIT, stated rather than implied: nothing about a village is
## persisted, so this is re-read on every load, and a region whose ecology
## has genuinely moved could hand a village a different trade than it was
## founded with. It keys on the yields rather than on terrain directly
## because those are what "feeds a village" means; in practice a fisher's
## own reading is driven by water area, which is terrain and does not move.
static func trade_for(region) -> String:
	if region == null:
		return FALLBACK_TRADE
	var production := NpcProduction.new()
	var best := ""
	var best_yield := 0.0
	for trade in FOOD_TRADES:
		var here := production.yield_per_second(trade, region, Vector2.ZERO)
		if here > best_yield:
			best_yield = here
			best = trade
	return best if best != "" else FALLBACK_TRADE
