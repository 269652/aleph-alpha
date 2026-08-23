extends RefCounted

## The "strengthometer" for the hold-E-to-charge-then-release throw (see
## docs/concept/stone.md's held-item pickup/throw mechanism). A classic
## charge-meter minigame: the value bounces back and forth between a min and
## a max repeatedly while held, rather than filling monotonically -- release
## power depends on exact TIMING (letting go near a peak vs. a trough), not
## just on how long the key was held.
##
## Pure function of elapsed time, no state of its own: the caller (Player)
## tracks how long E has been held and asks fraction_at(that elapsed time)
## every frame -- the same "pure math, wiring keeps the state" split as
## PebbleDispersion/Kick.

const MIN_FRACTION := 0.0
const MAX_FRACTION := 1.0

## How long one full up-and-down bounce takes. Fast enough that charging
## reads as an active skill-check rather than a wait, slow enough that a
## player can actually aim for a specific value rather than it being a blur.
const BOUNCE_PERIOD_SECONDS := 0.9


## The meter's value in [MIN_FRACTION, MAX_FRACTION] after `elapsed_seconds`
## of holding -- a TRIANGLE wave (constant rate up, constant rate down), not
## a sine wave, so the meter moves at a steady, readable pace throughout
## instead of lingering near the ends the way a sine wave's shallow slope
## there would.
static func fraction_at(elapsed_seconds: float) -> float:
	var phase := fposmod(elapsed_seconds, BOUNCE_PERIOD_SECONDS) / BOUNCE_PERIOD_SECONDS  # [0, 1)
	var triangle := 1.0 - absf(2.0 * phase - 1.0)  # 0 -> 1 -> 0 across one period
	return MIN_FRACTION + triangle * (MAX_FRACTION - MIN_FRACTION)
