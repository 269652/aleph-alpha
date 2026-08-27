extends GutTest

const EcosystemSimulation = preload("res://src/world/ecosystem_simulation.gd")
const Chunk = preload("res://src/world/chunk.gd")

var simulation: EcosystemSimulation


func before_each():
	simulation = EcosystemSimulation.new()


func _make_chunk(biome_name: String, temperature: float, moisture: float, size: int = 4) -> Chunk:
	var chunk := Chunk.new()
	chunk.width = size
	chunk.height = size
	chunk.elevation = PackedFloat32Array()
	chunk.elevation.resize(size * size)
	chunk.biome = PackedStringArray()
	chunk.biome.resize(size * size)
	chunk.biome.fill(biome_name)
	chunk.temperature = PackedFloat32Array()
	chunk.temperature.resize(size * size)
	chunk.temperature.fill(temperature)
	chunk.moisture = PackedFloat32Array()
	chunk.moisture.resize(size * size)
	chunk.moisture.fill(moisture)
	return chunk


func test_add_region_starts_populated_for_a_hospitable_biome():
	# Vegetation/creatures are assumed to already exist in the world at
	# equilibrium when a region is first visited, not grown from nothing --
	# matches the static tree placement the game already uses.
	simulation.add_region(Vector2i(0, 0), _make_chunk("rainforest", 0.9, 0.9))

	assert_gt(simulation.average_vegetation_density(Vector2i(0, 0)), 0.0)
	assert_gt(simulation.herbivore_population(Vector2i(0, 0)), 0.0)
	assert_gt(simulation.predator_population(Vector2i(0, 0)), 0.0)


func test_add_region_stays_empty_for_an_inhospitable_biome():
	simulation.add_region(Vector2i(0, 0), _make_chunk("ocean", 0.9, 0.9))

	assert_eq(simulation.average_vegetation_density(Vector2i(0, 0)), 0.0)
	assert_eq(simulation.herbivore_population(Vector2i(0, 0)), 0.0)
	assert_eq(simulation.predator_population(Vector2i(0, 0)), 0.0)


func test_has_region_reflects_add_and_remove():
	var coord := Vector2i(3, 3)
	assert_false(simulation.has_region(coord))

	simulation.add_region(coord, _make_chunk("grassland", 0.7, 0.7))
	assert_true(simulation.has_region(coord))

	simulation.remove_region(coord)
	assert_false(simulation.has_region(coord))


func test_step_does_not_crash_with_no_regions_loaded():
	simulation.step(1.0)
	pass_test("step() with zero regions should be a no-op, not an error")


func test_step_keeps_populations_within_their_capacities_over_many_days():
	simulation.add_region(Vector2i(0, 0), _make_chunk("forest", 0.7, 0.7))

	for i in 50:
		simulation.step(1.0)

	var vegetation_capacity := 1.0  # forest's own carrying capacity is < 1.0; loose upper bound
	assert_between(simulation.average_vegetation_density(Vector2i(0, 0)), 0.0, vegetation_capacity)
	assert_gte(simulation.herbivore_population(Vector2i(0, 0)), 0.0)
	assert_gte(simulation.predator_population(Vector2i(0, 0)), 0.0)


func test_migration_moves_surplus_population_to_an_adjacent_spare_capacity_region():
	# Two thriving, at-equilibrium regions have zero surplus each -- nothing
	# should migrate between them just because their capacities differ. A
	# region that suddenly becomes overcrowded relative to its OWN new
	# capacity is what should push population toward a spare-capacity
	# neighbor -- exactly what a drought does to an existing population.
	var crowded_coord := Vector2i(0, 0)
	var spare_coord := Vector2i(1, 0)
	simulation.add_region(crowded_coord, _make_chunk("rainforest", 0.9, 0.9))
	simulation.add_region(spare_coord, _make_chunk("rainforest", 0.9, 0.9))

	simulation.update_environment(crowded_coord, _make_chunk("desert", 0.9, 0.0))

	var spare_population_before := simulation.herbivore_population(spare_coord)
	for i in 5:
		simulation.step(1.0)

	assert_gt(simulation.herbivore_population(spare_coord), spare_population_before)


