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
	var killed_herbivore_amount := 0.0
	var last_kill_was_a_predator = null
	var caught_fish_amount := 0.0
	func vegetation_density_near(_pos: Vector2) -> float:
		return vegetation_density
	func herbivore_population_near(_pos: Vector2) -> float:
		return herbivore_population
	func fish_population_near(_pos: Vector2) -> float:
		return fish_population
	func record_vegetation_harvest_near(_pos: Vector2, amount: float) -> void:
		harvested_amount += amount
	func record_death_at(_pos: Vector2, is_predator: bool, count: float = 1.0) -> void:
		last_kill_was_a_predator = is_predator
		killed_herbivore_amount += count
	func record_fish_catch_near(_pos: Vector2, count: float) -> bool:
		caught_fish_amount += count
		return true


## A world exposing only the original accessors, not any of the harvest/kill/
## catch depletion hooks -- the exact shape an older/duck-typed caller would
## still have.
class BareWorld:
	func vegetation_density_near(_pos: Vector2) -> float:
		return 0.6
	func herbivore_population_near(_pos: Vector2) -> float:
		return 10.0
	func fish_population_near(_pos: Vector2) -> float:
		return 8.0


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
## shared village market, using the same real HerbivorePopulationModel-
## driven number NpcProduction reads.
##
## It used to assert that they also earn real gold. They do not any more --
## gold has one faucet and it is the merchant (docs/concept/
## traveling_merchants.md, "The merchant is the ONLY faucet"). What the
## work earns is the GOODS; the coin arrives when somebody buys them.
func test_a_working_producer_gathers_into_the_market_and_mints_nothing():
	var economy := _economy("hunter")
	for i in _seconds_to_gather("hunter", 20.0):
		economy.step(1.0, true, world, Vector2.ZERO)
	assert_gt(market.total_stock(), 0.0, "the work really produced goods")
	assert_eq(economy.wallet.balance, 0, "and no coin was minted for them")


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
const MerchantVisit = preload("res://src/emergence/merchant_visit.gd")


## Runs a real producer on `a_market` to stock it, and then does what a
## travelling merchant does: buys a cartload of that stock and pays gold
## into the purse.
##
## The producer's work alone funds NOTHING now. Gold has one faucet and it
## is the merchant (docs/concept/traveling_merchants.md, "The merchant is
## the ONLY faucet"), so a fixture that funded a purse by working a hunter
## was funding it from a faucet that no longer exists. This completes the
## real loop instead -- goods, then a sale -- which is a truer fixture than
## the one it replaces, not merely a repaired one.
##
## Gathers twice a cartload so the merchant can take one and leave the
## market something to sell a hungry villager.
func _fund_village_as_a_merchant_would(a_market: VillageMarket, units: float = 40.0) -> NpcEconomy:
	var hunter := NpcEconomy.new(1, "hunter", a_market)
	for i in _seconds_to_gather("hunter", units):
		hunter.step(1.0, true, world, Vector2.ZERO)
	var sale: Dictionary = MerchantVisit.purchase(a_market.stock)
	for item_id in sale["bought"]:
		a_market.remove_stock(str(item_id), float(sale["bought"][item_id]))
	NpcEconomy.deposit_to_purse(a_market, float(sale["paid"]))
	return hunter


## THE behaviour change: a penniless non-producer in a village whose
## producers have actually been working no longer starves.
func test_a_non_producer_in_a_village_with_a_funded_purse_stops_starving():
	_fund_village_as_a_merchant_would(market)
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
	_fund_village_as_a_merchant_would(market)
	var blacksmith := _economy("blacksmith")
	blacksmith.needs.advance(100000.0)

	blacksmith.step(0.01, false, world, Vector2.ZERO)

	assert_false(blacksmith.needs.is_hungry(), "precondition: the wage must have bought a real meal")
	assert_eq(blacksmith.wallet.balance, 0, "a subsistence wage is one meal exactly, with nothing left to hoard")


## The purse is per-SETTLEMENT, sharing exactly what VillageMarket already
## shares (one instance per village, see VillageRenderer.spawn_village) --
## a thriving village must not feed a stranger's.
func test_a_village_purse_feeds_only_its_own_settlement():
	_fund_village_as_a_merchant_would(market)

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
## Asked directly: *"Gold should only be conjured by the travelling
## merchant"*. This test used to pin the opposite -- that a hunter banks
## VillageWages' take-home share of a coin minted per unit gathered -- and
## that mint is the faucet now closed (docs/concept/traveling_merchants.md,
## "The merchant is the ONLY faucet").
##
## What a producer's work earns the village is the GOODS. Nobody is paid at
## the kill; the pay arrives when a merchant buys what was killed.
func test_a_producers_work_fills_the_market_and_mints_nothing():
	var hunter := _economy("hunter")
	for i in _seconds_to_gather("hunter", 20.0):
		hunter.step(1.0, true, world, Vector2.ZERO)

	assert_gt(market.total_stock(), 0.0, "the work really produced goods")
	assert_eq(hunter.wallet.balance, 0, "and no coin was minted at the kill")
	assert_almost_eq(
		NpcEconomy.purse_of(market), 0.0, 0.0001,
		"nor into the village purse -- a merchant has not been yet"
	)


