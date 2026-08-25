extends RefCounted

const SeasonCycle = preload("res://src/world/season_cycle.gd")

## The player's survival meters: hunger and thirst rise over time, stamina
## drains on exertion and regenerates, and fitness reflects overall condition,
## dropping under prolonged starvation/dehydration and recovering otherwise.
## Mirrors CreatureNeeds' API style (see creature_needs.gd) but scoped to the
## player and with two extra meters (stamina, fitness).

## How long going without takes to bottom a meter out.
##
## Measured in the WORLD'S OWN DAY (SeasonCycle.SECONDS_PER_DAY, four real
## hours), because that is the clock every other slow body-clock in this
## project already keeps -- a kingfisher's appetite (PiscivoreAppetite), a
## songbird's crop (BirdDigestion), fruit going over (FruitSpoilage). These
## were 0.004 and 0.006 per second: 250 and 167 real seconds, so the player
## starved about 58 times per in-game day, and about 346 times per sunrise
## (lighting runs on real UTC, see SolarPosition). The numbers were chosen
## against "how long before this nags a player" without checking what the
## calendar would allow, which is the same two-clocks mistake as the snowfall
## cover/thaw times and the gut-passage timer.
##
## A day of eating nothing empties you. Thirst runs on two thirds of that, so
## you go looking for water before you go looking for a meal -- the real order
## of the two, and the order the old constants already had. Bracketed from
## both sides by test_the_meters_are_measured_in_the_worlds_days_not_minutes
## and its neighbours; the old pin only ever guarded the fast side.
const SECONDS_TO_STARVE := SeasonCycle.SECONDS_PER_DAY
const SECONDS_TO_DEHYDRATE := SeasonCycle.SECONDS_PER_DAY * (2.0 / 3.0)
const HUNGER_RATE_PER_SECOND := 1.0 / SECONDS_TO_STARVE
const THIRST_RATE_PER_SECOND := 1.0 / SECONDS_TO_DEHYDRATE
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
