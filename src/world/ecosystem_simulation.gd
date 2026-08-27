extends RefCounted

## Ties vegetation growth, herbivore population, and predator population
## together per loaded chunk region (Phase 1 roadmap's "living ecosystem").
##
## Scope decisions, matching how EarthChunkManager already treats terrain:
## - Regions are per-chunk aggregates for herbivores/predators (as roadmapped)
##   and per-cell for vegetation within a chunk (also as roadmapped) -- but
##   there is no true whole-planet background simulation. Only regions
##   currently add_region()-ed (i.e. loaded, same as terrain chunks) are
##   simulated; nothing decays or grows while unloaded. A "catch-up pass" for
##   unloaded regions is a real, separate follow-up (tracked in
##   docs/progress.md as "Variable-Fidelity Chunk Simulation").
## - "Water access" is approximated as the fraction of a region's cells that
##   are ocean biome -- the only water body this project currently models.
## - Land health (docs/concept/world.md "Land health: overharvesting leaves a
##   lasting mark, not just a slower respawn") is a PER-CHUNK AGGREGATE
##   scalar, deliberately NOT per-cell like vegetation density itself. This
##   is a documented fidelity call: herbivore/predator/fish populations are
##   already chunk aggregates in this same file, and the "harvest" numbers
##   feeding land health (a farmer NPC's yield, a region's average density)
##   are themselves already chunk-aggregate reads -- a per-cell land-health
##   grid would double the persisted state and per-step cost of this feature
##   for a value nothing yet reads at finer-than-chunk granularity.

const Chunk = preload("res://src/world/chunk.gd")
const VegetationGrowthModel = preload("res://src/world/vegetation_growth_model.gd")
const HerbivorePopulationModel = preload("res://src/world/herbivore_population_model.gd")
const PredatorPopulationModel = preload("res://src/world/predator_population_model.gd")
const AquaticPopulationModel = preload("res://src/world/aquatic_population_model.gd")
const WaterAreaSurvey = preload("res://src/world/water_area_survey.gd")

var _vegetation_model := VegetationGrowthModel.new()
var _herbivore_model := HerbivorePopulationModel.new()
var _predator_model := PredatorPopulationModel.new()
var _aquatic_model := AquaticPopulationModel.new()
var _water_survey := WaterAreaSurvey.new()

var _chunks: Dictionary = {}  # Vector2i chunk_coord -> Chunk
var _vegetation_density: Dictionary = {}  # Vector2i chunk_coord -> PackedFloat32Array
var _water_access: Dictionary = {}  # Vector2i chunk_coord -> float
var _herbivore_population: Dictionary = {}  # Vector2i chunk_coord -> float
var _predator_population: Dictionary = {}  # Vector2i chunk_coord -> float
var _water_area_cells: Dictionary = {}  # Vector2i chunk_coord -> float (see fish_capacity_at)
var _water_temperature: Dictionary = {}  # Vector2i chunk_coord -> float
var _fish_population: Dictionary = {}  # Vector2i chunk_coord -> float
var _land_health: Dictionary = {}  # Vector2i chunk_coord -> float, see land_health()
## Vegetation harvested (via record_vegetation_harvest) since the last step()
## call, per region -- consumed and reset to 0.0 by step() itself, which
## turns it into a per-day rate to compare against the region's own
## regrowth_rate (see step()'s doc comment and VegetationGrowthModel.
## step_land_health).
var _harvest_accumulator: Dictionary = {}  # Vector2i chunk_coord -> float