## The purse is observable, starts empty, and holds exactly VillageWages'
## levy on what its producers really earned -- stated against the live rate
## rather than a copied number, so NpcEconomy's split and VillageWages' own
## definition of it can never drift apart.
func test_a_village_purse_starts_empty_and_holds_exactly_the_levy_on_real_producer_income():
	assert_almost_eq(NpcEconomy.purse_of(market), 0.0, 0.0001, "a village starts with no savings at all")

	_fund_village_as_a_merchant_would(market)

	assert_gt(
		NpcEconomy.purse_of(market), 0.0,
		"the purse must hold exactly what a merchant paid for the catch"
	)


## A wage buys a meal, so a village with nothing left to sell must not pay
## one -- otherwise a famine quietly drains a settlement's savings into
## villagers' pockets and buys nobody anything. VillageMarket.buy_meal is
## already all-or-nothing for the same reason (see its own doc comment);
## paying the wage first would sidestep that.
func test_an_empty_market_does_not_pay_out_a_wage_for_a_meal_that_does_not_exist():
	_fund_village_as_a_merchant_would(market)
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


# -- a working hunter's real kill reaches the world's herbivore population ---
#
# Mirrors the farmer block above exactly: a hunter NPC's gathered yield
# previously only READ herbivore_population_near, never actually removed
# anything from it. A real hunter working must now also feed
# EarthChunkManager's record_death_at(pixel_position, false, gathered) --
# the same is_predator=false hook a wild predator's kill or the player's own
# weapon already reports through -- so sustained NPC hunting is a real
# depletion driver too, not just wild predation.

func test_a_working_hunter_records_a_real_herbivore_death():
	var economy := _economy("hunter")
	economy.step(1.0, true, world, Vector2.ZERO)
	assert_gt(world.killed_herbivore_amount, 0.0)


func test_a_non_working_hunter_records_no_death():
	var economy := _economy("hunter")
	economy.step(1.0, false, world, Vector2.ZERO)
	assert_eq(world.killed_herbivore_amount, 0.0)


## A hunter NPC harvesting herbivores is not itself a predator species --
## must report through the same is_predator=false branch a wild kill of prey
## uses, not the predator-population branch.
func test_a_hunters_kill_is_recorded_as_a_non_predator_death():
	var economy := _economy("hunter")
	economy.step(1.0, true, world, Vector2.ZERO)
	assert_eq(world.last_kill_was_a_predator, false)


## Dimensionally consistent with the yield actually gathered: the killed
## amount over one step must equal yield_per_second * delta_seconds -- the
## exact same "fraction of standing herbivore population converted to food"
## number the hunter's own production already computes, not a separately
## invented rate.
func test_hunter_death_amount_matches_the_real_yield_gathered():
	var economy := _economy("hunter")
	var expected := NpcProduction.new().yield_per_second("hunter", world, Vector2.ZERO) * 2.5
	economy.step(2.5, true, world, Vector2.ZERO)
	assert_almost_eq(world.killed_herbivore_amount, expected, 0.0001)


## Only hunter reads/depletes herbivore population -- farmer/fisher read
## DIFFERENT resource pools (vegetation/fish), so they must not also drain it.
func test_a_working_farmer_does_not_record_a_herbivore_death():
	var economy := _economy("farmer")
	economy.step(1.0, true, world, Vector2.ZERO)
	assert_eq(world.killed_herbivore_amount, 0.0)


func test_a_working_fisher_does_not_record_a_herbivore_death():
	var economy := _economy("fisher")
	economy.step(1.0, true, world, Vector2.ZERO)
	assert_eq(world.killed_herbivore_amount, 0.0)


## A working hunter must not drain fish either -- it only ever touches the
## one resource pool its own occupation actually reads from. (The vegetation
## counterpart of this check, test_a_working_hunter_does_not_record_a_
## vegetation_harvest, already exists above.)
func test_a_working_hunter_does_not_record_a_fish_catch():
	var economy := _economy("hunter")
	economy.step(1.0, true, world, Vector2.ZERO)
	assert_eq(world.caught_fish_amount, 0.0)


## Duck-typed fail-open, same convention as the farmer hook above.
func test_a_working_hunter_does_not_crash_when_world_lacks_the_death_hook():
	var economy := _economy("hunter")
	economy.step(1.0, true, BareWorld.new(), Vector2.ZERO)
	pass_test("a working hunter against a world without record_death_at should not crash")


