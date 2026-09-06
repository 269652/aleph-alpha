extends RefCounted

## Pure state machine for a caterpillar working a food source -- either a
## real, in-season fallen leaf on the ground, or a real nearby tree
## currently in leaf (see CaterpillarMarker, docs/concept/soil_fauna.md's
## caterpillar section). Requested live: "wire caterpillars which live on
## trees and on the ground around them; they should also do groundforaging
## and eat green leaves (spring, summer only)".
##
## Mirrors CarrionForageBehavior's own SEEKING -> APPROACHING -> (feeding)
## shape closely -- no flight, so there is no separate "descend" phase,
## approaching IS the walk and ends on arrival -- but departs from it in one
## deliberate way: a tree never runs out the way a carcass does, so EATING
## ends on its OWN clock (EAT_SECONDS) rather than staying committed "until
## it's gone". This is also what actually gives "groundforaging" somewhere
## to happen: without a real end to a tree visit, a caterpillar that found
## one first would never be seen on the ground at all. Ground litter, which
## DOES get consumed in one visit, needs no timeout of its own -- the caller
## simply doesn't re-offer an already-eaten leaf, the same way
## CarrionForageBehavior's own fallen-fruit case (a single-visit item)
## already works without one.
##
## SEEKING -> APPROACHING -> EATING -> SEEKING. No engine dependencies, so
## the whole cycle is unit-testable headlessly, same split as every other
## creature behaviour in this codebase: this decides WHEN things happen; the
## marker owns the world effect (actually finding/walking to/eating from a
## real tree or a real LeafLitterField record).

enum Phase { SEEKING, APPROACHING, EATING }

## How long between committing to a new food source once seeking again --
## short, like CarrionForageBehavior's own (2.0): a slow ground crawler
## doesn't range far, so it doesn't idle long once something edible is
## actually nearby.
const REHUNT_SECONDS := 2.0

## How long one visit lasts before a caterpillar moves on of its own accord
## -- see the class doc comment for why this exists at all (a tree, unlike
## a carcass, never runs out). Long enough to read as genuinely settled in
## to eat, short enough that a caterpillar is reliably seen doing its OTHER
## named activities within a normal observation window rather than reading
## as married to the first tree it finds.
const EAT_SECONDS := 5.0

## How often a bite actually lands while eating.
const BITE_INTERVAL := 1.2

var phase := Phase.SEEKING

var _phase_elapsed := 0.0
var _bite_elapsed := 0.0


## Whether this caterpillar is willing to commit to a target right now:
## seeking, and past the re-hunt interval.
func can_commit() -> bool:
	return phase == Phase.SEEKING and _phase_elapsed >= REHUNT_SECONDS


## Commits to a target the caller has picked. Returns false (a no-op) if not
## yet willing to commit, so a caller can just offer a target and let this
## decide.
func begin_approach() -> bool:
	if not can_commit():
		return false
	_enter(Phase.APPROACHING)
	return true


## Arrived at the target -- caller decides "arrived" by real distance, not a
## timer, since how long the walk takes depends on how far the target was.
func arrive() -> bool:
	if phase != Phase.APPROACHING:
		return false
	_enter(Phase.EATING)
	return true


## Gives up on the current target (ground litter already eaten by something
## else, the chunk unloaded) and returns to seeking with a fresh re-hunt
## clock.
func abort() -> void:
	_enter(Phase.SEEKING)


## Advances by `delta`. Returns true on a tick a bite should land while
## EATING -- the caller then applies that bite to its actual target
## (removing a real leaf-litter record, or nothing at all for a tree, which
## has no depletable resource to remove). Same single-bite-per-call
## contract as CarrionForageBehavior.advance (a delta spanning several
## whole BITE_INTERVALs still reports only one bite -- an accepted
## simplification, not new here). Once `_phase_elapsed` (time in the
## CURRENT phase, the same field SEEKING's own can_commit reads) reaches
## EAT_SECONDS, this returns to SEEKING with a freshly-zeroed clock in the
## SAME call -- not one carrying EATING's own elapsed time over, which
## would let a caterpillar re-commit sooner than a normal abort ever could
## (see test_a_large_delta_crossing_the_eat_window_still_returns_to_
## seeking_cleanly).
func advance(delta: float) -> bool:
	_phase_elapsed += delta
	if phase != Phase.EATING:
		return false
	_bite_elapsed += delta
	var bit := false
	if _bite_elapsed >= BITE_INTERVAL:
		_bite_elapsed -= BITE_INTERVAL
		bit = true
	if _phase_elapsed >= EAT_SECONDS:
		_enter(Phase.SEEKING)
	return bit


func _enter(next_phase: int) -> void:
	phase = next_phase
	_phase_elapsed = 0.0
	_bite_elapsed = 0.0
