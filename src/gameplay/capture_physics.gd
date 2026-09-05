extends RefCounted

## docs/concept/capture_dsl.md: derives a capture attempt's real success
## chance from a device's own tuned base rate plus real target biology --
## never authored directly per attempt, the same "derive, don't hand-tune
## per situation" discipline spell_cost.gd holds itself to for spell price.
##
## Pure and engine-free, like the rest of the DSL's logic modules: no RNG
## held here. The actual roll is the caller's job (see capture_executor.gd's
## own doc comment on why), this only turns a base rate + an individual's
## boldness into the legal probability that roll is checked against.

const FlyerPersonality = preload("res://src/gameplay/flyer_personality.gd")

## How much a target's boldness shifts the odds either way. Tuned and
## pinned by test (CLAUDE.md: never an eyeballed number), not per-device:
## at FlyerPersonality.MIDDLING_BOLDNESS (the "unremarkable middle" a
## personality-less target -- a hand-placed fixture, an older save -- is
## already taken to be everywhere else boldness is read) a target gets
## exactly the device's own `base` chance; the boldest real individual gets
## base + BOLDNESS_WEIGHT/2, the shyest gets base - BOLDNESS_WEIGHT/2.
const BOLDNESS_WEIGHT := 0.3


## A capture attempt's real odds, clamped to a legal probability.
func catch_chance(base: float, boldness: float = FlyerPersonality.MIDDLING_BOLDNESS) -> float:
	var shift := (boldness - FlyerPersonality.MIDDLING_BOLDNESS) * BOLDNESS_WEIGHT
	return clampf(base + shift, 0.0, 1.0)