## Starts simulating a newly-loaded region, seeded at ecosystem equilibrium
## for its biome mix (vegetation at carrying capacity, herbivores/predators at
## the population their local resources can sustain) -- consistent with the
## game's existing static tree placement: the world is assumed to already
## contain a mature ecosystem, not one growing from nothing on first visit.
func add_region(chunk_coord: Vector2i, chunk: Chunk) -> void:
	_chunks[chunk_coord] = chunk

	var density := PackedFloat32Array()
	density.resize(chunk.biome.size())
	for i in chunk.biome.size():
		density[i] = _vegetation_model.effective_capacity(
			chunk.biome[i], chunk.temperature[i], chunk.moisture[i]
		)
	_vegetation_density[chunk_coord] = density
	_water_access[chunk_coord] = _water_access_fraction(chunk)
	# A newly-loaded region is assumed pristine, matching this function's own
	# doc comment ("the world is assumed to already contain a mature
	# ecosystem, not one growing from nothing") -- a real persisted value (if
	# any) is installed afterward via seed_land_health, the same override
	# pattern seed_populations/seed_fish_population already use.
	_land_health[chunk_coord] = 1.0
	_harvest_accumulator[chunk_coord] = 0.0

	var herbivore_capacity := _herbivore_model.carrying_capacity(
		_average(density), _water_access[chunk_coord]
	)
	_herbivore_population[chunk_coord] = herbivore_capacity
	_predator_population[chunk_coord] = _predator_model.carrying_capacity(herbivore_capacity)

	_water_area_cells[chunk_coord] = _water_survey.interior_water_cell_count(chunk)
	_water_temperature[chunk_coord] = _water_survey.mean_interior_water_temperature(chunk)
	_fish_population[chunk_coord] = _aquatic_model.carrying_capacity(
		_water_area_cells[chunk_coord], _water_temperature[chunk_coord]
	)


## Stops simulating a region (its unloaded chunk's terrain is regenerated
## deterministically on revisit -- see EarthChunkManager -- so this state is
## likewise dropped rather than persisted; the same known simplification).
func remove_region(chunk_coord: Vector2i) -> void:
	_chunks.erase(chunk_coord)
	_vegetation_density.erase(chunk_coord)
	_water_access.erase(chunk_coord)
	_herbivore_population.erase(chunk_coord)
	_predator_population.erase(chunk_coord)
	_water_area_cells.erase(chunk_coord)
	_water_temperature.erase(chunk_coord)
	_fish_population.erase(chunk_coord)
	_land_health.erase(chunk_coord)
	_harvest_accumulator.erase(chunk_coord)


func has_region(chunk_coord: Vector2i) -> bool:
	return _chunks.has(chunk_coord)


## Swaps an already-loaded region's environmental input (e.g. a drought
## lowering moisture) without resetting its current vegetation/population
## state -- conditions changing for a living region, not a fresh region.
func update_environment(chunk_coord: Vector2i, chunk: Chunk) -> void:
	if _chunks.has(chunk_coord):
		_chunks[chunk_coord] = chunk
		_water_access[chunk_coord] = _water_access_fraction(chunk)
		_water_area_cells[chunk_coord] = _water_survey.interior_water_cell_count(chunk)
		_water_temperature[chunk_coord] = _water_survey.mean_interior_water_temperature(chunk)


