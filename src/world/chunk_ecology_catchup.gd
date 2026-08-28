extends RefCounted

## Unloaded-chunk ecology catch-up integration (variable-fidelity LOD).
##
## Loaded chunks near the player run at individual-agent fidelity; unloaded
## chunks are NOT ticked per frame. Instead each records the world-time it was
## unloaded, and on reload this advances its aggregate state forward by the whole
## elapsed unloaded duration in ONE deterministic, pure step -- so the region
## reflects everything that "would have happened" while the player was away
## (vegetation regrew, trees fruited, herds grew, predators tracked their prey).
## See docs/concept/ecosystem_dynamics.md -- Population dynamics + Variable-fidelity.
##
## Reuses the SAME logistic/predator-prey models as the loaded per-chunk step
## (HerbivorePopulationModel / PredatorPopulationModel) so loaded and unloaded
## chunks share one model of truth -- no divergence beyond intended variation.

const HerbivorePopulationModel = preload("res://src/world/herbivore_population_model.gd")
const PredatorPopulationModel = preload("res://src/world/predator_population_model.gd")
const AquaticPopulationModel = preload("res://src/world/aquatic_population_model.gd")
const VegetationGrowthModel = preload("res://src/world/vegetation_growth_model.gd")
const RobinPopulationModel = preload("res://src/world/robin_population_model.gd")
const SparrowPopulationModel = preload("res://src/world/sparrow_population_model.gd")
const KingfisherPopulationModel = preload("res://src/world/kingfisher_population_model.gd")

## Game seconds that make up one simulated ecological "day" (the model_s unit the
## population models integrate in). One in-game hour of unloaded time is one
## ecological day of catch-up growth. Pinned by the growth tests below.
const SECONDS_PER_DAY := 3600.0

## Vegetation regrows toward full density (1.0) at this exponential rate per day.
## Gap-to-1.0 shrinks by (1 - e^(-rate*days)) each call, so vegetation approaches
## 1.0 monotonically and never overshoots. Pinned by the vegetation tests.
const VEGETATION_REGROWTH_PER_DAY := 0.2

## Aggregate ripe-fruit stock a chunk's trees can hold before further ripening is
## offset by abscission/decay -- fruit accumulates with elapsed time but is
## bounded here. Pinned by test_fruit_stock_stays_bounded.
const FRUIT_STOCK_MAX := 500.0

var _herbivore_model := HerbivorePopulationModel.new()
var _predator_model := PredatorPopulationModel.new()
var _aquatic_model := AquaticPopulationModel.new()
var _vegetation_model := VegetationGrowthModel.new()
var _robin_model := RobinPopulationModel.new()
var _sparrow_model := SparrowPopulationModel.new()
var _kingfisher_model := KingfisherPopulationModel.new()


## Integrate a chunk's aggregate ecology forward by `elapsed_seconds` in one step.
## `state`    -> {herbivores, predators, fruit_stock, vegetation, fish, land_health,
##                robins, sparrows, kingfishers}
## `capacity` -> {herbivore_capacity, fruit_growth_rate, fish_capacity,
##                robin_capacity, sparrow_capacity}
## Robin/sparrow capacities are supplied inputs (their food-density signal --
## worm burrows, ground seed -- lives outside this pure function, the same
## reason fish_capacity is a supplied input rather than derived here).
## Kingfisher has no capacity input: like predator deriving its capacity from
## the freshly-advanced herbivore population, kingfisher capacity is derived
## from the freshly-advanced fish population below.
## Pure: does not mutate `state`; returns a fresh dictionary.
func advance(state: Dictionary, elapsed_seconds: float, capacity: Dictionary) -> Dictionary:
	var elapsed := maxf(0.0, elapsed_seconds)
	var delta_days := elapsed / SECONDS_PER_DAY

	var herbivores: float = state.get("herbivores", 0.0)
	var predators: float = state.get("predators", 0.0)
	var fruit_stock: float = state.get("fruit_stock", 0.0)
	var vegetation: float = state.get("vegetation", 0.0)
	var fish: float = state.get("fish", 0.0)
	var land_health: float = state.get("land_health", 1.0)
	var robins: float = state.get("robins", 0.0)
	var sparrows: float = state.get("sparrows", 0.0)
	var kingfishers: float = state.get("kingfishers", 0.0)

	var herbivore_capacity: float = capacity.get("herbivore_capacity", 0.0)
	var fruit_growth_rate: float = capacity.get("fruit_growth_rate", 0.0)
	var fish_capacity: float = capacity.get("fish_capacity", 0.0)
	var robin_capacity: float = capacity.get("robin_capacity", 0.0)
	var sparrow_capacity: float = capacity.get("sparrow_capacity", 0.0)

	# Vegetation regrows toward 1.0 (exponential approach, monotone, no overshoot).
	var new_vegetation := 1.0 - (1.0 - vegetation) * exp(-VEGETATION_REGROWTH_PER_DAY * delta_days)

	# Land health (docs/concept/world.md "Land health: overharvesting leaves
	# a lasting mark, not just a slower respawn"): nothing harvests an
	# unloaded chunk, so this is pure recovery, never depletion -- harvest
	# rate is always 0.0 here, and step_land_health only depletes when
	# harvest exceeds regrowth, so a 0.0/0.0 comparison always takes the
	# recovery branch, at the same slow real-world-grounded pace loaded
	# chunks use (VegetationGrowthModel.LAND_HEALTH_RECOVERY_PACE_PER_DAY).
	var new_land_health := _vegetation_model.step_land_health(land_health, 0.0, 0.0, delta_days)

	# Fruit stock accumulates linearly with elapsed time, bounded by chunk capacity.
	var new_fruit_stock := minf(fruit_stock + fruit_growth_rate * elapsed, FRUIT_STOCK_MAX)

	# Herbivores: shared logistic growth toward the region's carrying capacity.
	var new_herbivores := _herbivore_model.step(herbivores, herbivore_capacity, delta_days)

	# Predators: carrying capacity derived from prey (herbivores) via the trophic
	# ratio, then the same logistic step -- rises with abundant prey, falls when
	# prey is scarce. Uses the post-step (current) herbivore level as its prey base.
	var predator_capacity := _predator_model.carrying_capacity(new_herbivores)
	var new_predators := _predator_model.step(predators, predator_capacity, delta_days)

	# Fish: same logistic step as herbivores, but its capacity is an
	# independent input (water area/temperature), not derived from anything
	# else in this state -- see docs/concept/fishing.md#unloaded-chunk-catch-up.
	var new_fish := _aquatic_model.step(fish, fish_capacity, delta_days)

	# Robin/sparrow: same logistic step as fish, against their own
	# independently-supplied capacity (worm/seed density, not derived from
	# anything else in this state).
	var new_robins := _robin_model.step(robins, robin_capacity, delta_days)
	var new_sparrows := _sparrow_model.step(sparrows, sparrow_capacity, delta_days)

	# Kingfisher: carrying capacity derived from the freshly-advanced fish
	# population, the same "post-step prey level" ordering predator_capacity
	# uses above for herbivores.
	var kingfisher_capacity := _kingfisher_model.carrying_capacity(new_fish)
	var new_kingfishers := _kingfisher_model.step(kingfishers, kingfisher_capacity, delta_days)

	return {
		"herbivores": new_herbivores,
		"predators": new_predators,
		"fruit_stock": new_fruit_stock,
		"vegetation": new_vegetation,
		"fish": new_fish,
		"land_health": new_land_health,
		"robins": new_robins,
		"sparrows": new_sparrows,
		"kingfishers": new_kingfishers,
	}
