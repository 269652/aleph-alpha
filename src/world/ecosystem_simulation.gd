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

const Chunk = preload("res://src/world/chunk.gd")
const VegetationGrowthModel = preload("res://src/world/vegetation_growth_model.gd")
const HerbivorePopulationModel = preload("res://src/world/herbivore_population_model.gd")
const PredatorPopulationModel = preload("res://src/world/predator_population_model.gd")

var _vegetation_model := VegetationGrowthModel.new()
var _herbivore_model := HerbivorePopulationModel.new()
var _predator_model := PredatorPopulationModel.new()

var _chunks: Dictionary = {}  # Vector2i chunk_coord -> Chunk
var _vegetation_density: Dictionary = {}  # Vector2i chunk_coord -> PackedFloat32Array
var _water_access: Dictionary = {}  # Vector2i chunk_coord -> float
var _herbivore_population: Dictionary = {}  # Vector2i chunk_coord -> float
var _predator_population: Dictionary = {}  # Vector2i chunk_coord -> float


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

	var herbivore_capacity := _herbivore_model.carrying_capacity(
		_average(density), _water_access[chunk_coord]
	)
	_herbivore_population[chunk_coord] = herbivore_capacity
	_predator_population[chunk_coord] = _predator_model.carrying_capacity(herbivore_capacity)


## Stops simulating a region (its unloaded chunk's terrain is regenerated
## deterministically on revisit -- see EarthChunkManager -- so this state is
## likewise dropped rather than persisted; the same known simplification).
func remove_region(chunk_coord: Vector2i) -> void:
	_chunks.erase(chunk_coord)
	_vegetation_density.erase(chunk_coord)
	_water_access.erase(chunk_coord)
	_herbivore_population.erase(chunk_coord)
	_predator_population.erase(chunk_coord)


func has_region(chunk_coord: Vector2i) -> bool:
	return _chunks.has(chunk_coord)


## Swaps an already-loaded region's environmental input (e.g. a drought
## lowering moisture) without resetting its current vegetation/population
## state -- conditions changing for a living region, not a fresh region.
func update_environment(chunk_coord: Vector2i, chunk: Chunk) -> void:
	if _chunks.has(chunk_coord):
		_chunks[chunk_coord] = chunk
		_water_access[chunk_coord] = _water_access_fraction(chunk)


## Advances every currently-loaded region by delta_days simulated days:
## vegetation grows/spreads per-cell, then herbivore and predator populations
## grow/decline toward their resource-derived capacity and migrate toward
## adjacent regions with spare capacity.
func step(delta_days: float) -> void:
	for chunk_coord in _vegetation_density.keys():
		var chunk: Chunk = _chunks[chunk_coord]
		_vegetation_density[chunk_coord] = _vegetation_model.step_grid(
			_vegetation_density[chunk_coord],
			chunk.biome,
			chunk.temperature,
			chunk.moisture,
			chunk.width,
			chunk.height,
			delta_days
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


func average_vegetation_density(chunk_coord: Vector2i) -> float:
	return _average(_vegetation_density.get(chunk_coord, PackedFloat32Array()))


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


func _average(values: PackedFloat32Array) -> float:
	if values.is_empty():
		return 0.0
	var total := 0.0
	for value in values:
		total += value
	return total / values.size()


func _water_access_fraction(chunk: Chunk) -> float:
	if chunk.biome.is_empty():
		return 0.0
	var ocean_count := 0
	for biome_name in chunk.biome:
		if biome_name == "ocean":
			ocean_count += 1
	return float(ocean_count) / chunk.biome.size()