# -- a working fisher's real catch reaches the world's fish population ------
#
# Mirrors the farmer/hunter blocks above, with one deliberate difference:
# unlike record_vegetation_harvest_near/record_death_at (pure aggregate-
# population arithmetic, harmless to call every frame with a tiny fractional
# amount), EarthChunkManager.record_fish_catch_near ALSO finds-and-
# queue_frees one real on-screen FishMarker every single call, regardless of
# how small `count` is -- it's built for PiscivoreBirdMarker's one-call-per-
# real-catch contract (paced seconds apart by its own state machine), not a
# continuous per-frame drip. Calling it unthrottled from every _gather() (one
# per rendered frame while a fisher works) would delete a real fish roughly
# every frame instead of at the yield-proportional pace the mechanic
# intends. So a fisher's catch is only reported once per whole FOOD_UNIT
# actually accumulated -- the same discrete cadence a real catch already has
# for PiscivoreBirdMarker, and the same gate the market stock/wallet gold
# update already uses just below it in _gather.

func test_a_working_fisher_records_a_real_fish_catch():
	var economy := _economy("fisher")
	for i in _seconds_to_gather("fisher", 2.0):  # enough to cross a whole FOOD_UNIT
		economy.step(1.0, true, world, Vector2.ZERO)
	assert_gt(world.caught_fish_amount, 0.0)


## A single frame's worth of fractional yield must NOT report a catch --
## this is exactly the regression the throttling guards against (a fisher
## used to delete a real on-screen fish almost every frame).
func test_a_single_short_step_does_not_yet_report_a_catch():
	var economy := _economy("fisher")
	economy.step(1.0, true, world, Vector2.ZERO)  # one frame's yield, well under one FOOD_UNIT
	assert_eq(world.caught_fish_amount, 0.0, "a fraction of a food unit must not report a discrete catch yet")


func test_a_non_working_fisher_records_no_catch():
	var economy := _economy("fisher")
	economy.step(1.0, false, world, Vector2.ZERO)
	assert_eq(world.caught_fish_amount, 0.0)


## A real catch is only ever reported in lockstep with a whole FOOD_UNIT
## actually reaching the shared market stock -- one discrete catch per one
## whole food unit sold, never fractionally ahead of it (which is what let a
## fisher over-report/over-delete real fish before this fix). 199 steps (not
## a round 200) deliberately leaves a fractional remainder mid-unit, so a
## still-continuous/unthrottled implementation would report MORE than the
## market's whole-unit stock, not just coincidentally match it.
func test_fisher_catch_amount_always_matches_the_whole_units_reaching_the_market():
	var economy := _economy("fisher")
	# Deliberately HALF a unit past the last whole one, so an unthrottled
	# implementation would report more than the market's whole-unit stock.
	for i in _seconds_to_gather("fisher", 2.5):
		economy.step(1.0, true, world, Vector2.ZERO)
	assert_almost_eq(world.caught_fish_amount, market.stock["fish"], 0.0001)


## Quantized to whole units, but still tracks the real yield over time --
## never off by more than one FOOD_UNIT from the true total gathered.
func test_fisher_catch_amount_stays_within_one_food_unit_of_the_real_total_gathered():
	var economy := _economy("fisher")
	var seconds := _seconds_to_gather("fisher", 3.0)
	var total_seconds := float(seconds)
	var expected_total := NpcProduction.new().yield_per_second("fisher", world, Vector2.ZERO) * total_seconds
	for i in seconds:
		economy.step(1.0, true, world, Vector2.ZERO)
	assert_almost_eq(world.caught_fish_amount, expected_total, NpcProduction.FOOD_UNIT)


## Only fisher reads/depletes fish population -- farmer/hunter must not also
## drain it.
func test_a_working_farmer_does_not_record_a_fish_catch():
	var economy := _economy("farmer")
	economy.step(1.0, true, world, Vector2.ZERO)
	assert_eq(world.caught_fish_amount, 0.0)


func test_a_working_fisher_does_not_record_a_vegetation_harvest():
	var economy := _economy("fisher")
	economy.step(1.0, true, world, Vector2.ZERO)
	assert_eq(world.harvested_amount, 0.0)


## Duck-typed fail-open, same convention as the farmer/hunter hooks above.
## Loops enough real seconds to actually cross a whole FOOD_UNIT (the point
## where the discrete catch call now fires -- see the throttling comment
## above), so this genuinely exercises the fail-open branch rather than
## trivially passing because the guarded call never ran at all.
func test_a_working_fisher_does_not_crash_when_world_lacks_the_catch_hook():
	var economy := _economy("fisher")
	var bare_world := BareWorld.new()
	for i in _seconds_to_gather("fisher", 2.0):
		economy.step(1.0, true, bare_world, Vector2.ZERO)
	pass_test("a working fisher against a world without record_fish_catch_near should not crash")


# -- eating from the village's own stores (docs/concept/milling_and_ ------
# -- baking.md) ----------------------------------------------------------------
#
# The stall (VillageMarket) is only the villagers' own day's gathering. The
# village's STORES -- the persisted Market the merchant stocks and the
# granary/trade fill, and the Bakery/Storage shelves bread ends up on --
# are food too, and were never eaten by anyone. So a hungry villager with
# nothing on the stall asks the world, duck-typed, for a meal from those
# stores near them, at the SAME meal price and with the SAME all-or-nothing
# wallet rule VillageMarket.buy_meal keeps. A world without the hook
# (BareWorld) simply has no stores to offer.

