extends RefCounted

## docs/concept/village_estates.md mechanism 5: what the village VOTES to
## build next.
##
## docs/concept/village_growth.md's ladder walks a FIXED order gated on raw
## household count -- sawmill, hall, farm, forge, brewery, the same five in
## the same sequence in every village on the planet. Two villages of the
## same size are the same town.
##
## Here the order emerges from who actually lives there. Every household
## petitions, the estates are weighted (an estate assembly was never one
## household one vote), and the loudest petition wins. Two villages of the
## same size with different estate mixes build visibly different towns,
## which is the thing a headcount ladder can never do.
##
## **The vote rule, in one line:** a household short of something petitions
## for the works that would supply it; a household with nothing to complain
## of petitions for the charter that would let it rise.
##
## Deliberately a LAYER over VillageGrowth rather than a replacement. The
## shelter-first rule, the ladder's set of buildings and the tie-break order
## are all read from that module, so the two cannot drift, and a village
## with no estate census at all falls straight through to the behaviour it
## already had.
##
## Pure and static. Deterministic on identical input -- test-pinned,
## because a Dictionary iteration order leaking into a village's
## architecture would be the hardest kind of bug to see.

const VillageEstates = preload("res://src/emergence/village_estates.gd")
const VillageGrowth = preload("res://src/emergence/village_growth.gd")
const VillageLabor = preload("res://src/emergence/village_labor.gd")
const EstateAscension = preload("res://src/emergence/estate_ascension.gd")

## How far each estate's voice carries in the assembly. Strictly rising,
## and that is the historical fact rather than a balance knob: a burgher
## sat in the assembly, a cottager did not. Pinned by the ordering it
## produces (test_village_assembly.gd), never by these numbers -- weight is
## a thumb on the scale and never a veto, which is why enough cottagers
## still outvote a handful of burghers.
const ESTATE_VOTE_WEIGHT := {
	"kossaet": 1.0,
	"bauer": 2.0,
	"handwerker": 3.0,
	"buerger": 4.0,
}

## Which rung of the growth ladder would actually SUPPLY a good a household
## is short of. Only goods a ladder building really produces appear: a
## village short of candles has no building on its ladder that makes
## candles, so it honestly petitions for nothing on that count rather than
## voting for the nearest-sounding rung.
const REMEDY_BY_GOOD := {
	VillageEstates.FOOD_KIND_TOKEN: "farmhouse",
	VillageEstates.FUEL_ITEM_ID: "sawmill",
	# Grain before flour: you cannot bake what you did not grow, and the
	# farm is the only rung on this ladder that grows anything.
	"bread": "farmhouse",
	# The herbalist's physic garden is worked off the farmstead's own field
	# (docs/concept/village_farms.md).
	"herb": "farmhouse",
	"beer": "brewery",
}

## A satisfaction at or above this is not a shortage worth petitioning
## about. Matches EstateAscension's own reading of a whole ration, so the
## assembly and the ladder agree on what "supplied" means.
const SUPPLIED := EstateAscension.FULL_SATISFACTION


## The one building this village votes to raise next, or "".
##
## `state` keys:
##   estate_counts         estate -> households
##   household_count       how many households there are
##   housed_count          how many of them have a roof
##   present_building_ids  what really stands here
##   satisfaction          good -> [0,1], EstateConsumption.draw's own report
##   waiting_estate        the estate of the household at the head of the
##                         housing queue, if the caller knows it
static func next_building(state: Dictionary) -> String:
	var household_count := int(state.get("household_count", 0))
	if household_count <= 0:
		return ""

	# Shelter before adornment, exactly as the ladder already rules -- but
	# the house raised is the WAITING HOUSEHOLD'S OWN estate's house, which
	# closes village_growth.md's named gap that a growth house is always the
	# small one. A burgher who lost their roof is not rehoused in a cottage.
	if int(state.get("housed_count", 0)) < household_count:
		var waiting := String(state.get("waiting_estate", VillageEstates.STARTING_ESTATE))
		var house_id: String = VillageEstates.house_id_for(waiting)
		return house_id if house_id != "" else VillageEstates.house_id_for(VillageEstates.STARTING_ESTATE)

	var estate_counts: Dictionary = state.get("estate_counts", {})
	var present: Array = state.get("present_building_ids", [])
	var petitions: Dictionary = _petitions(
		estate_counts, present, state.get("satisfaction", {})
	)
	if petitions.is_empty():
		# Nothing anybody in this village is asking for -- but silence is
		# not always an answer. A village whose estates are unknown to us,
		# or whose supply has never been ASSESSED, has not abstained: we
		# simply never asked it. Either way it falls through to the ladder
		# it already walked, so the assembly can only ever be a layer over
		# VillageGrowth and never a regression on it.
		#
		# Once a real reading HAS been taken, the fallback is gone: a
		# village that really wants nothing really builds nothing, which is
		# the whole point of asking.
		if estate_counts.is_empty() or Dictionary(state.get("satisfaction", {})).is_empty():
			return VillageGrowth.next_building(household_count, household_count, present)
		return ""
	return _winner(petitions)


