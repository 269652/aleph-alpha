extends RefCounted

## Pure state machine for a fish-eating bird (kingfisher) diving to catch
## fish -- see docs/concept/ecosystem_dynamics.md's "fish-eating birds" (A
## new aerial tier). cruise -> dive -> grab-or-miss -> ascend -> cooldown ->
## cruise. This module only decides WHEN a dive happens and WHETHER it
## succeeds -- applying a successful grab to the real aquatic population
## (EcosystemSimulation.record_catch) is the caller's job (see
## PiscivoreBirdMarker), the same separation FishingSession/FishingMinigame
## already use for the player's own catch.

## HOVERING and CARRYING are the two halves of a strike the player actually
## watches: a kingfisher holds station over its fish before dropping, and
## leaves with it visibly in its beak.
enum Phase { CRUISE, HOVERING, DIVING, ASCENDING, CARRYING, COOLDOWN }

## How long the bird holds station over its target before dropping. This is
## the signature kingfisher beat -- without it the strike is over before the
## player registers that anything is happening.
const HOVER_DURATION := 1.4

## How long it flies off with a fish in its beak before swallowing it. The
## visible payoff of a successful strike.
const CARRY_DURATION := 2.5

const DIVE_DURATION := 0.6
const ASCEND_DURATION := 0.6

## Real birds don't dive continuously -- a digestion/re-hunt interval before
## the next attempt.
const COOLDOWN_DURATION := 8.0

## Real herons/ospreys/kingfishers miss most strikes -- a dive is a
## probability roll, not a guaranteed catch. Pinned by
## test_grab_outcome_varies_with_seed (neither always-succeeds nor
## never-succeeds across many seeds).
const CATCH_CHANCE := 0.35

var phase := Phase.CRUISE

var _phase_elapsed := 0.0
var _dive_seed := 0
## True once this dive's grab-or-miss has been resolved (so advance() only
## reports it once, even though phase stays DIVING for the rest of
## DIVE_DURATION so the descent animation can keep playing).
var _grab_resolved := false
var _last_grab_succeeded := false


## Begins the hover that precedes a strike. The caller has found a fish and
## flown to it; this holds the bird over the water for HOVER_DURATION and then
## drops it into the dive on its own.
##
## Refused unless cruising, so a bird already committed to a strike cannot
## restart it.
func begin_hover(seed_value: int) -> bool:
	if phase != Phase.CRUISE:
		return false
	phase = Phase.HOVERING
	_phase_elapsed = 0.0
	_dive_seed = seed_value
	_grab_resolved = false
	return true


## Starts a dive if currently cruising and there's something to dive for.
## No-op (returns false) if already diving/ascending/on cooldown, or if
## fish_population is zero -- a bird doesn't dive at an empty patch of water.
func try_start_dive(fish_population: float, seed_value: int) -> bool:
	if phase != Phase.CRUISE or fish_population <= 0.0:
		return false
	phase = Phase.DIVING
	_phase_elapsed = 0.0
	_dive_seed = seed_value
	_grab_resolved = false
	return true


## Advances the state machine by `delta` seconds. Returns true exactly once
## per dive, the tick its grab-or-miss outcome resolves -- the caller should
## check did_last_grab_succeed() then and, if true, record the catch against
## the real aquatic population.
func advance(delta: float) -> bool:
	_phase_elapsed += delta
	var resolved_this_tick := false
	match phase:
		Phase.HOVERING:
			if _phase_elapsed >= HOVER_DURATION:
				phase = Phase.DIVING
				_phase_elapsed = 0.0
		Phase.DIVING:
			if not _grab_resolved and _phase_elapsed >= DIVE_DURATION * 0.5:
				_grab_resolved = true
				_last_grab_succeeded = _seeded_unit_float(_dive_seed) < CATCH_CHANCE
				resolved_this_tick = true
			if _phase_elapsed >= DIVE_DURATION:
				# A catch is carried off visibly; a miss is just a bird
				# pulling up empty.
				phase = Phase.CARRYING if _last_grab_succeeded else Phase.ASCENDING
				_phase_elapsed = 0.0
		Phase.CARRYING:
			if _phase_elapsed >= CARRY_DURATION:
				phase = Phase.ASCENDING  # swallowed; back to the air
				_phase_elapsed = 0.0
		Phase.ASCENDING:
			if _phase_elapsed >= ASCEND_DURATION:
				phase = Phase.COOLDOWN
				_phase_elapsed = 0.0
		Phase.COOLDOWN:
			if _phase_elapsed >= COOLDOWN_DURATION:
				phase = Phase.CRUISE
				_phase_elapsed = 0.0
	return resolved_this_tick


func did_last_grab_succeed() -> bool:
	return _last_grab_succeeded


## [0,1] visual dive depth for animation (see PiscivoreBirdMarker): rises
## 0 -> 1 through the dive, falls 1 -> 0 through the ascend, 0 otherwise.
func dive_progress() -> float:
	if phase == Phase.DIVING:
		return clampf(_phase_elapsed / DIVE_DURATION, 0.0, 1.0)
	if phase == Phase.ASCENDING:
		return clampf(1.0 - _phase_elapsed / ASCEND_DURATION, 0.0, 1.0)
	return 0.0


func _seeded_unit_float(seed_value: int) -> float:
	return float(absi(hash(seed_value)) % 10000) / 10000.0
