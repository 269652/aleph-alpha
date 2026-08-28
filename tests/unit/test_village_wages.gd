extends GutTest

## VillageWages: the shared village purse that gives a NON-producer
## occupation a real gold source for the first time.
##
## Before this, NpcEconomy only ever credited a wallet inside _gather(),
## which is gated on NpcProduction.is_producer() -- so the five
## non-producer occupations in NpcIdentity.OCCUPATIONS started at zero
## gold, could never afford VillageMarket.VILLAGE_LOCAL_FOOD_PRICE, and
## therefore stayed permanently hungry forever. Hunger was an occupation
## constant, not an economy.
##
## Everything asserted here is anchored to a LIVE constant of another
## module (the real occupation census, the market's real meal price,
## NpcProduction.YIELD_TO_GOLD_RATE) and recomputed in the test rather
## than copied as a literal, so the two can never silently drift apart --
## same discipline as VillageMarket's own
## test_village_local_price_is_below_shops_cooked_meat_price.

const VillageWages = preload("res://src/world/village_wages.gd")
const NpcIdentity = preload("res://src/world/npc_identity.gd")
const NpcProduction = preload("res://src/world/npc_production.gd")
const VillageMarket = preload("res://src/world/village_market.gd")
const Wallet = preload("res://src/gameplay/wallet.gd")

const EPSILON := 0.0001


## The real occupation census, recounted here from the two live source
## dictionaries rather than trusting VillageWages' own count -- this is
## the anchor the wage share is derived from, so the test has to build it
## independently for the assertion to mean anything.
func _census() -> Dictionary:
	var producers := 0
	var non_producers := 0
	for occupation in NpcIdentity.OCCUPATIONS:
		if NpcProduction.PRODUCER_ITEM_BY_OCCUPATION.has(occupation):
			producers += 1
		else:
			non_producers += 1
	return {"producers": producers, "non_producers": non_producers}


func test_the_census_this_module_is_anchored_to_is_the_real_occupation_list():
	var census := _census()
	assert_eq(
		VillageWages.producer_occupation_count(),
		census["producers"],
		"producer count must be read off NpcProduction's real producer table"
	)
	assert_eq(
		VillageWages.non_producer_occupation_count(),
		census["non_producers"],
		"non-producer count must be read off NpcIdentity's real occupation list"
	)
	assert_gt(census["producers"], 0, "the real census must actually contain producers")
	assert_gt(census["non_producers"], 0, "the real census must actually contain non-producers")


## THE WAGE_SHARE ANCHOR, stated as a number: the share levied off a
## producer is exactly the non-producer share of the real occupation
## census (NpcIdentity.OCCUPATIONS minus NpcProduction's producer table),
## not a chosen fraction.
func test_wage_share_is_the_non_producer_share_of_the_real_occupation_census():
	var census := _census()
	var expected := float(census["non_producers"]) / float(census["producers"] + census["non_producers"])
	assert_almost_eq(
		VillageWages.wage_share(),
		expected,
		EPSILON,
		"wage share must be the live non-producer fraction of NpcIdentity.OCCUPATIONS"
	)


## THE WAGE_SHARE ANCHOR, stated as the behaviour it exists for: with the
## real census producing, the purse holds exactly enough that every
## non-producer's cut equals what a producer kept. One levy rate, derived,
## makes village income neutral between working a producing occupation and
## a non-producing one -- which is the only rate that isn't a guess.
func test_the_wage_share_leaves_a_producer_exactly_what_it_gives_each_non_producer():
	var census := _census()
	var gross := 1.0
	var purse := 0.0
	for i in census["producers"]:
		purse = VillageWages.deposit(purse, gross)
	var per_non_producer := purse / float(census["non_producers"])
	assert_almost_eq(
		per_non_producer,
		VillageWages.take_home_of(gross),
		EPSILON,
		"the levy must leave a producer exactly the purse's per-non-producer share"
	)


func test_the_split_creates_and_destroys_no_gold():
	for gross in [0.5, 1.0, 3.0, 17.25]:
		assert_almost_eq(
			VillageWages.levy_on(gross) + VillageWages.take_home_of(gross),
			gross,
			EPSILON,
			"levy plus take-home must be exactly the gross earnings"
		)


