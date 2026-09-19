extends RefCounted

## docs/concept/npc.md "Needs and the local production economy": a producer
## occupation's real per-second food yield.
##
## Producer occupations (farmer, hunter, fisher) read the SAME weather-tied
## regional numbers the wild ecosystem itself already runs on -- never an
## invented economy stat:
## - farmer -> EarthChunkManager.vegetation_density_near, the same
##   effective_capacity-chasing density (VegetationGrowthModel) that
##   visibly thins wild grass under a real drought.
## - hunter -> EarthChunkManager.herbivore_population_near, the same
##   regional headcount (HerbivorePopulationModel, ultimately driven by
##   vegetation + water access) wildlife density already runs on.
## - fisher -> EarthChunkManager.fish_population_near, the same regional
##   headcount (AquaticPopulationModel, driven by water area + temperature)
##   fish density already runs on.
##
## `world` is duck-typed exactly like the rest of this codebase's world-
## reading code (NpcMarker.setup, CreatureMarker, PiscivoreBirdMarker) --
## null or missing the accessor fails open to zero yield rather than
## crashing.
##
## Reuses existing food item ids (ItemCatalog) for what each producer
## gathers rather than inventing new ones.

const VegetationGrowthModel = preload("res://src/world/vegetation_growth_model.gd")
const VillageFarm = preload("res://src/gameplay/village_farm.gd")
const HuntableQuarry = preload("res://src/gameplay/huntable_quarry.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")
const HerbivorePopulationModel = preload("res://src/world/herbivore_population_model.gd")
const AquaticPopulationModel = preload("res://src/world/aquatic_population_model.gd")

const PRODUCER_ITEM_BY_OCCUPATION := {
	"farmer": "fruit",
	"hunter": "meat",
	"fisher": "fish",
}

## How many cells one region's vegetation density is a mean OF.
##
## This is the whole unit fix. `vegetation_density_near` returns a per-CELL
## MEAN in 0..1, while `herbivore_population_near` and `fish_population_near`
## return chunk TOTALS -- and one shared rate used to be applied to all
## three alike, which is how a farmer's yield came out four orders of
## magnitude below a fisher's on the same map (measured,
## tools/probe_village_demand.gd; see
## docs/concept/settlement_food_calibration.md).
##
## EarthChunkManager.CHUNK_SIZE squared. Declared here rather than imported,
## because that module preloads this one and the dependency can only run one
## way; pinned across the seam by
## test_the_region_this_module_prices_is_the_chunk_the_world_loads.
const CELLS_PER_REGION := 32 * 32

## How long one simulated day is, in world seconds. Same seam, same reason:
## EarthChunkManager.SECONDS_PER_SIMULATED_DAY, pinned by the same test.
const SECONDS_PER_SIMULATED_DAY := 60.0

## How far each trade RANGES while foraging, in tiles -- their own reach,
## every one of them a constant this codebase already measured for that
## trade's real work.
##
## Without a reach the drip hands ONE villager the whole chunk's sustainable
## yield, and a 1024-cell chunk of grassland holds far more food than any
## one person can get to. Measured consequence when it did: the ambient drip
## came out at 1152 food per work block against the 225 a real worked field
## yields -- a farmer five times better off not farming, which inverts the
## one thing about a village that is not negotiable.
##
## - farmer/herbalist: VillageFarm.FIELD_REACH_TILES, how far a villager
##   works out from their own farmhouse.
## - hunter: HuntableQuarry.SEARCH_RADIUS_PX, how far they really look for
##   an animal.
## - fisher: NpcMarker's own CAST_DISTANCE_PX, how far a line reaches --
##   written out rather than imported, because npc_marker.gd is a Node2D
##   scene script and this is a pure module; pinned to it by
##   test_a_fishers_reach_is_the_cast_this_game_already_measured.
##
## That these are the RIGHT three numbers is not asserted here, it is
## cross-checked: at VillageFarm.FIELD_REACH_TILES the farmer's drip comes
## out at about a seventh of a real field's measured 225 per work block,
## which is the "about eight times the drip it replaces" that
## village_farms.md already states as the design intent -- an anchor written
## down before this change and arrived at independently of it.
const REACH_TILES_BY_OCCUPATION := {
	"farmer": VillageFarm.FIELD_REACH_TILES,
	"herbalist": VillageFarm.FIELD_REACH_TILES,
	"hunter": HuntableQuarry.SEARCH_RADIUS_PX / TerrainRenderer.TILE_SIZE,
	"fisher": 64.0 / TerrainRenderer.TILE_SIZE,
}

## A logistic population grows fastest at half its carrying capacity, and
## the yield at that point -- r*K/4 -- is its MAXIMUM SUSTAINABLE YIELD:
## the most that can be taken for ever without the population declining.
## Textbook, not a number chosen here.
const MAX_SUSTAINABLE_YIELD_DIVISOR := 4.0

