extends RefCounted

## Condition-gated animal reproduction (bioenergetics).
##
## Each creature carries an energy/condition value on a 0..1 unit scale that
## rises when it eats (feed), decays slowly over time via basal metabolism
## (decay), and gates reproduction: a creature reproduces only when it is both
## well-fed (energy above a threshold) and healthy (health fraction above a
## threshold), and then only after a refractory cooldown (inter-birth interval).
## Birth pays an energy cost large enough that even a maxed-out creature drops
## below the reproduction threshold, so it cannot immediately re-fire.
##
## Pure, stateless helpers operating on passed-in values so they stay fully
## unit-testable, matching the style of creature_needs.gd (no engine deps).

## Energy is a normalized body-condition fraction in [0, 1].
const MAX_ENERGY := 1.0

## Basal metabolic decline per simulated second. Slow relative to feeding.
const DECAY_RATE_PER_SECOND := 0.01

## Reproduction gates.
const REPRO_ENERGY_THRESHOLD := 0.6
const REPRO_HEALTH_THRESHOLD := 0.7
## A full real-world day between births for one animal (requested directly:
## "reproduction should take at least 1 real day (24h)"). It was 30 SECONDS,
## which only ever looked survivable because the ecology simulation was never
## actually running (see World.owns_ecosystem_simulation_for); the moment it
## did, well-fed animals bred every half-minute and a clearing filled with
## deer. Breeding is meant to be a slow background change to a region's
## makeup that a returning player notices, not something they watch happen.
const REPRO_COOLDOWN := 24.0 * 60.0 * 60.0

## Energy paid per birth. Must exceed MAX_ENERGY - REPRO_ENERGY_THRESHOLD so
## that energy_after_birth(MAX_ENERGY) lands strictly below the threshold,
## guaranteeing the gate cannot immediately re-fire after a birth.
const BIRTH_ENERGY_COST := 0.45


static func decay(energy: float, delta: float) -> float:
	return clampf(energy - DECAY_RATE_PER_SECOND * delta, 0.0, MAX_ENERGY)


static func feed(energy: float, amount: float) -> float:
	return clampf(energy + amount, 0.0, MAX_ENERGY)


static func can_reproduce(
		energy: float,
		health_fraction: float,
		seconds_since_last_birth: float) -> bool:
	return energy >= REPRO_ENERGY_THRESHOLD \
		and health_fraction >= REPRO_HEALTH_THRESHOLD \
		and seconds_since_last_birth >= REPRO_COOLDOWN


static func birth_energy_cost() -> float:
	return BIRTH_ENERGY_COST


static func energy_after_birth(energy: float) -> float:
	return clampf(energy - BIRTH_ENERGY_COST, 0.0, MAX_ENERGY)
