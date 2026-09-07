extends RefCounted

## Pure state machine for one bee forager's real round trip: hive ->
## (scout for) a real flower with nectar -> hive again. Mirrors
## AntForageBehavior exactly -- see docs/concept/bees.md's own "What's
## reused verbatim, what's a deliberate new duplicate, and why": a small
## (this whole file), pure, independently-tunable duplicate rather than a
## shared import, the same "three similar things beats a premature
## abstraction" preference this project already states elsewhere
## (DesertScrub's own doc comment).
##
## `phase` DEFAULTS to APPROACHING, not SCOUTING -- the identical
## backward-compatibility seam AntForageBehavior's own doc comment
## explains: a direct construction (e.g. a test) can start with an
## already-known target and walk straight to it; begin_scouting() is how
## a caller opts into the "no known target yet" path (real production
## dispatch, BeeForagerMarker, always calls it).
##
## No engine dependencies, so the whole cycle is unit-testable
## headlessly -- this decides WHEN things happen; the marker
## (BeeForagerMarker) owns the world effect (actually sensing/drinking a
## flower's real nectar, and depositing it home as honey).

enum Phase { SCOUTING, APPROACHING, RETURNING }

var phase := Phase.APPROACHING

## Whether real nectar was actually there on arrival -- another
## forager, or simple bad luck (the bloom drained itself dry), may have
## taken it in the time this bee spent flying over. A real bee does not
## just vanish if so; it still flies home, simply with nothing to
## deposit once it gets there.
var found_food := false


func begin_scouting() -> void:
	phase = Phase.SCOUTING


## A scouting bee's own local sensing found real nectar nearby -- now fly
## the last short distance to it. Committing is "I know where it is now",
## not "I already have it": arrive_at_food still resolves the real
## drink-or-miss check on genuine arrival, same as ever.
func commit_to_food() -> void:
	phase = Phase.APPROACHING


## Arrived at the flower's real position. `succeeded` is the caller's own
## real-world check (e.g. whether the bloom still had nectar to drink) --
## this state machine has no way to know that on its own.
func arrive_at_food(succeeded: bool) -> void:
	found_food = succeeded
	phase = Phase.RETURNING


## Wandered too long/far while scouting and found nothing real -- flies
## home empty-handed, the same "still returns, just with nothing to show
## for it" contract an unsuccessful APPROACHING trip already has.
func give_up_scouting() -> void:
	found_food = false
	phase = Phase.RETURNING