## Advances every currently-loaded region by delta_days simulated days:
## land health first (see below), then vegetation grows/spreads per-cell
## against that freshly-updated land health, then herbivore and predator
## populations grow/decline toward their resource-derived capacity and
## migrate toward adjacent regions with spare capacity.
##
## Land health step: compares this region's HARVEST rate since the last
## step() (see record_vegetation_harvest/_harvest_accumulator) against its
## own current regrowth_rate (how fast the land can currently replace what
## was taken, at its PRE-step density/capacity) -- sustained harvest above
## that rate depletes land health; anything at or below it (including no
## harvest at all) lets it slowly recover. See VegetationGrowthModel.
## step_land_health for the tested rates.
func step(delta_days: float) -> void:
	for chunk_coord in _vegetation_density.keys():
		var chunk: Chunk = _chunks[chunk_coord]
		var density: PackedFloat32Array = _vegetation_density[chunk_coord]
		var current_land_health: float = _land_health.get(chunk_coord, 1.0)

		if delta_days > 0.0:
			var regrowth_rate := _vegetation_model.regrowth_rate(
				_average(density), _average_capacity(chunk, current_land_health)
			)
			var harvest_rate: float = _harvest_accumulator.get(chunk_coord, 0.0) / delta_days
			current_land_health = _vegetation_model.step_land_health(
				current_land_health, harvest_rate, regrowth_rate, delta_days
			)
			_land_health[chunk_coord] = current_land_health
		_harvest_accumulator[chunk_coord] = 0.0

		_vegetation_density[chunk_coord] = _vegetation_model.step_grid(
			density,
			chunk.biome,
			chunk.temperature,
			chunk.moisture,
			chunk.width,
			chunk.height,
			delta_days,
			current_land_health
		)

	var herbivore_capacities: Dictionary = {}
	for chunk_coord in _vegetation_density.keys():
		herbivore_capacities[chunk_coord] = _herbivore_model.carrying_capacity(
			average_vegetation_density(chunk_coord), _water_access.get(chunk_coord, 0.0)
		)
	# Migrate on the new capacities before locally stepping population toward
	# them: a region whose capacity just collapsed (e.g. a drought) should let
	# its population flee toward a spare-capacity neighbor first, rather than
	# being clamped straight to the new (possibly zero) capacity locally with
	# nothing left to migrate.
	if not _herbivore_population.is_empty():
		_herbivore_population = _herbivore_model.migrate(
			_herbivore_population, herbivore_capacities, delta_days
		)
	for chunk_coord in _herbivore_population.keys():
		_herbivore_population[chunk_coord] = _herbivore_model.step(
			_herbivore_population[chunk_coord], herbivore_capacities.get(chunk_coord, 0.0), delta_days
		)

	var predator_capacities: Dictionary = {}
	for chunk_coord in _herbivore_population.keys():
		predator_capacities[chunk_coord] = _predator_model.carrying_capacity(
			_herbivore_population[chunk_coord]
		)
	if not _predator_population.is_empty():
		_predator_population = _predator_model.migrate(
			_predator_population, predator_capacities, delta_days
		)
	for chunk_coord in _predator_population.keys():
		_predator_population[chunk_coord] = _predator_model.step(
			_predator_population[chunk_coord], predator_capacities.get(chunk_coord, 0.0), delta_days
		)

	# Fish: same logistic-growth-plus-migration shape as herbivores, but
	# capacity comes from water area/temperature instead of vegetation (see
	# docs/concept/fishing.md#aquatic-population-model) -- an independent
	# population, not derived from the land trophic chain.
	var fish_capacities: Dictionary = {}
	for chunk_coord in _fish_population.keys():
		fish_capacities[chunk_coord] = _aquatic_model.carrying_capacity(
			_water_area_cells.get(chunk_coord, 0.0), _water_temperature.get(chunk_coord, 0.5)
		)
	if not _fish_population.is_empty():
		_fish_population = _aquatic_model.migrate(_fish_population, fish_capacities, delta_days)
	for chunk_coord in _fish_population.keys():
		_fish_population[chunk_coord] = _aquatic_model.step(
			_fish_population[chunk_coord], fish_capacities.get(chunk_coord, 0.0), delta_days
		)


func average_vegetation_density(chunk_coord: Vector2i) -> float:
	return _average(_vegetation_density.get(chunk_coord, PackedFloat32Array()))


## This region's persistent land health (docs/concept/world.md "Land health:
## overharvesting leaves a lasting mark, not just a slower respawn"), in
## [0.0, 1.0]. Fail-open to 1.0 (pristine) for an unknown/unloaded region --
## same convention as herbivore_capacity_at/fish_capacity_at failing open to
## 0.0: a region nothing has ever touched should read as untouched, not as
## the worst possible degradation.
func land_health(chunk_coord: Vector2i) -> float:
	return _land_health.get(chunk_coord, 1.0)


## Overrides a region's land health -- used on chunk reload to install a
## persisted (or unloaded-time-caught-up) value instead of add_region's
## fresh-pristine seeding, the same override pattern seed_populations/
## seed_fish_population already use. A no-op for a region that isn't
## currently loaded, matching seed_populations's own guard.
func seed_land_health(chunk_coord: Vector2i, value: float) -> void:
	if _land_health.has(chunk_coord):
		_land_health[chunk_coord] = clampf(value, 0.0, 1.0)


