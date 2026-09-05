extends RefCounted

## Pure state machine for one ant-colony forager's real round trip: mound ->
## a known food location -> mound again. See docs/concept/soil_fauna.md
## "Real foraging: a round trip, not an instant resolve".
##
## Simpler than CarrionForageBehavior/GroundForageBehavior/
## PiscivoreBirdBehavior: there is no SEEKING phase here, because the
## COLONY already found a real, reachable food candidate before dispatching
## a forager at all (see EarthChunkManager._forage_seed_near_mound/
## _forage_windfall_near_mound, and PheromoneField.best_candidate_index for
## how that candidate is chosen when more than one is in reach) -- this
## state machine owns only the walk-there-and-back, and whether the food
## was actually still there when the ant arrived. No engine dependencies,
## so the whole cycle is unit-testable headlessly, same split as every
## other creature behaviour in this codebase: this decides WHEN things
## happen; the marker (AntForagerMarker) owns the world effect (actually
## taking the seed/nut, and later caching or consuming it).

enum Phase { APPROACHING, RETURNING }

var phase := Phase.APPROACHING

## Whether the food was genuinely still there on arrival -- something else
## (a mouse, a bird, simple bad luck) may have taken it in the time this
## forager spent walking. A real forager does not just vanish if so; it
## still walks home, simply with nothing to cache once it gets there.
var found_food := false


## Arrived at the food's real position. `succeeded` is the caller's own
## real-world check (e.g. take_grass_seed_at's return value) -- this state
## machine has no way to know that on its own.
func arrive_at_food(succeeded: bool) -> void:
	found_food = succeeded
	phase = Phase.RETURNING
