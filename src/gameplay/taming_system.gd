extends RefCounted

## Pure taming-probability model (concept/pets.md "Taming System"). Combines
## three factors into a single 0..1 chance:
## - temperament: calm creatures start from a higher base chance than
##   aggressive ones (wary/unknown temperaments sit between the two).
## - health_fraction: a weakened creature is easier to tame ("wear it down
##   first"), so chance rises as health_fraction falls.
## - food_quality: better bait/food offered raises the chance.
## Formula: base(temperament) + (1 - health_fraction) * 0.3 + food_quality * 0.3,
## clamped to [0, 1]. All three terms are additive so each visibly moves the
## result independent of the others.

const _TEMPERAMENT_BASE := {
	"calm": 0.6,
	"aggressive": 0.2,
}
const _DEFAULT_TEMPERAMENT_BASE := 0.4


func taming_chance(temperament: String, health_fraction: float, food_quality: float) -> float:
	var base: float = _TEMPERAMENT_BASE.get(temperament, _DEFAULT_TEMPERAMENT_BASE)
	var weakness_bonus: float = (1.0 - clampf(health_fraction, 0.0, 1.0)) * 0.3
	var food_bonus: float = clampf(food_quality, 0.0, 1.0) * 0.3
	return clampf(base + weakness_bonus + food_bonus, 0.0, 1.0)


## Deterministic hash-fraction roll against `chance`, given a seed. Same
## (chance, seed_value) always yields the same result.
func attempt_tame(chance: float, seed_value: int) -> bool:
	var roll := float(absi(hash("%d_taming_attempt" % seed_value)) % 10000) / 10000.0
	return roll < chance