func test_update_environment_changes_future_steps_without_resetting_current_state():
	var coord := Vector2i(0, 0)
	simulation.add_region(coord, _make_chunk("grassland", 0.8, 0.8))
	for i in 10:
		simulation.step(1.0)
	var population_at_swap := simulation.herbivore_population(coord)

	simulation.update_environment(coord, _make_chunk("grassland", 0.8, 0.8))

	assert_almost_eq(simulation.herbivore_population(coord), population_at_swap, 0.01)


func test_seed_populations_overrides_the_equilibrium_from_add_region():
	# add_region seeds a region at carrying-capacity equilibrium; the
	# unloaded-chunk catch-up (EarthChunkManager) needs to override that with
	# the caught-up populations from ChunkEcologyCatchup on revisit.
	var chunk := _make_chunk("grassland", 0.6, 0.6)
	var sim = EcosystemSimulation.new()
	sim.add_region(Vector2i.ZERO, chunk)
	var cap = sim.herbivore_capacity_at(Vector2i.ZERO)
	assert_gt(cap, 0.0, "grassland should have positive herbivore capacity")

	sim.seed_populations(Vector2i.ZERO, 2.0, 1.0)
	assert_almost_eq(sim.herbivore_population(Vector2i.ZERO), 2.0, 0.001)
	assert_almost_eq(sim.predator_population(Vector2i.ZERO), 1.0, 0.001)


func test_herbivore_capacity_at_is_zero_for_an_unknown_region():
	var sim = EcosystemSimulation.new()
	assert_eq(sim.herbivore_capacity_at(Vector2i(9, 9)), 0.0)


## See docs/concept/fishing.md#aquatic-population-model.

func test_add_region_seeds_fish_population_for_a_chunk_with_water():
	simulation.add_region(Vector2i(0, 0), _make_chunk("ocean", 0.55, 0.5))
	assert_gt(simulation.fish_population(Vector2i(0, 0)), 0.0)


func test_add_region_stays_fish_free_for_a_land_only_chunk():
	simulation.add_region(Vector2i(0, 0), _make_chunk("grassland", 0.55, 0.5))
	assert_eq(simulation.fish_population(Vector2i(0, 0)), 0.0)


func test_step_keeps_fish_population_within_capacity_over_many_days():
	simulation.add_region(Vector2i(0, 0), _make_chunk("ocean", 0.55, 0.5))
	var capacity := simulation.fish_capacity_at(Vector2i(0, 0))
	for i in 50:
		simulation.step(1.0)
	assert_between(simulation.fish_population(Vector2i(0, 0)), 0.0, capacity + 0.01)


func test_fish_capacity_at_is_zero_for_an_unknown_region():
	var sim = EcosystemSimulation.new()
	assert_eq(sim.fish_capacity_at(Vector2i(9, 9)), 0.0)


func test_record_catch_decrements_fish_population():
	simulation.add_region(Vector2i(0, 0), _make_chunk("ocean", 0.55, 0.5))
	var before := simulation.fish_population(Vector2i(0, 0))
	simulation.record_catch(Vector2i(0, 0), 1.0)
	assert_almost_eq(simulation.fish_population(Vector2i(0, 0)), before - 1.0, 0.001)


func test_record_catch_does_not_go_negative():
	simulation.add_region(Vector2i(0, 0), _make_chunk("ocean", 0.55, 0.5))
	simulation.record_catch(Vector2i(0, 0), 100000.0)
	assert_eq(simulation.fish_population(Vector2i(0, 0)), 0.0)


func test_seed_fish_population_overrides_add_regions_equilibrium():
	simulation.add_region(Vector2i(0, 0), _make_chunk("ocean", 0.55, 0.5))
	simulation.seed_fish_population(Vector2i(0, 0), 3.0)
	assert_almost_eq(simulation.fish_population(Vector2i(0, 0)), 3.0, 0.001)


