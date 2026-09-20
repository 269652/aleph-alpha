extends GutTest

## docs/concept/village_economy_balance.md mechanism 1: a worker is PAID
## for a day's work, not fed when found starving.
##
## Measured before this existed (tools/probe_village_economy.gd): a purse
## reading 0 -> 20 -> 1 -> 1 -> 19 -> 1, wallets 0 at every sample, ten of
## ten villagers broke, and "worst: income" permanent -- the only wage in
## the game was the meal a villager could not afford, so the income need
## (ten meals in hand) could never rise off the floor.
##
## Pure: VillageWages is a static module and every number here is derived
## from the draw the settlement economy was measured against.

const VillageWages = preload("res://src/world/village_wages.gd")
const VillageMarket = preload("res://src/world/village_market.gd")
const SettlementState = preload("res://src/emergence/settlement_state.gd")
const HouseholdWellbeing = preload("res://src/emergence/household_wellbeing.gd")
const MerchantVisit = preload("res://src/emergence/merchant_visit.gd")
const Wallet = preload("res://src/gameplay/wallet.gd")


# -- the keep and the wage ----------------------------------------------------

## The keep is what a household's meals cost over one assessment: the real
## measured draw at the market's own price, and nothing else.
func test_the_keep_is_the_measured_draw_at_the_markets_own_price():
	assert_almost_eq(
		VillageWages.keep_per_assessment(),
		SettlementState.FOOD_PER_HOUSEHOLD * float(VillageMarket.VILLAGE_LOCAL_FOOD_PRICE),
		0.0001
	)


func test_a_worker_paid_the_living_wage_nets_something_after_eating():
	assert_gt(VillageWages.living_wage_per_assessment(), VillageWages.keep_per_assessment())


## The multiple is pinned by the property it produces, not by its value: a
## paid household that buys its meals puts by exactly its keep -- "a day's
## work earns a day's keep and as much again".
func test_a_paid_household_that_buys_its_meals_saves_exactly_its_keep():
	var saved: float = VillageWages.living_wage_per_assessment() - VillageWages.keep_per_assessment()
	assert_almost_eq(saved, VillageWages.keep_per_assessment(), 0.0001)


## And what that does to the readout the report was looking at: the income
## need is a purse of INCOME_MEALS_FOR_FULL meals, and a household on the
## living wage reaches it from nothing inside the number of assessments the
## module itself derives -- simulated, not asserted.
func test_a_household_on_the_living_wage_reaches_a_full_purse_when_the_module_says_it_will():
	var assessments: float = VillageWages.assessments_to_full_purse()
	assert_true(assessments > 0.0 and is_finite(assessments), "a bounded wait: %s" % assessments)
	var wallet := Wallet.new()
	var carry := 0.0
	var steps := 0
	var full := false
	while steps < int(ceil(assessments)) + 1:
		carry += VillageWages.living_wage_per_assessment() - VillageWages.keep_per_assessment()
		var coins := int(floor(carry))
		carry -= float(coins)
		wallet.add(coins)
		steps += 1
		var need: Dictionary = HouseholdWellbeing.assess({
			"wallet_balance": wallet.balance,
			"meal_price": VillageMarket.VILLAGE_LOCAL_FOOD_PRICE,
		})["needs"]
		if is_equal_approx(float(need["income"]), 1.0):
			full = true
			break
	assert_true(full, "a paid household never reached a full purse in %d assessments" % steps)
	assert_true(
		steps >= int(floor(assessments)),
		"it filled sooner than the derivation says (%d < %s), so the derivation is wrong" % [steps, assessments]
	)


## In lived days that is a wait a player watches out, not a season: shorter
## than two of the merchant's own rounds (his cover is the longest a village
## worth the detour waits between sales).
func test_a_full_purse_arrives_within_two_of_the_merchants_rounds():
	var seconds: float = VillageWages.assessments_to_full_purse() * SettlementState.ASSESSMENT_SECONDS
	assert_lt(seconds, 2.0 * MerchantVisit.cover_seconds())


# -- the bill -------------------------------------------------------------------

func test_the_bill_is_every_household_paid_the_living_wage_over_the_span():
	assert_almost_eq(
		VillageWages.wage_bill_for(10, 1.0), 10.0 * VillageWages.living_wage_per_assessment(), 0.0001
	)
	assert_almost_eq(
		VillageWages.wage_bill_for(3, 4.0), 12.0 * VillageWages.living_wage_per_assessment(), 0.0001
	)


func test_a_village_with_nobody_in_it_and_a_span_of_no_time_each_owe_nothing():
	assert_almost_eq(VillageWages.wage_bill_for(0, 5.0), 0.0, 0.0001)
	assert_almost_eq(VillageWages.wage_bill_for(-4, 5.0), 0.0, 0.0001)
	assert_almost_eq(VillageWages.wage_bill_for(6, 0.0), 0.0, 0.0001)
	assert_almost_eq(VillageWages.wage_bill_for(6, -1.0), 0.0, 0.0001)


# -- the payout: who gets the coins -------------------------------------------

func test_a_bill_the_coins_cover_is_split_evenly():
	assert_eq(VillageWages.wage_payouts([0, 0, 0], 12), [4, 4, 4])


## The remainder goes to the poorest: when the purse cannot cover the whole
## bill, it is the household with nothing in hand that gets the coin.
func test_the_remainder_goes_to_the_poorest_first():
	assert_eq(VillageWages.wage_payouts([5, 0, 3], 7), [2, 3, 2])
	assert_eq(VillageWages.wage_payouts([5, 0, 3], 2), [0, 1, 1])


func test_ties_between_equally_poor_households_break_by_position():
	assert_eq(VillageWages.wage_payouts([2, 2, 2], 1), [1, 0, 0])
	assert_eq(VillageWages.wage_payouts([2, 2, 2], 2), [1, 1, 0])


## What is handed out is exactly what was there to hand out: a payout can
## neither invent a coin nor lose one.
func test_the_payouts_add_up_to_exactly_the_coins():
	for coins in [0, 1, 5, 9, 10, 23, 100]:
		var payouts: Array = VillageWages.wage_payouts([7, 0, 12, 3, 0], coins)
		var total := 0
		for payout in payouts:
			total += int(payout)
		assert_eq(total, coins, "%d coins" % coins)


func test_nobody_is_ever_paid_a_negative_wage():
	for payout in VillageWages.wage_payouts([1, 2, 3], -8):
		assert_eq(int(payout), 0)
	assert_eq(VillageWages.wage_payouts([], 10), [])


func test_one_payout_per_household_in_the_order_given():
	assert_eq(VillageWages.wage_payouts([9, 1, 4, 4], 0).size(), 4)
	assert_eq(VillageWages.wage_payouts([9, 1, 4, 4], 6), [1, 2, 2, 1])


func test_the_payout_is_deterministic():
	var first: Array = VillageWages.wage_payouts([3, 3, 0, 8], 7)
	for _i in 4:
		assert_eq(VillageWages.wage_payouts([3, 3, 0, 8], 7), first)
