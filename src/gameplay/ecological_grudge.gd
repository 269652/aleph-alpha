extends RefCounted
## When the forest has a grievance against you (docs/concept/monsters.md,
## entry 5 -- the Curupira).
##
## The roster's own statement of its one behaviour: *"it is provoked by YOUR
## ecology. It ignores a player who hunts sustainably and hunts a player who
## has driven the local `herbivore_population` down -- the ecosystem sim is
## the aggro table. It is the only creature in the game that reads your
## footprint rather than your position."*
##
## That is the whole reason this monster is worth building rather than
## reskinning a wolf, and it needs no new state at all: `EarthChunkManager.
## herbivore_population_at_chunk` and `herbivore_capacity_at_chunk` are both
## live and public, and the ecosystem simulation has been stepping them
## every day since Phase 1.
##
## THE THRESHOLD IS DERIVED, NOT PICKED. `PopulationModel.step` is logistic
## growth -- `rate * P * (1 - P/K)` -- and that expression is maximal at
## exactly `P = K/2`. That is the textbook maximum sustainable yield: the
## population level at which a herd replaces itself fastest, and therefore
## the exact point below which a harvest stops being sustainable and starts
## being extraction. So the game's own growth model decides when a hunter
## has gone too far, and `test_the_threshold_is_where_the_real_growth_model_
## peaks` asserts that against the real model rather than trusting this
## paragraph.
##
## Pure: RefCounted, static functions, no world, no creature, no player --
## and deliberately no way to ask where anybody is standing. A grudge that
## could see the player would be an ordinary predator with extra steps, so a
## reflection test forbids every position-shaped method name here.

## The species whose aggro table is the ecosystem simulation. Named here
## rather than on the species itself, so "which creatures read a footprint"
## is one list rather than a flag scattered across six data tables.
const BEARS_A_GRUDGE := {"curupira": true}


## The share of a region's carrying capacity a herd must keep for the taking
## to be sustainable: a half, because that is where logistic growth peaks.
const SUSTAINABLE_FRACTION := 0.5


## How much of this region's herd is gone, as a fraction of what the ground
## could support. 0.0 is untouched, 1.0 is stripped.
##
## A region ABOVE its own capacity reads as untouched rather than as
## negatively depleted -- an overfull herd is a different problem, and not
## this creature's.
static func depletion_of(population: float, capacity: float) -> float:
	if capacity <= 0.0:
		return 0.0
	return clampf(1.0 - population / capacity, 0.0, 1.0)


## Whether the forest holds this region's state against whoever did it.
##
## Ground that can support nothing is never provoked: a desert is not a
## crime scene, and an empty region with no capacity is not evidence that
## anybody hunted there.
static func is_provoked(population: float, capacity: float) -> bool:
	if capacity <= 0.0:
		return false
	return depletion_of(population, capacity) > 1.0 - SUSTAINABLE_FRACTION
