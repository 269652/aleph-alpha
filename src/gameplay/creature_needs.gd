extends RefCounted

## A creature's survival needs: hunger and thirst that rise over time and
## reset when the creature eats/drinks, and body warmth. Drives food/water-
## seeking behavior (see CreatureBehavior). Kept as a plain data+logic object,
## no engine dependency, so it's fully unit-testable.
##
## Since docs/concept/ethogram.md slice 3 this is a FACADE: hunger and thirst
## run on the one drive clock every animal shares (Drives) with the land
## mammal's profile from the ethogram (Ethogram.drive_profile("", "mammal")
## -- the same 0.02/s and 0.03/s, the same half-way threshold, the same
## staggered start this file always had, now species data rather than
## constants here). The API is unchanged for CreatureMarker and every test;
## the numbers below are re-exported from the profile for callers that read
## them. Warmth stays here: it is the player's own body-temperature model
## (SurvivalMeters), not a drive.

const SurvivalMeters = preload("res://src/gameplay/survival_meters.gd")
const Drives = preload("res://src/gameplay/drives.gd")
const Ethogram = preload("res://src/gameplay/ethogram.gd")

const BODY_PLAN := "mammal"

## The ethogram's mammal profile, re-exported. Per-simulated-second rise
## rates chosen so a creature crosses its need thresholds within a reasonable
## stretch of play, and verified behaviorally
## (test_becomes_hungry_once_past_the_threshold), not by asserting the number.
static var HUNGER_RATE_PER_SECOND: float = (
	1.0 / float(Ethogram.drive_profile("", BODY_PLAN)[Ethogram.DRIVE_HUNGER]["rise_seconds"])
)
static var THIRST_RATE_PER_SECOND: float = (
	1.0 / float(Ethogram.drive_profile("", BODY_PLAN)[Ethogram.DRIVE_THIRST]["rise_seconds"])
)

## A creature actively seeks food/water once its need passes these fractions.
static var HUNGRY_THRESHOLD: float = float(
	Ethogram.drive_profile("", BODY_PLAN)[Ethogram.DRIVE_HUNGER]["threshold"]
)
static var THIRSTY_THRESHOLD: float = float(
	Ethogram.drive_profile("", BODY_PLAN)[Ethogram.DRIVE_THIRST]["threshold"]
)

## How far into its own need cycle a freshly-created animal starts, at most.
## Deliberately below HUNGRY_THRESHOLD/THIRSTY_THRESHOLD so no animal spawns
## already starving, and high enough that a herd's onsets spread right across
## the run-up rather than bunching (see Drives' `stagger`).
static var START_STAGGER: float = float(
	Ethogram.drive_profile("", BODY_PLAN)[Ethogram.DRIVE_HUNGER]["stagger"]
)

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

var _drives: Drives

var hunger: float:
	get:
		return _drives.level(Ethogram.DRIVE_HUNGER)
	set(value):
		_drives.levels[Ethogram.DRIVE_HUNGER] = clampf(value, 0.0, 1.0)

var thirst: float:
	get:
		return _drives.level(Ethogram.DRIVE_THIRST)
	set(value):
		_drives.levels[Ethogram.DRIVE_THIRST] = clampf(value, 0.0, 1.0)


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
	_drives = Drives.new(Ethogram.drive_profile("", BODY_PLAN), seed_value)


func advance(delta_seconds: float) -> void:
	_drives.advance(delta_seconds)


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
	return _drives.is_urgent(Ethogram.DRIVE_HUNGER)


func is_thirsty() -> bool:
	return _drives.is_urgent(Ethogram.DRIVE_THIRST)


func feed() -> void:
	_drives.satisfy(Ethogram.DRIVE_HUNGER)


func drink() -> void:
	_drives.satisfy(Ethogram.DRIVE_THIRST)


## The needs as the behaviour kernel's gates (Drives.gains): what
## CreatureMarker hands CreatureBehavior as `drives`.
func gains() -> Dictionary:
	return _drives.gains()