## building_id -> total weight petitioned for it.
static func _petitions(
	estate_counts: Dictionary, present: Array, satisfaction: Dictionary
) -> Dictionary:
	var supply: Dictionary = VillageLabor.supply_for(estate_counts)
	var petitions := {}
	for estate in VillageEstates.ESTATE_IDS:
		var households := int(estate_counts.get(estate, 0))
		if households <= 0:
			continue
		var asked: String = _ask_of(estate, present, satisfaction, supply, estate_counts)
		if asked == "":
			continue
		var weight := float(households) * float(ESTATE_VOTE_WEIGHT.get(estate, 1.0))
		petitions[asked] = float(petitions.get(asked, 0.0)) + weight
	return petitions


## What one estate asks for: the remedy for its worst shortage if there is
## a buildable one, otherwise the charter that would let it rise, otherwise
## nothing.
static func _ask_of(
	estate: String,
	present: Array,
	satisfaction: Dictionary,
	supply: Dictionary,
	estate_counts: Dictionary
) -> String:
	var remedy: String = REMEDY_BY_GOOD.get(_worst_shortage_of(estate, satisfaction), "")
	if remedy != "" and _is_petitionable(remedy, present, supply, estate_counts):
		return remedy
	for charter in EstateAscension.charter_building_ids_for(estate):
		if _is_petitionable(charter, present, supply, estate_counts):
			return charter
	return ""


## The good this estate is shortest of, or "" if it is fully supplied.
## Goods are walked in the basket's own fixed order, so an exact tie breaks
## the same way every time rather than on Dictionary iteration.
static func _worst_shortage_of(estate: String, satisfaction: Dictionary) -> String:
	var worst_good := ""
	var worst := SUPPLIED
	for good in VillageEstates.basket_goods(estate):
		var level := clampf(float(satisfaction.get(good, 1.0)), 0.0, 1.0)
		if level < worst:
			worst = level
			worst_good = good
	return worst_good


## Whether the village may vote for this building at all.
##
## Two gates, and the exemption between them is load-bearing. A works
## nobody could put a single body in is never petitioned for -- a village
## with no craftsmen does not vote for a forge it would then leave cold.
## But a CHARTER is exempt: a civic seat is not staffed before it exists,
## it is what CREATES the estate that keeps it. Without that exemption
## every rung of the estate ladder deadlocks on needing the people its own
## charter would produce.
static func _is_petitionable(
	building_id: String, present: Array, supply: Dictionary, estate_counts: Dictionary
) -> bool:
	if present.has(building_id):
		return false
	if _is_charter_for_any_estate_here(building_id, estate_counts):
		return true
	return VillageLabor.can_staff(building_id, supply)


static func _is_charter_for_any_estate_here(building_id: String, estate_counts: Dictionary) -> bool:
	for estate in estate_counts:
		if int(estate_counts[estate]) <= 0:
			continue
		if EstateAscension.charter_building_ids_for(estate).has(building_id):
			return true
	return false


## The loudest petition. Ties break on the growth ladder's own order, so
## the assembly is deterministic and a village with no strong opinion still
## behaves exactly as that ladder already does.
static func _winner(petitions: Dictionary) -> String:
	var best := ""
	var best_weight := 0.0
	for building_id in VillageGrowth.LADDER_BUILDING_IDS:
		var weight := float(petitions.get(building_id, 0.0))
		if weight > best_weight:
			best_weight = weight
			best = building_id
	return best