func herbivore_population(chunk_coord: Vector2i) -> float:
	return _herbivore_population.get(chunk_coord, 0.0)


## This region's herbivore carrying capacity K (from vegetation + water) --
## the target the unloaded-chunk catch-up integrates toward (see
## ChunkEcologyCatchup / EarthChunkManager). 0.0 for an unknown region.
func herbivore_capacity_at(chunk_coord: Vector2i) -> float:
	if not _vegetation_density.has(chunk_coord):
		return 0.0
	return _herbivore_model.carrying_capacity(
		_average(_vegetation_density[chunk_coord]), _water_access.get(chunk_coord, 0.0)
	)


## Overrides a region's populations -- used on chunk reload to install the
## caught-up herbivore/predator counts computed by ChunkEcologyCatchup, instead
## of add_region's fresh-equilibrium seeding (which resets the region).
func seed_populations(chunk_coord: Vector2i, herbivores: float, predators: float) -> void:
	if _herbivore_population.has(chunk_coord):
		_herbivore_population[chunk_coord] = maxf(0.0, herbivores)
		_predator_population[chunk_coord] = maxf(0.0, predators)


func predator_population(chunk_coord: Vector2i) -> float:
	return _predator_population.get(chunk_coord, 0.0)


func fish_population(chunk_coord: Vector2i) -> float:
	return _fish_population.get(chunk_coord, 0.0)


## This region's fish carrying capacity K (from water area + temperature) --
## the target the unloaded-chunk catch-up integrates toward, same role as
## herbivore_capacity_at (see ChunkEcologyCatchup / EarthChunkManager). 0.0
## for an unknown region.
func fish_capacity_at(chunk_coord: Vector2i) -> float:
	if not _water_area_cells.has(chunk_coord):
		return 0.0
	return _aquatic_model.carrying_capacity(
		_water_area_cells[chunk_coord], _water_temperature.get(chunk_coord, 0.5)
	)


## Overrides a region's fish population -- used on chunk reload to install
## the caught-up count from ChunkEcologyCatchup, instead of add_region's
## fresh-equilibrium seeding (see seed_populations's identical role for
## herbivores/predators).
func seed_fish_population(chunk_coord: Vector2i, fish: float) -> void:
	if _fish_population.has(chunk_coord):
		_fish_population[chunk_coord] = maxf(0.0, fish)


## Subtracts a harvest (player rod or piscivore bird catch, see
## docs/concept/fishing.md#harvest-fishing-as-the-mortality-term) directly
## from this region's aggregate fish population -- the explicit mortality
## term the land herbivore/predator population still lacks (killing one
## today doesn't touch EcosystemSimulation at all). Never goes negative; a
## catch against an unknown region is a silent no-op (nothing to subtract
## from).
func record_catch(chunk_coord: Vector2i, count: float) -> void:
	if _fish_population.has(chunk_coord):
		_fish_population[chunk_coord] = maxf(0.0, _fish_population[chunk_coord] - count)


## Records a real vegetation harvest against this region -- record_catch's
## counterpart for standing vegetation, which previously had NO mortality
## term at all: only weather ever moved _vegetation_density. Two effects:
## (1) immediately removes `amount` from the region's standing density,
## spread evenly across its cells (the actual bite/graze/gather happening
## now), floored at 0.0 like record_catch; (2) banks `amount` into this
## region's harvest accumulator, which the next step() call turns into a
## per-day rate compared against the region's own regrowth_rate to decide
## whether land health should deplete (see step()'s own doc comment) -- a
## single harvest never directly moves land health, only SUSTAINED pressure
## across many steps does. A harvest against an unknown region is a
## harmless no-op, matching record_catch.
func record_vegetation_harvest(chunk_coord: Vector2i, amount: float) -> void:
	if not _vegetation_density.has(chunk_coord):
		return
	var density: PackedFloat32Array = _vegetation_density[chunk_coord]
	if density.size() > 0 and amount > 0.0:
		var per_cell := amount / density.size()
		for i in density.size():
			density[i] = maxf(0.0, density[i] - per_cell)
		_vegetation_density[chunk_coord] = density
	_harvest_accumulator[chunk_coord] = _harvest_accumulator.get(chunk_coord, 0.0) + amount


