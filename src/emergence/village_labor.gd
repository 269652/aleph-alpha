extends RefCounted

## docs/concept/village_estates.md mechanism 4: a building is not
## production; a STAFFED building is.
##
## This is the honest answer to docs/concept/village_growth.md's own
## standing gap -- "the ladder's rungs are buildings, not yet production."
## A village there raises a sawmill, a forge and a brewery and gets a
## sprite out of each. Here it gets an output scale, and the scale is zero
## until somebody of the right estate is there to stand in it.
##
## It is also the squeeze that makes the estate ladder COST something.
## VillageEstates gives each estate exactly one class of labour, so
## promoting a cottager to a husbandman removes a pair of hands and creates
## a farmer -- the village is never richer in total labour for having
## promoted anybody (test-pinned). A village that promotes everyone cannot
## work its own mill. That is Anno's central tension and, precisely, what
## happened to villages that turned their cottagers into burghers.
##
## Labour is POOLED per village, not assigned per building: two forges in
## one village share its craftsmen, so raising a second without raising
## more craftsmen halves them both. That is why demand is read across
## everything standing rather than one building at a time.
##
## Pure and static, no state of its own -- the same shape VillageEstates
## and EstateConsumption already have.

const VillageEstates = preload("res://src/emergence/village_estates.gd")

## How many heads of which class each standing building needs to run at
## full output. A building absent from this table takes no workforce and
## always runs: a house is lived in, not worked in.
##
## Every class named here is one some estate really supplies and every
## building named is a real BuildingCatalog entity, both test-pinned -- a
## post no villager could fill, or one in a place that cannot be built, is
## a workforce demand that can never be met.
const LABOUR_BY_BUILDING := {
	# The farm is worked by husbandmen, two to a farmstead: plough-land is
	# the one job in the village that is nobody else's.
	"farmhouse": {"field": 2},
	# Two men on a saw. NOT a guild trade, and that correction came out of
	# VillageAssembly's own tests rather than out of taste: with the mill
	# needing a craftsman, a village of cottagers could never staff the one
	# works that supplies its own firewood, and craftsmen only exist
	# downstream of a mill -- a deadlock at the very bottom of the ladder.
	# It is also what BuildingCatalog already says the building IS: "a shed,
	# a saw pit and a log deck, not an enclosed hall". A water mill would
	# want a millwright; this is a saw pit.
	"sawmill": {"hand": 2},
	# Shifting and stacking; no trade required.
	"warehouse": {"hand": 1},
	# A forge is a trade end to end.
	"blacksmith": {"craft": 2},
	# A mash floor is a brewer's trade over somebody else's back: the malt
	# has to be shifted and the mash raked, and the brewer does not do it
	# alone. The one rung that can be bottlenecked from BELOW as well as
	# above, which is why its output scale is the interesting one.
	"brewery": {"craft": 1, "hand": 1},
	# The civic seat is kept by the estate that holds civic rights.
	"city_hall": {"civic": 1},
}


## `{labour_class -> heads}` for a village's estate census -- one head per
## household of the estate that supplies that class. An estate the table
## does not know supplies nothing rather than crashing.
static func supply_for(estate_counts: Dictionary) -> Dictionary:
	var supply := {}
	for estate in estate_counts:
		var households := int(estate_counts[estate])
		if households <= 0:
			continue
		var labour_class := VillageEstates.labour_class_for(estate)
		if labour_class == "":
			continue
		supply[labour_class] = int(supply.get(labour_class, 0)) + households
	return supply


## `{labour_class -> heads}` demanded by everything standing. Buildings
## accumulate: two forges want twice the craftsmen.
static func demand_for(present_building_ids: Array) -> Dictionary:
	var demand := {}
	for building_id in present_building_ids:
		for labour_class in LABOUR_BY_BUILDING.get(building_id, {}):
			demand[labour_class] = (
				int(demand.get(labour_class, 0)) + int(LABOUR_BY_BUILDING[building_id][labour_class])
			)
	return demand


## Every head in a supply or demand table, summed -- the number that makes
## "promotion moves a head rather than creating one" checkable.
static func total_heads(table: Dictionary) -> int:
	var total := 0
	for heads in table.values():
		total += int(heads)
	return total


## `{labour_class -> [0,1]}`, how much of each class's demand the village
## can actually field. A class nothing demands is fully met -- there is no
## post going unfilled.
static func fulfilment(supply: Dictionary, demand: Dictionary) -> Dictionary:
	var out := {}
	for labour_class in demand:
		var wanted := float(demand[labour_class])
		out[labour_class] = (
			1.0 if wanted <= 0.0
			else clampf(float(supply.get(labour_class, 0)) / wanted, 0.0, 1.0)
		)
	return out


## What share of its full output this building actually runs at, given the
## village's whole labour supply and whole labour demand.
##
## The MINIMUM across the classes this building needs, never the mean: a
## sawmill with its sawyer and no hand runs at the hand's rate, because one
## missing post is a real bottleneck. The same reasoning makes an estate's
## satisfaction a minimum (EstateConsumption).
##
## A building that takes no workforce always runs at 1.0, and surplus
## labour never pushes anything past 1.0.
static func output_scale_for(building_id: String, supply: Dictionary, demand: Dictionary) -> float:
	var needs: Dictionary = LABOUR_BY_BUILDING.get(building_id, {})
	if needs.is_empty():
		return 1.0
	var met := fulfilment(supply, demand)
	var scale := 1.0
	for labour_class in needs:
		scale = minf(scale, float(met.get(labour_class, 0.0)))
	return clampf(scale, 0.0, 1.0)


## Whether the village holds at least ONE head of every class this building
## needs -- the assembly's own gate (mechanism 5): a village does not vote
## to build what it could not put a single body in. Deliberately weaker
## than "can run at full": a village that can half-staff a mill still wants
## the mill.
static func can_staff(building_id: String, supply: Dictionary) -> bool:
	for labour_class in LABOUR_BY_BUILDING.get(building_id, {}):
		if int(supply.get(labour_class, 0)) <= 0:
			return false
	return true
