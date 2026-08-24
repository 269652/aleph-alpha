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

const PRODUCER_ITEM_BY_OCCUPATION := {
	"farmer": "fruit",
	"hunter": "meat",
	"fisher": "fish",
}

## Fraction of the real standing regional resource number (vegetation
## density, herbivore headcount, fish headcount) converted to gathered food
## per second of work. Deliberately ONE shared rate across all three
## producer roles: each already reads a domain-appropriate real number at
## its own natural scale (a 0-1 density for farming vs. a population
## headcount for hunting/fishing), so a single "gather this fraction of the
## standing resource" rule keeps the three producers on one rule rather than
## three independently-guessed magnitudes -- matches this codebase's
## existing fraction-per-time-unit tuned-rate convention (Vegetation
## GrowthModel.GROWTH_PACE_PER_DAY=0.5, HerbivorePopulationModel.
## MIGRATION_RATE_PER_DAY=0.5, VegetationGrowthModel.SPREAD_RATE_PER_DAY=0.1),
## applied per real second since NPC work is observed in real seconds (see
## NpcMarker.SECONDS_PER_SIMULATED_DAY), not simulated days. Verified
## behaviorally (yield scales with the real number, drops under worse real
## conditions, zero for a non-producer) rather than pinned to a specific
## magnitude -- same "chosen for reasonable pacing, verified behaviorally"
## convention as CreatureNeeds.HUNGER_RATE_PER_SECOND's own doc comment.
const PRODUCTION_RATE_PER_SECOND := 0.05

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
func yield_per_second(occupation: String, world, pixel_position: Vector2) -> float:
	if world == null:
		return 0.0
	match occupation:
		"farmer":
			if not world.has_method("vegetation_density_near"):
				return 0.0
			return PRODUCTION_RATE_PER_SECOND * world.vegetation_density_near(pixel_position)
		"hunter":
			if not world.has_method("herbivore_population_near"):
				return 0.0
			return PRODUCTION_RATE_PER_SECOND * world.herbivore_population_near(pixel_position)
		"fisher":
			if not world.has_method("fish_population_near"):
				return 0.0
			return PRODUCTION_RATE_PER_SECOND * world.fish_population_near(pixel_position)
		_:
			return 0.0
