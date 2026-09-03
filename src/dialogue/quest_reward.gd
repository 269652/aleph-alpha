extends RefCounted

## What a villager pays for an errand, derived from what they actually hold
## (docs/concept/quests.md, "Rewards are derived, and re-derived").
##
## ## Why this module has to exist at all
##
## The often-repeated claim that "accepting a quest gives you deadline,
## failure and persistence for free because Contract already exists" is only
## two-thirds true. `Contract.obligations` is `Array[String]`,
## `Contract.consideration` is a `String`, and NOTHING in this codebase
## interprets either of them -- they are free-form prose by that module's own
## design note. So persistence and traceability come free; the number does
## not. This is the number.
##
## ## Why the reward is quoted in meals
##
## There is no price for a raw material anywhere in this simulation.
## `Shop.CATALOG` prices five finished goods (fishing_rod, torch,
## cooked_meat, leather_helm, iron_sword) and not one recipe input, so
## `Shop.market_price_of("rock", market)` is 0 -- and every item a household
## shortfall ever names is a raw input (wood, hide, stone, rock, plant_fibre,
## iron_ore, coal, log, stick). `Market.price_for` is a scarcity MULTIPLIER,
## not a price, and it is pinned at its ceiling for exactly the items a
## shortfall names, because a shortfall IS a stock of zero -- so it cannot
## discriminate between errands either.
##
## The one price this world genuinely holds is `VillageWages.
## subsistence_wage()`: one meal at the village market's own price. So a
## reward is quoted in MEALS and converted, rather than read off a gold table
## for materials nothing stocks. That is the honest grounding available
## today; if a real materials market ever exists, this is the one function
## that changes.
##
## ## Why it is derived and never stored
##
## `gold_for` is called at the offer AND again at fulfilment, against
## whatever the payer holds at that moment. Nothing persists the amount, so
## a villager who went broke while you were away genuinely pays less -- and
## `short` is how much less, so they can say so rather than silently
## shortchanging you. That behaviour costs nothing to implement precisely
## because the reward was never stored.
##
## Pure static module -- numbers in, numbers out. No store, no Node.

const VillageWages = preload("res://src/world/village_wages.gd")

## The only reward kind that is real. quests.md's Consequences section also
## names softened shop prices and skill-web discounts as settlement-level
## rewards; both need `factions.md`'s reputation aggregate, which is not
## built, so neither is offered here rather than being stubbed.
const KIND_GOLD := "gold"

## What one fetched unit is worth to someone who cannot fetch it themselves,
## in subsistence meals -- one day's food for one villager per unit hauled.
## Pinned by test_the_unit_value_is_anchored_to_the_subsistence_wage rather
## than left as a comment.
const MEALS_PER_UNIT := 1.0

## quests.md: the NPC pays "roughly what they'd have paid the market, plus a
## relationship premium, for you to skip the market and hand the input to
## them directly." The premium is load-bearing: without it the errand pays
## exactly what selling the same goods would, and no player would ever take
## one. Pinned by test_the_premium_puts_the_offer_above_the_bare_meal_price.
const RELATIONSHIP_PREMIUM := 0.5


## What the errand is worth before anyone's ability to pay is considered.
## Zero for an empty or nonsensical ask -- an errand for nothing is not a
## debt.
static func full_gold_for(count: int) -> int:
	if count <= 0:
		return 0
	return ceili(
		float(count) * MEALS_PER_UNIT * (1.0 + RELATIONSHIP_PREMIUM)
		* float(VillageWages.subsistence_wage())
	)


## The reward as it stands RIGHT NOW, against this payer's current gold.
##
## `amount` is what actually changes hands, `full` what the errand is worth,
## and `short` the difference -- the number the apology is made of. A payer
## with a negative balance (which no Wallet produces, but a caller reading a
## stale or absent source might hand over) pays nothing rather than being
## owed something.
static func gold_for(count: int, payer_gold: int) -> Dictionary:
	var full := full_gold_for(count)
	var payable := maxi(payer_gold, 0)
	var amount := mini(full, payable)
	return {
		"kind": KIND_GOLD,
		"amount": amount,
		"full": full,
		"short": full - amount,
		"is_short": amount < full,
	}
