extends RefCounted

## The player's survival meters: hunger and thirst rise over time, stamina
## drains on exertion and regenerates, and fitness reflects overall condition,
## dropping under prolonged starvation/dehydration and recovering otherwise.
## Mirrors CreatureNeeds' API style (see creature_needs.gd) but scoped to the
## player and with two extra meters (stamina, fitness).

## Hunger/thirst drain slowly enough that a short excursion never starves you
## (pinned by test_meters_drain_slowly_enough_for_a_short_excursion): thirst is
## a touch faster than hunger, and both take minutes, not seconds, to matter.
const HUNGER_RATE_PER_SECOND := 0.004
const THIRST_RATE_PER_SECOND := 0.006
const STAMINA_REGEN_PER_SECOND := 0.05
const FITNESS_DROP_PER_SECOND := 0.01
const FITNESS_RECOVER_PER_SECOND := 0.01

## The player actively suffers/seeks relief once a need passes these fractions.
const HUNGRY_THRESHOLD := 0.5
const THIRSTY_THRESHOLD := 0.5
const EXHAUSTED_THRESHOLD := 0.2
const STARVING_THRESHOLD := 0.85
const DEHYDRATED_THRESHOLD := 0.85

## Body temperature (1.0 = comfortable, 0.0 = freezing). Drifts toward the
## ambient target each regulate_temperature call (see concept/survival.md's
## "Body temperature & weather exposure").
const WARMTH_RATE_PER_SECOND := 0.05
## How much full wetness (soaked) pulls the ambient warmth target down --
## evaporative/conductive heat loss.
const WETNESS_CHILL := 0.5
## Below COLD the player is "cold" (accelerated fitness loss); below FREEZING
## also suffers a movement slow (applied by the caller).
const COLD_THRESHOLD := 0.4
const FREEZING_THRESHOLD := 0.15

var hunger := 0.0
var thirst := 0.0
var stamina := 1.0
var fitness := 1.0
var warmth := 1.0


func advance(delta_seconds: float) -> void:
	hunger = clampf(hunger + HUNGER_RATE_PER_SECOND * delta_seconds, 0.0, 1.0)
	thirst = clampf(thirst + THIRST_RATE_PER_SECOND * delta_seconds, 0.0, 1.0)
	stamina = clampf(stamina + STAMINA_REGEN_PER_SECOND * delta_seconds, 0.0, 1.0)
	if is_starving() or is_dehydrated() or is_cold():
		fitness = clampf(fitness - FITNESS_DROP_PER_SECOND * delta_seconds, 0.0, 1.0)
	else:
		fitness = clampf(fitness + FITNESS_RECOVER_PER_SECOND * delta_seconds, 0.0, 1.0)


## Moves body warmth toward the ambient target. `ambient_warmth` is the local
## "how warm is it here" in [0,1] (climate x season x weather); high `wetness`
## chills the target further. Warmth eases toward the target rather than
## snapping, so stepping inside/into the sun warms you up gradually.
func regulate_temperature(ambient_warmth: float, wetness: float, delta_seconds: float) -> void:
	var target := clampf(ambient_warmth - WETNESS_CHILL * clampf(wetness, 0.0, 1.0), 0.0, 1.0)
	warmth = move_toward(warmth, target, WARMTH_RATE_PER_SECOND * delta_seconds)


func is_cold() -> bool:
	return warmth <= COLD_THRESHOLD


func is_freezing() -> bool:
	return warmth <= FREEZING_THRESHOLD


func eat(amount: float) -> void:
	hunger = clampf(hunger - amount, 0.0, 1.0)


func drink(amount: float) -> void:
	thirst = clampf(thirst - amount, 0.0, 1.0)


func rest(amount: float) -> void:
	stamina = clampf(stamina + amount, 0.0, 1.0)


func spend_stamina(amount: float) -> void:
	stamina = clampf(stamina - amount, 0.0, 1.0)


func is_hungry() -> bool:
	return hunger >= HUNGRY_THRESHOLD


func is_thirsty() -> bool:
	return thirst >= THIRSTY_THRESHOLD


func is_exhausted() -> bool:
	return stamina <= EXHAUSTED_THRESHOLD


func is_starving() -> bool:
	return hunger >= STARVING_THRESHOLD


func is_dehydrated() -> bool:
	return thirst >= DEHYDRATED_THRESHOLD
