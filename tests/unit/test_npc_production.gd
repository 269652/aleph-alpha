extends GutTest

## NpcProduction (docs/concept/npc.md "Needs and the local production
## economy"): a producer occupation's real per-second food yield, reading
## the SAME weather-tied regional numbers the wild ecosystem already runs
## on (EarthChunkManager.vegetation_density_near/herbivore_population_near/
## fish_population_near) -- never an invented economy stat. Reuses existing
## food item ids (ItemCatalog: "fruit"/"meat"/"fish") rather than inventing
## new ones.

const NpcProduction = preload("res://src/world/npc_production.gd")

## Duck-typed world stub exposing the three real EarthChunkManager
## accessors NpcProduction reads, with settable canned values -- lets a test
## simulate "a real drought" by lowering vegetation_density/herbivore_
## population/fish_population, the same numbers the wild ecosystem itself
## would report under those conditions.
class StubWorld:
	var vegetation_density := 0.6
	var herbivore_population := 10.0
	var fish_population := 8.0
	func vegetation_density_near(_pos: Vector2) -> float:
		return vegetation_density
	func herbivore_population_near(_pos: Vector2) -> float:
		return herbivore_population
	func fish_population_near(_pos: Vector2) -> float:
		return fish_population


var production: NpcProduction
var world: StubWorld


func before_each():
	production = NpcProduction.new()
	world = StubWorld.new()


func test_farmer_hunter_and_fisher_are_producers():
	assert_true(production.is_producer("farmer"))
	assert_true(production.is_producer("hunter"))
	assert_true(production.is_producer("fisher"))


func test_non_producer_occupations_are_not_producers():
	for occupation in ["blacksmith", "merchant", "guard", "herbalist", "nurse"]:
		assert_false(production.is_producer(occupation), "%s should not be a producer" % occupation)


func test_item_id_for_reuses_real_existing_food_items():
	const ItemCatalog = preload("res://src/gameplay/item_catalog.gd")
	var catalog := ItemCatalog.new()
	assert_eq(production.item_id_for("farmer"), "fruit")
	assert_eq(production.item_id_for("hunter"), "meat")
	assert_eq(production.item_id_for("fisher"), "fish")
	for occupation in ["farmer", "hunter", "fisher"]:
		assert_true(catalog.has(production.item_id_for(occupation)))


func test_item_id_for_a_non_producer_is_empty():
	assert_eq(production.item_id_for("blacksmith"), "")


func test_non_producer_yield_is_always_zero():
	for occupation in ["blacksmith", "merchant", "guard", "herbalist", "nurse"]:
		assert_eq(production.yield_per_second(occupation, world, Vector2.ZERO), 0.0)


func test_farmer_yield_is_positive_when_vegetation_is_present():
	assert_gt(production.yield_per_second("farmer", world, Vector2.ZERO), 0.0)


func test_hunter_yield_is_positive_when_herbivores_are_present():
	assert_gt(production.yield_per_second("hunter", world, Vector2.ZERO), 0.0)


func test_fisher_yield_is_positive_when_fish_are_present():
	assert_gt(production.yield_per_second("fisher", world, Vector2.ZERO), 0.0)


## The core causal claim of docs/concept/npc.md: a real drought (here,
## depressed vegetation density -- the same number a real drought lowers
## for the wild ecosystem) measurably lowers a farmer's yield. Not asserted
## against a hardcoded number -- verified as a real relative decrease.
func test_farmer_yield_drops_under_drought_conditions():
	var lush := production.yield_per_second("farmer", world, Vector2.ZERO)
	world.vegetation_density = 0.05  # a real drought's depressed density
	var drought := production.yield_per_second("farmer", world, Vector2.ZERO)
	assert_lt(drought, lush)
	assert_gt(drought, 0.0, "a mild drought thins yield, it does not need to zero it")


## Total ecological collapse (zero standing resource) should zero the yield,
## not merely shrink it -- there is nothing to gather.
func test_farmer_yield_is_zero_when_vegetation_is_totally_gone():
	world.vegetation_density = 0.0
	assert_eq(production.yield_per_second("farmer", world, Vector2.ZERO), 0.0)


func test_hunter_yield_drops_when_regional_game_is_scarce():
	var plentiful := production.yield_per_second("hunter", world, Vector2.ZERO)
	world.herbivore_population = 0.5
	var scarce := production.yield_per_second("hunter", world, Vector2.ZERO)
	assert_lt(scarce, plentiful)


func test_fisher_yield_drops_when_regional_fish_are_scarce():
	var plentiful := production.yield_per_second("fisher", world, Vector2.ZERO)
	world.fish_population = 0.5
	var scarce := production.yield_per_second("fisher", world, Vector2.ZERO)
	assert_lt(scarce, plentiful)


func test_yield_is_zero_without_a_world():
	assert_eq(production.yield_per_second("farmer", null, Vector2.ZERO), 0.0)


## A world that doesn't expose the accessor (an older/duck-typed test
## double) fails open to zero rather than crashing -- same convention as
## the rest of this codebase's world-duck-typing.
func test_yield_is_zero_when_world_lacks_the_accessor():
	var bare_world = RefCounted.new()
	assert_eq(production.yield_per_second("farmer", bare_world, Vector2.ZERO), 0.0)


## Named constants, tested and reasoned rather than eyeballed (see
## CLAUDE.md's no-manual-tuning rule): YIELD_TO_GOLD_RATE is a producer's
## per-unit earnings the instant gathered food crosses into the village
## stock, deliberately below VillageMarket.VILLAGE_LOCAL_FOOD_PRICE so
## village-local trade carries a real wholesale-vs-retail margin instead of
## round-tripping a buyer's gold back to the seller unchanged.
func test_yield_to_gold_rate_is_below_village_local_price():
	const VillageMarket = preload("res://src/world/village_market.gd")
	assert_lt(NpcProduction.YIELD_TO_GOLD_RATE, VillageMarket.VILLAGE_LOCAL_FOOD_PRICE)


func test_yield_to_gold_rate_is_positive():
	assert_gt(NpcProduction.YIELD_TO_GOLD_RATE, 0)


func test_production_rate_is_positive_and_less_than_one():
	# A fraction-per-second of the standing real resource, not a > 100%
	# instant-conversion rate.
	assert_gt(NpcProduction.PRODUCTION_RATE_PER_SECOND, 0.0)
	assert_lt(NpcProduction.PRODUCTION_RATE_PER_SECOND, 1.0)
