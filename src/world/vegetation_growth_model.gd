extends RefCounted

## Per-cell vegetation density simulation (Phase 1 roadmap: "sunlight + moisture
## -> growth rate -> density, spreading to eligible neighbor cells, capped by
## carrying capacity"). Operates on a chunk-sized grid of density values;
## ClimateModel's temperature stands in for "sunlight" (there is no separate
## light model in this project -- temperature already encodes latitude +
## elevation, the two things that drive real-world solar exposure).
##
## Two distinct capacity concepts, deliberately kept separate:
## - carrying_capacity_for_biome(): a biome's ceiling under ideal conditions
##   (a fixed terrain property -- rainforest simply can support more biomass
##   than desert, regardless of today's weather).
## - effective_capacity(): what the ceiling reduces to under CURRENT
##   temperature/moisture -- this is the actual logistic target a cell chases.
## A drought doesn't change a desert's ceiling (it's already low); it lowers a
## grassland's effective target out from under its established vegetation,
## which is what should make existing vegetation visibly die back.

## Fixed biological pace at which density chases its current effective target,
## in fraction-of-gap-closed per simulated day. Deliberately NOT gated by
## growth_rate: a drought should make existing vegetation die back, not freeze
## in place just because conditions are currently unfavorable for new growth.
## Verified by test_step_density_moves_toward_carrying_capacity and
## test_step_density_declines_when_effective_capacity_drops_below_density.
const GROWTH_PACE_PER_DAY := 0.5

## How much of the density gradient to a denser vegetated neighbor gets picked
## up per simulated day. Verified by
## test_step_grid_spreads_density_toward_a_lower_density_vegetated_neighbor and
## test_step_grid_never_exceeds_each_cells_effective_capacity.
const SPREAD_RATE_PER_DAY := 0.1

## Mountain's 0.12 is deliberately below tundra's 0.2 (sparser alpine
## vegetation above the tree line) but nonzero -- real high-altitude terrain
## still sustains some sparse grazing (e.g. mountain goats), unlike ocean's
## genuine 0.0. Pinned by
## test_mountain_carrying_capacity_is_a_small_nonzero_placeholder.
const CARRYING_CAPACITY_BY_BIOME := {
	"ocean": 0.0,
	"mountain": 0.12,
	"tundra": 0.2,
	"desert": 0.15,
	"grassland": 0.6,
	"forest": 0.85,
	"rainforest": 1.0,
}


## A biome's ceiling capacity under ideal conditions. Unlisted biomes default
## to 0.0 (can't sustain vegetation) rather than erroring, so new biomes fail
## safe instead of crashing the simulation.
func carrying_capacity_for_biome(biome_name: String) -> float:
	return CARRYING_CAPACITY_BY_BIOME.get(biome_name, 0.0)


## How suitable current conditions are for vegetation, in [0.0, 1.0], from
## normalized temperature and moisture -- both are required (a desert with
## warmth but no water grows nothing; a moist but frozen tundra grows nothing
## either), so this is their product.
func growth_rate(temperature: float, moisture: float) -> float:
	return clampf(temperature, 0.0, 1.0) * clampf(moisture, 0.0, 1.0)


## What a biome's ceiling capacity reduces to right now, given how suitable
## current conditions are. This -- not the raw ceiling -- is what density
## actually chases each step.
func effective_capacity(biome_name: String, temperature: float, moisture: float) -> float:
	return carrying_capacity_for_biome(biome_name) * growth_rate(temperature, moisture)


## Moves a single cell's density toward effective_capacity at a fixed pace,
## over delta_days simulated days -- grows if below it, dies back if above it
## (e.g. a drought just lowered effective_capacity out from under existing
## density).
func step_density(density: float, capacity: float, delta_days: float) -> float:
	if capacity <= 0.0:
		# No division-safe target to chase -- decay at the same fixed pace
		# instead of an instant cutoff, so a sudden drought reads as a
		# visible decline over several simulated days, not a snap to zero.
		return maxf(0.0, density * (1.0 - clampf(GROWTH_PACE_PER_DAY * delta_days, 0.0, 1.0)))
	var change := GROWTH_PACE_PER_DAY * density * (1.0 - density / capacity) * delta_days
	return clampf(density + change, 0.0, maxf(capacity, density))


## Advances a whole chunk-sized grid by delta_days: each cell grows/dies back
## toward its own current effective_capacity, then picks up extra density
## from any denser vegetated neighbor (4-connected), modeling seed dispersal.
## Spread never reduces the source cell (real dispersal doesn't deplete the
## parent patch) and never pushes a cell past its own effective_capacity.
func step_grid(
	density: PackedFloat32Array,
	biome: Array,
	temperature: PackedFloat32Array,
	moisture: PackedFloat32Array,
	width: int,
	height: int,
	delta_days: float
) -> PackedFloat32Array:
	var capacity := PackedFloat32Array()
	capacity.resize(density.size())
	for i in density.size():
		capacity[i] = effective_capacity(biome[i], temperature[i], moisture[i])

	var next := PackedFloat32Array()
	next.resize(density.size())

	for y in height:
		for x in width:
			var index := y * width + x
			var cell_capacity: float = capacity[index]
			var grown := step_density(density[index], cell_capacity, delta_days)

			# A cell with zero capacity (ocean, mountain) can never receive
			# spread, no matter how dense its neighbors are.
			var inflow := 0.0
			if cell_capacity > 0.0:
				for neighbor_index in _neighbor_indices(x, y, width, height):
					var gradient: float = density[neighbor_index] - density[index]
					if gradient > 0.0:
						inflow += SPREAD_RATE_PER_DAY * gradient * delta_days

			next[index] = clampf(grown + inflow, 0.0, maxf(cell_capacity, density[index]))

	return next


const _NEIGHBOR_OFFSETS: Array[Vector2i] = [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]


func _neighbor_indices(x: int, y: int, width: int, height: int) -> Array[int]:
	var result: Array[int] = []
	for offset in _NEIGHBOR_OFFSETS:
		var neighbor: Vector2i = Vector2i(x, y) + offset
		if neighbor.x >= 0 and neighbor.x < width and neighbor.y >= 0 and neighbor.y < height:
			result.append(neighbor.y * width + neighbor.x)
	return result