## An animal was BORN near the player -- an individual event, watched
## happening -- so the region's aggregate population goes up to match.
##
## This is the counterpart of record_catch, and it exists because the world
## runs at two fidelities (see concept/ecosystem_dynamics.md). Away from the
## player a population is a number that grows logistically; near the player,
## actual animals court, mate and produce actual offspring. If those two never
## spoke, watching a meadow would create animals that evaporated as soon as
## the chunk unloaded, and the aggregate would keep breeding a herd that had
## already outgrown its range.
##
## Capped at the region's carrying capacity: the land decides the ceiling, not
## how long the player stood and watched. An unknown region is a silent no-op,
## the same as record_catch -- there is no aggregate there to move.
func record_birth(chunk_coord: Vector2i, count: float) -> void:
	if not _herbivore_population.has(chunk_coord):
		return
	_herbivore_population[chunk_coord] = minf(
		herbivore_capacity_at(chunk_coord),
		_herbivore_population[chunk_coord] + count
	)


## An animal DIED near the player -- shot, savaged, starved or sick -- so the
## region's aggregate population comes down to match. record_birth's mirror,
## and the mortality term this model simply did not have: record_catch covered
## fish and record_vegetation_harvest covered standing plants, but a land
## animal killed in front of the player moved nothing at all. The visible
## consequence of that gap: _reconcile_chunk_creatures sizes a chunk's markers
## against the aggregate, so a valley hunted bare quietly restocked itself, and
## "farm your own instead" could never be the smarter choice because hunting
## cost the world nothing (see concept/animal_husbandry.md's "Consequence").
##
## Deliberately NOT symmetric with record_birth in one respect. A birth is
## capped at carrying capacity because the land decides the ceiling; a death
## takes no such cap, because nothing stops a region being emptied. Floored at
## 0.0 exactly like record_catch, and a silent no-op for a region the aggregate
## does not track -- deaths genuinely happen in chunks that were never added.
##
## `is_predator`: the two pools are separate and the predator model's own
## carrying capacity is DERIVED from the herbivore one, so booking a wolf
## against the herbivore pool would both under-count the wolves and quietly
## shrink what the land is said to support. Callers pass the species' real
## predator status (see CreatureInfo.PREDATOR_SPECIES).
##
## Kept animals are the one death this must NOT be called for: carrying
## capacity governs WILD animals and the player's stock is deliberately extra
## (see KeptAnimals, and _thin_creatures' refusal to cull anything the player
## has a stake in), so a barn losing a sheep is not the land losing one.
func record_death(chunk_coord: Vector2i, count: float, is_predator: bool = false) -> void:
	var pool: Dictionary = _predator_population if is_predator else _herbivore_population
	if not pool.has(chunk_coord):
		return
	pool[chunk_coord] = maxf(0.0, pool[chunk_coord] - count)


func _average(values: PackedFloat32Array) -> float:
	if values.is_empty():
		return 0.0
	var total := 0.0
	for value in values:
		total += value
	return total / values.size()


## This chunk's average effective_capacity at the given land_health -- the
## same per-cell computation step_grid does internally, factored out so
## step()'s land-health update can compare a live harvest rate against the
## region's real current regrowth capability without duplicating step_grid
## itself.
func _average_capacity(chunk: Chunk, land_health: float) -> float:
	if chunk.biome.is_empty():
		return 0.0
	var total := 0.0
	for i in chunk.biome.size():
		total += _vegetation_model.effective_capacity(
			chunk.biome[i], chunk.temperature[i], chunk.moisture[i], land_health
		)
	return total / chunk.biome.size()


func _water_access_fraction(chunk: Chunk) -> float:
	if chunk.biome.is_empty():
		return 0.0
	var ocean_count := 0
	for biome_name in chunk.biome:
		if biome_name == "ocean":
			ocean_count += 1
	return float(ocean_count) / chunk.biome.size()
