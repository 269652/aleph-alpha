extends RefCounted

## Pure state machine for a bird that feeds off the GROUND -- a robin hunting
## earthworms (see docs/concept/soil_fauna.md's "Ground foraging behaviour").
## seek -> descend -> peck -> resume -> seek.
##
## Same separation as PiscivoreBirdBehavior, and for the same reason: this
## module decides only WHEN things happen and WHETHER the strike lands.
## Actually removing the worm from the world is the caller's job (see
## AmbientFlyerMarker, which calls EarthChunkManager.take_worm_at), exactly as
## FishingSession/FishingMinigame already split the player's own catch. No
## engine dependencies at all, so the whole feeding cycle is unit-testable
## headlessly.
##
## A robin does not eat on the wing like a swallow -- it flies, lands, stands,
## strikes, swallows, and moves on. That is why the visible beat here is
## "land and sit", not a swoop.

const PollinatorForaging = preload("res://src/gameplay/pollinator_foraging.gd")

enum Phase { SEEKING, DESCENDING, PECKING, RESUMING }

## How far a ground-feeding bird looks for something to eat, in tiles.
## Deliberately much shorter than PollinatorForaging.FORAGE_SEARCH_TILES (18):
## a real robin holds a small feeding territory and works it, where a bee
## commutes hundreds of metres from the hive. Comfortably inside the 3x3 chunk
## window EarthChunkManager.worms_near actually scans (32 tiles to a chunk),
## past which a bird is blind regardless of what is really in the soil.
const SEARCH_TILES := 10.0

## How close it must get before it counts as landing on the worm. Shared with
## the pollinator path rather than restated: "close enough to have arrived" is
## the same question for a bee on a bloom and a robin on a worm, and two
## different answers would be two different bugs.
const LANDING_DISTANCE := PollinatorForaging.LANDING_DISTANCE


## Which worm this bird should go for.
##
## Delegates to PollinatorForaging.choose_target, which despite its home is
## not really about nectar at all: it is "pick one of the NEAREST_CANDIDATE_
## POOL nearest candidates, scattered by a per-flyer seed". That scatter is
## the whole reason two robins standing in the same meadow don't queue up
## behind the same worm -- see that constant for the measured failure (eight
## flyers all choosing one bloom and conga-lining after it, only the leader
## ever feeding) it exists to fix, which a second, parallel "nearest wins"
## implementation here would reintroduce.
##
## It applies to worms unchanged: worm entries carry no "nectar" key, which
## choose_target defaults to 1.0 (an unavailable worm is never in the list in
## the first place -- see EarthwormPatch.is_surfaced), and a robin keeps no
## visit memory, because an eaten burrow is already excluded for
## EarthwormPatch.RECOVERY_SECONDS by the sim itself rather than by the bird
## having to remember it.
static func choose_worm(position: Vector2, worms: Array, seed_value: int) -> Dictionary:
	return PollinatorForaging.choose_target(position, worms, [], 0.0, seed_value)

## How long the bird flies around between meals. This is the "run" half of a
## real robin's run-stop-peck cycle: it does not chain strikes back to back,
## and without the interval the bird would hop worm to worm without ever
## reading as a bird in flight. Comparable to PiscivoreBirdBehavior's
## COOLDOWN_DURATION, which exists for the same reason.
const REHUNT_SECONDS := 6.0

## How long the bird sits on the ground working the worm. In the same range as
## PollinatorForaging.DRINK_SECONDS (2.4) -- long enough to read as "settled
## on it" rather than a bounce.
const PECK_SECONDS := 2.2

## How many times the head dips across that phase. A single dip reads as the
## bird freezing; several read as pecking.
const PECK_COUNT := 3

## The head-up beat after the strike, before take-off: it swallows and looks
## around. Without it the bird teleports back into flight the instant it eats.
const RESUME_SECONDS := 0.9

## How long a committed descent may run before the bird gives up. A target can
## become unreachable (another robin took the worm, the chunk unloaded), and
## without a timeout the bird would chase a dead point forever.
const DESCENT_TIMEOUT := 8.0

## Which of the PECK_COUNT dips actually takes the worm: the middle one.
const _STRIKE_DIP := PECK_COUNT / 2

