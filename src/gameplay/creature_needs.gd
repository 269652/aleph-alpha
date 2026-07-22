extends RefCounted

## A creature's survival needs: hunger and thirst that rise over time and
## reset when the creature eats/drinks. Drives food/water-seeking behavior
## (see CreatureBehavior). Kept as a plain data+logic object, no engine
## dependency, so it's fully unit-testable.

## Per-simulated-second rise rate. Chosen so a creature crosses its need
## thresholds within a reasonable stretch of play, and verified behaviorally
## (test_becomes_hungry_once_past_the_threshold), not by asserting the number.
const HUNGER_RATE_PER_SECOND := 0.02
const THIRST_RATE_PER_SECOND := 0.03

## A creature actively seeks food/water once its need passes these fractions.
const HUNGRY_THRESHOLD := 0.5
const THIRSTY_THRESHOLD := 0.5

var hunger := 0.0
var thirst := 0.0


func advance(delta_seconds: float) -> void:
	hunger = clampf(hunger + HUNGER_RATE_PER_SECOND * delta_seconds, 0.0, 1.0)
	thirst = clampf(thirst + THIRST_RATE_PER_SECOND * delta_seconds, 0.0, 1.0)


func is_hungry() -> bool:
	return hunger >= HUNGRY_THRESHOLD


func is_thirsty() -> bool:
	return thirst >= THIRSTY_THRESHOLD


func feed() -> void:
	hunger = 0.0


func drink() -> void:
	thirst = 0.0
