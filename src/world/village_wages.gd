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
## -- The LEVY half is no longer wired (2026-09-20) --
##
## Asked directly: *"Gold should only be conjured by the travelling
## merchant"*. `levy_on`, `take_home_of` and `deposit` split a coin that
## NpcEconomy minted per food unit gathered, and that mint was the faucet
## (docs/concept/traveling_merchants.md, "The merchant is the ONLY
## faucet"). It is closed: a producer's work earns the village GOODS, and
## the merchant pays for those.
##
## The three functions and their derivation are kept, still tested, because
## the reasoning below is worth having written down if a levy is ever
## wanted again -- but nothing in src/ calls them, and
## test_the_old_levy_arithmetic_is_not_wired_to_anything fails if anything
## starts. What IS live here is the subsistence wage (paid out of the
## purse) and estate_tax_for/tax_debits (paid into it, out of real
## wallets).
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
const VillageEstates = preload("res://src/emergence/village_estates.gd")
const SettlementState = preload("res://src/emergence/settlement_state.gd")
const HouseholdWellbeing = preload("res://src/emergence/household_wellbeing.gd")

## docs/concept/village_economy_balance.md mechanism 1: a day's work earns
## a day's keep and as much again to put by.
##
## Pinned by the PROPERTY it produces rather than by its value
## (test_village_living_wage.gd): a paid household that buys its meals saves
## exactly its keep, and reaches HouseholdWellbeing's full purse inside the
## wait assessments_to_full_purse derives -- simulated, not asserted.
const LIVING_WAGE_KEEP_MULTIPLE := 2.0


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


## What one household's meals cost over ONE settlement assessment: the
## measured draw (SettlementState.FOOD_PER_HOUSEHOLD, off the villagers'
## own hunger clock) at the market's own price. Anchored to the assessment,
## the clock the draw itself was measured on, so no day-length constant
## enters here at all.
static func keep_per_assessment() -> float:
	return SettlementState.FOOD_PER_HOUSEHOLD * float(VillageMarket.VILLAGE_LOCAL_FOOD_PRICE)


## The living wage, per household per assessment (docs/concept/
## village_economy_balance.md mechanism 1). NOT the subsistence wage above:
## that one is the safety net, a meal for somebody found starving; this is
## what a worker is paid for the work, whether or not they are hungry.
static func living_wage_per_assessment() -> float:
	return keep_per_assessment() * LIVING_WAGE_KEEP_MULTIPLE


## How many assessments a household on the living wage, buying its own
## meals, takes to reach HouseholdWellbeing's full purse from nothing --
## the readout the whole wage exists to move. INF if the wage does not
## clear the keep, which is the honest answer for a wage nobody could save
## on.
static func assessments_to_full_purse() -> float:
	var saved_per_assessment := living_wage_per_assessment() - keep_per_assessment()
	if saved_per_assessment <= 0.0:
		return INF
	var full_purse := float(HouseholdWellbeing.INCOME_MEALS_FOR_FULL * VillageMarket.VILLAGE_LOCAL_FOOD_PRICE)
	return full_purse / saved_per_assessment


## The whole village's bill over `assessments`: every household is a worker
## (one villager to a household, every villager with a trade). Nobody, or
## no time, owes nothing rather than going negative -- the same clamp
## estate_tax_for keeps.
static func wage_bill_for(household_count: int, assessments: float) -> float:
	if household_count <= 0 or assessments <= 0.0:
		return 0.0
	return float(household_count) * living_wage_per_assessment() * assessments


## Who gets the `coins` a settlement can really pay this assessment, given
## the households' `balances` in whole gold: one payout per balance, in the
## order given, the same shape tax_debits keeps for the other direction.
##
## Split as evenly as whole coins allow, the remainder to the POOREST first
## (balance, then position, so the answer is deterministic): when the purse
## cannot cover the whole bill, it is the household with nothing in hand
## that gets the coin. The payouts add up to exactly `coins` -- a payout can
## neither invent a coin nor lose one -- and a nonsense demand pays nobody.
static func wage_payouts(balances: Array, coins: int) -> Array:
	var payouts: Array = []
	for _balance in balances:
		payouts.append(0)
	if coins <= 0 or balances.is_empty():
		return payouts
	var each := coins / balances.size()
	var remainder := coins - each * balances.size()
	for index in balances.size():
		payouts[index] = each
	var order: Array = []
	for index in balances.size():
		order.append([int(balances[index]), index])
	order.sort()
	for rank in remainder:
		payouts[int(order[rank][1])] += 1
	return payouts


## docs/concept/village_estates.md mechanism 6: what a village's own
## households pay into this same purse over `days`.
##
## Deliberately the SAME purse the subsistence wage already comes out of,
## rather than a second treasury -- which is exactly what closes the estate
## loop on machinery that already exists: supply the baskets, households
## rise, a risen household pays more tax, the purse funds the wages and the
## next building, the building supplies the baskets.
##
## `estate_counts` is a real estate census (HouseholdStore.estate_census);
## `provision_by_estate` is how well each estate is actually being kept,
## in [0, 1] -- EstateConsumption's own reading. An estate whose provision
## nobody reported is taxed as DESTITUTE rather than as provided: the same
## destitute default every other estate module takes, and the only one that
## cannot invent revenue out of missing information.
##
## A destitute village raises nothing however many live in it. That is
## Anno's own shape and the real one: there is no surplus to take, so a
## village that stops supplying its people also stops being able to pay for
## anything -- which is the pressure that makes the whole loop a loop
## rather than a one-way ratchet.
static func estate_tax_for(
	estate_counts: Dictionary, provision_by_estate: Dictionary, days: float
) -> float:
	if days <= 0.0:
		return 0.0
	var take := 0.0
	for estate in estate_counts:
		var households := float(estate_counts[estate])
		if households <= 0.0:
			continue
		var provision := float(provision_by_estate.get(estate, 0.0))
		take += VillageEstates.tax_per_day(estate, provision) * households * days
	return take


## What each household actually hands over, given their `balances` in whole
## gold and a whole-coin `owed`.
##
## Tax is a TRANSFER, not a faucet (docs/concept/traveling_merchants.md,
## "The merchant is the ONLY faucet"). estate_tax_for says what a village is
## OWED; this says what it can really collect, and the caller takes exactly
## these coins out of exactly these wallets before crediting the purse.
## Without it, _collect_estate_tax credited the purse and debited nobody,
## which made it a second place gold came from nothing.
##
## One debit per balance, in the order given, so a caller maps each back to
## the household it came from without a second key -- the same shape
## SettlementSurplus.allocate keeps for the merchant's own sale.
##
## Two rules worth stating because they are deliberate:
##
## - **Nobody is ever debited more than they hold.** That single property is
##   what makes this a transfer: collecting can never invent a coin.
## - **A village collects what is there, not what it is due.** Households
##   short of coin pay what they have and the rest is simply not collected;
##   the shortfall is NOT banked as arrears. A debt a household can never
##   pay is a number that only grows, and it would make the purse's balance
##   a fiction again -- which is the very thing this closes.
static func tax_debits(balances: Array, owed: int) -> Array:
	var debits: Array = []
	for _balance in balances:
		debits.append(0)
	var remaining := owed
	if remaining <= 0:
		return debits
	for index in balances.size():
		if remaining <= 0:
			break
		var held := int(balances[index])
		if held <= 0:
			continue
		var take := mini(held, remaining)
		debits[index] = take
		remaining -= take
	return debits
