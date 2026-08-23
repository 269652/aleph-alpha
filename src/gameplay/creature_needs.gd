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


## How far into its own need cycle a freshly-created animal starts, at most.
## Deliberately below HUNGRY_THRESHOLD/THIRSTY_THRESHOLD so no animal spawns
## already starving, and high enough that a herd's onsets spread right across
## the run-up rather than bunching.
const START_STAGGER := 0.45


## `seed_value` staggers where this individual begins in its own cycle.
##
## Without it every creature started at exactly 0 and rose at exactly the same
## rate, so a whole herd crossed into hunger on the SAME tick -- they all
## switched to the eat action in one frame and all drew their eat frames at
## once (see ProceduralAnimalAnimation.LOOK_VARIANTS for the 1.18 seconds of
## generation that produced, and the frame spikes it was reported as). Real
## animals are not on one clock.
##
## Defaults to 0, so a caller that doesn't care -- every existing test --
## keeps the old exactly-empty start.
func _init(seed_value: int = 0) -> void:
	if seed_value == 0:
		return
	hunger = _stagger(seed_value, "hunger")
	thirst = _stagger(seed_value, "thirst")


## Hash-derived rather than RandomNumberGenerator, matching the deterministic
## "the same individual always rolls the same" idiom used throughout the
## world sim (TallGrass, FlowerPatch, TreeGenome).
func _stagger(seed_value: int, channel: String) -> float:
	var roll := float(absi(hash("%d_%s_need" % [seed_value, channel])) % 10000) / 10000.0
	return roll * START_STAGGER


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