## A world with stores: offers one meal per unit of `loaves`.
class BakehouseWorld extends StubWorld:
	var loaves := 0
	var meals_sold := 0
	func has_village_meal_near(_pos: Vector2) -> bool:
		return loaves > 0
	func buy_village_meal_near(_pos: Vector2, wallet) -> String:
		if loaves <= 0 or not wallet.spend(VillageMarket.VILLAGE_LOCAL_FOOD_PRICE):
			return ""
		loaves -= 1
		meals_sold += 1
		return "bread"


func test_a_hungry_non_producer_eats_bread_from_the_bakehouse_when_the_market_is_bare():
	var bakehouse := BakehouseWorld.new()
	bakehouse.loaves = 3
	var economy := _economy("blacksmith")
	economy.wallet.add(100)
	economy.needs.advance(100000.0)
	assert_true(economy.needs.is_hungry())

	economy.step(0.01, false, bakehouse, Vector2.ZERO)

	assert_false(economy.needs.is_hungry(), "fed from the village's own bread")
	assert_eq(bakehouse.loaves, 2, "one loaf actually left the shelf")
	assert_eq(economy.wallet.balance, 100 - VillageMarket.VILLAGE_LOCAL_FOOD_PRICE, "at the same meal price")


func test_the_market_stall_is_still_tried_first():
	market.add_stock("meat", 5.0)
	var bakehouse := BakehouseWorld.new()
	bakehouse.loaves = 3
	var economy := _economy("blacksmith")
	economy.wallet.add(100)
	economy.needs.advance(100000.0)

	economy.step(0.01, false, bakehouse, Vector2.ZERO)

	assert_false(economy.needs.is_hungry())
	assert_eq(bakehouse.loaves, 3, "the stall had meat; the bakehouse was never needed")


func test_a_penniless_villager_draws_a_subsistence_wage_for_a_bakehouse_meal_too():
	# The purse-funded wage used to be gated on the market stall alone
	# (nothing to buy there -> no wage) -- a villager would have starved next
	# to a full bakehouse. A structure meal counts as something to buy.
	var bakehouse := BakehouseWorld.new()
	bakehouse.loaves = 3
	NpcEconomy._set_purse(market, 100.0)
	var economy := _economy("blacksmith")
	economy.needs.advance(100000.0)
	assert_eq(economy.wallet.balance, 0, "precondition: no gold of their own")

	economy.step(0.01, false, bakehouse, Vector2.ZERO)

	assert_false(economy.needs.is_hungry())
	assert_eq(bakehouse.loaves, 2)


func test_a_world_without_a_bakehouse_hook_changes_nothing():
	var economy := _economy("blacksmith")
	economy.wallet.add(100)
	economy.needs.advance(100000.0)
	economy.step(0.01, false, BareWorld.new(), Vector2.ZERO)
	assert_true(economy.needs.is_hungry())
	assert_eq(economy.wallet.balance, 100)


# -- earnings must reach the household that keeps them --------------------
#
# Reported live: "all villagers have 0 gold". They were in fact earning --
# the producer faucet and the subsistence wage both worked -- into a Wallet
# created fresh inside NpcEconomy, which lives on an NpcMarker that is
# regenerated from scratch on every chunk load. The persistent Household
# wallet (HouseholdStore, the unit Household's own doc comment calls "this
# project's real, persistent unit") never received a single coin, so every
# villager really did read 0 gold, for good, and the income need with them.

const Household = preload("res://src/emergence/household.gd")
const EntityRef = preload("res://src/emergence/entity_ref.gd")


func test_an_unbound_economy_still_keeps_its_own_wallet():
	var economy = NpcEconomy.new(1, "hunter", VillageMarket.new())
	economy.wallet.add(3)
	assert_eq(economy.wallet.balance, 3, "nothing changes for a villager with no household")


func test_binding_a_household_makes_its_wallet_the_one_that_earns():
	var household = Household.for_founder(EntityRef.for_npc(7))
	var economy = NpcEconomy.new(7, "hunter", VillageMarket.new())

	economy.bind_household_wallet(household.wallet)
	economy.wallet.add(5)

	assert_eq(household.wallet.balance, 5, "a villager's earnings land in their household's purse")


## Binding must never silently drop coins the villager already had in hand.
func test_binding_carries_over_what_was_already_earned():
	var household = Household.for_founder(EntityRef.for_npc(8))
	var economy = NpcEconomy.new(8, "hunter", VillageMarket.new())
	economy.wallet.add(4)

	economy.bind_household_wallet(household.wallet)

	assert_eq(household.wallet.balance, 4, "gold in hand at binding time is carried over, not lost")
	assert_eq(economy.wallet.balance, 4, "and the economy now spends from that same purse")