func test_fish_migration_moves_surplus_population_to_an_adjacent_spare_capacity_region():
	var crowded_coord := Vector2i(0, 0)
	var spare_coord := Vector2i(1, 0)
	simulation.add_region(crowded_coord, _make_chunk("ocean", 0.55, 0.5))
	simulation.add_region(spare_coord, _make_chunk("ocean", 0.55, 0.5))

	# Crashing the crowded region's water temperature far from the aquatic
	# model's optimum collapses its fish capacity toward zero, leaving its
	# already-seeded population overcrowded relative to its OWN new
	# capacity -- exactly what a real cold-water event does.
	simulation.update_environment(crowded_coord, _make_chunk("ocean", 0.0, 0.0))

	var spare_population_before := simulation.fish_population(spare_coord)
	for i in 5:
		simulation.step(1.0)

	assert_gt(simulation.fish_population(spare_coord), spare_population_before)


# -- individual births feed back into the aggregate --------------------------
#
# The world runs at two fidelities (see the LOD section of
# concept/ecosystem_dynamics.md): away from the player, populations are a
# number that grows logistically; near the player, actual animals court, mate
# and produce actual offspring. Those two have to be the SAME population, or
# watching a meadow would be a way of creating animals that vanish the moment
# you look away -- and the herd you built up would evaporate on a chunk
# reload.
#
# record_catch already does this for fishing (an individual act moving the
# aggregate). This is its counterpart for birth.

func test_a_birth_near_the_player_raises_the_regions_population():
	var sim = EcosystemSimulation.new()
	sim.add_region(Vector2i.ZERO, _make_chunk("grassland", 0.6, 0.6))
	# A region seeded BELOW its ceiling -- a recovering population is where
	# births actually matter; regions start at capacity, where they cannot.
	# Well below this region's ceiling (about 1.3 here), so the birth has
	# room to land and the assertion is about the birth, not the cap.
	sim.seed_populations(Vector2i.ZERO, 0.2, 0.0)
	sim.record_birth(Vector2i.ZERO, 0.5)
	assert_almost_eq(sim.herbivore_population(Vector2i.ZERO), 0.7, 0.001)


## The aggregate model is still the authority on what the land can support: a
## birth cannot push a region past its own carrying capacity, or watching a
## meadow long enough would overrun it in a way the off-screen model never
## would.
func test_births_cannot_push_a_region_past_what_it_can_support():
	var sim = EcosystemSimulation.new()
	sim.add_region(Vector2i.ZERO, _make_chunk("grassland", 0.6, 0.6))
	sim.seed_populations(Vector2i.ZERO, 1.0, 0.0)
	for _i in 500:
		sim.record_birth(Vector2i.ZERO, 1.0)
	assert_lte(
		sim.herbivore_population(Vector2i.ZERO),
		sim.herbivore_capacity_at(Vector2i.ZERO) + 0.001,
		"the land decides the ceiling, not how long the player watched"
	)


## A birth in a region that is not loaded is a silent no-op, matching
## record_catch: there is no aggregate there to move.
func test_a_birth_in_an_unknown_region_is_harmless():
	var sim = EcosystemSimulation.new()
	sim.record_birth(Vector2i(999, 999), 1.0)
	assert_eq(sim.herbivore_population(Vector2i(999, 999)), 0.0)


# -- animals spread between neighbouring regions -----------------------------
#
# Every chunk used to be a sealed jar: it grew to its own capacity and
# stopped, and an emptied region refilled only from its own survivors. So a
# valley the player hunted out stayed empty forever regardless of the herds
# next door.

func _two_neighbours() -> EcosystemSimulation:
	var sim = EcosystemSimulation.new()
	sim.add_region(Vector2i(0, 0), _make_chunk("grassland", 0.6, 0.6))
	sim.add_region(Vector2i(1, 0), _make_chunk("grassland", 0.6, 0.6))
	return sim


