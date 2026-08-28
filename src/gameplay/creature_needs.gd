extends RefCounted

## A creature's survival needs: hunger and thirst that rise over time and
## reset when the creature eats/drinks. Drives food/water-seeking behavior
## (see CreatureBehavior). Kept as a plain data+logic object, no engine
## dependency, so it's fully unit-testable.

const SurvivalMeters = preload("res://src/gameplay/survival_meters.gd")

## Per-simulated-second rise rate. Chosen so a creature crosses its need
## thresholds within a reasonable stretch of play, and verified behaviorally
## (test_becomes_hungry_once_past_the_threshold), not by asserting the number.
const HUNGER_RATE_PER_SECOND := 0.02
const THIRST_RATE_PER_SECOND := 0.03

## A creature actively seeks food/water once its need passes these fractions.
const HUNGRY_THRESHOLD := 0.5
const THIRSTY_THRESHOLD := 0.5

## Body warmth, 1.0 comfortable to 0.0 freezing -- the animal half of the
## body-temperature model the PLAYER already had (SurvivalMeters.warmth).
##
## Deliberately the same model and the same numbers rather than a parallel one:
## warmth eases toward a local ambient target instead of snapping, the rate and
## the "cold" threshold are SurvivalMeters' own, and the ambient figure comes
## from the same EarthChunkManager.ambient_warmth the player's meter reads. An
## animal and the person standing next to it in the same storm should not
## disagree about how cold it is there.
##
## Not modelled, and named rather than silently missing: a per-species cold
## tolerance. A camel and a reindeer plainly should not chill at the same rate,
## but nothing in the roster carries a coat or a climate today, and inventing
## one number per species would be exactly the eyeballed table this project
## refuses to write. Species divergence belongs to the genome
## (concept/animal_genetics.md's hardiness gene), not to a hand-typed column.
var warmth := 1.0

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


## Moves body warmth toward the local ambient, the same easing
## SurvivalMeters.regulate_temperature uses. `ambient_warmth` is "how warm is it
## here" in [0,1] -- climate x season x weather, from
## EarthChunkManager.ambient_warmth.
##
## No wetness term, unlike the player's: nothing tracks how wet an ANIMAL is
## (WetnessTracker is the player's own), so adding one here would be inventing
## a value rather than reading one.
func regulate_temperature(ambient_warmth: float, delta_seconds: float) -> void:
	warmth = move_toward(
		warmth,
		clampf(ambient_warmth, 0.0, 1.0),
		SurvivalMeters.WARMTH_RATE_PER_SECOND * delta_seconds
	)


func is_cold() -> bool:
	return warmth <= SurvivalMeters.COLD_THRESHOLD


func is_hungry() -> bool:
	return hunger >= HUNGRY_THRESHOLD


func is_thirsty() -> bool:
	return thirst >= THIRSTY_THRESHOLD


func feed() -> void:
	hunger = 0.0


func drink() -> void:
	thirst = 0.0
