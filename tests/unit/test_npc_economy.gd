extends GutTest

## NpcEconomy (docs/concept/npc.md "Needs and the local production
## economy"): ties one NPC's hunger (NpcNeeds), gold (Wallet), and the
## local production economy together. A producer gathers real food into
## its village's shared VillageMarket while working and earns real gold
## doing it; anyone who goes hungry tries a free bite from their own
## production (producers only, and only while genuinely producing
## something right now) or else buys a meal from the shared market with
## their own gold. An NPC that can't get fed genuinely stays hungry -- no
## death/lifecycle consequence is wired to that yet (deliberately out of
## scope this pass).

const NpcEconomy = preload("res://src/world/npc_economy.gd")
const NpcNeeds = preload("res://src/world/npc_needs.gd")
const VillageMarket = preload("res://src/world/village_market.gd")
const NpcProduction = preload("res://src/world/npc_production.gd")

## A world stub whose real-model reads are directly controllable, same
## shape as NpcProduction's own test stub.
class StubWorld:
	var vegetation_density := 0.6
	var herbivore_population := 10.0
	var fish_population := 8.0
	var harvested_amount := 0.0
	func vegetation_density_near(_pos: Vector2) -> float:
		return vegetation_density
	func herbivore_population_near(_pos: Vector2) -> float:
		return herbivore_population
	func fish_population_near(_pos: Vector2) -> float:
		return fish_population
	func record_vegetation_harvest_near(_pos: Vector2, amount: float) -> void:
		harvested_amount += amount


## A world exposing only the original accessor, not the new harvest hook --
## the exact shape an older/duck-typed caller would still have.
class BareWorld:
	func vegetation_density_near(_pos: Vector2) -> float:
		return 0.6


var market: VillageMarket
var world: StubWorld


func before_each():
	market = VillageMarket.new()
	world = StubWorld.new()


func _economy(occupation: String, seed_value: int = 1) -> NpcEconomy:
	return NpcEconomy.new(seed_value, occupation, market)


func test_hunger_rises_over_time_regardless_of_occupation():
	var economy := _economy("blacksmith")
	economy.step(1.0, false, world, Vector2.ZERO)
	assert_gt(economy.needs.hunger, 0.0)


func test_starts_with_an_empty_wallet():
	assert_eq(_economy("hunter").wallet.balance, 0)


## The core production loop: a hunter working gathers real food into the
## shared village market and earns real gold, using the same real
## HerbivorePopulationModel-driven number NpcProduction reads.
func test_a_working_producer_gathers_into_the_market_and_earns_gold():
	var economy := _economy("hunter")
	for i in 200:
		economy.step(1.0, true, world, Vector2.ZERO)  # is_working = true, plenty of real seconds
	assert_gt(market.total_stock(), 0.0)
	assert_gt(economy.wallet.balance, 0)


func test_a_non_working_producer_gathers_nothing():
	var economy := _economy("hunter")
	for i in 200:
		economy.step(1.0, false, world, Vector2.ZERO)  # never actually working
	assert_eq(market.total_stock(), 0.0)
	assert_eq(economy.wallet.balance, 0)


func test_a_non_producer_never_gathers_even_while_working():
	var economy := _economy("blacksmith")
	for i in 200:
		economy.step(1.0, true, world, Vector2.ZERO)
	assert_eq(market.total_stock(), 0.0)
	assert_eq(economy.wallet.balance, 0)


## A producer takes a free bite from their own currently-active production
## when hungry -- no market/gold transaction.
func test_a_hungry_working_producer_self_feeds_for_free():
	var economy := _economy("hunter")
	economy.needs.advance(100000.0)
	assert_true(economy.needs.is_hungry())

	economy.step(0.01, true, world, Vector2.ZERO)

	assert_false(economy.needs.is_hungry(), "a working producer should have fed itself")
	assert_eq(economy.wallet.balance, 0, "self-feeding is free, not a purchase")


## Total ecological collapse (nothing left to gather) means even a producer
## has no free bite available -- they fall through to the paid market like
## anyone else.
func test_a_producer_with_zero_real_yield_cannot_self_feed():
	world.herbivore_population = 0.0
	var economy := _economy("hunter")
	economy.needs.advance(100000.0)

	economy.step(0.01, true, world, Vector2.ZERO)

	assert_true(economy.needs.is_hungry(), "no game left to hunt -- no free bite, and no market stock either")


