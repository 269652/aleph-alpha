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

## How fast a region's persistent LAND HEALTH (see step_land_health, and
## docs/concept/world.md's "Land health: overharvesting leaves a lasting
## mark, not just a slower respawn") recovers per simulated day once left
## fallow (harvest not exceeding regrowth).
##
## Real-world grounding: GROWTH_PACE_PER_DAY stands in for standing-BIOMASS
## regrowth, which real vegetation completes within a single growing season
## (weeks to a few months). Land health instead stands for soil ORGANIC
## MATTER AND STRUCTURE -- a slower, different process. Once meaningfully
## depleted by sustained overuse, real soil organic matter takes on the
## order of a DECADE OR MORE of rest to rebuild measurably, and 20-50+ years
## for substantial recovery in degraded-rangeland restoration studies (see
## USDA-NRCS soil health guidance and rangeland soil-organic-carbon recovery
## literature) -- roughly a 40x-longer real-world timescale than a single
## growing season. This uses GROWTH_PACE_PER_DAY / 40, the conservative
## (fastest-recovering) end of that cited range, so the mechanic is still
## felt within a play session rather than requiring literal decades. Pinned
## by test_step_land_health_exact_recovery_pace; the order-of-magnitude
## claim itself is pinned by
## test_land_health_recovery_is_at_least_an_order_of_magnitude_slower_than_growth.
const LAND_HEALTH_RECOVERY_PACE_PER_DAY := GROWTH_PACE_PER_DAY / 40.0

## How fast land health depletes per simulated day while a region is
## genuinely OVERharvested (see step_land_health): harvest rate exceeding the
## region's own current regrowth rate.
##
## Real land degrades faster than it heals: sustained overgrazing/
## overharvesting produces measurable soil-health decline within a handful
## of years in overstocked-rangeland studies (commonly cited 3-10 years),
## well short of LAND_HEALTH_RECOVERY_PACE_PER_DAY's decade-plus recovery
## timescale -- but still much slower than a single season's biomass
## dieback, so one harvest that briefly outpaces regrowth for a single step
## should not visibly scar the land; only SUSTAINED pressure should. Set to
## GROWTH_PACE_PER_DAY / 8 -- 5x LAND_HEALTH_RECOVERY_PACE_PER_DAY's pace
## (40/8), matching that real damage-outpaces-repair asymmetry, while
## staying below raw GROWTH_PACE_PER_DAY itself. Pinned by
## test_step_land_health_exact_depletion_pace; the ordering claim is pinned
## by test_land_health_depletion_sits_between_recovery_and_raw_growth_pace.
const LAND_HEALTH_DEPLETION_PACE_PER_DAY := GROWTH_PACE_PER_DAY / 8.0

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
## current conditions are AND the region's persistent land health (see
## step_land_health). This -- not the raw ceiling -- is what density
## actually chases each step. Land health multiplies the weather-adjusted
## ceiling down FURTHER, the same shape as a drought, but driven by
## sustained overharvest rather than weather, and recovering on a far
## slower timescale (see LAND_HEALTH_RECOVERY_PACE_PER_DAY). Clamped to
## [0.0, 1.0] so it can only ever reduce the ceiling, never boost it past
## the weather-driven one. Defaults to 1.0 (pristine, no extra reduction)
## so every pre-existing caller that doesn't yet track land health sees the
## exact same number as before this parameter existed -- verified by
## test_effective_capacity_defaults_land_health_to_full_and_is_unaffected.
func effective_capacity(
	biome_name: String, temperature: float, moisture: float, land_health: float = 1.0
) -> float:
	return (
		carrying_capacity_for_biome(biome_name)
		* growth_rate(temperature, moisture)
		* clampf(land_health, 0.0, 1.0)
	)


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


## Instantaneous rate at which density is currently gaining ground toward
## capacity, in density-per-simulated-day -- the same logistic term
## step_density's growth branch integrates over delta_days, factored out so
## a caller (land health) can compare a live HARVEST rate against it without
## re-deriving step_density's math. Zero when there's no capacity to grow
## toward, or density has already met/exceeded it (a shrinking or
## already-full cell is not "regrowing"). Pinned exactly by
## test_regrowth_rate_matches_the_logistic_growth_term_exactly.
func regrowth_rate(density: float, capacity: float) -> float:
	if capacity <= 0.0 or density >= capacity:
		return 0.0
	return GROWTH_PACE_PER_DAY * density * (1.0 - density / capacity)


## Advances a region's persistent LAND HEALTH (docs/concept/world.md "Land
## health: overharvesting leaves a lasting mark, not just a slower respawn")
## by delta_days -- distinct from, and far slower than, the standing
## vegetation density/biomass effective_capacity/step_density already model.
##
## Depletes at LAND_HEALTH_DEPLETION_PACE_PER_DAY whenever harvest_rate_per_day
## exceeds regrowth_rate_per_day: more is being taken than the land can
## currently replace, i.e. genuine SUSTAINED overharvest, not any single
## harvest event. Otherwise (harvest at or below what the land can currently
## regrow, including zero -- genuinely fallow) recovers at the much slower
## LAND_HEALTH_RECOVERY_PACE_PER_DAY. Always clamped to [0.0, 1.0].
func step_land_health(
	land_health: float, harvest_rate_per_day: float, regrowth_rate_per_day: float, delta_days: float
) -> float:
	if harvest_rate_per_day > regrowth_rate_per_day:
		return clampf(land_health - LAND_HEALTH_DEPLETION_PACE_PER_DAY * delta_days, 0.0, 1.0)
	return clampf(land_health + LAND_HEALTH_RECOVERY_PACE_PER_DAY * delta_days, 0.0, 1.0)


## Advances a whole chunk-sized grid by delta_days: each cell grows/dies back
## toward its own current effective_capacity, then picks up extra density
## from any denser vegetated neighbor (4-connected), modeling seed dispersal.
## Spread never reduces the source cell (real dispersal doesn't deplete the
## parent patch) and never pushes a cell past its own effective_capacity.
## `land_health` is a single region-aggregate value applied uniformly to
## every cell in this grid (see EcosystemSimulation's own doc comment for
## why land health is tracked per-chunk rather than per-cell) -- defaults to
## 1.0 (pristine) so existing callers are unaffected, matching
## effective_capacity's own default.
func step_grid(
	density: PackedFloat32Array,
	biome: Array,
	temperature: PackedFloat32Array,
	moisture: PackedFloat32Array,
	width: int,
	height: int,
	delta_days: float,
	land_health: float = 1.0
) -> PackedFloat32Array:
	var capacity := PackedFloat32Array()
	capacity.resize(density.size())
	for i in density.size():
		capacity[i] = effective_capacity(biome[i], temperature[i], moisture[i], land_health)

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
