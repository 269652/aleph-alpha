extends RefCounted

## Pure SIRS (Susceptible -> Infected -> Recovered -> Susceptible-again)
## wildlife disease model -- docs/concept/disease.md. Three real archetypes
## (HERD/PREDATOR/CARRION disease_id strings) share this one state-transition
## shape but carry their own transmission/severity/lethality constants, the
## same way HerbivorePopulationModel/PredatorPopulationModel share
## PopulationModel's core step logic while differing in their own tuned
## rates. Callers own the actual state (state: State, disease_id: String,
## severity: float, state_seconds: float) per creature/player -- this module
## holds nothing itself, the same "caller owns data, pure module owns rules"
## contract Sickness/Taming/DebuffStack already use.
##
## This is the WILDLIFE-side model, distinct from Sickness (survival.md's
## single-instance player illness). Player disease spillover (see
## docs/concept/disease.md "Player spillover") deliberately reuses Sickness
## for the player's own severity/diagnosis rather than this module -- this
## module only decides WHETHER an exposure happens and how a creature's own
## SIRS state evolves; Player.apply_disease_bite feeds the result into
## Sickness, it doesn't touch this state machine.

enum State { SUSCEPTIBLE, INFECTED, RECOVERED }

const HERD := "herd"  # foot-and-mouth-like
const PREDATOR := "predator"  # rabies-like
const CARRION := "carrion"  # anthrax-like

## Region pressure (docs/concept/disease.md "Region pressure"): keyed by
## RegionDifficulty.Tier's raw int values (0=EASY,1=MEDIUM,2=HARD, the same
## `difficulty_tier: int` convention CreatureRenderer already uses) rather
## than preloading RegionDifficulty here just for its enum -- one fewer
## cross-module dependency for a pure formula module, matching
## RegionDifficulty's own "distance-only, no cross-dependency" reasoning.
## HARD (far-out) regions run hotter disease pressure than EASY ones near
## spawn, mirroring real tropical/dense-biome disease burden.
const REGION_PRESSURE_MULTIPLIER := {
	0: 1.0,  # EASY
	1: 1.6,  # MEDIUM
	2: 2.4,  # HARD
}
const DEFAULT_REGION_PRESSURE := 1.0

## -- Herd (foot-and-mouth-like): mild, density-driven, never itself lethal --
## Real foot-and-mouth spreads through herds by direct contact/shared
## grazing ground and is rarely fatal by itself -- it makes the carrier
## easier prey instead (see movement_speed_multiplier).
const HERD_BASE_TRANSMISSION_CHANCE := 0.4
## How far past 1x carrying capacity density_ratio is allowed to climb --
## see herd_transmission_chance.
const DENSITY_RATIO_CAP := 3.0
const HERD_INFECTIOUS_DURATION := 40.0
const HERD_IMMUNITY_DURATION := 90.0
## How much top speed an infected herbivore loses at full (1.0) severity --
## the doc's actual "bite": "the disease doesn't kill you, it makes you
## prey" real epidemiology dynamic, not direct damage.
const HERD_MOVEMENT_PENALTY_AT_FULL_SEVERITY := 0.4

## -- Predator (rabies-like): rides the bite, severe, meaningfully lethal --
const PREDATOR_BASE_BITE_CHANCE := 0.5
const PREDATOR_INFECTIOUS_DURATION := 18.0
const PREDATOR_IMMUNITY_DURATION := 60.0
const PREDATOR_DEATH_CHANCE_PER_SECOND := 0.05

## -- Carrion (anthrax-like): environmental + insect-vector, genuinely
## population-crash-capable (real anthrax die-offs are not exaggeration) --
## Both pinned so that, combined with HARD's 2.4x region pressure, the
## worst-hit regions cross 1.0 and saturate at certain -- "in the most
## dangerous regions, an unburied carcass IS a real hazard, no dice roll
## about it" is a deliberate design choice, not an eyeballed number (see
## test_disease_model.gd's determinism tests, which rely on exactly this).
const CARRION_CONTAMINATION_CHANCE := 0.5
const CARRION_CARRY_CHANCE := 0.5
const CARRION_GRAZE_TRANSMISSION_CHANCE := 0.55
const CARRION_INFECTIOUS_DURATION := 14.0
const CARRION_IMMUNITY_DURATION := 60.0
const CARRION_DEATH_CHANCE_PER_SECOND := 0.09

