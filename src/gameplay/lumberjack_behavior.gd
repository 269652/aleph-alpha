extends RefCounted

## Pure state machine for the Sägewerk's Lumberjack NPC (see
## docs/concept/timber_construction.md's NPC construction section: "an NPC
## swinging an axe is not a separate mechanic, it is the same one with a
## different caller"). Mirrors CarrionForageBehavior's split exactly: this
## decides WHEN things happen; LumberjackMarker owns the actual world effect
## (finding/walking to/swinging at a real ChoppableTree, dropping items at
## the Sägewerk). No engine dependencies, so the whole cycle is
## unit-testable headlessly, same as every other creature/NPC behaviour in
## this codebase.
##
## SEEKING -> APPROACHING -> FELLING -> CARRYING -> DEPOSIT -> SEEKING.
## Scoped to exactly this loop per this pass's brief -- CARRY_MATERIAL/
## PLACE_PIECE (the Lumberjack building a house itself) stay unbuilt, for a
## later pass.

enum Phase { SEEKING, APPROACHING, FELLING, CARRYING, DEPOSIT }

## How long between committing to a new tree -- mirrors
## CarrionForageBehavior.REHUNT_SECONDS's own reasoning (a worker doesn't
## idle long once there's a tree in reach), same magnitude since both are
## "look around, then go" gates rather than a load-bearing simulation rate.
const REHUNT_SECONDS := 2.0

## How often a felling swing lands while FELLING -- matches the real-world
## pace an axe/saw stroke actually falls at, not an instant chop; the exact
## number is illustrative pacing (per this project's no-manual-tuning rule,
## pinned by test_a_swing_lands_once_the_swing_interval_elapses et al, not
## eyeballed at the call site).
const SWING_INTERVAL := 1.0

## A beat to set the carried log down at the Sägewerk before turning back to
## the woods -- mirrors CarrionForageBehavior.BITE_INTERVAL's own "a dwell,
## not an instant transition" shape, pinned by
## test_deposit_completes_once_deposit_seconds_elapse.
const DEPOSIT_SECONDS := 1.0

var phase := Phase.SEEKING

var _phase_elapsed := 0.0
var _swing_elapsed := 0.0


## Whether this Lumberjack is willing to commit to a newly-found tree right
## now: seeking, and past the re-hunt interval.
func can_commit() -> bool:
	return phase == Phase.SEEKING and _phase_elapsed >= REHUNT_SECONDS


## Commits to a tree the caller has picked. Returns false (a no-op) if not
## yet willing to commit, so a caller can just offer a target and let this
## decide.
func begin_approach() -> bool:
	if not can_commit():
		return false
	_enter(Phase.APPROACHING)
	return true


## Arrived at the tree -- caller decides "arrived" by real distance, not a
## timer, since how long the walk takes depends on how far the tree was.
func arrive() -> bool:
	if phase != Phase.APPROACHING:
		return false
	_enter(Phase.FELLING)
	return true


## Gives up on the current tree (it's gone -- felled and cleared by someone
## else, the chunk unloaded) and returns to seeking with a fresh re-hunt
## clock.
func abort() -> void:
	_enter(Phase.SEEKING)


## Advances by `delta`. Returns true exactly on each tick a felling swing
## should land -- the caller then calls take_damage on its actual target. A
## no-op (always false) outside FELLING.
func advance(delta: float) -> bool:
	_phase_elapsed += delta
	if phase != Phase.FELLING:
		return false
	_swing_elapsed += delta
	if _swing_elapsed >= SWING_INTERVAL:
		_swing_elapsed -= SWING_INTERVAL
		return true
	return false


## The trunk is fully worked up (bucked into its last log) -- move the
## carried haul back to the Sägewerk.
func start_carry() -> bool:
	if phase != Phase.FELLING:
		return false
	_enter(Phase.CARRYING)
	return true


## Arrived back at the Sägewerk with a load.
func arrive_home() -> bool:
	if phase != Phase.CARRYING:
		return false
	_enter(Phase.DEPOSIT)
	return true


## Advances the DEPOSIT dwell by `delta`. Returns true exactly once, the
## tick the dwell completes -- the caller then credits the Sägewerk's log
## stock and calls finish_deposit. A no-op (always false) outside DEPOSIT.
func advance_deposit(delta: float) -> bool:
	if phase != Phase.DEPOSIT:
		return false
	_phase_elapsed += delta
	return _phase_elapsed >= DEPOSIT_SECONDS


## The load is set down -- back to the woods for another tree.
func finish_deposit() -> void:
	_enter(Phase.SEEKING)


func _enter(next_phase: int) -> void:
	phase = next_phase
	_phase_elapsed = 0.0
	_swing_elapsed = 0.0
