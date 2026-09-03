extends RefCounted

## Pure state machine for a ground decomposer (ant, carrion bug) working a
## carcass or guts pile -- see docs/concept/carrion.md. Deliberately simpler
## than GroundForageBehavior/PiscivoreBirdBehavior: no flight, so there is no
## separate "descend" phase -- approaching IS the walk, and it ends on
## arrival exactly like a bird's own descent does. No separate "resume"
## beat either -- a decomposer that's done eating just turns and walks off,
## unlike a bird that visibly needs a beat to swallow and look around.
##
## SEEKING -> APPROACHING -> FEEDING -> SEEKING. No engine dependencies, so
## the whole cycle is unit-testable headlessly, same split as every other
## creature behaviour in this codebase: this decides WHEN things happen: the
## marker owns the world effect (actually finding/walking to/biting a real
## Carcass/CarcassGuts node).

enum Phase { SEEKING, APPROACHING, FEEDING }

## How long between committing to a new target -- short, unlike a bird's own
## multi-second re-hunt: an ant or carrion bug doesn't idle long once
## carrion is actually around.
const REHUNT_SECONDS := 2.0

## How often a bite actually lands while feeding.
const BITE_INTERVAL := 1.0

## How much a candidate's effective distance shrinks per adult fly already
## on it (see docs/concept/flies.md's Carcass.fly_count) -- real scavengers
## really do cue off circling flies as a sign something worth investigating
## is there (docs/concept/carrion.md), so a fly-blown carcass should read as
## closer to a decomposer than an identically-placed fresh one, not just
## equally close. See effective_distance.
const FLY_ATTRACTION_DISCOUNT_PX_PER_FLY := 8.0

## The effective-distance floor -- even a heavily fly-blown carcass cannot
## read as closer than this, so a genuinely distant one still never beats a
## real nearby target that is already closer than the floor itself.
const MIN_EFFECTIVE_DISTANCE_PX := 4.0

var phase := Phase.SEEKING

var _phase_elapsed := 0.0
var _bite_elapsed := 0.0


## Whether this decomposer is willing to commit to a target right now:
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
	_enter(Phase.FEEDING)
	return true


## Gives up on the current target (it's gone, consumed by something else,
## the chunk unloaded) and returns to seeking with a fresh re-hunt clock.
func abort() -> void:
	_enter(Phase.SEEKING)


## Advances by `delta`. Returns true exactly on each tick a bite should
## land -- the caller then calls take_bite on its actual target. A no-op
## (always false) outside the feeding phase.
func advance(delta: float) -> bool:
	_phase_elapsed += delta
	if phase != Phase.FEEDING:
		return false
	_bite_elapsed += delta
	if _bite_elapsed >= BITE_INTERVAL:
		_bite_elapsed -= BITE_INTERVAL
		return true
	return false


func _enter(next_phase: int) -> void:
	phase = next_phase
	_phase_elapsed = 0.0
	_bite_elapsed = 0.0


## How far away a carcass with `fly_count` adult flies on it EFFECTIVELY
## reads to a decomposer scanning at `real_distance_px` -- lower reads as
## more attractive. Static and pure (no target selection happens here, only
## the score DecomposerMarker._nearest_carrion picks the smallest of), so it
## is unit-testable without a live scene, matching every other tuned
## formula in this codebase.
static func effective_distance(real_distance_px: float, fly_count: int) -> float:
	var discount := float(maxi(fly_count, 0)) * FLY_ATTRACTION_DISCOUNT_PX_PER_FLY
	return maxf(real_distance_px - discount, MIN_EFFECTIVE_DISTANCE_PX)