## How much extra local graze risk a fly-blown carcass carries per adult fly
## already on it (see docs/concept/flies.md's Carcass.fly_count, docs/
## concept/carrion.md), on top of the base/region-scaled chance -- real
## blowflies/carrion beetles are anthrax's own documented carry mechanism
## (see the CARRION archetype's own doc comment above), so a carcass a
## swarm has already found is measurably MORE dangerous to graze near than
## an identically-rotten, fly-free one, not just as dangerous. Pinned large
## enough that even a single founder fly can saturate risk to certain on
## its own -- the same deliberate "saturate for determinism, most-dangerous
## case IS a real hazard, no dice roll about it" precedent
## CARRION_CONTAMINATION_CHANCE's own comment above already sets for HARD
## region pressure, extended here to a fly-blown carcass specifically. A
## first-pass number (see test_disease_model.gd), not a balance-tested one.
const FLY_BLOWN_GRAZE_RISK_BONUS_PER_FLY := 0.5

const INFECTIOUS_DURATION_BY_DISEASE := {
	HERD: HERD_INFECTIOUS_DURATION,
	PREDATOR: PREDATOR_INFECTIOUS_DURATION,
	CARRION: CARRION_INFECTIOUS_DURATION,
}
const IMMUNITY_DURATION_BY_DISEASE := {
	HERD: HERD_IMMUNITY_DURATION,
	PREDATOR: PREDATOR_IMMUNITY_DURATION,
	CARRION: CARRION_IMMUNITY_DURATION,
}
## Herd never kills directly (see design pillar above); predator/carrion do.
const DEATH_CHANCE_PER_SECOND_BY_DISEASE := {
	HERD: 0.0,
	PREDATOR: PREDATOR_DEATH_CHANCE_PER_SECOND,
	CARRION: CARRION_DEATH_CHANCE_PER_SECOND,
}


func region_pressure_multiplier(region_tier: int) -> float:
	return REGION_PRESSURE_MULTIPLIER.get(region_tier, DEFAULT_REGION_PRESSURE)


func is_lethal_capable(disease_id: String) -> bool:
	return death_chance_per_second(disease_id) > 0.0


func infectious_duration(disease_id: String) -> float:
	return INFECTIOUS_DURATION_BY_DISEASE.get(disease_id, HERD_INFECTIOUS_DURATION)


func immunity_duration(disease_id: String) -> float:
	return IMMUNITY_DURATION_BY_DISEASE.get(disease_id, HERD_IMMUNITY_DURATION)


## How fast visible symptom severity (0..1) climbs across the infectious
## window -- ramps from 0 to 1 exactly at infectious_duration, so a creature
## reads as "fully symptomatic" right as its infectious window ends.
func severity_rise_rate(disease_id: String) -> float:
	var duration := infectious_duration(disease_id)
	if duration <= 0.0:
		return 1.0
	return 1.0 / duration


func death_chance_per_second(disease_id: String) -> float:
	return DEATH_CHANCE_PER_SECOND_BY_DISEASE.get(disease_id, 0.0)


## Herd (foot-and-mouth-like) contact-transmission chance: density-weighted
## -- a crowded region (population close to or over its carrying capacity)
## is a measurable tinderbox, a sparse one mostly isn't (docs/concept/
## disease.md's "Density-dependent" pillar) -- then scaled by region
## pressure. Guards a zero/negative carrying_capacity (an unconfigured or
## momentarily-empty region) to 0.0 rather than dividing by zero.
func herd_transmission_chance(local_population: float, carrying_capacity: float, region_tier: int) -> float:
	if carrying_capacity <= 0.0:
		return 0.0
	# Not normalized/capped at exactly 1x capacity: a badly overcrowded
	# region (ratio well past 1) keeps raising real risk rather than reading
	# identically to "just at capacity" -- capped at DENSITY_RATIO_CAP only
	# so one pathological input can't send the multiplication wildly out of
	# proportion before the final [0,1] clamp does its job anyway.
	var density_ratio := clampf(local_population / carrying_capacity, 0.0, DENSITY_RATIO_CAP)
	var chance := HERD_BASE_TRANSMISSION_CHANCE * density_ratio * region_pressure_multiplier(region_tier)
	return clampf(chance, 0.0, 1.0)


## Predator (rabies-like) bite-transmission chance -- rolled the instant an
## infected predator's strike lands (docs/concept/disease.md: "transmission
## riding the existing attack-resolution path").
func predator_bite_transmission_chance(region_tier: int) -> float:
	return clampf(PREDATOR_BASE_BITE_CHANCE * region_pressure_multiplier(region_tier), 0.0, 1.0)


## A rotten, unburied carcass's chance to be contaminated (docs/concept/
## disease.md's anthrax-like archetype) -- rolled once, the instant it first
## crosses Carcass.is_rotten().
func carcass_contamination_chance(region_tier: int) -> float:
	return clampf(CARRION_CONTAMINATION_CHANCE * region_pressure_multiplier(region_tier), 0.0, 1.0)


