extends RefCounted

## docs/concept/village_estates.md's second novel mechanic: the guild
## chest, and the point where the SOCIAL layer becomes economically
## load-bearing rather than bookkeeping.
##
## `InstitutionStore` already forms real `guild` institutions out of
## repeated fulfilled contracts between households -- who has actually
## traded with whom, over and over, recorded as history. Until now that was
## a fact about a village that nothing in the village ever used. Here it
## decides whether one bad season costs the village its comfort or its
## craftsmen.
##
## A guild **sets goods aside while its village is supplied** and
## **releases them when it is not**. That is what a Zunftkasse was actually
## for: a relief chest, and often a literal guild granary, held against the
## season that would otherwise unmake a trade.
##
## Paired with VillageEstates' seasonal fuel term it produces a behaviour
## nobody wrote: a guild village banks firewood through the summer, when
## the basket asks for half as much and there is a real surplus, and burns
## it through the winter, when the basket asks for double. The mechanism
## has no idea what a season is. It only knows "supplied" and "short".
##
## Pure and static. The caller owns the chest; this module only says what
## moves. Every tuned value is pinned by test_guild_relief.gd against the
## relation or the real-world quantity it comes from.
##
## **A village with no guild is completely unaffected**: an empty chest
## relieves nobody and sets nothing aside, so both calls are the identity,
## end to end (test-pinned).

const SeasonCycle = preload("res://src/world/season_cycle.gd")

## How much demand a chest may hold: one whole SEASON's worth. Derived from
## the real world clock rather than chosen -- and it is exactly the horizon
## the seasonal fuel term swings over, which is the horizon a relief chest
## has to cover to be worth keeping at all. (The four is a literal only
## because SEASONS.size() is not a constant expression GDScript will fold;
## test_a_chest_holds_at_most_one_real_seasons_demand divides by the REAL
## list's size, so a fifth season breaks loudly here.)
const CHEST_HORIZON_DAYS := SeasonCycle.DAYS_PER_YEAR / 4.0

## What share of what is left on the shelf a chest may take in one pass.
## Well under everything on purpose: a guild that banked the whole surplus
## would strip the village it is meant to protect, and a village that never
## sees a surplus never builds anything either.
const SET_ASIDE_SHARE := 0.2


## The most of one good a chest may hold, given what the village uses of it
## per day. A good the village has no use for has no cap, and is therefore
## never banked -- a chest is a larder, not a warehouse.
static func cap_for(daily_demand: float) -> float:
	return maxf(daily_demand, 0.0) * CHEST_HORIZON_DAYS


## Moves a share of a SUPPLIED village's leftover stock into the chest.
##
## `daily_demand` is what the village uses of each good per day (the cap is
## derived from it, and a good absent from it is never banked).
## `supplied` is whether the village's own baskets were actually met -- you
## do not stockpile while your own people go short, which is both the
## historical rule and what stops the chest from causing the famine it
## exists to prevent.
##
## Returns `{"chest": ..., "stock": ...}`. Nothing is created: what the
## chest gains, the shelf loses, exactly. The caller's own dictionaries are
## left untouched.
static func set_aside(
	stock: Dictionary, daily_demand: Dictionary, chest: Dictionary, supplied: bool
) -> Dictionary:
	var next_stock := stock.duplicate()
	var next_chest := chest.duplicate()
	if not supplied:
		return {"chest": next_chest, "stock": next_stock}

	for good in daily_demand:
		var cap := cap_for(float(daily_demand[good]))
		if cap <= 0.0:
			continue
		var room := cap - float(next_chest.get(good, 0.0))
		if room <= 0.0:
			continue
		var on_shelf := float(next_stock.get(good, 0.0))
		if on_shelf <= 0.0:
			continue
		var taken := minf(on_shelf * SET_ASIDE_SHARE, room)
		if taken <= 0.0:
			continue
		next_chest[good] = float(next_chest.get(good, 0.0)) + taken
		var left := on_shelf - taken
		if left <= 0.0:
			next_stock.erase(good)
		else:
			next_stock[good] = left
	return {"chest": next_chest, "stock": next_stock}


## Releases held goods to top a short supply up toward fully satisfied.
##
## `satisfaction` is the share of each good that was actually supplied
## (EstateConsumption.draw's own report), `demand` what the village asked
## for over the same span, `chest` what the guild is holding.
##
## Returns `{"satisfaction": ..., "chest": ..., "released": ...}`. Relief
## TOPS UP rather than starting over -- the chest never pays for what the
## market already supplied -- and never pushes a good past fully supplied,
## because a guild feeding its members twice over is not relief, it is
## waste. An empty chest relieves nobody and the reading stands.
static func relieve(satisfaction: Dictionary, demand: Dictionary, chest: Dictionary) -> Dictionary:
	var next_satisfaction := satisfaction.duplicate()
	var next_chest := chest.duplicate()
	var released := {}

	for good in demand:
		var wanted := float(demand[good])
		if wanted <= 0.0:
			continue
		var supplied := clampf(float(next_satisfaction.get(good, 0.0)), 0.0, 1.0)
		if supplied >= 1.0:
			continue
		var held := float(next_chest.get(good, 0.0))
		if held <= 0.0:
			continue
		var short := wanted * (1.0 - supplied)
		var given := minf(held, short)
		if given <= 0.0:
			continue
		released[good] = given
		var left := held - given
		if left <= 0.0:
			next_chest.erase(good)
		else:
			next_chest[good] = left
		next_satisfaction[good] = clampf(supplied + given / wanted, 0.0, 1.0)

	return {"satisfaction": next_satisfaction, "chest": next_chest, "released": released}
