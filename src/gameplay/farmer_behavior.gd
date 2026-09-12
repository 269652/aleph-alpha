extends RefCounted

## Pure state machine for the Farm's Farmer NPC (see
## docs/concept/npc_farm_production.md). Mirrors LumberjackBehavior's own
## split exactly: this decides WHEN things happen; FarmerMarker owns the
## actual world effect (which FarmPlot needs attention, walking to it,
## tilling/watering/harvesting it, crediting the Farm's own StructureStock).
##
## SEEKING -> APPROACHING -> WORKING -> SEEKING. Simpler than
## LumberjackBehavior's own SEEKING/APPROACHING/FELLING/CARRYING/DEPOSIT
## loop: a Farm's plots are the Farm's own fixed fixtures (never more than a
## few strides apart), so a harvested crop credits the Farm's stock the
## moment WORKING completes -- no separate CARRYING leg back to a distant
## worksite the way a felled log needs one.

enum Phase { SEEKING, APPROACHING, WORKING }

## How long between committing to a newly-chosen plot -- mirrors
## LumberjackBehavior.REHUNT_SECONDS' own "a worker doesn't idle long once
## there's something to do" reasoning; shorter here since a Farmer's next
## target (one of its own few plots) is always immediately knowable, unlike
## a Lumberjack scanning for a standing tree.
const REHUNT_SECONDS := 1.0

## How long tending one plot takes -- kneeling to till, water, or harvest a
## bed is a real, non-instant action, in the same "long enough to read as a
## real action" range LumberjackBehavior.DEPOSIT_SECONDS already uses.
const WORK_SECONDS := 2.0

var phase := Phase.SEEKING

var _phase_elapsed := 0.0


## Whether this Farmer is willing to commit to a newly-chosen plot right
## now: seeking, and past the re-commit interval.
func can_commit() -> bool:
	return phase == Phase.SEEKING and _phase_elapsed >= REHUNT_SECONDS


## Commits to the plot the caller has picked. Returns false (a no-op) if not
## yet willing to commit, so a caller can just offer a target and let this
## decide.
func begin_approach() -> bool:
	if not can_commit():
		return false
	_enter(Phase.APPROACHING)
	return true


## Arrived at the target plot -- caller decides "arrived" by real distance,
## not a timer.
func arrive() -> bool:
	if phase != Phase.APPROACHING:
		return false
	_enter(Phase.WORKING)
	return true


## Gives up on the current target (the plot vanished, the chunk unloaded)
## and returns to seeking with a fresh re-commit clock.
func abort() -> void:
	_enter(Phase.SEEKING)


## Advances by `delta`. Returns true exactly on the tick the WORKING dwell
## completes -- the caller then performs the actual till/water/harvest
## action and calls finish_work. A no-op (always false) outside WORKING --
## mirrors LumberjackBehavior.advance's dual "tick the SEEKING clock, report
## the one meaningful WORKING tick" contract, collapsed into one phase since
## a Farmer only ever has one timed action, not two.
func advance(delta: float) -> bool:
	_phase_elapsed += delta
	if phase != Phase.WORKING:
		return false
	return _phase_elapsed >= WORK_SECONDS


## The plot's action is done -- back to seeking the next one.
func finish_work() -> void:
	_enter(Phase.SEEKING)


func _enter(next_phase: int) -> void:
	phase = next_phase
	_phase_elapsed = 0.0
