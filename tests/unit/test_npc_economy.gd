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