func test_a_producer_still_keeps_a_real_share_of_what_they_earn():
	assert_gt(VillageWages.take_home_of(1.0), 0.0, "the purse must not swallow a producer's whole income")
	assert_gt(VillageWages.levy_on(1.0), 0.0, "a producing household must actually fund the purse")


## THE SUBSISTENCE ANCHOR: one wage is exactly one meal at the market's
## own real price -- asserted against the live constant, so if
## VILLAGE_LOCAL_FOOD_PRICE ever moves, the wage moves with it.
func test_one_subsistence_wage_is_exactly_one_meal_at_the_markets_own_price():
	assert_eq(
		VillageWages.subsistence_wage(),
		VillageMarket.VILLAGE_LOCAL_FOOD_PRICE,
		"a subsistence wage must be exactly one live village-local meal price"
	)


## The same anchor proven through the real market rather than the
## constant: a villager paid exactly one wage can buy exactly one real
## meal, and is broke again immediately after. Subsistence, not savings.
func test_a_villager_paid_one_wage_can_buy_exactly_one_real_meal_and_no_more():
	var market := VillageMarket.new()
	market.add_stock("fruit", 10.0)
	var wallet := Wallet.new()
	var payout: Dictionary = VillageWages.pay_subsistence(float(VillageWages.subsistence_wage()))
	wallet.add(payout["paid"])
	assert_ne(market.buy_meal(wallet), "", "one subsistence wage must cover one real market meal")
	assert_eq(wallet.balance, 0, "a subsistence wage is exactly one meal, with nothing left over")
	assert_eq(market.buy_meal(wallet), "", "it must not stretch to a second meal")


## THE RATE ANCHOR, in the units the simulation actually ticks in: how
## many real gathered food units of producer income one non-producer meal
## costs the village, computed from the live YIELD_TO_GOLD_RATE and the
## live meal price rather than asserted as a magic number.
func test_a_producer_funds_one_meal_wage_after_a_derived_number_of_real_food_units():
	var per_unit := float(NpcProduction.YIELD_TO_GOLD_RATE)
	var units := int(ceil(VillageWages.gross_earnings_per_wage() / per_unit))
	assert_gt(units, 0, "funding a wage must take at least one real gathered unit")
	var purse := 0.0
	for i in units - 1:
		purse = VillageWages.deposit(purse, per_unit)
	assert_false(
		VillageWages.can_pay_subsistence(purse),
		"the purse must not cover a wage one whole food unit early"
	)
	purse = VillageWages.deposit(purse, per_unit)
	assert_true(
		VillageWages.can_pay_subsistence(purse),
		"the derived unit count must be exactly when the purse can first pay"
	)


func test_deposit_accrues_only_the_purses_share_of_the_earnings():
	assert_almost_eq(
		VillageWages.deposit(0.0, 4.0),
		VillageWages.levy_on(4.0),
		EPSILON,
		"a deposit must add the levy, not the whole gross"
	)
	assert_almost_eq(
		VillageWages.deposit(10.0, 4.0),
		10.0 + VillageWages.levy_on(4.0),
		EPSILON,
		"a deposit must accrue on top of what the purse already holds"
	)


## Mirrors Wallet.add's own clamp-to-no-op contract rather than inventing
## a different one for negative input.
func test_deposit_ignores_zero_and_negative_earnings():
	assert_almost_eq(VillageWages.deposit(3.0, 0.0), 3.0, EPSILON, "zero earnings must not move the purse")
	assert_almost_eq(VillageWages.deposit(3.0, -5.0), 3.0, EPSILON, "negative earnings must not drain the purse")


func test_an_empty_purse_pays_nothing():
	var payout: Dictionary = VillageWages.pay_subsistence(0.0)
	assert_eq(payout["paid"], 0, "an empty purse must pay no wage")
	assert_almost_eq(float(payout["purse"]), 0.0, EPSILON, "an empty purse must stay empty")
	assert_false(VillageWages.can_pay_subsistence(0.0), "an empty purse cannot pay")


