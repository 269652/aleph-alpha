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


# -- one currency, and each resource's own renewal --------------------------
#
# Asked for directly: "Erst Granary-Raten rekalibrieren, dann alles
# ableiten." See docs/concept/settlement_food_calibration.md.
#
# MEASURED on real settlement chunks (tools/probe_village_demand.gd): one
# producer per assessment brought in 0.16-0.27 (farmer), 0.94-1.63 (hunter)
# and 0-1481 (fisher) against a village draw of 20. Four orders of magnitude
# apart, because ONE PRODUCTION_RATE_PER_SECOND was applied to three
# quantities that are not the same kind of number:
#
#   vegetation_density_near   a per-CELL MEAN, 0..1
#   herbivore_population_near a chunk TOTAL headcount
#   fish_population_near      a chunk TOTAL headcount
#
# The unit conversion is not invented either -- NpcEconomy._deplete_
# continuous already spends ONE unit of each per food unit gathered, so a
# cell's density unit, a herbivore and a fish are each one food unit by the
# game's own accounting. What was missing was multiplying the MEAN back up
# by the cells it is a mean OF.
#
# And the rate: a forager sustainably takes a share of what the resource
# REPLACES, not of what stands there. Every one of these three is a logistic
# population with its own growth rate per day already written down, and a
# logistic population's maximum sustainable yield is r*K/4. So the one
# invented 0.05 is gone and each resource is scaled by its own renewal.


const VegetationGrowthModel = preload("res://src/world/vegetation_growth_model.gd")
const HerbivorePopulationModel = preload("res://src/world/herbivore_population_model.gd")
const AquaticPopulationModel = preload("res://src/world/aquatic_population_model.gd")


## The whole point: a farmer's region reading is the chunk's standing crop,
## not the per-cell average it is reported as.
func test_a_regions_standing_food_is_a_whole_chunk_total_for_every_producer():
	world.vegetation_density = 0.25
	world.herbivore_population = 7.0
	world.fish_population = 9.0
	assert_almost_eq(
		production.standing_food("farmer", world, Vector2.ZERO),
		0.25 * float(NpcProduction.CELLS_PER_REGION), 0.001,
		"a per-cell mean has to be multiplied back up by the cells it averages"
	)
	assert_almost_eq(production.standing_food("hunter", world, Vector2.ZERO), 7.0, 0.001)
	assert_almost_eq(production.standing_food("fisher", world, Vector2.ZERO), 9.0, 0.001)
	assert_eq(production.standing_food("blacksmith", world, Vector2.ZERO), 0.0)


## Each resource is scaled by ITS OWN renewal, never by one shared rate.
func test_each_producer_is_scaled_by_its_own_resources_renewal_rate():
	assert_almost_eq(
		NpcProduction.renewal_rate_per_day("farmer"),
		VegetationGrowthModel.GROWTH_PACE_PER_DAY, 0.0001
	)
	assert_almost_eq(
		NpcProduction.renewal_rate_per_day("hunter"),
		HerbivorePopulationModel.GROWTH_RATE_PER_DAY, 0.0001
	)
	assert_almost_eq(
		NpcProduction.renewal_rate_per_day("fisher"),
		AquaticPopulationModel.GROWTH_RATE_PER_DAY, 0.0001
	)
	assert_eq(NpcProduction.renewal_rate_per_day("guard"), 0.0)


## A logistic population's maximum sustainable yield is r*K/4 -- standard,
## not a number picked here, and the only rate at which a forager can keep
## working a region for ever.
func test_a_producers_yield_is_its_resources_own_maximum_sustainable_yield():
	for occupation in ["farmer", "hunter", "fisher"]:
		var standing: float = production.standing_food(occupation, world, Vector2.ZERO)
		var expected: float = (
			NpcProduction.renewal_rate_per_day(occupation) * standing * NpcProduction.reach_share(occupation)
			/ NpcProduction.MAX_SUSTAINABLE_YIELD_DIVISOR
			/ NpcProduction.SECONDS_PER_SIMULATED_DAY
		)
		assert_almost_eq(
			production.yield_per_second(occupation, world, Vector2.ZERO), expected, 0.000001,
			occupation
		)