func test_a_hunted_out_region_refills_from_its_neighbour():
	var sim := _two_neighbours()
	var full: float = sim.herbivore_capacity_at(Vector2i(0, 0))
	sim.seed_populations(Vector2i(0, 0), full, 0.0)
	sim.seed_populations(Vector2i(1, 0), 0.0, 0.0)
	for _day in 40:
		sim.step(1.0)
	assert_gt(
		sim.herbivore_population(Vector2i(1, 0)), 0.0,
		"an emptied region beside a full one should repopulate"
	)


## Migration must not conjure animals -- it moves them. Growth is a separate
## term, so this checks the emptied region gains while the full one is not
## simply left untouched.
func test_the_region_they_come_from_actually_loses_them():
	var sim := _two_neighbours()
	var full: float = sim.herbivore_capacity_at(Vector2i(0, 0))
	sim.seed_populations(Vector2i(0, 0), full, 0.0)
	sim.seed_populations(Vector2i(1, 0), 0.0, 0.0)
	sim.step(1.0)
	assert_lt(
		sim.herbivore_population(Vector2i(0, 0)), full,
		"the animals that arrived next door came from somewhere"
	)


## Capped, always: migration cannot push a region past what its land supports.
func test_migration_never_overfills_a_region():
	var sim := _two_neighbours()
	sim.seed_populations(Vector2i(0, 0), sim.herbivore_capacity_at(Vector2i(0, 0)), 0.0)
	sim.seed_populations(Vector2i(1, 0), sim.herbivore_capacity_at(Vector2i(1, 0)), 0.0)
	for _day in 100:
		sim.step(1.0)
	for coord in [Vector2i(0, 0), Vector2i(1, 0)]:
		assert_lte(
			sim.herbivore_population(coord),
			sim.herbivore_capacity_at(coord) + 0.001,
			"the land decides the ceiling, migration or not"
		)


## Regions that are not neighbours do not exchange animals: this is a
## diffusion across a grid, not a teleport.
func test_animals_do_not_jump_to_a_region_that_is_not_adjacent():
	var sim = EcosystemSimulation.new()
	sim.add_region(Vector2i(0, 0), _make_chunk("grassland", 0.6, 0.6))
	sim.add_region(Vector2i(9, 9), _make_chunk("grassland", 0.6, 0.6))
	sim.seed_populations(Vector2i(0, 0), sim.herbivore_capacity_at(Vector2i(0, 0)), 0.0)
	sim.seed_populations(Vector2i(9, 9), 0.0, 0.0)
	sim.step(1.0)
	assert_almost_eq(
		sim.herbivore_population(Vector2i(9, 9)), 0.0, 0.0001,
		"a distant region is not a neighbour"
	)


# -- land health: overharvesting leaves a lasting mark ------------------------
#
# docs/concept/world.md "Land health: overharvesting leaves a lasting mark,
# not just a slower respawn" -- a persistent per-chunk-aggregate value (same
# fidelity tier as herbivore/predator/fish population, all Dictionary[
# Vector2i, float] here already) that depletes under sustained
# harvest-exceeds-regrowth pressure and multiplies effective_capacity down
# further, on top of the existing weather-driven ceiling.

func test_add_region_seeds_land_health_at_full():
	simulation.add_region(Vector2i(0, 0), _make_chunk("grassland", 0.6, 0.6))
	assert_almost_eq(simulation.land_health(Vector2i(0, 0)), 1.0, 0.0001)


## Fail-open, same convention as herbivore_capacity_at/fish_capacity_at for
## an unknown region -- an unloaded/never-visited region reads as pristine,
## not as fully degraded.
func test_land_health_is_full_for_an_unknown_region():
	var sim = EcosystemSimulation.new()
	assert_almost_eq(sim.land_health(Vector2i(9, 9)), 1.0, 0.0001)


func test_seed_land_health_overrides_the_fresh_seeding():
	simulation.add_region(Vector2i(0, 0), _make_chunk("grassland", 0.6, 0.6))
	simulation.seed_land_health(Vector2i(0, 0), 0.4)
	assert_almost_eq(simulation.land_health(Vector2i(0, 0)), 0.4, 0.0001)