## All-or-nothing, exactly like Wallet.spend and VillageMarket.remove_stock:
## a part-wage would let a villager pay part of a meal price, which the
## market has no notion of.
func test_a_purse_short_of_a_whole_wage_pays_nothing_rather_than_a_partial_wage():
	var short := float(VillageWages.subsistence_wage()) - 0.5
	var payout: Dictionary = VillageWages.pay_subsistence(short)
	assert_eq(payout["paid"], 0, "a short purse must pay nothing at all")
	assert_almost_eq(float(payout["purse"]), short, EPSILON, "a refused payout must leave the purse untouched")


func test_paying_a_wage_leaves_the_exact_remainder():
	var purse := float(VillageWages.subsistence_wage()) + 1.25
	var payout: Dictionary = VillageWages.pay_subsistence(purse)
	assert_eq(payout["paid"], VillageWages.subsistence_wage(), "a funded purse must pay one whole wage")
	assert_almost_eq(float(payout["purse"]), 1.25, EPSILON, "the purse must lose exactly the wage it paid")


func test_the_purse_can_never_go_negative_however_often_it_is_drawn():
	var purse := 10.0
	var paid_total := 0
	for i in 50:
		var payout: Dictionary = VillageWages.pay_subsistence(purse)
		purse = float(payout["purse"])
		paid_total += int(payout["paid"])
		assert_true(purse >= 0.0, "the purse must never go negative (iteration %d)" % i)
	assert_eq(
		paid_total,
		int(10.0 / float(VillageWages.subsistence_wage())) * VillageWages.subsistence_wage(),
		"a purse must pay out whole wages until it runs dry, then stop"
	)


## The degenerate village the survey found everywhere: nobody produces, so
## nothing is ever levied and the purse can fund no one. It must fail
## quietly to zero, not divide by zero or hand out gold from nowhere.
func test_a_village_with_no_producers_accrues_nothing_and_pays_no_one():
	var purse := 0.0
	for i in 100:
		purse = VillageWages.deposit(purse, 0.0)  # no producer, so no gross income ever arrives
	assert_almost_eq(purse, 0.0, EPSILON, "a village with no producers must accrue no purse")
	var payout: Dictionary = VillageWages.pay_subsistence(purse)
	assert_eq(payout["paid"], 0, "a village with no producers must pay no wage")


func test_wage_share_for_a_village_with_nobody_to_support_levies_nothing():
	assert_almost_eq(
		VillageWages.wage_share_for(3, 0),
		0.0,
		EPSILON,
		"with no non-producers to support, a producer keeps everything"
	)


func test_wage_share_for_an_empty_village_is_zero_rather_than_undefined():
	assert_almost_eq(VillageWages.wage_share_for(0, 0), 0.0, EPSILON, "an empty census must not divide by zero")


func test_wage_share_for_a_village_of_only_non_producers_is_total_but_moot():
	assert_almost_eq(
		VillageWages.wage_share_for(0, 5),
		1.0,
		EPSILON,
		"with no producers the share is total -- and moot, since no income ever arrives"
	)


func test_wage_share_never_leaves_the_zero_to_one_range():
	for producers in range(0, 6):
		for non_producers in range(0, 6):
			var share := VillageWages.wage_share_for(producers, non_producers)
			assert_between(share, 0.0, 1.0, "share for %d/%d must be a real fraction" % [producers, non_producers])


## Nonsense input is CLAMPED to nobody, not special-cased into its own
## rate -- the same convention Wallet.add and VillageMarket.add_stock use
## for a negative amount. So a negative headcount degrades to the already
## documented "none of those" census rather than a negative share.
func test_a_negative_headcount_counts_as_nobody_rather_than_a_nonsense_rate():
	assert_almost_eq(
		VillageWages.wage_share_for(-3, 2),
		VillageWages.wage_share_for(0, 2),
		EPSILON,
		"a negative producer count must clamp to a village with no producers"
	)
	assert_almost_eq(
		VillageWages.wage_share_for(3, -2),
		VillageWages.wage_share_for(3, 0),
		EPSILON,
		"a negative non-producer count must clamp to a village with nobody to support"
	)
	assert_almost_eq(
		VillageWages.wage_share_for(-3, -2),
		0.0,
		EPSILON,
		"an entirely nonsense census must levy nothing at all"
	)