## Each producer's resource renews at ITS OWN rate, written down in its own
## model. That is what replaced the single invented PRODUCTION_RATE_PER_
## SECOND: "gather this fraction of what is standing" said nothing about
## what the land can bear, and applying one fraction to a density and to two
## headcounts is what made the three producers incomparable.
const RENEWAL_RATE_PER_DAY_BY_OCCUPATION := {
	"farmer": VegetationGrowthModel.GROWTH_PACE_PER_DAY,
	"hunter": HerbivorePopulationModel.GROWTH_RATE_PER_DAY,
	"fisher": AquaticPopulationModel.GROWTH_RATE_PER_DAY,
}

## One whole gatherable/sellable food unit -- matches NpcNeeds.feed()'s
## one-shot-to-zero meal size and VillageMarket.FOOD_UNITS_PER_MEAL, so
## production, stock, and consumption all move in the same real unit.
const FOOD_UNIT := 1.0

## Gold a producer earns per food unit the instant it crosses into the
## village stock (docs/concept/economy.md's "selling to the market" faucet,
## now running at village scale -- see NpcEconomy). Deliberately below
## VillageMarket.VILLAGE_LOCAL_FOOD_PRICE (2) so village-local trade carries
## a real wholesale-vs-retail margin rather than round-tripping a buyer's
## gold back to the seller unchanged, the same wholesale-vs-retail gap real
## produce markets have. Verified by
## test_yield_to_gold_rate_is_below_village_local_price.
const YIELD_TO_GOLD_RATE := 1


func is_producer(occupation: String) -> bool:
	return PRODUCER_ITEM_BY_OCCUPATION.has(occupation)


## The real food item this producer occupation gathers, or "" for a
## non-producer.
func item_id_for(occupation: String) -> String:
	return PRODUCER_ITEM_BY_OCCUPATION.get(occupation, "")


## Real per-second food yield for `occupation` at `pixel_position`, reading
## world's real weather-tied accessor for that occupation (see file doc
## comment). 0.0 for a non-producer, or when world is null/doesn't expose
## the accessor (fail-open).
## How fast `occupation`'s own resource replaces itself here, per simulated
## day. 0.0 for a non-producer.
static func renewal_rate_per_day(occupation: String) -> float:
	return float(RENEWAL_RATE_PER_DAY_BY_OCCUPATION.get(occupation, 0.0))


## The food this region is standing on for `occupation`, in FOOD UNITS --
## one currency for all three producers.
##
## That they are the same currency is not an assumption made here: it is
## what NpcEconomy._deplete_continuous/_deplete_discrete_unit already spend.
## One food unit gathered costs the region one unit of vegetation density,
## one herbivore, or one fish. So a cell's density unit, a deer and a fish
## are each one food unit by the game's own accounting, and the only thing
## missing was multiplying the per-cell MEAN back up by the cells it is a
## mean of.
##
## Duck-typed and fail-open exactly as before: a null world, or one missing
## the accessor, has no food in it rather than crashing.
func standing_food(occupation: String, world, pixel_position: Vector2) -> float:
	if world == null:
		return 0.0
	match occupation:
		"farmer":
			if not world.has_method("vegetation_density_near"):
				return 0.0
			return world.vegetation_density_near(pixel_position) * float(CELLS_PER_REGION)
		"hunter":
			if not world.has_method("herbivore_population_near"):
				return 0.0
			return world.herbivore_population_near(pixel_position)
		"fisher":
			if not world.has_method("fish_population_near"):
				return 0.0
			return world.fish_population_near(pixel_position)
	return 0.0


## How many of a region's cells this trade's own reach covers -- a disc of
## REACH_TILES_BY_OCCUPATION, capped at the region itself (nobody forages
## more ground than there is).
static func reach_cells(occupation: String) -> float:
	var tiles := float(REACH_TILES_BY_OCCUPATION.get(occupation, 0.0))
	return minf(PI * tiles * tiles, float(CELLS_PER_REGION))


## The share of a region this trade reaches. A statement about the PERSON,
## not about the crop, which is why it multiplies every resource alike.
static func reach_share(occupation: String) -> float:
	return reach_cells(occupation) / float(CELLS_PER_REGION)


## Real per-second food yield for `occupation` at `pixel_position`: this
## region's own MAXIMUM SUSTAINABLE YIELD of that resource, r*K/4 per
## simulated day, spread over the day's seconds.
##
## A forager who takes a share of what STANDS there can strip a region; one
## who takes a share of what it REPLACES can work it for ever. The second is
## the rate a real fishery or a real hunting ground is managed at, and it is
## the only one of the two that says the same thing about grass, deer and
## fish -- which is what the three producers needed before any of them could
## be compared with the others or with what a village eats.
##
## The region's standing stock stands in for its carrying capacity K:
## EcosystemSimulation seeds a region at equilibrium ("the world is assumed
## to already contain a mature ecosystem"), so an unworked region's N IS its
## K -- and a region that HAS been worked down yields less, which is the
## right direction and is what land health already reads
## (VegetationGrowthModel.step_land_health compares a harvest rate against
## exactly this regrowth).
func yield_per_second(occupation: String, world, pixel_position: Vector2) -> float:
	var renewal := renewal_rate_per_day(occupation)
	if renewal <= 0.0:
		return 0.0
	return (
		renewal * standing_food(occupation, world, pixel_position) * reach_share(occupation)
		/ MAX_SUSTAINABLE_YIELD_DIVISOR / SECONDS_PER_SIMULATED_DAY
	)