## Where in the peck phase the strike resolves, as a fraction.
##
## DERIVED from _STRIKE_DIP rather than eyeballed, and deliberately the MIDDLE
## of that dip rather than its leading edge: the worm has to disappear while
## the beak is actually in the grass (see
## test_the_beak_is_down_at_the_moment_the_strike_resolves), and a fraction
## sitting exactly on a dip boundary lands on the wrong side of it under
## ordinary float accumulation. Dip `i` occupies half-slot `2i+1` of `2 *
## PECK_COUNT`, so its midpoint is `(2i + 1.5) / (2 * PECK_COUNT)`.
const PECK_STRIKE_FRACTION := (2.0 * float(_STRIKE_DIP) + 1.5) / (2.0 * float(PECK_COUNT))

var phase := Phase.SEEKING

var _phase_elapsed := 0.0
## True once this peck's strike has been reported, so advance() reports it
## exactly once even though the phase continues for the rest of PECK_SECONDS
## so the animation can play out.
var _strike_resolved := false


## Whether the bird is willing to commit to a worm right now: airborne, and
## past the re-hunt interval.
func can_commit() -> bool:
	return phase == Phase.SEEKING and _phase_elapsed >= REHUNT_SECONDS


## Commits to a worm the caller has picked. Returns false (a no-op) if the
## bird is already busy or has not flown around long enough yet, so a caller
## can just offer a target and let this decide.
func begin_descent() -> bool:
	if not can_commit():
		return false
	_enter(Phase.DESCENDING)
	return true


## The bird has reached the worm. Ends the descent on ARRIVAL rather than on a
## timer, because how long the flight takes depends on how far the worm was.
func arrive() -> bool:
	if phase != Phase.DESCENDING:
		return false
	_enter(Phase.PECKING)
	return true


## Gives up on the current target and returns to the air -- for when the worm
## is gone by the time the bird gets there (another robin ate it, the chunk
## unloaded). Costs the full re-hunt interval, so a bird that whiffs flies
## around again rather than instantly re-targeting.
func abort() -> void:
	_enter(Phase.SEEKING)


## Advances by `delta`. Returns true exactly once per peck, on the tick the
## strike resolves -- the caller should take the worm from the world then.
func advance(delta: float) -> bool:
	_phase_elapsed += delta
	var resolved := false
	# A single large delta can cross more than one phase boundary, so a
	# transition carries the remainder forward instead of zeroing it (no time
	# is lost). Bounded by the phase count, so it can never spin.
	for _i in Phase.size():
		if (
			phase == Phase.PECKING
			and not _strike_resolved
			and _phase_elapsed >= PECK_SECONDS * PECK_STRIKE_FRACTION
		):
			_strike_resolved = true
			resolved = true
		var duration := _phase_duration()
		if duration <= 0.0 or _phase_elapsed < duration:
			break
		_enter(_phase_after(), _phase_elapsed - duration)
	return resolved


## Whether the bird is sitting on the ground rather than flying -- what drives
## AmbientFlyerMarker's `perched` folded-wing state.
func is_grounded() -> bool:
	return phase == Phase.PECKING or phase == Phase.RESUMING


## Whether the head is currently dipped into the grass. Alternates across the
## peck phase so the bird visibly pecks; starts UP, because it lands first and
## then dips.
func is_beak_down() -> bool:
	if phase != Phase.PECKING:
		return false
	var slot := int(peck_progress() * float(PECK_COUNT) * 2.0)
	return slot % 2 == 1


## [0,1] progress through the peck phase -- the animation clock, the same role
## PiscivoreBirdBehavior.dive_progress plays for a dive.
func peck_progress() -> float:
	if phase != Phase.PECKING:
		return 0.0
	return clampf(_phase_elapsed / PECK_SECONDS, 0.0, 1.0)


## How long the current phase lasts before it times out on its own. SEEKING
## and DESCENDING are the two that do NOT end on their own clock -- seeking
## ends when the bird commits, descending when it arrives -- but descending
## still has a give-up timeout (see DESCENT_TIMEOUT).
func _phase_duration() -> float:
	match phase:
		Phase.DESCENDING:
			return DESCENT_TIMEOUT
		Phase.PECKING:
			return PECK_SECONDS
		Phase.RESUMING:
			return RESUME_SECONDS
		_:
			return 0.0


func _phase_after() -> int:
	if phase == Phase.PECKING:
		return Phase.RESUMING
	# A timed-out descent and a finished resume both put the bird back in the
	# air with a fresh re-hunt interval to fly out.
	return Phase.SEEKING


func _enter(next_phase: int, carried_elapsed: float = 0.0) -> void:
	phase = next_phase
	_phase_elapsed = carried_elapsed
	_strike_resolved = false
