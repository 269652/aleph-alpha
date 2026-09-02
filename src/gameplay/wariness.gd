extends RefCounted

## How rattled an individual animal is, right now (see
## docs/concept/animal_husbandry.md "The approach" -> "Wariness, and how a
## spooked animal recovers").
##
## An animal that has just fled from the player should be harder to approach
## than one that never noticed them, and it should get over it. Without this,
## every approach in the world starts from the same blank slate, so chasing an
## animal costs the player nothing and patience buys them nothing -- the two
## halves of the same missing mechanic.
##
## A RAMP, not a flag. `ecosystem_dynamics.md` enforces "thresholds are ramps
## or hysteresis, never hard switches" everywhere else in the sim, and a
## spooked/not-spooked boolean would be exactly the hard switch it forbids: an
## animal would be either fully calm or fully wild with nothing in between for
## the player to work against.
##
## **What the player presses for this is nothing, and that is deliberate.**
## Wariness decays by ABSENCE -- the input is leaving the animal alone. It is
## the one mechanic in this game whose correct play is to walk away. The player
## still chose it: they chose to spook the animal, and they choose when to come
## back.
##
## Pure and engine-free: this is arithmetic over a float. Storing it per
## individual, and deciding when a spook happened, is the caller's job (see
## CreatureMarker).

const GrazerForaging = preload("res://src/gameplay/grazer_foraging.gd")

## What an animal that has never met the player carries.
const INITIAL := 0.0

## How much of the REMAINING headroom one spook takes. Expressed as a fraction
## of what is left rather than a flat addition, which is what makes repeated
## spooks compound while still never leaving [0,1]: an animal you have chased
## four times is warier than one you startled once, but no afternoon of bad
## approaches can make it permanently unapproachable.
const SPOOK_FRACTION := 0.5

## How long being left alone takes to halve it, in seconds.
##
## Not an eyeballed number: it is ONE ordinary grazing bout (head down, then
## the pause before the next bite). Tying it to the grazing cycle means the
## recovery reads as the animal going back to what it was doing, and it stays
## correct if grazing is ever retuned.
const HALF_LIFE_SECONDS := GrazerForaging.GRAZE_SECONDS + GrazerForaging.REGRAZE_SECONDS

## How many of those bouts it takes for a single spook to have very nearly
## cleared. Four half-lives leaves 1/16th of it, which is below what any of
## FlightDistance's terms can express as a visible difference.
const RECOVERY_BOUTS := 4

## Below this, an animal is simply calm. An exponential decay never actually
## reaches zero, and "not quite zero forever" is a real trap: anything that
## treats `wariness > 0.0` as "has been spooked" would latch on the first
## fright and never let go. Snapping is what makes "left alone long enough"
## mean something a caller can test.
const CALM_EPSILON := 0.005


## This animal after being startled once more.
static func after_spook(wariness: float) -> float:
	var current := clampf(wariness, 0.0, 1.0)
	return current + SPOOK_FRACTION * (1.0 - current)


## This animal after `seconds` with the player's scent on it (see
## WindScent, FlightDistance.smells_player).
##
## A whiff is not a fright: it does not make an animal bolt, it makes it JUMPY
## -- head up, nervous, breaking earlier when something does finally come close.
## Routing the scent channel through wariness rather than through a second flee
## trigger is what keeps FlightDistance the single owner of "when does this
## animal run", and it is also the truer behaviour: a deer that catches your
## scent across a meadow does not sprint, it stops trusting the meadow.
##
## Rises toward fully wary on the same clock the decay uses, so one grazing
## bout spent standing upwind of an animal costs you half of its patience --
## and moving round to its downwind side stops the clock rather than resetting
## anything.
static func after_scent(wariness: float, seconds: float) -> float:
	if seconds <= 0.0:
		return clampf(wariness, 0.0, 1.0)
	var current := clampf(wariness, 0.0, 1.0)
	var closed := 1.0 - pow(0.5, seconds / HALF_LIFE_SECONDS)
	return current + (1.0 - current) * closed


## This animal after `seconds` of nothing happening to it.
##
## Exponential rather than linear so it is frame-rate independent by
## construction: two half-steps land exactly where one whole step does, which a
## `value - rate * delta` ramp does not guarantee once it clamps at zero.
static func after_calm(wariness: float, seconds: float) -> float:
	if seconds <= 0.0:
		return clampf(wariness, 0.0, 1.0)
	var decayed := clampf(wariness, 0.0, 1.0) * pow(0.5, seconds / HALF_LIFE_SECONDS)
	return 0.0 if decayed < CALM_EPSILON else decayed
