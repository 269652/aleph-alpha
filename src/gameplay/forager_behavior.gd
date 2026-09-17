extends RefCounted

## Pure state machine for a villager who hunts or fishes REAL quarry (see
## docs/concept/npc.md, "Work against the real world, not against a
## number").
##
## Mirrors LumberjackBehavior's split exactly, because it is the same
## mechanic with a different caller -- that doc's own phrase: "an NPC
## swinging an axe is not a separate mechanic, it is the same one with a
## different caller." This decides WHEN things happen; NpcMarker owns the
## world effect (finding a real CreatureMarker or FishMarker, walking to
## it, striking it, crediting the village market). No engine dependency,
## so the whole cycle is unit-testable headlessly.
##
## SEEKING -> APPROACHING -> TAKING -> SEEKING.
##
## Shorter than the Lumberjack's cycle by its two carrying phases, and
## deliberately so: a felled trunk has to be hauled to the Sägewerk that
## shapes it, while a hunter's catch goes straight into the village market
## the moment it is taken. Adding a haul for symmetry would be inventing a
## building for it to be hauled to.

const LumberjackBehavior = preload("res://src/gameplay/lumberjack_behavior.gd")

enum Phase { SEEKING, APPROACHING, TAKING }

## How long a villager looks around before committing to a quarry they have
## found. The Lumberjack's OWN interval rather than a second guess at the
## same thing: both are "look around, then go" gates on the same kind of
## worker, and two numbers for one behaviour would drift (test-pinned
## against it in test_forager_behavior.gd).
const REHUNT_SECONDS := LumberjackBehavior.REHUNT_SECONDS

## How often a blow lands while TAKING -- likewise the Lumberjack's own
## swing pace. A spear thrust and an axe stroke fall at about the same
## rate, and the alternative is a second invented number for the same act.
const STRIKE_INTERVAL := LumberjackBehavior.SWING_INTERVAL

var phase := Phase.SEEKING

var _phase_elapsed := 0.0
var _strike_elapsed := 0.0


## Whether this villager is willing to commit to newly-found quarry right
## now: seeking, and past the look-around interval.
func can_commit() -> bool:
	return phase == Phase.SEEKING and _phase_elapsed >= REHUNT_SECONDS


## Commits to quarry the caller has picked. Returns false (a no-op) when
## not yet willing, so a caller can simply offer a target every frame and
## let this decide.
func begin_approach() -> bool:
	if not can_commit():
		return false
	_enter(Phase.APPROACHING)
	return true


## Arrived at the quarry -- the caller decides "arrived" by real distance,
## not a timer, since how long the walk takes depends on how far it was.
func arrive() -> bool:
	if phase != Phase.APPROACHING:
		return false
	_enter(Phase.TAKING)
	return true


## Gives up on the current quarry -- it fled, something else killed it, or
## its chunk unloaded -- and looks around again before committing next.
func abort() -> void:
	_enter(Phase.SEEKING)


## Advances by `delta`. Returns true exactly on each tick a blow should
## land; the caller then calls take_damage on its real target. A no-op
## (always false) outside TAKING, so a villager never swings at thin air
## while still walking.
func advance(delta: float) -> bool:
	_phase_elapsed += delta
	if phase != Phase.TAKING:
		return false
	_strike_elapsed += delta
	if _strike_elapsed >= STRIKE_INTERVAL:
		_strike_elapsed -= STRIKE_INTERVAL
		return true
	return false


## The quarry is taken -- back out to look for more, after the same beat
## any fresh search takes. A hunter does not lock onto the next deer over
## the body of the last.
func finish_take() -> void:
	_enter(Phase.SEEKING)


func _enter(next_phase: int) -> void:
	phase = next_phase
	_phase_elapsed = 0.0
	_strike_elapsed = 0.0