## The core trade loop: a hungry non-producer spends real gold from their
## own wallet to buy real stock from the shared village market.
func test_a_hungry_non_producer_buys_from_the_market_when_stocked_and_can_afford():
	market.add_stock("meat", 5.0)
	var economy := _economy("blacksmith")
	economy.wallet.add(100)
	economy.needs.advance(100000.0)
	assert_true(economy.needs.is_hungry())

	economy.step(0.01, false, world, Vector2.ZERO)

	assert_false(economy.needs.is_hungry())
	assert_eq(economy.wallet.balance, 100 - VillageMarket.VILLAGE_LOCAL_FOOD_PRICE)
	assert_almost_eq(market.stock["meat"], 4.0, 0.001)


## The honest failure modes docs/concept/npc.md asks for: an NPC that can't
## get fed (empty stock, no gold) genuinely stays hungry -- no crash, no
## silent free pass.

func test_hungry_non_producer_stays_hungry_when_the_market_has_no_stock():
	var economy := _economy("blacksmith")
	economy.wallet.add(100)
	economy.needs.advance(100000.0)

	economy.step(0.01, false, world, Vector2.ZERO)

	assert_true(economy.needs.is_hungry())
	assert_eq(economy.wallet.balance, 100, "a failed purchase must not touch the wallet")


func test_hungry_non_producer_stays_hungry_when_they_have_no_gold():
	market.add_stock("meat", 5.0)
	var economy := _economy("blacksmith")
	economy.needs.advance(100000.0)

	economy.step(0.01, false, world, Vector2.ZERO)

	assert_true(economy.needs.is_hungry())
	assert_almost_eq(market.stock["meat"], 5.0, 0.001, "a failed purchase must not touch stock")


func test_a_sated_npc_does_not_buy_anything():
	market.add_stock("meat", 5.0)
	var economy := _economy("blacksmith")
	economy.wallet.add(100)

	economy.step(0.01, false, world, Vector2.ZERO)

	assert_eq(economy.wallet.balance, 100)
	assert_almost_eq(market.stock["meat"], 5.0, 0.001)


# -- a working farmer's real harvest reaches the world's land-health model ----
#
# docs/concept/world.md "Land health: overharvesting leaves a lasting mark,
# not just a slower respawn" -- a farmer NPC's gathered yield previously only
# READ vegetation_density_near, never actually removed anything from it (only
# weather ever moved that number). A real farmer working must now also feed
# EarthChunkManager's record_vegetation_harvest_near hook, the same real
# resource its own yield comes from -- so sustained NPC farming is a real
# depletion driver, not just the player's.

func test_a_working_farmer_records_a_real_vegetation_harvest():
	var economy := _economy("farmer")
	economy.step(1.0, true, world, Vector2.ZERO)
	assert_gt(world.harvested_amount, 0.0)


func test_a_non_working_farmer_records_no_harvest():
	var economy := _economy("farmer")
	economy.step(1.0, false, world, Vector2.ZERO)
	assert_eq(world.harvested_amount, 0.0)


## Only farmer reads/depletes vegetation -- hunter/fisher read a DIFFERENT
## resource pool (herbivore/fish population), so they must not also drain
## vegetation density.
func test_a_working_hunter_does_not_record_a_vegetation_harvest():
	var economy := _economy("hunter")
	economy.step(1.0, true, world, Vector2.ZERO)
	assert_eq(world.harvested_amount, 0.0)


## Dimensionally consistent with the yield actually gathered: the harvested
## amount over one step must equal yield_per_second * delta_seconds -- the
## exact same "fraction of standing vegetation converted to food" number the
## farmer's own production already computes, not a separately invented rate.
func test_farmer_harvest_amount_matches_the_real_yield_gathered():
	var economy := _economy("farmer")
	var expected := NpcProduction.new().yield_per_second("farmer", world, Vector2.ZERO) * 2.5
	economy.step(2.5, true, world, Vector2.ZERO)
	assert_almost_eq(world.harvested_amount, expected, 0.0001)


