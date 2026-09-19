extends RefCounted

## docs/concept/village_estates.md mechanism 1: the four ESTATES a
## village's households hold, and what each one costs to keep.
##
## This is the table the whole overhaul hangs off. docs/concept/
## village_growth.md built a village whose households are all the same kind
## of household, whose needs are a SCORE nobody ever pays for, and whose
## population only ever goes up. An estate is the thing that makes a
## village stratified: a household at one holds a different standing, lives
## in a different house, supplies a different class of labour, and consumes
## a visibly different basket of real goods -- which is what lets the
## population rise, fall, and cost something to promote.
##
## Pure static table, no state of its own, the same shape
## OccupationProduction/SettlementTier/VillageWages already use.
##
## -- Why THESE four --
##
## They are the estates (Stände) a Central European village of this period
## actually had, not Anno's tier names transplanted. A Kossät held a
## cottage, a garden and no plough-land, and sold labour by the day. A
## Bauer held a hide of land, a plough and draught animals. A Handwerker
## held a trade, a workshop and a guild membership. A Bürger held civic
## rights, capital and a seat in the assembly. Each was a different legal
## standing doing a different kind of work -- which is exactly the three
## things this table encodes (house, labour class, basket) and the reason
## it needs no invented fifth rung to be interesting.
##
## -- Why two estates share a house tier --
##
## There are exactly three real house sheets (BuildingCatalog.BUILDING_IDS)
## and inventing a fourth would be art that does not exist, which this
## project does not do. It is also simply true: a craftsman's house WAS a
## husbandman's house with the workshop in the front room. What visibly
## changes at that rung is not the roof; it is that the village's sawmill
## finally has a sawyer (see VillageLabor).
##
## Every tuned value below is pinned by test_village_estates.gd against the
## ORDERING or the INVARIANT it produces -- a higher estate demands
## strictly more, every basket good is a good the world really produces --
## never by asserting a number somebody liked, per this project's
## no-manual-tuning rule.

const SeasonCycle = preload("res://src/world/season_cycle.gd")

## The ladder, bottom rung first. Index IS rank (see rank_of), so this one
## array is the only statement of the order anywhere.
const ESTATE_IDS: Array[String] = ["kossaet", "bauer", "handwerker", "buerger"]

## What a household holds when it is founded or arrives. A village's
## newcomers are cottagers; everything above that is earned through
## EstateAscension's charter gate, never granted at founding.
const STARTING_ESTATE := "kossaet"

## The one good in a basket that is a CATEGORY rather than an item id: any
## stocked item of ItemCatalog kind "food", which is the same filter
## VillageMarket/SettlementFood already apply before a settlement counts as
## fed. A village eats what it has -- venison, fish, apples, bread.
##
## Spelled with a colon on purpose: `kind:` cannot occur in an item id, so
## the token can never collide with one however the catalog grows
## (test-pinned).
const FOOD_KIND_TOKEN := "kind:food"

## The fuel every hearth burns. Real `wood`, the same id SettlementGathering
## already gathers and every building is already priced in -- so a village
## short of firewood is short of exactly the thing it also builds with,
## which is a real competition for one resource rather than two parallel
## economies.
const FUEL_ITEM_ID := "wood"

## Which BuildingCatalog house an estate lives in.
const _HOUSE_BY_ESTATE := {
	"kossaet": "house_small",
	"bauer": "house_medium",
	"handwerker": "house_medium",
	"buerger": "house_large",
}

## The one class of labour each estate supplies (pillar 4). DISTINCT per
## estate -- that is what makes promotion cost the rung below rather than
## merely relabel it: raising a cottager to a husbandman removes a pair of
## `hand`s and creates a `field`.
const _LABOUR_CLASS_BY_ESTATE := {
	"kossaet": "hand",  # day labour: felling, hauling, digging, building
	"bauer": "field",  # tenured farming, the farmhouse's real output
	"handwerker": "craft",  # the sawyer, the smith, the brewer
	"buerger": "civic",  # the clerk, the factor, the assembly
}

## Every labour class there is, in ladder order -- derived from the table
## above rather than restated, so a new estate cannot strand a stale list.
const LABOUR_CLASSES: Array[String] = ["hand", "field", "craft", "civic"]

## What a household of each estate consumes per household per DAY.
##
## `subsistence` -- short for a sustained run and the household descends,
## then leaves. What you must have.
## `station` -- short and the household simply does not RISE. What you must
## have to be the thing you are claiming to be.
##
## Pillar 5: every good named here is a real ItemCatalog id some real
## mechanism already puts into the world. `kind:food` comes from foraging,
## hunting, fishing and farming; `wood` from the forest; `herb` from a
## village herbalist's own field (docs/concept/village_farms.md); `bread`
## from the real grow_wheat -> mill_flour -> bake_bread chain
## (docs/concept/milling_and_baking.md); `candle` from the furniture set;
## `hide` from real butchery; `honey` from real bee colonies
## (docs/concept/bees.md); `beer` from the brewery this ladder's top rung
## already raises. A basket that named a good nothing produces would be a
## need no village could ever meet.
const _BASKETS := {
	"kossaet": {
		"subsistence": {FOOD_KIND_TOKEN: 1.0, FUEL_ITEM_ID: 0.5},
		"station": {"herb": 0.10},
	},
	"bauer": {
		"subsistence": {FOOD_KIND_TOKEN: 1.2, FUEL_ITEM_ID: 0.6},
		"station": {"bread": 0.40, "candle": 0.05},
	},
	"handwerker": {
		"subsistence": {FOOD_KIND_TOKEN: 1.2, FUEL_ITEM_ID: 0.8},
		"station": {"bread": 0.50, "candle": 0.10, "hide": 0.05},
	},
	"buerger": {
		"subsistence": {FOOD_KIND_TOKEN: 1.2, FUEL_ITEM_ID: 1.0},
		"station": {"bread": 0.60, "candle": 0.15, "beer": 0.30, "honey": 0.05},
	},
}