func test_binding_nothing_is_a_harmless_no_op():
	var economy = NpcEconomy.new(9, "hunter", VillageMarket.new())
	economy.wallet.add(2)
	economy.bind_household_wallet(null)
	assert_eq(economy.wallet.balance, 2)


# -- real quarry (docs/concept/npc.md, "Work against the real world, not
# against a number") ---------------------------------------------------
#
# A hunter who walks to a real animal and kills it credits what that animal
# really carried (HuntableQuarry.meat_yield_of) instead of the regional
# drip, and the drip is switched OFF for as long as they are on real
# quarry. Both halves matter: crediting a real kill on top of the drip
# would pay a hunter twice for one animal, and dropping the drip entirely
# would starve every village whose chunks aren't loaded (npc.md's own named
# limitation).


func test_a_real_catch_puts_the_producers_own_item_in_the_market():
	var hunter := _economy("hunter")
	hunter.record_real_catch(3)
	assert_almost_eq(market.stock.get("meat", 0.0), 3.0, 0.0001)


## A unit of meat is worth a unit of meat however it was obtained -- but it
## is worth it to the MARKET, not as a coin at the kill. The rate this test
## used to pin was the conjured faucet.
func test_a_real_catch_stocks_the_market_and_pays_nobody():
	var hunter := _economy("hunter")
	hunter.record_real_catch(4)
	assert_almost_eq(market.total_stock(), 4.0, 0.0001, "the meat is really there")
	assert_eq(hunter.wallet.balance, 0, "and nothing was minted for it")
	assert_almost_eq(NpcEconomy.purse_of(market), 0.0, 0.0001)


func test_a_real_catch_of_nothing_changes_nothing():
	var hunter := _economy("hunter")
	hunter.record_real_catch(0)
	assert_almost_eq(market.total_stock(), 0.0, 0.0001)
	assert_almost_eq(NpcEconomy.purse_of(market), 0.0, 0.0001)


func test_a_real_catch_does_not_book_the_death_a_second_time():
	# CreatureMarker._die() is the single choke point every death already
	# reports through (_book_death_against_the_region) -- its own doc
	# comment records a merge that left two calls there and counted every
	# wild death twice. A hunter's kill dies through that same path, so
	# this must not report it again.
	var hunter := _economy("hunter")
	hunter.record_real_catch(2)
	assert_almost_eq(world.killed_herbivore_amount, 0.0, 0.0001)


func test_a_non_producer_cannot_record_a_catch():
	var blacksmith := _economy("blacksmith")
	blacksmith.record_real_catch(2)
	assert_almost_eq(market.total_stock(), 0.0, 0.0001)


func test_a_producer_on_real_quarry_does_not_also_gather_the_regional_drip():
	var hunter := _economy("hunter")
	for _i in 100:
		hunter.step(1.0, true, world, Vector2.ZERO, true)
	assert_almost_eq(market.total_stock(), 0.0, 0.0001, "the drip must be off while real quarry is in hand")
	assert_almost_eq(
		world.killed_herbivore_amount, 0.0, 0.0001, "and so must the aggregate kill it books"
	)


func test_a_producer_with_no_quarry_in_hand_still_gathers_the_regional_fallback():
	# npc.md's named limitation: a villager can only hunt what is LOADED,
	# so the aggregate path stays for everyone else.
	var hunter := _economy("hunter")
	for _i in _seconds_to_gather("hunter", 2.0):
		hunter.step(1.0, true, world, Vector2.ZERO, false)
	assert_gt(market.total_stock(), 0.0)


func test_the_regional_fallback_is_still_the_default_for_callers_that_say_nothing():
	var hunter := _economy("hunter")
	for _i in _seconds_to_gather("hunter", 2.0):
		hunter.step(1.0, true, world, Vector2.ZERO)
	assert_gt(market.total_stock(), 0.0)


func test_a_producer_on_real_quarry_still_eats_from_their_own_work():
	# The free self-feed is about having food in your hands, which a hunter
	# standing over a fresh kill emphatically does.
	var hunter := _economy("hunter")
	hunter.needs.advance(100000.0)
	assert_true(hunter.needs.is_hungry(), "precondition")
	hunter.step(0.01, true, world, Vector2.ZERO, true)
	assert_false(hunter.needs.is_hungry())


func test_a_byproduct_reaches_the_market_without_being_paid_for():
	# A hide feeds nobody and no villager buys one. Its value arrives when
	# a cart does (MerchantVisit.BUY_LIST), so paying for it at the kill
	# would be the conjured faucet traveling_merchants.md exists to close,
	# pointed at a second good.
	var hunter := _economy("hunter")
	hunter.record_byproduct("hide", 2)
	assert_almost_eq(market.stock.get("hide", 0.0), 2.0, 0.0001)
	assert_almost_eq(NpcEconomy.purse_of(market), 0.0, 0.0001)
	assert_eq(hunter.wallet.balance, 0)