func test_seed_land_health_on_an_unknown_region_is_a_harmless_no_op():
	var sim = EcosystemSimulation.new()
	sim.seed_land_health(Vector2i(9, 9), 0.4)
	assert_almost_eq(sim.land_health(Vector2i(9, 9)), 1.0, 0.0001)


## record_vegetation_harvest mirrors record_catch's shape/role for fishing:
## an explicit mortality/removal term the wild vegetation density otherwise
## lacks entirely (only weather moves it today).
func test_record_vegetation_harvest_immediately_reduces_standing_density():
	simulation.add_region(Vector2i(0, 0), _make_chunk("grassland", 0.8, 0.8))
	var before := simulation.average_vegetation_density(Vector2i(0, 0))
	simulation.record_vegetation_harvest(Vector2i(0, 0), 0.1)
	assert_lt(simulation.average_vegetation_density(Vector2i(0, 0)), before)


func test_record_vegetation_harvest_never_goes_negative():
	simulation.add_region(Vector2i(0, 0), _make_chunk("grassland", 0.8, 0.8))
	simulation.record_vegetation_harvest(Vector2i(0, 0), 1000.0)
	assert_almost_eq(simulation.average_vegetation_density(Vector2i(0, 0)), 0.0, 0.0001)


func test_record_vegetation_harvest_on_an_unknown_region_is_a_harmless_no_op():
	var sim = EcosystemSimulation.new()
	sim.record_vegetation_harvest(Vector2i(9, 9), 1.0)
	assert_almost_eq(sim.average_vegetation_density(Vector2i(9, 9)), 0.0, 0.0001)


## The core causal claim: sustained harvest that outpaces regrowth, repeated
## step after step, measurably depletes land health -- not a single harvest
## event.
func test_sustained_overharvest_depletes_land_health_over_many_steps():
	simulation.add_region(Vector2i(0, 0), _make_chunk("grassland", 0.8, 0.8))
	for i in 60:
		# A harvest far larger than one day's regrowth could ever replace,
		# every single simulated day -- genuine sustained overharvest.
		simulation.record_vegetation_harvest(Vector2i(0, 0), 0.5)
		simulation.step(1.0)
	assert_lt(simulation.land_health(Vector2i(0, 0)), 1.0)


## A region harvested lightly enough to stay within its own regrowth (or not
## harvested at all) should NOT have its land health ground down -- this is
## the "sustained overharvest", not "any use at all", distinction the concept
## doc calls for.
func test_light_or_no_harvest_does_not_deplete_land_health():
	simulation.add_region(Vector2i(0, 0), _make_chunk("grassland", 0.8, 0.8))
	for i in 30:
		simulation.step(1.0)
	assert_almost_eq(simulation.land_health(Vector2i(0, 0)), 1.0, 0.0001)


## A degraded region left alone (no further harvest) should recover, however
## slowly -- see VegetationGrowthModel.LAND_HEALTH_RECOVERY_PACE_PER_DAY.
func test_land_health_recovers_over_time_once_harvesting_stops():
	simulation.add_region(Vector2i(0, 0), _make_chunk("grassland", 0.8, 0.8))
	simulation.seed_land_health(Vector2i(0, 0), 0.2)
	for i in 30:
		simulation.step(1.0)
	assert_gt(simulation.land_health(Vector2i(0, 0)), 0.2)


## The full multiplicative chain within this layer: a degraded region's
## vegetation density settles at a LOWER equilibrium than an identical twin
## region with full land health, given the EXACT SAME weather -- proving
## land health is a real additional factor, not redundant with weather.
func test_degraded_land_health_measurably_lowers_settled_vegetation_density():
	var degraded_coord := Vector2i(0, 0)
	var healthy_coord := Vector2i(5, 5)
	simulation.add_region(degraded_coord, _make_chunk("grassland", 0.8, 0.8))
	simulation.add_region(healthy_coord, _make_chunk("grassland", 0.8, 0.8))
	simulation.seed_land_health(degraded_coord, 0.3)

	for i in 30:
		simulation.step(1.0)

	assert_lt(
		simulation.average_vegetation_density(degraded_coord),
		simulation.average_vegetation_density(healthy_coord),
		"degraded land health must settle at a lower density than untouched land under identical weather"
	)