## The invented constant is gone. It was "chosen for reasonable pacing,
## verified behaviorally" by its own doc comment, and applying it to a
## density and to two headcounts alike is what made the three producers
## incomparable.
func test_no_single_invented_production_rate_survives():
	assert_false(
		"PRODUCTION_RATE_PER_SECOND" in NpcProduction,
		"one rate across three different quantities is exactly the bug"
	)


## Against the village's own draw, the three now say something sensible:
## a farmer can feed a village, a fisher on open water can feed several, and
## a hunter working a chunk that holds about one deer cannot feed anybody.
## Pinned so the ORDER cannot silently invert again.
func test_a_farmer_out_produces_a_hunter_on_the_same_ordinary_land():
	world.vegetation_density = 0.15   # measured on real settlement chunks
	world.herbivore_population = 0.9  # measured on the same chunks
	world.fish_population = 0.0
	assert_gt(
		production.yield_per_second("farmer", world, Vector2.ZERO),
		production.yield_per_second("hunter", world, Vector2.ZERO),
		"a chunk of grassland holds far more food as grass than as deer"
	)


## NpcProduction prices a REGION it cannot import the size of --
## EarthChunkManager preloads this module, so the dependency runs one way
## only. These are the pins that keep the two from drifting: the region this
## module prices is the chunk the world actually loads, and the day it
## spreads a yield over is the day the world actually runs.
func test_the_region_this_module_prices_is_the_chunk_the_world_loads():
	var EarthChunkManager = load("res://src/world/earth_chunk_manager.gd")
	assert_eq(
		NpcProduction.CELLS_PER_REGION,
		EarthChunkManager.CHUNK_SIZE * EarthChunkManager.CHUNK_SIZE,
		"a per-cell mean is multiplied back up by the wrong number of cells otherwise"
	)
	assert_almost_eq(
		NpcProduction.SECONDS_PER_SIMULATED_DAY,
		float(EarthChunkManager.SECONDS_PER_SIMULATED_DAY), 0.001,
		"a per-day renewal spread over the wrong day is the wrong rate"
	)


## One producer reaches a part of a region, never all of it: a 1024-cell
## chunk of grassland holds far more food than one person can work, and
## handing them all of it made foraging beat farming five to one.
func test_one_producer_reaches_only_part_of_a_region():
	for occupation in ["farmer", "hunter", "fisher"]:
		assert_gt(NpcProduction.reach_share(occupation), 0.0, occupation)
		assert_lte(
			NpcProduction.reach_share(occupation), 1.0,
			"nobody forages more ground than there is"
		)
	assert_eq(NpcProduction.reach_share("guard"), 0.0, "a guard forages nothing")


## Each trade's reach is the one this game already measured for that trade's
## own real work -- never a number invented for the drip.
func test_each_trades_reach_is_its_own_real_working_reach():
	assert_almost_eq(
		NpcProduction.reach_cells("farmer"),
		PI * pow(float(VillageFarm.FIELD_REACH_TILES), 2.0), 0.001
	)
	assert_almost_eq(
		NpcProduction.reach_cells("hunter"),
		PI * pow(HuntableQuarry.SEARCH_RADIUS_PX / TerrainRenderer.TILE_SIZE, 2.0), 0.001
	)


## The fisher's reach is NpcMarker's own cast distance, written out in
## NpcProduction because a pure module cannot import a Node2D scene script.
func test_a_fishers_reach_is_the_cast_this_game_already_measured():
	var NpcMarker = load("res://src/rendering/npc_marker.gd")
	assert_almost_eq(
		NpcProduction.reach_cells("fisher"),
		PI * pow(NpcMarker.CAST_DISTANCE_PX / TerrainRenderer.TILE_SIZE, 2.0), 0.001
	)


const VillageFarm = preload("res://src/gameplay/village_farm.gd")
const HuntableQuarry = preload("res://src/gameplay/huntable_quarry.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")