## Duck-typed fail-open: a world that doesn't expose the new hook (an older
## test double, or any other duck-typed caller) must not crash a working
## farmer's step -- same convention as the rest of this codebase's
## world-duck-typing (see NpcProduction.yield_per_second's own fail-open).
func test_a_working_farmer_does_not_crash_when_world_lacks_the_harvest_hook():
	var economy := _economy("farmer")
	economy.step(1.0, true, BareWorld.new(), Vector2.ZERO)
	pass_test("a working farmer against a world without the harvest hook should not crash")


# -- the village purse: a non-producer's first real gold source ---------------
#
# docs/concept/npc.md "Needs and the local production economy" says a
# non-producer "eat[s] by buying it, out of their own wallet" but never says
# where that wallet's gold comes from -- and NpcEconomy only ever credited a
# wallet inside _gather(), which is gated on NpcProduction.is_producer().
# Five of NpcIdentity.OCCUPATIONS' eight occupations therefore started at
# zero gold, could never afford VillageMarket.VILLAGE_LOCAL_FOOD_PRICE, and
# stayed hungry forever no matter what the weather, the harvest or the
# market stock did: hunger was an occupation constant, not an economy.
#
# VillageWages closes that: a producing household's gross gold is split, the
# village's share accrues in a shared purse, and a villager who cannot
# afford a meal draws one subsistence wage back out of it. Everything below
# is funded by a REAL hunter doing REAL work against the same real
# HerbivorePopulationModel-driven yield -- no gold is ever poked in by hand,
# so what feeds the blacksmith is literally a hunter's catch.

const VillageWages = preload("res://src/world/village_wages.gd")


## Runs a real producer on `a_market` for long enough to both stock it and
## fund its purse, exactly the way a village actually does it.
func _fund_village_with_a_real_hunters_work(a_market: VillageMarket, seconds: int = 60) -> NpcEconomy:
	var hunter := NpcEconomy.new(1, "hunter", a_market)
	for i in seconds:
		hunter.step(1.0, true, world, Vector2.ZERO)
	return hunter


## THE behaviour change: a penniless non-producer in a village whose
## producers have actually been working no longer starves.
func test_a_non_producer_in_a_village_with_a_funded_purse_stops_starving():
	_fund_village_with_a_real_hunters_work(market)
	assert_true(market.can_buy_meal(), "precondition: the hunter's catch really reached the market")

	var blacksmith := _economy("blacksmith")
	blacksmith.needs.advance(100000.0)
	assert_eq(blacksmith.wallet.balance, 0, "precondition: a non-producer owns no gold of their own")

	blacksmith.step(0.01, false, world, Vector2.ZERO)

	assert_false(
		blacksmith.needs.is_hungry(),
		"a village purse funded by a real hunter's catch must feed that village's blacksmith"
	)


## The other half of the same claim -- the wage is drawn from something
## real, so a village where nobody ever produced has nothing to pay with and
## its non-producers genuinely still starve. Stock alone is not income.
func test_a_non_producer_in_a_village_with_an_empty_purse_still_starves():
	market.add_stock("meat", 5.0)  # food on the shelf, but no producer ever earned for it
	var blacksmith := _economy("blacksmith")
	blacksmith.needs.advance(100000.0)

	blacksmith.step(0.01, false, world, Vector2.ZERO)

	assert_true(blacksmith.needs.is_hungry(), "an unfunded purse must not conjure a wage out of nothing")
	assert_eq(blacksmith.wallet.balance, 0, "a village that levied nothing has nothing to pay")
	assert_almost_eq(market.stock["meat"], 5.0, 0.001, "and the stock must be left untouched")


## Subsistence, not savings: the wage is exactly one meal at the market's
## own price, so it is gone again the instant it is used.
func test_a_drawn_wage_is_spent_on_the_meal_and_leaves_no_savings():
	_fund_village_with_a_real_hunters_work(market)
	var blacksmith := _economy("blacksmith")
	blacksmith.needs.advance(100000.0)

	blacksmith.step(0.01, false, world, Vector2.ZERO)

	assert_false(blacksmith.needs.is_hungry(), "precondition: the wage must have bought a real meal")
	assert_eq(blacksmith.wallet.balance, 0, "a subsistence wage is one meal exactly, with nothing left to hoard")


