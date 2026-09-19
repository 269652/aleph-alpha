extends RefCounted

## docs/concept/village_estates.md mechanism 2: the goods actually LEAVE.
##
## This is the single change the whole estate overhaul hangs off, and the
## one thing docs/concept/village_growth.md's wellbeing model could not do.
## That model READS a settlement's food stock and scores it; nothing is
## ever spent, so a village with a full granary and forty households scores
## exactly as well as the same granary with four. Here a household's needs
## are a FLOW: the units are removed from real stock, the same unit cannot
## satisfy two households, and a village four days from empty reads as one
## four days from empty because it is visibly draining.
##
## Pure and static, no state of its own -- the caller owns the stock and
## the carry, the same division SettlementGathering/VillageImmigration
## already draw.
##
## Two properties worth stating because they are deliberate:
##
## - **The draw never goes into debt and never refuses.** A village with
##   half the firewood burns half the firewood and is half warm. It does
##   not hold out for a full ration and it does not borrow against next
##   week -- both would hide a shortage that the whole point is to expose.
## - **An estate's verdict is the MINIMUM over its goods, not the mean.** A
##   household with all the bread in the world and no fuel is not eighty
##   percent provided for; it is cold. The minimum is what makes ONE
##   missing good a real crisis, which is exactly how an Anno supply chain
##   fails and exactly what a mean would smooth away.

const VillageEstates = preload("res://src/emergence/village_estates.gd")


## What a whole village draws over `days`, given `estate_counts`
## (estate -> households) and the season its fuel term is read from.
## `{good -> units}`, empty for an empty census or a span of no time.
##
## Both halves of every basket are included: a station good is drawn
## exactly like a subsistence one, because a household that HAS bread eats
## the bread. What differs between the halves is only what going short of
## them MEANS (see subsistence_satisfaction / station_satisfaction), not
## whether the goods move.
static func demand_for(estate_counts: Dictionary, days: float, season: String) -> Dictionary:
	if days <= 0.0:
		return {}
	var demand := {}
	for estate in estate_counts:
		var households := float(estate_counts[estate])
		if households <= 0.0:
			continue
		var scale := households * days
		_accrue(demand, VillageEstates.seasonal_basket(estate, season), scale)
		_accrue(demand, VillageEstates.station_basket(estate), scale)
	return demand


## Adds `basket` scaled by `scale` into `into`, in place.
static func _accrue(into: Dictionary, basket: Dictionary, scale: float) -> void:
	for good in basket:
		into[good] = float(into.get(good, 0.0)) + float(basket[good]) * scale


## Spends `demand` against `stock`, returning
## `{"taken": {good -> units}, "satisfaction": {good -> [0,1]},
##   "stock": the stock afterwards}`.
##
## `food_ids` is the list of stocked item ids that really count as food
## (ItemCatalog kind "food" -- resolved by the caller, which is the only
## side that knows the live catalog including crafted dishes). The
## FOOD_KIND_TOKEN demand is spent across them, MOST PLENTIFUL FIRST so a
## glut is eaten down before a scarcity, ties breaking on item id so the
## draw is deterministic rather than dependent on Dictionary order.
##
## The caller's own dictionary is never mutated: the stock that comes back
## is a copy, so a caller can price the draw before committing to it.
static func draw(demand: Dictionary, stock: Dictionary, food_ids: Array) -> Dictionary:
	var remaining := stock.duplicate()
	var taken := {}
	var satisfaction := {}
	for good in demand:
		var wanted := float(demand[good])
		if wanted <= 0.0:
			satisfaction[good] = 1.0
			continue
		var got := (
			_spend_food(remaining, wanted, food_ids)
			if good == VillageEstates.FOOD_KIND_TOKEN
			else _spend_item(remaining, good, wanted)
		)
		taken[good] = got
		satisfaction[good] = clampf(got / wanted, 0.0, 1.0)
	return {"taken": taken, "satisfaction": satisfaction, "stock": remaining}


## Removes up to `wanted` of one real item id, returning what it actually
## got. Never leaves a negative balance and drops an emptied id rather than
## keeping a zero, so the stock dictionary stays the same shape a market's
## own does.
static func _spend_item(stock: Dictionary, item_id: String, wanted: float) -> float:
	var have := float(stock.get(item_id, 0.0))
	if have <= 0.0:
		return 0.0
	var got := minf(have, wanted)
	var left := have - got
	if left <= 0.0:
		stock.erase(item_id)
	else:
		stock[item_id] = left
	return got


## Spends a `kind:food` demand across whatever real food the village has.
## Most plentiful first: a village eats its glut down before it touches the
## last of something scarce, which is both what people do and what keeps a
## single rare delicacy from being consumed as a staple.
static func _spend_food(stock: Dictionary, wanted: float, food_ids: Array) -> float:
	var stocked: Array = []
	for item_id in food_ids:
		if float(stock.get(item_id, 0.0)) > 0.0:
			stocked.append(item_id)
	# Sorted by id FIRST so the plentiful-first sort below, which is stable
	# only as far as its own comparator, still breaks its ties the same way
	# on every run and every platform.
	stocked.sort()
	stocked.sort_custom(func(a, b): return float(stock.get(a, 0.0)) > float(stock.get(b, 0.0)))

	var got := 0.0
	for item_id in stocked:
		if got >= wanted:
			break
		got += _spend_item(stock, item_id, wanted - got)
	return got


## The worst-supplied good of this estate's SUBSISTENCE basket, in [0, 1].
## Short here for a sustained run and the household descends, then leaves
## (EstateAscension).
static func subsistence_satisfaction(estate: String, satisfaction: Dictionary) -> float:
	return _worst(VillageEstates.subsistence_basket(estate), satisfaction)


## The worst-supplied good of this estate's STATION basket, in [0, 1].
## Short here and the household simply does not RISE -- it is not in any
## danger, it just has no claim to a standing it is not living at.
static func station_satisfaction(estate: String, satisfaction: Dictionary) -> float:
	return _worst(VillageEstates.station_basket(estate), satisfaction)


## The minimum over a basket's goods (see this file's header for why a
## minimum rather than a mean). An EMPTY basket is 1.0, deliberately: an
## estate with nothing to be short of is not destitute, and 0.0 here would
## make a rung with an empty station basket permanently unable to ascend.
## A good the report never mentions was not supplied -- the same destitute
## default HouseholdWellbeing already takes of a missing input.
static func _worst(basket: Dictionary, satisfaction: Dictionary) -> float:
	if basket.is_empty():
		return 1.0
	var worst := 1.0
	for good in basket:
		worst = minf(worst, clampf(float(satisfaction.get(good, 0.0)), 0.0, 1.0))
	return worst
