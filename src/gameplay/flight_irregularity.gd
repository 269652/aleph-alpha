extends RefCounted

## The one place this game says "a butterfly's path never repeats the same arc
## twice".
##
## ## Why a butterfly's flight is irregular, and why that is not decoration
##
## Erratic, unpredictable flight is a genuine anti-predator adaptation --
## "protean" behaviour: a flight path a bird cannot extrapolate is a flight
## path a bird cannot intercept. It is a large part of why butterflies fly the
## way they do rather than an aesthetic quirk, and it applies to everything
## they do in the air, not only to crossing a meadow. Real spiral flights and
## courtship flights are chaotic ascending chases -- irregular, jagged, and
## never a clean ellipse. Reported as: the interactions are "overly dramatic
## and only a circle".
##
## ## Why this module exists at all
##
## The irregularity was ALREADY in the game, in
## PollinatorForaging.tumbled_heading: two incommensurable frequencies with a
## per-individual phase, deliberately not one sine, "because a single sine
## reads as a regular slalom, where a butterfly's path never repeats the same
## arc twice". Giving the dances a second, slightly different wobble would be
## the same statement made twice, with two sets of numbers to keep in step --
## the duplicate-waiting-to-drift this codebase has been bitten by before. So
## the spectrum lives here, once, and the flutter reads it back out
## (PollinatorForaging.TUMBLE_FREQUENCY is defined as this module's own).
##
## ## Why there is an INTEGRAL as well as the wobble
##
## A flyer holding a constant airspeed on an orbit whose radius varies turns
## at w = v/r -- the tighter it is, the faster it comes round. The ANGLE it
## has swept is therefore the integral of that rate, and getting it by
## accumulating per frame would make the shape depend on frame rate and on
## SimulationLod's step size, which is exactly the class of bug this system
## has produced before. This wobble is a sum of sines, so its integral is
## closed-form: callers get an exact swept angle from a pure function of time.
##
## Pure and engine-free like the rest of the behaviour modules.

## The fast component, in radians per second.
##
## Carried over unchanged from the flutter this module was factored out of --
## it is the same statement about the same animal, and PollinatorForaging.
## TUMBLE_FREQUENCY now reads it from here rather than holding its own copy.
## About one veer per second at the fast end, which is what a butterfly
## crossing a meadow visibly does.
const FAST_RADIANS_PER_SECOND := 6.5

## The slow component, as a fraction of the fast one.
##
## IRRATIONAL-ish on purpose: 0.37 shares no small common factor with 1, so
## the sum never closes back onto itself and the path genuinely never repeats.
## A round fraction (a half, a third) would give a repeating figure, which is
## the "only a circle" complaint one level down.
const SLOW_FREQUENCY_RATIO := 0.37

## How much of the swing the slow component carries. Half, so the fast veer
## still dominates and the slow one re-shapes it rather than replacing it.
const SLOW_WEIGHT := 0.5

## What the two components sum to at worst, so `wobble` comes back normalised
## to +/-1 and every caller can scale it by something with real units.
const NORMALISER := 1.0 + SLOW_WEIGHT


func _init() -> void:
	pass


## This individual's phase, in radians. Hash-derived like the rest of the
## world's per-individual variation rather than held as RNG state, so a given
## flyer is deterministic and reproducible while two flyers in one meadow
## disagree.
static func phase(seed_value: int) -> float:
	return float(absi(hash(seed_value)) % 628) * 0.01


## A normalised, non-repeating swing in [-1, 1] for this individual at
## `elapsed_seconds`.
static func wobble(elapsed_seconds: float, seed_value: int) -> float:
	var own := phase(seed_value)
	return (
		sin(elapsed_seconds * FAST_RADIANS_PER_SECOND + own)
		+ SLOW_WEIGHT * sin(
			elapsed_seconds * FAST_RADIANS_PER_SECOND * SLOW_FREQUENCY_RATIO + own * 2.1
		)
	) / NORMALISER


## The fastest `wobble` can change, in units per second.
##
## Exact rather than sampled: the wobble is a sum of two sinusoids, so its
## derivative is a sum of two cosines and the largest that can be is the sum of
## their amplitudes -- reached only where both cosines peak together, which the
## irrational-ish frequency ratio makes rare but not impossible.
##
## Exists because a caller that scales the wobble by a real distance is
## implicitly choosing a SPEED, and until something says what that speed is
## nobody can check it against the animal's own (see
## NectaringPosture.shuffle_offset, where an unchecked one had a feeding
## butterfly moving faster than a flying one).
static func max_rate() -> float:
	return (
		FAST_RADIANS_PER_SECOND * (1.0 + SLOW_WEIGHT * SLOW_FREQUENCY_RATIO) / NORMALISER
	)


## The exact integral of `wobble` from 0 to `elapsed_seconds`.
##
## Zero at t = 0 by construction (the constant of integration is chosen to
## make it so), which is what lets a caller add it to a starting angle without
## anything jumping the instant an orbit begins.
static func wobble_integral(elapsed_seconds: float, seed_value: int) -> float:
	var own := phase(seed_value)
	var fast := FAST_RADIANS_PER_SECOND
	var slow := FAST_RADIANS_PER_SECOND * SLOW_FREQUENCY_RATIO
	# integral of sin(w t + p) dt = (cos(p) - cos(w t + p)) / w
	var fast_part := (cos(own) - cos(elapsed_seconds * fast + own)) / fast
	var slow_part := (
		SLOW_WEIGHT * (cos(own * 2.1) - cos(elapsed_seconds * slow + own * 2.1)) / slow
	)
	return (fast_part + slow_part) / NORMALISER