## A decomposer feeding on a contaminated carcass's chance to carry spores
## onward to the next carcass it feeds on (docs/concept/disease.md: real
## blowflies/carrion beetles mechanically carrying anthrax spores).
func decomposer_carry_chance(region_tier: int) -> float:
	return clampf(CARRION_CARRY_CHANCE * region_pressure_multiplier(region_tier), 0.0, 1.0)


## A herbivore grazing near a contaminated carcass's chance to be exposed.
## `fly_count` is how many adult flies (see Carcass.fly_count) are currently
## on that carcass -- a fly-blown carcass is a measurably bigger local
## hazard than a fly-free one, not just as big (see
## FLY_BLOWN_GRAZE_RISK_BONUS_PER_FLY). Defaults to 0 so every existing
## caller that has no fly count to offer keeps its exact prior behaviour.
func carrion_graze_transmission_chance(region_tier: int, fly_count: int = 0) -> float:
	var base := CARRION_GRAZE_TRANSMISSION_CHANCE * region_pressure_multiplier(region_tier)
	var fly_bonus := float(maxi(fly_count, 0)) * FLY_BLOWN_GRAZE_RISK_BONUS_PER_FLY
	return clampf(base + fly_bonus, 0.0, 1.0)


## Deterministic hash-fraction roll against `chance`, given a seed -- same
## pattern as Sickness.attempt_infect/CreatureMarker._step_restraint's
## struggle roll, so every caller's (chance, seed_value) pair always yields
## the same result.
func attempt_transmit(chance: float, seed_value: int) -> bool:
	var roll := float(absi(hash("%d_disease_transmit" % seed_value)) % 10000) / 10000.0
	return roll < chance


## Rolls whether a SUSCEPTIBLE individual becomes INFECTED given `chance`
## (from one of the transmission-chance functions above). Separate name from
## attempt_transmit so call sites read as "is this exposure an infection"
## rather than a generic roll, even though the underlying dice are shared.
func attempt_infect(chance: float, seed_value: int) -> bool:
	return attempt_transmit(chance, seed_value)


## How much of an infected herbivore's top speed is lost at its current
## severity -- real foot-and-mouth's actual bite is secondary (see the HERD
## constants above): a weakened animal is measurably easier prey, not
## directly damaged.
func movement_speed_multiplier(severity: float) -> float:
	return 1.0 - clampf(severity, 0.0, 1.0) * HERD_MOVEMENT_PENALTY_AT_FULL_SEVERITY


## Advances one tick of the full SIRS state machine for a single
## creature/player and one disease. Returns a NEW {"state", "severity",
## "state_seconds", "died"} rather than mutating -- same "caller owns state,
## every method returns fresh data" contract DebuffStack already uses.
##
## SUSCEPTIBLE just accumulates state_seconds (not meaningful by itself, but
## keeps the return shape uniform across all three states -- becoming
## INFECTED is attempt_infect's job, not this function's, the same way
## DebuffStack.apply/advance are separate calls).
## INFECTED ramps severity per severity_rise_rate, rolls a death chance each
## tick for lethal-capable diseases, and -- if it survives its full
## infectious_duration -- moves to RECOVERED.
## RECOVERED counts down its own immunity_duration and then drops back to
## SUSCEPTIBLE (immunity waning -- the extra "S" a plain SIR model lacks,
## the design pillar's "Recovered(-immune) -> Susceptible again").
func advance_state(
	state: int, disease_id: String, severity: float, state_seconds: float, delta: float, seed_value: int
) -> Dictionary:
	match state:
		State.INFECTED:
			var new_seconds: float = state_seconds + delta
			var new_severity: float = clampf(severity + severity_rise_rate(disease_id) * delta, 0.0, 1.0)
			if is_lethal_capable(disease_id):
				var death_chance: float = death_chance_per_second(disease_id) * delta
				if attempt_transmit(death_chance, seed_value):
					return {
						"state": State.INFECTED,
						"severity": new_severity,
						"state_seconds": new_seconds,
						"died": true,
					}
			if new_seconds >= infectious_duration(disease_id):
				return {"state": State.RECOVERED, "severity": 0.0, "state_seconds": 0.0, "died": false}
			return {
				"state": State.INFECTED, "severity": new_severity, "state_seconds": new_seconds, "died": false
			}
		State.RECOVERED:
			var recovered_seconds: float = state_seconds + delta
			if recovered_seconds >= immunity_duration(disease_id):
				return {"state": State.SUSCEPTIBLE, "severity": 0.0, "state_seconds": 0.0, "died": false}
			return {
				"state": State.RECOVERED, "severity": 0.0, "state_seconds": recovered_seconds, "died": false
			}
		_:
			return {
				"state": State.SUSCEPTIBLE,
				"severity": 0.0,
				"state_seconds": state_seconds + delta,
				"died": false,
			}