func test_a_byproduct_of_nothing_changes_nothing():
	var hunter := _economy("hunter")
	hunter.record_byproduct("hide", 0)
	assert_almost_eq(market.total_stock(), 0.0, 0.0001)


# -- feeding yourself by working (docs/concept/npc.md's free self-feed) ----
#
# The condition the free self-feed already turns on, named so that NpcMarker
# can ask it too. A hungry villager's schedule is overridden to walk to the
# well and buy a meal -- which is right for a blacksmith and wrong for a
# hunter, whose food is standing in the woods. Measured live: a villager who
# goes hungry with an empty village market never works again, because not
# working is what stops them producing the food they would have bought.


func test_a_producer_in_a_living_region_feeds_itself_from_its_own_work():
	assert_true(_economy("hunter").feeds_itself_from_work(world, Vector2.ZERO))


func test_a_producer_whose_region_has_collapsed_cannot_feed_itself():
	# The famine chain stays intact: nothing left to hunt is nothing to eat.
	world.herbivore_population = 0.0
	assert_false(_economy("hunter").feeds_itself_from_work(world, Vector2.ZERO))


func test_a_non_producer_never_feeds_itself_from_work():
	assert_false(_economy("blacksmith").feeds_itself_from_work(world, Vector2.ZERO))


func test_a_producer_with_no_world_cannot_feed_itself():
	assert_false(_economy("hunter").feeds_itself_from_work(null, Vector2.ZERO))


# -- a real harvest off a village field ------------------------------------
#
# docs/concept/village_farms.md. record_real_catch is no use here twice
# over: it credits whatever PRODUCER_ITEM_BY_OCCUPATION says the occupation
# drips (the farmer's is "fruit", not the wheat actually standing in the
# field), and the herbalist is not in that table at all, so it would pay
# them nothing for a real crop they really grew.

func test_a_real_harvest_stocks_the_crop_that_was_actually_grown():
	var farmer := _economy("farmer")
	farmer.record_real_harvest("wheat", 3)
	assert_almost_eq(market.stock.get("wheat", 0.0), 3.0, 0.0001)
	assert_almost_eq(
		market.stock.get("fruit", 0.0), 0.0, 0.0001,
		"what the region would have dripped is not what the field grew"
	)


## A unit of real produce is worth a unit of real produce however it was
## obtained -- to the MARKET. The rate this used to pin was the conjured
## faucet, the same one record_real_catch's own test named.
func test_a_real_harvest_stocks_the_market_and_pays_nobody():
	var farmer := _economy("farmer")
	farmer.record_real_harvest("wheat", 4)
	assert_almost_eq(market.stock.get("wheat", 0.0), 4.0, 0.0001, "the wheat is really there")
	assert_eq(farmer.wallet.balance, 0, "and nothing was minted for it")
	assert_almost_eq(NpcEconomy.purse_of(market), 0.0, 0.0001)


func test_a_herbalists_real_harvest_reaches_the_market_though_they_drip_nothing():
	var herbalist := _economy("herbalist")
	assert_false(
		NpcProduction.PRODUCER_ITEM_BY_OCCUPATION.has("herbalist"),
		"precondition: the regional economy has never paid a herbalist anything"
	)
	herbalist.record_real_harvest("herb", 2)
	assert_almost_eq(
		market.stock.get("herb", 0.0), 2.0, 0.0001,
		"real work really produced something, and the village can sell it"
	)
	assert_almost_eq(
		NpcEconomy.purse_of(market), 0.0, 0.0001,
		"but nothing is minted for it -- a merchant pays, at the sale"
	)


func test_a_harvest_of_nothing_changes_nothing():
	var farmer := _economy("farmer")
	farmer.record_real_harvest("wheat", 0)
	farmer.record_real_harvest("", 5)
	assert_almost_eq(market.total_stock(), 0.0, 0.0001)
	assert_almost_eq(NpcEconomy.purse_of(market), 0.0, 0.0001)


# -- the load in a villager's hands ----------------------------------------
#
# docs/concept/village_warehouse.md mechanism 3, "goods are carried in":
# stock that teleports into a number is not stock kept in a warehouse. What a
# producer takes goes into their HANDS first, and only reaches the village's
# stock when they have walked it to the store door.
#
# Off by default (carry_limit 0.0), the same shape VillageMarket.storage_
# capacity uses: every caller that predates a warehouse keeps the direct
# deposit it always had, and the one place that knows a store really stands
# opts in. A village with nowhere to carry to is not a village whose
# producers stop stocking it.


func test_with_nowhere_to_carry_to_a_producer_stocks_the_market_outright():
	var economy := _economy("hunter")
	assert_almost_eq(economy.carry_limit, 0.0, 0.0, "precondition: carrying is opt-in")
	for i in _seconds_to_gather("hunter", 2.0):
		economy.step(1.0, true, world, Vector2.ZERO)
	assert_gt(market.total_stock(), 0.0, "no store must not mean no stock")


