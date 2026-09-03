extends GutTest

## What a villager pays you, derived from what they actually hold.
##
## docs/concept/quests.md is explicit that this is the part the Contract
## substrate does NOT give for free: `Contract.consideration` is a String and
## nothing in the codebase interprets it. So the reward has to be a real
## number computed from real state, and -- the claim that matters -- computed
## AGAIN at fulfilment rather than trusted from the offer, so "a villager who
## went broke while you were away pays less, and says so" is behaviour rather
## than flavour text.

const QuestReward = preload("res://src/dialogue/quest_reward.gd")
const VillageWages = preload("res://src/world/village_wages.gd")


## The reward is quoted in the one price this simulation genuinely holds --
## a meal at the village market's own price -- and never in an invented gold
## table for raw materials no shop stocks.
func test_the_unit_value_is_anchored_to_the_subsistence_wage():
	assert_eq(
		QuestReward.full_gold_for(1),
		ceili(
			QuestReward.MEALS_PER_UNIT
			* (1.0 + QuestReward.RELATIONSHIP_PREMIUM)
			* float(VillageWages.subsistence_wage())
		)
	)


## quests.md: paying "roughly what they'd have paid the market, PLUS a
## relationship premium". Without the premium, doing the errand is strictly
## worse than selling the same goods, and nobody would ever take one.
func test_the_premium_puts_the_offer_above_the_bare_meal_price():
	assert_gt(QuestReward.full_gold_for(1), VillageWages.subsistence_wage())


func test_more_of_the_same_thing_is_worth_more():
	assert_gt(QuestReward.full_gold_for(3), QuestReward.full_gold_for(1))


func test_asking_for_nothing_is_worth_nothing():
	assert_eq(QuestReward.full_gold_for(0), 0)
	assert_eq(QuestReward.full_gold_for(-2), 0)


## The cap quests.md names: "capped at what they genuinely hold".
func test_the_reward_is_capped_at_what_the_payer_actually_holds():
	var reward := QuestReward.gold_for(3, 2)
	assert_eq(reward["amount"], 2)
	assert_eq(reward["full"], QuestReward.full_gold_for(3))


## A villager with money pays the whole thing and owes nothing.
func test_a_solvent_payer_owes_nothing():
	var reward := QuestReward.gold_for(1, 500)
	assert_eq(reward["amount"], QuestReward.full_gold_for(1))
	assert_eq(reward["short"], 0)
	assert_false(reward["is_short"])


## The number the sentence needs: not just "less", but how much less, so the
## villager can say it.
func test_a_short_payer_knows_exactly_how_short_they_are():
	var reward := QuestReward.gold_for(3, 2)
	assert_true(reward["is_short"])
	assert_eq(reward["short"], QuestReward.full_gold_for(3) - 2)


## A wallet cannot go negative, and neither can an apology.
func test_a_penniless_payer_offers_nothing_and_never_a_debt():
	var reward := QuestReward.gold_for(3, 0)
	assert_eq(reward["amount"], 0)
	assert_true(reward["is_short"])
	assert_eq(reward["short"], QuestReward.full_gold_for(3))

	var negative := QuestReward.gold_for(3, -10)
	assert_eq(negative["amount"], 0)


func test_the_reward_names_its_own_kind():
	assert_eq(QuestReward.gold_for(1, 10)["kind"], QuestReward.KIND_GOLD)


## The whole point of deriving rather than storing: the same offer, re-read
## against a poorer wallet, is a smaller reward. Nothing had to expire or be
## rewritten for that to happen.
func test_the_same_errand_pays_less_once_the_payer_is_poorer():
	var before := QuestReward.gold_for(2, 100)
	var after := QuestReward.gold_for(2, 1)
	assert_gt(before["amount"], after["amount"])
	assert_false(before["is_short"])
	assert_true(after["is_short"])