## The seasonal term (pillar 6), and the one line in this whole design Anno
## cannot have: this world runs a real SeasonCycle, so firewood is not a
## constant on a basket -- it is what a village must have banked by autumn.
## Spring and autumn are the plain baseline; only fuel moves at all.
const WINTER_FUEL_MULTIPLIER := 2.0
const SUMMER_FUEL_MULTIPLIER := 0.5

const _FUEL_MULTIPLIER_BY_SEASON := {
	"winter": WINTER_FUEL_MULTIPLIER,
	"summer": SUMMER_FUEL_MULTIPLIER,
}

## Mechanism 6: what a FULLY provided household of each estate pays the
## village per day. Rises up the ladder because a higher standing has more
## surplus to tax, which is both Anno's own shape and the real one.
const BASE_TAX_PER_DAY := {
	"kossaet": 0.25,
	"bauer": 0.60,
	"handwerker": 1.00,
	"buerger": 1.75,
}


## What a player is shown an estate as. The German names are the historical
## ones and are what this table is grounded in (see the file header); the
## readout uses their nearest real English equivalents, because a panel is
## not a glossary.
##
## "" for an unknown estate rather than a made-up name: a readout that
## invents a title for standing nobody holds is worse than one that says
## nothing.
const _DISPLAY_NAMES := {
	"kossaet": "Cottager",
	"bauer": "Husbandman",
	"handwerker": "Craftsman",
	"buerger": "Burgher",
}


static func display_name_of(estate: String) -> String:
	return _DISPLAY_NAMES.get(estate, "")


## The estate's position on the ladder; -1 for anything that is not one.
static func rank_of(estate: String) -> int:
	return ESTATE_IDS.find(estate)


## The rung above, or "" at the top (and for an unknown estate).
static func next_estate(estate: String) -> String:
	var rank := rank_of(estate)
	if rank < 0 or rank + 1 >= ESTATE_IDS.size():
		return ""
	return ESTATE_IDS[rank + 1]


## The rung below, or "" at the bottom (and for an unknown estate). A
## household at the bottom with nowhere to descend to LEAVES instead -- see
## EstateAscension.is_exodus.
static func previous_estate(estate: String) -> String:
	var rank := rank_of(estate)
	if rank <= 0:
		return ""
	return ESTATE_IDS[rank - 1]


## The BuildingCatalog house id this estate lives in; "" for an unknown
## estate.
static func house_id_for(estate: String) -> String:
	return _HOUSE_BY_ESTATE.get(estate, "")


## The one labour class this estate supplies; "" for an unknown estate.
static func labour_class_for(estate: String) -> String:
	return _LABOUR_CLASS_BY_ESTATE.get(estate, "")


## What this estate must have, per household per day. A COPY, so a caller
## that scales it for a season or a span cannot rewrite the table.
static func subsistence_basket(estate: String) -> Dictionary:
	return _BASKETS.get(estate, {}).get("subsistence", {}).duplicate()


## What this estate must have to RISE, per household per day. A copy, as
## above.
static func station_basket(estate: String) -> Dictionary:
	return _BASKETS.get(estate, {}).get("station", {}).duplicate()


## Every good either half of this estate's basket names, subsistence first
## then station, each once.
static func basket_goods(estate: String) -> Array:
	var goods: Array = subsistence_basket(estate).keys()
	for good in station_basket(estate):
		if not goods.has(good):
			goods.append(good)
	return goods


## The whole daily draw of one household of this estate, both halves summed
## -- the number that makes promoting everybody a real cost rather than a
## free win.
static func daily_basket_total(estate: String) -> float:
	var total := 0.0
	for units in subsistence_basket(estate).values():
		total += float(units)
	for units in station_basket(estate).values():
		total += float(units)
	return total


## The subsistence basket with this season's fuel term applied. An unknown
## season is the plain baseline rather than an error -- a caller with no
## clock in hand gets the shoulder-season basket, which is the honest
## middle rather than a guess in either direction.
static func seasonal_basket(estate: String, season: String) -> Dictionary:
	var basket := subsistence_basket(estate)
	if not basket.has(FUEL_ITEM_ID):
		return basket
	var multiplier: float = _FUEL_MULTIPLIER_BY_SEASON.get(season, 1.0)
	basket[FUEL_ITEM_ID] = float(basket[FUEL_ITEM_ID]) * multiplier
	return basket


## The same, off the real world clock rather than a season name.
static func seasonal_basket_at(estate: String, elapsed_seconds: float) -> Dictionary:
	return seasonal_basket(estate, SeasonCycle.new().season_at(elapsed_seconds))


## Mechanism 6: what one household of this estate pays the village per day,
## scaled by how well provided it actually is. A destitute household pays
## nothing -- there is no surplus to take -- and a fully provided one pays
## the base. An unknown estate is untaxable rather than free money.
static func tax_per_day(estate: String, provision: float) -> float:
	var base: float = BASE_TAX_PER_DAY.get(estate, 0.0)
	return base * clampf(provision, 0.0, 1.0)
