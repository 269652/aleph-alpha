extends RefCounted

## A settlement's shared PURSE: the half of docs/concept/npc.md's local
## production economy that was missing, and the reason villager hunger has
## been an occupation constant rather than an economy.
##
## NpcEconomy only ever credits a Wallet inside `_gather()`, which is gated
## on `NpcProduction.is_producer()`. Of the eight occupations in
## NpcIdentity.OCCUPATIONS only three produce, so the other five start at
## zero gold, can never afford VillageMarket.VILLAGE_LOCAL_FOOD_PRICE, and
## stay hungry forever no matter what the weather, the harvest, or the
## market stock does. npc.md already says a non-producer "eat[s] by BUYING
## it, out of their own wallet" -- it just never says where that wallet's
## gold comes from. This is that: a producing household's gold income is
## split, a share going to the village, and a non-producer draws a
## subsistence wage back out of it. A blacksmith stays fed because a
## hunter's catch funds the village, which is exactly the specialization
## npc.md calls "real rather than cosmetic".
##
## -- Why the levy rate is DERIVED, not chosen --
##
## The share is the non-producer fraction of the real occupation census
## (NpcIdentity.OCCUPATIONS minus NpcProduction.PRODUCER_ITEM_BY_OCCUPATION),
## which is the one rate that isn't a guess: it is precisely the rate at
## which a producer's take-home equals each non-producer's cut of the
## purse, i.e. village income is neutral between working a producing
## occupation and a non-producing one. Any other number silently declares
## one half of the village richer than the other for no modelled reason.
## Because NpcIdentity picks an occupation by a uniform modulo of that same
## array (NpcIdentity._index), the census fraction is also the EXPECTED mix
## of a real generated village, not just a global tally -- and adding a
## ninth occupation moves the rate on its own instead of stranding a
## hand-tuned constant. Pinned by
## test_wage_share_is_the_non_producer_share_of_the_real_occupation_census
## and, behaviourally, by
## test_the_wage_share_leaves_a_producer_exactly_what_it_gives_each_non_producer.
##
## -- Why the purse is a float but a wage is a whole int --
##
## Wallet is integer gold and NpcProduction.YIELD_TO_GOLD_RATE is 1, so
## levying a fraction of a single earning per-call would round to all-or-
## nothing and destroy the split. The purse therefore accrues fractionally
## (the same carry-until-it-crosses-a-whole-unit idiom NpcEconomy already
## runs on `_accumulated_yield`) and only ever pays out in whole gold a
## Wallet can actually hold. Payout is all-or-nothing for the same reason
## Wallet.spend and VillageMarket.remove_stock are: half a meal price buys
## nothing the market has any notion of.
##
## Deliberately a FLAT wage, not a top-up to whatever the claimant is
## short: the caller (NpcEconomy) already knows who is hungry and already
## discovers a failed VillageMarket.buy_meal, so who draws and when is its
## decision; this module only answers what the village can afford to pay.
##
## Pure static module, no Node/store/scene dependency -- arguments in,
## values out, the purse balance itself owned by whoever is persisting the
## settlement. Same shape as OccupationProduction.

const NpcIdentity = preload("res://src/world/npc_identity.gd")
const NpcProduction = preload("res://src/world/npc_production.gd")
const VillageMarket = preload("res://src/world/village_market.gd")


## How many of the real occupations actually gather food.
static func producer_occupation_count() -> int:
	var count := 0
	for occupation in NpcIdentity.OCCUPATIONS:
		if NpcProduction.PRODUCER_ITEM_BY_OCCUPATION.has(occupation):
			count += 1
	return count


## How many of the real occupations have no food source of their own --
## the villagers this purse exists to keep alive.
static func non_producer_occupation_count() -> int:
	return NpcIdentity.OCCUPATIONS.size() - producer_occupation_count()


## The levy rate for an arbitrary village census: the non-producer share of
## its people. A census with nobody to support levies nothing; an empty or
## nonsensical (negative) census is treated as empty rather than dividing
## by zero. A census with no producers at all returns 1.0, which is the
## honest continuation of the formula and moot in practice -- with no
## producer there is no gross income for the rate to ever apply to.
static func wage_share_for(producer_count: int, non_producer_count: int) -> float:
	var producers := maxi(producer_count, 0)
	var non_producers := maxi(non_producer_count, 0)
	var total := producers + non_producers
	if total <= 0:
		return 0.0
	return float(non_producers) / float(total)


## The live levy rate, off the real occupation census -- see the file doc
## comment for why this is derived rather than tuned.
static func wage_share() -> float:
	return wage_share_for(producer_occupation_count(), non_producer_occupation_count())


## The village's share of one producing household's gross gold income.
static func levy_on(gross_gold: float) -> float:
	return maxf(gross_gold, 0.0) * wage_share()


## What the producing household itself keeps. Exactly the complement of
## levy_on(), so the split creates and destroys no gold.
static func take_home_of(gross_gold: float) -> float:
	var gross := maxf(gross_gold, 0.0)
	return gross - levy_on(gross)


## The purse after a producing household earned `gross_gold`. Zero or
## negative earnings are a no-op, matching Wallet.add's own clamp rather
## than inventing a second convention for nonsense input.
static func deposit(purse_gold: float, gross_gold: float) -> float:
	return maxf(purse_gold, 0.0) + levy_on(gross_gold)


## One subsistence wage, in whole gold: exactly one meal at the village
## market's own live price, so a wage feeds a villager once and leaves
## nothing to hoard. Anchored to VillageMarket.VILLAGE_LOCAL_FOOD_PRICE
## rather than restated, so the two can never drift (pinned by
## test_one_subsistence_wage_is_exactly_one_meal_at_the_markets_own_price
## and, through a real market purchase, by
## test_a_villager_paid_one_wage_can_buy_exactly_one_real_meal_and_no_more).
static func subsistence_wage() -> int:
	return VillageMarket.VILLAGE_LOCAL_FOOD_PRICE


## Non-mutating check for whether pay_subsistence() would pay anything.
static func can_pay_subsistence(purse_gold: float) -> bool:
	return purse_gold >= float(subsistence_wage())


## Draws one subsistence wage. Returns {"paid": int gold to hand the
## claimant's Wallet, "purse": float purse afterwards}. All-or-nothing: a
## purse short of a whole wage pays 0 and is left untouched, and the purse
## it returns is never negative.
static func pay_subsistence(purse_gold: float) -> Dictionary:
	var purse := maxf(purse_gold, 0.0)
	if not can_pay_subsistence(purse):
		return {"paid": 0, "purse": purse}
	var wage := subsistence_wage()
	return {"paid": wage, "purse": maxf(purse - float(wage), 0.0)}


## How much gross producer income one subsistence wage costs the village --
## the levy rate expressed in the units the simulation actually ticks in,
## so a caller can say "N gathered food units per fed non-producer" against
## NpcProduction.YIELD_TO_GOLD_RATE instead of guessing. INF when nothing
## is levied at all (a census with no non-producers to support): such a
## purse never funds a wage, however long it runs.
static func gross_earnings_per_wage() -> float:
	var share := wage_share()
	if share <= 0.0:
		return INF
	return float(subsistence_wage()) / share
