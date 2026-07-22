extends RefCounted

## Pure sickness/diagnosis model (docs/concept/survival.md "Sickness &
## medicine"). Deliberately scoped to a single sickness instance's rules --
## the doc's "contagion between players" idea is explicitly flagged as an
## undecided open question there, so it stays out of scope here.
##
## Like TamingSystem/FishingMinigame, this holds no mutable state itself:
## callers own the actual sickness data (severity: float, a fixed
## sickness_id, and a diagnosed bool) elsewhere and pass severity through
## each call. Per "Sickness Diagnosis", an undiagnosed sickness should only
## expose its vague severity to the caller -- the specific sickness_id is
## meant to be revealed only once diagnose() below returns true.

## infection_chance() weights: exposure_level raises the chance, resistance
## lowers it, by equal-magnitude additive terms so either input alone
## visibly moves the result; base chance is 0 so an unexposed target has no
## risk at all.
const INFECTION_EXPOSURE_WEIGHT := 0.8
const INFECTION_RESISTANCE_WEIGHT := 0.8

## progress() rates: severity worsens by PROGRESS_RATE per second while
## untreated, or recovers at TREATED_RECOVERY_MULTIPLIER times that rate
## per second while being_treated -- treatment always outpaces the
## sickness so committing to a cure is worthwhile.
const PROGRESS_RATE := 0.05
const TREATED_RECOVERY_MULTIPLIER := 2.0

## diagnose() weights: a base chance plus additive contributions from
## diagnosis_skill and severity -- a more severe/obvious case is easier to
## read, same reasoning TamingSystem.taming_chance() uses for its factors.
const DIAGNOSE_BASE_CHANCE := 0.1
const DIAGNOSE_SKILL_WEIGHT := 0.6
const DIAGNOSE_SEVERITY_WEIGHT := 0.3


## 0..1 chance of infection: rises with exposure_level, falls with
## resistance, both clamped to [0,1] first so extreme inputs can't push
## contributions out of range before the final clamp.
func infection_chance(exposure_level: float, resistance: float) -> float:
	var exposure := clampf(exposure_level, 0.0, 1.0)
	var guard := clampf(resistance, 0.0, 1.0)
	var chance := exposure * INFECTION_EXPOSURE_WEIGHT - guard * INFECTION_RESISTANCE_WEIGHT
	return clampf(chance, 0.0, 1.0)


## Deterministic hash-fraction roll against `chance`, given a seed -- same
## pattern as TamingSystem.attempt_tame, so the same (chance, seed_value)
## always yields the same result and infection rolls stay reproducible.
func attempt_infect(chance: float, seed_value: int) -> bool:
	var roll := float(absi(hash("%d_sickness_infect" % seed_value)) % 10000) / 10000.0
	return roll < chance


## New severity after delta seconds: worsens toward 1 while untreated, or
## recovers toward 0 (faster) while being_treated. Clamped to [0, 1].
func progress(severity: float, delta: float, being_treated: bool) -> float:
	var change := PROGRESS_RATE * delta
	if being_treated:
		change *= -TREATED_RECOVERY_MULTIPLIER
	return clampf(severity + change, 0.0, 1.0)


func is_recovered(severity: float) -> bool:
	return severity <= 0.0


## Diagnosis succeeds with a chance that rises with diagnosis_skill and
## with severity (a more severe case is more obvious to identify). Seeded
## the same way as attempt_infect -- a diagnosis attempt needs to replay
## identically for save/load and for deterministic tests, rather than
## depending on wall-clock RNG state.
func diagnose(severity: float, diagnosis_skill: float, seed_value: int) -> bool:
	var skill := clampf(diagnosis_skill, 0.0, 1.0)
	var obviousness := clampf(severity, 0.0, 1.0)
	var chance := clampf(DIAGNOSE_BASE_CHANCE + skill * DIAGNOSE_SKILL_WEIGHT + obviousness * DIAGNOSE_SEVERITY_WEIGHT, 0.0, 1.0)
	var roll := float(absi(hash("%d_sickness_diagnose" % seed_value)) % 10000) / 10000.0
	return roll < chance