# -- record_death -------------------------------------------------------------
#
# The mortality term the aggregate never had. record_catch does this for fish
# and record_vegetation_harvest for standing plants, but until now killing a
# land animal near the player moved nothing at all: _reconcile_chunk_creatures
# sizes a chunk's markers against an aggregate that never heard about the kill,
# so a valley hunted bare restocked itself. record_birth's mirror image.
#
# Deliberately NOT symmetric with record_birth in one respect: a birth is
# capped at carrying capacity because the land decides the ceiling, but a death
# needs no such cap, because nothing stops a region being emptied.

func test_a_death_lowers_the_regions_population():
	simulation.add_region(Vector2i.ZERO, _make_chunk("grassland", 0.6, 0.6))
	simulation.seed_populations(Vector2i.ZERO, 1.0, 0.5)
	simulation.record_death(Vector2i.ZERO, 0.25)
	assert_almost_eq(simulation.herbivore_population(Vector2i.ZERO), 0.75, 0.001)


## The whole point: hunting a region out has to STAY hunted out until the
## logistic term grows it back. Nothing may floor it at some minimum stock.
func test_a_region_can_be_emptied_completely():
	simulation.add_region(Vector2i.ZERO, _make_chunk("grassland", 0.6, 0.6))
	simulation.seed_populations(Vector2i.ZERO, 1.0, 0.5)
	simulation.record_death(Vector2i.ZERO, 100000.0)
	assert_eq(simulation.herbivore_population(Vector2i.ZERO), 0.0)


func test_a_population_never_goes_negative():
	simulation.add_region(Vector2i.ZERO, _make_chunk("grassland", 0.6, 0.6))
	simulation.seed_populations(Vector2i.ZERO, 0.1, 0.1)
	simulation.record_death(Vector2i.ZERO, 5.0)
	assert_gte(simulation.herbivore_population(Vector2i.ZERO), 0.0)


## Matches record_catch/record_vegetation_harvest: an event in a region the
## aggregate does not track is harmless, not a crash. Deaths happen in chunks
## that were never added (a marker outliving its region's removal, a test
## harness), and none of those may take the simulation down.
func test_a_death_in_an_unknown_region_is_a_no_op():
	simulation.record_death(Vector2i(99, 99), 1.0)
	assert_eq(simulation.herbivore_population(Vector2i(99, 99)), 0.0)


## A wolf is not a deer. The aggregate keeps two separate pools and the
## predator model's carrying capacity is derived from the herbivore one, so
## booking a predator kill against the herbivore pool would both under-count
## the wolves and quietly shrink what the land is said to support.
func test_a_predator_death_lowers_the_predator_population():
	simulation.add_region(Vector2i.ZERO, _make_chunk("grassland", 0.6, 0.6))
	simulation.seed_populations(Vector2i.ZERO, 1.0, 0.5)
	simulation.record_death(Vector2i.ZERO, 0.2, true)
	assert_almost_eq(simulation.predator_population(Vector2i.ZERO), 0.3, 0.001)


func test_a_herbivore_death_leaves_the_predator_population_alone():
	simulation.add_region(Vector2i.ZERO, _make_chunk("grassland", 0.6, 0.6))
	simulation.seed_populations(Vector2i.ZERO, 1.0, 0.5)
	simulation.record_death(Vector2i.ZERO, 0.25)
	assert_almost_eq(simulation.predator_population(Vector2i.ZERO), 0.5, 0.001)


func test_a_predator_death_leaves_the_herbivore_population_alone():
	simulation.add_region(Vector2i.ZERO, _make_chunk("grassland", 0.6, 0.6))
	simulation.seed_populations(Vector2i.ZERO, 1.0, 0.5)
	simulation.record_death(Vector2i.ZERO, 0.2, true)
	assert_almost_eq(simulation.herbivore_population(Vector2i.ZERO), 1.0, 0.001)