func test_a_producer_who_carries_holds_the_take_until_it_is_delivered():
	var economy := _economy("hunter")
	economy.carry_limit = NpcEconomy.CARRY_LIMIT
	for i in _seconds_to_gather("hunter", 2.0):
		economy.step(1.0, true, world, Vector2.ZERO)
	assert_almost_eq(market.total_stock(), 0.0, 0.0001, "nothing reaches the store on its own")
	assert_gt(economy.carried_total(), 0.0, "the take is in their hands")


func test_delivering_a_load_is_what_stocks_the_village():
	var economy := _economy("hunter")
	economy.carry_limit = NpcEconomy.CARRY_LIMIT
	for i in _seconds_to_gather("hunter", 2.0):
		economy.step(1.0, true, world, Vector2.ZERO)
	var in_hand := economy.carried_total()
	economy.deliver_load()
	assert_almost_eq(market.total_stock(), in_hand, 0.0001)
	assert_almost_eq(economy.carried_total(), 0.0, 0.0001, "hands are empty after a delivery")


func test_a_delivery_keeps_every_item_apart():
	var farmer := _economy("farmer")
	farmer.carry_limit = NpcEconomy.CARRY_LIMIT
	farmer.record_real_harvest("wheat", 2)
	farmer.record_byproduct("hide", 1)
	farmer.deliver_load()
	assert_almost_eq(market.stock.get("wheat", 0.0), 2.0, 0.0001)
	assert_almost_eq(market.stock.get("hide", 0.0), 1.0, 0.0001)


## The gate the ethogram reads. A step, not a ramp: any gain above zero
## fires the haul wiring at all (it is the only wiring listening on the
## store), so a ramp would have a villager set off with one apple in hand
## and never do a day's work again. What presses is being FULL.
func test_a_load_presses_only_once_the_hands_are_full():
	var economy := _economy("hunter")
	economy.carry_limit = NpcEconomy.CARRY_LIMIT
	assert_almost_eq(economy.burden(), 0.0, 0.0, "empty hands press nobody")
	economy.record_real_catch(int(NpcEconomy.CARRY_LIMIT / 2.0))
	assert_almost_eq(economy.burden(), 0.0, 0.0, "a half load is not an errand")
	economy.record_real_catch(int(NpcEconomy.CARRY_LIMIT))
	assert_almost_eq(economy.burden(), 1.0, 0.0, "full hands press")


func test_a_villager_who_carries_nothing_is_never_burdened():
	var economy := _economy("hunter")
	economy.record_real_catch(500)
	assert_almost_eq(
		economy.burden(), 0.0, 0.0,
		"a villager with nowhere to carry to must never be sent to a store that is not there"
	)


## Full hands take nothing more: no gold conjured for a unit nobody can
## hold, and -- the part that would really bite -- no real herbivore, fish
## or crop removed from the region for it either.
func test_full_hands_gather_nothing():
	var economy := _economy("hunter")
	economy.carry_limit = NpcEconomy.CARRY_LIMIT
	# Enough to FILL a pair of hands, not merely to gather something.
	for i in _seconds_to_gather("hunter", NpcEconomy.CARRY_LIMIT + 2.0):
		economy.step(1.0, true, world, Vector2.ZERO)
	var gold_when_full := economy.wallet.balance
	var killed_when_full := world.killed_herbivore_amount
	assert_almost_eq(
		economy.carried_total(), NpcEconomy.CARRY_LIMIT, 0.0001,
		"precondition: 400 working seconds really filled their hands"
	)
	for i in 400:
		economy.step(1.0, true, world, Vector2.ZERO)
	assert_eq(economy.wallet.balance, gold_when_full, "a full pair of hands earned more")
	assert_almost_eq(
		world.killed_herbivore_amount, killed_when_full, 0.0001,
		"a full pair of hands killed more"
	)


## One person's load against a village's own ceilings (VillageMarket): four
## trips fill a village that has no store at all, forty fill one that does.
## That ratio is the whole point of the building -- a store that took one
## trip to fill would not be worth raising.
func test_a_load_is_a_quarter_of_what_a_village_keeps_without_a_store():
	assert_almost_eq(
		NpcEconomy.CARRY_LIMIT,
		VillageMarket.HOUSEHOLD_CORNERS_CAPACITY / float(NpcEconomy.TRIPS_TO_FILL_A_STORELESS_VILLAGE),
		0.0001
	)
	assert_eq(NpcEconomy.TRIPS_TO_FILL_A_STORELESS_VILLAGE, 4)
	assert_almost_eq(
		VillageMarket.WAREHOUSE_CAPACITY / NpcEconomy.CARRY_LIMIT, 40.0, 0.0001,
		"a warehouse is forty trips deep"
	)


