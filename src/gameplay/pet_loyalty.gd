extends RefCounted

## Pure pet loyalty/bonding model (docs/concept/pets.md "Bonding/Loyalty
## Mechanic"). loyalty is a [0,1] scale the caller stores per-pet; feed()
## and neglect() are pure functions that return the new value rather than
## mutating anything. Guarding requires a stricter (higher) loyalty than
## merely following -- a loyal-but-not-devoted pet won't fight for you.

const BASELINE_LOYALTY := 0.5
const FOLLOW_THRESHOLD := 0.4
const GUARD_THRESHOLD := 0.75

const _FEED_RATE := 0.3
const _NEGLECT_DECAY_RATE := 0.02


## Returns loyalty increased by an amount proportional to food_quality
## (0..1), clamped at 1.0.
func feed(loyalty: float, food_quality: float) -> float:
	var gain: float = clampf(food_quality, 0.0, 1.0) * _FEED_RATE
	return clampf(loyalty + gain, 0.0, 1.0)


## Returns loyalty decreased by a slow constant decay rate times delta,
## clamped at 0.0.
func neglect(loyalty: float, delta: float) -> float:
	var loss: float = delta * _NEGLECT_DECAY_RATE
	return clampf(loyalty - loss, 0.0, 1.0)


func will_follow(loyalty: float) -> bool:
	return loyalty >= FOLLOW_THRESHOLD


func will_guard(loyalty: float) -> bool:
	return loyalty >= GUARD_THRESHOLD
