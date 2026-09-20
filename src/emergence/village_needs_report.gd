extends RefCounted

## docs/concept/village_estates.md mechanism 8: every need this village's
## estates really ask for, what they actually got, and which building would
## answer it.
##
## Asked directly: *"there should be sth. like a graph with every needs that
## can be resolved"*. Every part of that graph already existed and none of
## it was visible -- VillageEstates names each rung's basket,
## EstateConsumption.draw reports what they were supplied with, and
## VillageAssembly knows which building would supply a good on this land.
## This is the one place that puts them next to each other.
##
## It READS and never computes. Satisfaction comes from the draw and the
## remedy from the assembly, because a readout that worked either out for
## itself could disagree with the village it claims to describe -- the exact
## failure HousePanel's own "renders what it is handed" contract exists to
## avoid.
##
## Pure and engine-free, like every other rules module here: a state
## dictionary in, an ordered Array of rows out.

const VillageEstates = preload("res://src/emergence/village_estates.gd")
const VillageAssembly = preload("res://src/emergence/village_assembly.gd")
const SettlementFoodDemand = preload("res://src/emergence/settlement_food_demand.gd")
const ItemCatalog = preload("res://src/gameplay/item_catalog.gd")

## What a good with no reading yet is reported at. A village that has not
## been assessed is not a starving one -- it is one nobody has asked.
const UNASSESSED_SATISFACTION := 1.0

## The name the food TOKEN reads under. It is not an item id (it stands for
## "any real food on the shelf" -- see VillageEstates.FOOD_KIND_TOKEN), so
## ItemCatalog has nothing to say about it.
const FOOD_LABEL := "Food"


## One row per good the estates present here really ask for, worst supplied
## first. `state` is VillageAssembly.next_building's own state dictionary,
## unchanged -- the same reading feeds the decision and the readout, so they
## cannot drift.
##
## Each row: {good, label, satisfaction, estates, remedy, resolvable, next}.
static func rows_for(state: Dictionary) -> Array:
	var estate_counts: Dictionary = state.get("estate_counts", {})
	if int(state.get("household_count", 0)) <= 0 or estate_counts.is_empty():
		return []
	var satisfaction: Dictionary = state.get("satisfaction", {})
	var food_trade := String(state.get("food_trade", SettlementFoodDemand.FALLBACK_TRADE))
	var next_building: String = VillageAssembly.next_building(state)

	var asked_by: Dictionary = _asked_by(estate_counts)
	var rows: Array = []
	for good in asked_by:
		var remedy: String = VillageAssembly.remedy_for(good, food_trade)
		rows.append({
			"good": good,
			"label": _label_for(good),
			"satisfaction": clampf(
				float(satisfaction.get(good, UNASSESSED_SATISFACTION)), 0.0, 1.0
			),
			"estates": asked_by[good],
			"remedy": remedy,
			"resolvable": remedy != "",
			"next": remedy != "" and remedy == next_building,
		})
	rows.sort_custom(_worst_first)
	return rows


## good -> the estates present here that ask for it, in ESTATE_IDS' own
## order so the answer is the same every time rather than a Dictionary's
## iteration order.
static func _asked_by(estate_counts: Dictionary) -> Dictionary:
	var asked_by := {}
	for estate in VillageEstates.ESTATE_IDS:
		if int(estate_counts.get(estate, 0)) <= 0:
			continue
		for good in VillageEstates.basket_goods(estate):
			if not asked_by.has(good):
				asked_by[good] = []
			asked_by[good].append(estate)
	return asked_by


## Worst supplied first -- the order a village would fix them in, so the top
## of the list is what the assembly is arguing about. Ties break on the good
## itself, this project's own determinism discipline.
static func _worst_first(a: Dictionary, b: Dictionary) -> bool:
	if is_equal_approx(float(a["satisfaction"]), float(b["satisfaction"])):
		return String(a["good"]) < String(b["good"])
	return float(a["satisfaction"]) < float(b["satisfaction"])


## The name the rest of the game calls this good, so a readout can print a
## row without knowing item ids. Falls back to the id itself rather than to
## an empty string: an unnamed good is still a real shortage.
static func _label_for(good: String) -> String:
	if good == VillageEstates.FOOD_KIND_TOKEN:
		return FOOD_LABEL
	var catalog := ItemCatalog.new()
	if catalog.has(good):
		return catalog.display_name_of(good)
	return good
