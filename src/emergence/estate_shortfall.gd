extends RefCounted

## docs/concept/village_estates.md: the step that makes an unmet basket
## something a village can BUILD its way out of.
##
## Without it the estate layer is a demand nothing answers. A village short
## of bread has no bakery, no mill and no farm, and nothing in the game
## ever tells it to raise one -- so no household ever meets its station,
## nobody ever rises, and the whole ladder is decorative. The gap is real
## and was found by asking what a village actually produces: fields grow
## WHEAT and nothing else (VillageFarm.CROP_BY_OCCUPATION), the growth
## ladder raises no mill and no bakery, and nothing at all made beer until
## brew_beer landed.
##
## SettlementBuildDecision already reasons "bread -> bakery -> flour ->
## mill -> wheat -> farm" from a shortfall, through
## ConstructionPriority.deepest_missing_structure_id, and it reads
## shortfalls in ONE fixed shape -- the one
## Quest.production_shortfall_quests_for and SettlementFood.food_shortfall_
## for both produce. So an unmet basket is reported in exactly that shape
## and needs no new code whatsoever on the other side: a village short of
## beer raises a brewery, one short of bread raises the grain chain, by the
## same walk that already existed.
##
## Pure and static, no state of its own.

const VillageEstates = preload("res://src/emergence/village_estates.gd")

## The `kind` tag on every entry, so a caller can tell an estate shortfall
## apart from a production one or SettlementFood's staple one -- the same
## way that module tags its own "food".
const KIND := "estate"


## One shortfall entry per good this village went short of, worst first.
##
## `estate_counts` is a real estate census, `satisfaction` the share of each
## good that was actually supplied (EstateConsumption.draw's own report),
## and `days` the span it was measured over.
##
## Estates short of the SAME good ask once, for the whole village's unmet
## quantity: three small asks would be ranked below one big one by
## SettlementBuildDecision's worst-first ranking, and the village would
## build the wrong thing.
##
## FOOD_KIND_TOKEN is never reported. It is not an item id, nothing can be
## built to produce "any food", and SettlementFood.food_shortfall_for
## already asks for the staple a village can raise its way to -- a second,
## uncalibrated food ask beside it would have the two competing.
static func shortfalls_for(
	estate_counts: Dictionary, satisfaction: Dictionary, days: float
) -> Array:
	if days <= 0.0:
		return []

	var owed := {}
	for estate in VillageEstates.ESTATE_IDS:
		var households := float(estate_counts.get(estate, 0))
		if households <= 0.0:
			continue
		_accrue_shortfall(owed, VillageEstates.subsistence_basket(estate), satisfaction, households * days)
		_accrue_shortfall(owed, VillageEstates.station_basket(estate), satisfaction, households * days)

	# Worst first, item id as the deterministic tie-break -- the same
	# ordering discipline SettlementBuildDecision._rank_shortfalls holds,
	# so a village never changes its mind because a Dictionary was walked
	# in a different order.
	var keys: Array = []
	for good in owed:
		keys.append([-float(owed[good]), String(good)])
	keys.sort()

	var out: Array = []
	for key in keys:
		out.append({
			"kind": KIND,
			"household_id": "",
			"occupation": "",
			"recipe_id": "",
			# At least one whole unit: the build decision ranks and acts on
			# integers, and "0.4 of a loaf short" must not round away to
			# nothing -- a shortfall too small to name is still a shortfall
			# nothing is answering.
			"missing": [{"item_id": key[1], "need": maxi(1, int(round(-float(key[0]))))}],
		})
	return out


## Adds what this basket went short of, in real units, into `owed`.
static func _accrue_shortfall(
	owed: Dictionary, basket: Dictionary, satisfaction: Dictionary, scale: float
) -> void:
	for good in basket:
		if good == VillageEstates.FOOD_KIND_TOKEN:
			continue
		var supplied := clampf(float(satisfaction.get(good, 0.0)), 0.0, 1.0)
		if supplied >= 1.0:
			continue
		var short := float(basket[good]) * scale * (1.0 - supplied)
		if short <= 0.0:
			continue
		owed[good] = float(owed.get(good, 0.0)) + short
