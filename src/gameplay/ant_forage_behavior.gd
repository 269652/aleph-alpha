extends RefCounted

## Pure state machine for one ant-colony forager's real round trip: mound ->
## (scout for) a real food location -> mound again. See docs/concept/
## soil_fauna.md's "Real foraging: a round trip, not an instant resolve"
## and "Scouting: real search, not omniscient dispatch".
##
## `phase` DEFAULTS to APPROACHING, not SCOUTING -- a deliberate
## backward-compatibility seam, not an oversight: every dispatch used to
## (and a direct construction, e.g. a test, still can) start with a
## real, already-known target and walk straight to it. begin_scouting()
## is how a caller OPTS IN to the newer "no known target yet, wander and
## sense" path (see AntForagerMarker.scout) -- real production dispatch
## always calls it now, but nothing about the APPROACHING/RETURNING
## contract below changed for a caller that never does.
##
## Simpler than CarrionForageBehavior/GroundForageBehavior/
## PiscivoreBirdBehavior's own SEEKING phases: those roam indefinitely
## reading real-time sensor state every tick. SCOUTING here is not a
## general-purpose seek loop -- it exists specifically so a forager can
## start with NO known target and end up with one once AntForagerMarker's
## own local sensing (see that file's _sense_food_nearby) finds something
## real nearby, or give up if it doesn't in time. No engine dependencies,
## so the whole cycle is unit-testable headlessly, same split as every
## other creature behaviour in this codebase: this decides WHEN things
## happen; the marker (AntForagerMarker) owns the world effect (actually
## sensing/taking the seed/nut/leaf, and later caching or consuming it).

enum Phase { SCOUTING, APPROACHING, RETURNING }

var phase := Phase.APPROACHING

## Whether the food was genuinely still there on arrival -- something else
## (a mouse, a bird, simple bad luck) may have taken it in the time this
## forager spent walking. A real forager does not just vanish if so; it
## still walks home, simply with nothing to cache once it gets there.
var found_food := false


## Opts into the newer "no known target yet" path (see this file's own doc
## comment) -- a caller that never calls this keeps the original,
## unaffected APPROACHING-first contract.
func begin_scouting() -> void:
	phase = Phase.SCOUTING


## A scouting forager's own local sensing (see AntForagerMarker.
## _sense_food_nearby) found something real nearby -- now walk the last
## short distance to it, exactly like a forager dispatched straight at an
## already-known target always has. Committing is "I know where it is
## now", not "I already have it": arrive_at_food still resolves the real
## take-or-miss check on genuine arrival, same as ever.
func commit_to_food() -> void:
	phase = Phase.APPROACHING


## Arrived at the food's real position. `succeeded` is the caller's own
## real-world check (e.g. take_grass_seed_at's return value) -- this state
## machine has no way to know that on its own.
func arrive_at_food(succeeded: bool) -> void:
	found_food = succeeded
	phase = Phase.RETURNING


## Wandered too long/far while scouting and found nothing real -- a real
## scout does not just vanish, it walks home empty-handed, the same
## "still returns, just with nothing to show for it" contract an
## unsuccessful APPROACHING trip already has (see arrive_at_food(false)).
func give_up_scouting() -> void:
	found_food = false
	phase = Phase.RETURNING
