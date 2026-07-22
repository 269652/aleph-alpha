extends RefCounted

## Generic regional/aggregate population dynamics, shared by
## HerbivorePopulationModel and PredatorPopulationModel (Phase 1 roadmap:
## "regional/aggregate population model: reproduction/migration/death as a
## function of local [resource] density"). Deliberately resource-agnostic --
## the caller decides what "capacity" means (vegetation density for
## herbivores, prey population for predators).

var growth_rate_per_day: float


func _init(a_growth_rate_per_day: float) -> void:
	growth_rate_per_day = a_growth_rate_per_day


## Logistic growth/decline of a region's population toward carrying_capacity
## over delta_days simulated days. Population above capacity declines
## (famine/overcrowding); population below capacity grows (reproduction).
func step(population: float, carrying_capacity: float, delta_days: float) -> float:
	if carrying_capacity <= 0.0:
		return 0.0
	var change := (
		growth_rate_per_day * population * (1.0 - population / carrying_capacity) * delta_days
	)
	# Growth can't overshoot capacity in one step; decline (population already
	# above capacity) is only bounded below by zero, not back up to capacity.
	return clampf(population + change, 0.0, maxf(carrying_capacity, population))


## Redistributes population between regions whose surplus (population minus
## carrying capacity) differs from a 4-connected neighbor's, moving from
## higher-surplus toward lower-surplus regions. Conserves total population
## (individuals relocate, they aren't created or destroyed by migration).
## Only regions present as keys in `populations` are considered -- a region
## with no simulated neighbor in that set is left unchanged.
func migrate(
	populations: Dictionary, capacities: Dictionary, migration_rate_per_day: float, delta_days: float
) -> Dictionary:
	var net_flow: Dictionary = {}
	for coord in populations:
		net_flow[coord] = 0.0

	for coord in populations:
		var coord_v2i: Vector2i = coord
		for offset in [Vector2i(1, 0), Vector2i(0, 1)]:
			var neighbor: Vector2i = coord_v2i + offset
			if not populations.has(neighbor):
				continue

			var surplus_a: float = populations[coord] - capacities.get(coord, 0.0)
			var surplus_b: float = populations[neighbor] - capacities.get(neighbor, 0.0)
			var diff := surplus_a - surplus_b
			if diff == 0.0:
				continue

			var source: Vector2i = coord_v2i if diff > 0.0 else neighbor
			var dest: Vector2i = neighbor if diff > 0.0 else coord_v2i
			var flow: float = minf(
				migration_rate_per_day * absf(diff) * delta_days, populations[source]
			)

			net_flow[source] -= flow
			net_flow[dest] += flow

	var result: Dictionary = {}
	for coord in populations:
		result[coord] = maxf(0.0, populations[coord] + net_flow[coord])
	return result
