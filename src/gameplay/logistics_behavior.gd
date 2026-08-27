extends RefCounted

## Pure state machine for a Logistics worker: the autonomous carrier that
## moves a production building's accumulated output into a Storage building
## (see docs/concept/timber_construction.md's "Storage, logistics, and the
## autonomous dependency chain" section). Mirrors CarrionForageBehavior's own
## split exactly (SEEKING/APPROACHING is a walk, bracketed by a timed action)
## except a logistics run has TWO destinations -- a source, then Storage --
## so it needs one extra walk leg (CARRYING) a single-destination forager
## never needed.
##
## SEEKING -> APPROACHING -> COLLECTING -> CARRYING -> DEPOSITING -> SEEKING.
## No engine dependencies -- the caller (LogisticsMarker) owns WHERE the
## nearest source/storage are and WHAT was picked up; this only decides WHEN
## each leg completes, the same split every other creature/worker behaviour
## in this codebase already uses.

enum Phase { SEEKING, APPROACHING, COLLECTING, CARRYING, DEPOSITING }

## What advance() reports on a completed timed action -- lets one method
## drive both COLLECTING and DEPOSITING (generalizes GroundForageBehavior's
## own "advance returns true on the one meaningful tick" contract to two
## distinct events instead of one, since a logistics run has two timed
## actions where a single-destination forager only has one).
enum Outcome { NONE, COLLECTED, DEPOSITED }

## How long an idle worker waits before checking for a new source again --
## the same short "an idle worker checks again shortly" coordination pause
## CarrionForageBehavior.REHUNT_SECONDS already uses, not a long patrol
## interval.
const REHUNT_SECONDS := 2.0

## How long loading a producer's accumulated output onto a hand-cart takes --
## a real, non-instant task (stacking a few beams/planks), in the same
## "long enough to read as a real action" range GroundForageBehavior.PECK_
## SECONDS already uses.
const COLLECT_SECONDS := 3.0

## Unloading at Storage -- shorter than collecting: stacking material INTO an
## organized rack is faster than lifting it off an ungainly pile at the
## source.
const DEPOSIT_SECONDS := 2.0

var phase := Phase.SEEKING

var _phase_elapsed := 0.0


## Whether the worker is willing to commit to a source right now: idle, and
## past the coordination pause.
func can_commit() -> bool:
	return phase == Phase.SEEKING and _phase_elapsed >= REHUNT_SECONDS


## Commits to a source the caller has picked. Returns false (a no-op) if not
## yet willing to commit, so a caller can just offer a target and let this
## decide, the same shape CarrionForageBehavior.begin_approach already uses.
func begin_approach() -> bool:
	if not can_commit():
		return false
	_enter(Phase.APPROACHING)
	return true


## The worker has reached the source -- ends on real arrival, not a timer,
## same as CarrionForageBehavior.arrive.
func arrive_at_source() -> bool:
	if phase != Phase.APPROACHING:
		return false
	_enter(Phase.COLLECTING)
	return true


## The worker has reached Storage -- the second walk leg's own arrival,
## distinct from arrive_at_source because CARRYING's destination is a
## different real place than APPROACHING's was.
func arrive_at_storage() -> bool:
	if phase != Phase.CARRYING:
		return false
	_enter(Phase.DEPOSITING)
	return true


## Gives up on the current run (the source's output vanished, another worker
## took it, the chunk unloaded) and returns to seeking with a fresh
## coordination pause -- valid from APPROACHING or CARRYING, whichever leg
## the caller finds broken, mirroring CarrionForageBehavior.abort.
func abort() -> void:
	_enter(Phase.SEEKING)


## Advances by `delta`. Ticks the timed COLLECTING/DEPOSITING actions and
## reports the tick each one resolves on: COLLECTED transitions straight into
## CARRYING (the caller now knows what was picked up and can look up a
## storage target), DEPOSITED transitions back to SEEKING. A no-op (NONE) in
## every other phase, mirroring CarrionForageBehavior.advance's contract --
## including during SEEKING, where this just ticks the coordination-pause
## clock can_commit reads.
func advance(delta: float) -> int:
	_phase_elapsed += delta
	if phase == Phase.COLLECTING and _phase_elapsed >= COLLECT_SECONDS:
		_enter(Phase.CARRYING, _phase_elapsed - COLLECT_SECONDS)
		return Outcome.COLLECTED
	if phase == Phase.DEPOSITING and _phase_elapsed >= DEPOSIT_SECONDS:
		_enter(Phase.SEEKING, _phase_elapsed - DEPOSIT_SECONDS)
		return Outcome.DEPOSITED
	return Outcome.NONE


func _enter(next_phase: int, carried_elapsed: float = 0.0) -> void:
	phase = next_phase
	_phase_elapsed = carried_elapsed