## The purse is per-SETTLEMENT, sharing exactly what VillageMarket already
## shares (one instance per village, see VillageRenderer.spawn_village) --
## a thriving village must not feed a stranger's.
func test_a_village_purse_feeds_only_its_own_settlement():
	_fund_village_with_a_real_hunters_work(market)

	var other_market := VillageMarket.new()
	other_market.add_stock("meat", 5.0)
	var outsider := NpcEconomy.new(1, "blacksmith", other_market)
	outsider.needs.advance(100000.0)
	outsider.step(0.01, false, world, Vector2.ZERO)
	assert_true(outsider.needs.is_hungry(), "one village's purse must never pay another village's blacksmith")

	var local := _economy("blacksmith")
	local.needs.advance(100000.0)
	local.step(0.01, false, world, Vector2.ZERO)
	assert_false(local.needs.is_hungry(), "...while the funded village's own blacksmith eats")


## The funding side, anchored to VillageWages' own derived rate rather than
## a literal: a producer now banks their take-home share, not the whole
## gross -- and still banks something real, so the levy cannot quietly
## swallow a producing household's entire income. Tolerance is one whole
## gold because take-home accrues fractionally and a Wallet holds only whole
## gold (see the carry in NpcEconomy._gather).
func test_a_producer_keeps_only_their_take_home_share_of_what_they_earn():
	var hunter := _economy("hunter")
	for i in 100:
		hunter.step(1.0, true, world, Vector2.ZERO)

	# Every gathered unit went to the market -- a working hunter self-feeds
	# for free and never buys any of it back.
	var gross := market.total_stock() * float(NpcProduction.YIELD_TO_GOLD_RATE)
	assert_gt(gross, 0.0, "precondition: the hunter really earned something")
	assert_gt(hunter.wallet.balance, 0, "a producer must still earn real gold after the village takes its share")
	assert_almost_eq(
		float(hunter.wallet.balance),
		VillageWages.take_home_of(gross),
		1.0,
		"a producer banks VillageWages' take-home share of the gross, not all of it"
	)


## The purse is observable, starts empty, and holds exactly VillageWages'
## levy on what its producers really earned -- stated against the live rate
## rather than a copied number, so NpcEconomy's split and VillageWages' own
## definition of it can never drift apart.
func test_a_village_purse_starts_empty_and_holds_exactly_the_levy_on_real_producer_income():
	assert_almost_eq(NpcEconomy.purse_of(market), 0.0, 0.0001, "a village starts with no savings at all")

	_fund_village_with_a_real_hunters_work(market)

	var gross := market.total_stock() * float(NpcProduction.YIELD_TO_GOLD_RATE)
	assert_almost_eq(
		NpcEconomy.purse_of(market),
		VillageWages.levy_on(gross),
		0.0001,
		"the purse must hold exactly the levy on what its producers really earned"
	)


## A wage buys a meal, so a village with nothing left to sell must not pay
## one -- otherwise a famine quietly drains a settlement's savings into
## villagers' pockets and buys nobody anything. VillageMarket.buy_meal is
## already all-or-nothing for the same reason (see its own doc comment);
## paying the wage first would sidestep that.
func test_an_empty_market_does_not_pay_out_a_wage_for_a_meal_that_does_not_exist():
	_fund_village_with_a_real_hunters_work(market)
	market.stock.clear()  # the village has eaten through everything it had
	var funded_purse := NpcEconomy.purse_of(market)
	assert_gt(funded_purse, 0.0, "precondition: the purse really is funded")

	var blacksmith := _economy("blacksmith")
	blacksmith.needs.advance(100000.0)

	blacksmith.step(0.01, false, world, Vector2.ZERO)

	assert_true(blacksmith.needs.is_hungry(), "there is nothing to buy, so nobody gets fed")
	assert_eq(blacksmith.wallet.balance, 0, "a wage must not be paid for a meal that does not exist")
	assert_almost_eq(
		NpcEconomy.purse_of(market),
		funded_purse,
		0.0001,
		"a famine must not quietly drain the village's savings into pockets"
	)