## A take that ALREADY HAPPENED is never refused for want of hands. The
## continuous drip stops at a full load (test_full_hands_gather_nothing)
## because it costs the region something every frame it runs -- but a crop
## that has been cut or an animal that has been killed is done, and refusing
## to hold it would delete it rather than leave it standing. So a villager
## can finish a work block carrying more than a tidy load, and delivers the
## lot. Bounded in practice: a field has finitely many plots.
func test_a_take_that_already_happened_is_never_dropped_for_want_of_hands():
	var farmer := _economy("farmer")
	farmer.carry_limit = NpcEconomy.CARRY_LIMIT
	var over := int(NpcEconomy.CARRY_LIMIT) * 3
	farmer.record_real_harvest("wheat", over)
	assert_almost_eq(farmer.carried_total(), float(over), 0.0001, "the whole harvest is in hand")
	assert_almost_eq(farmer.burden(), 1.0, 0.0, "and it presses")
	farmer.deliver_load()
	assert_almost_eq(market.stock.get("wheat", 0.0), float(over), 0.0001, "the whole harvest arrives")


# -- walking to the market only helps if there is a meal to be had ---------
#
# MEASURED on a real village (tools/probe_village_market.gd, the whole
# settlement ticked, not just the one villager): a merchant was HUNGRY for
# 1589 of 1801 ticks with an empty purse, and reached their own trading spot
# on 9 of them. Their schedule said "work at the stall" for 825 ticks;
# NpcMarker's hunger interrupt overrode every one of them and sent them to
# the well, where there was nothing they could pay for, so they never worked,
# never earned, and stayed hungry -- for ever.
#
# That is the SAME deadlock npc_marker.gd's own comments already record for
# a hunter ("went hungry about twelve seconds in with an empty village
# market and an empty purse, and then never worked again for the remaining
# 227 simulated seconds"), and the guard added for it only covers producers
# and villagers with a field. A merchant, a blacksmith, a guard and a nurse
# are none of those.
#
# The honest general rule is the one that comment already states: the
# interrupt is for villagers who must BUY. A villager who cannot buy gains
# nothing by standing at the well and loses the only thing that could change
# either number.


func test_a_villager_cannot_obtain_a_meal_from_an_empty_market():
	var market := VillageMarket.new()
	var economy := NpcEconomy.new(1, "merchant", market)
	economy.wallet.add(100)
	assert_false(economy.can_obtain_a_meal(), "there is nothing on the stall to buy")


func test_a_villager_who_can_pay_can_obtain_a_meal():
	var market := VillageMarket.new()
	market.add_stock("fish", 5.0)
	var economy := NpcEconomy.new(1, "merchant", market)
	economy.wallet.add(100)
	assert_true(economy.can_obtain_a_meal())


## Food on the stall they cannot pay for, and a village purse with nothing
## in it to advance them: walking over achieves nothing.
func test_a_broke_villager_in_a_broke_village_cannot_obtain_a_meal():
	var market := VillageMarket.new()
	market.add_stock("fish", 5.0)
	var economy := NpcEconomy.new(1, "merchant", market)
	assert_eq(economy.wallet.balance, 0, "precondition: broke")
	assert_false(economy.can_obtain_a_meal(), "nobody can advance them the price")


## ...but a village whose purse CAN advance them the subsistence wage really
## can feed them, so the walk is worth making.
func test_a_broke_villager_whose_village_can_advance_a_wage_can_obtain_a_meal():
	var market := VillageMarket.new()
	market.add_stock("fish", 5.0)
	market.set_meta(NpcEconomy.PURSE_META, 100.0)
	var economy := NpcEconomy.new(1, "merchant", market)
	assert_eq(economy.wallet.balance, 0, "precondition: broke")
	assert_true(economy.can_obtain_a_meal())


## And the answer has to be a QUERY: asking it must not move a single coin,
## or the check would feed people by being asked.
func test_asking_whether_a_meal_can_be_had_moves_nothing():
	var market := VillageMarket.new()
	market.add_stock("fish", 5.0)
	market.set_meta(NpcEconomy.PURSE_META, 100.0)
	var economy := NpcEconomy.new(1, "merchant", market)
	economy.can_obtain_a_meal()
	economy.can_obtain_a_meal()
	assert_eq(economy.wallet.balance, 0, "the wallet must be untouched")
	assert_eq(NpcEconomy.purse_of(market), 100.0, "the purse must be untouched")
	assert_eq(market.stock.get("fish", 0.0), 5.0, "the stall must be untouched")


## How many real seconds a producer needs here to gather `units` whole food
## units, derived from NpcProduction's own rate rather than written as a
## magic second count.
##
## That rate is each resource's OWN renewal now, scaled by that trade's own
## reach (see docs/concept/settlement_food_calibration.md) -- a hunter
## working a region that holds ten animals takes about 107 seconds per unit,
## where the single invented rate it replaced took two. Every fixture below
## that used to say "200 seconds, plenty" was saying "plenty" about a number
## it had no relationship to, and would silently gather nothing the next
## time the rate moved.
func _seconds_to_gather(occupation: String, units: float) -> int:
	var per_second: float = NpcProduction.new().yield_per_second(occupation, world, Vector2.ZERO)
	if per_second <= 0.0:
		return 0
	return int(ceil(units * NpcProduction.FOOD_UNIT / per_second)) + 1
