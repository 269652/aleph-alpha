extends RefCounted

## What eating a toxic mushroom actually DOES to a non-player eater (see
## docs/concept/mushrooms.md's "Toxic effects: disorientation and
## illness", docs/concept/soil_fauna.md's "Progressive, mass-scaled
## bites, and real toxic effects").
##
## Reported live, directly: "i just saw a bug eat a psylo and it didn't do
## anything to it." Before this, no non-player creature anywhere in this
## codebase consulted MushroomSpecies.is_toxic at all -- MushroomToxin/
## DebuffStack only ever ran against Player.
##
## Two genuinely different real effects, not one "bad status" reskinned by
## severity alone: real psilocybin/ibotenic-acid mushrooms
## (MushroomSpecies.is_psychoactive) cause genuine motor-coordination
## impairment/disorientation; Death Cap's real amatoxin poisoning is a
## categorically different hazard -- a progressive illness with no
## perceptual component, and (for a real mammal, not an insect -- see
## is_lethal_capable's own doc comment) a real, small chance of death.
##
## Pure and content-driven, no engine dependencies -- the same
## constants-plus-static-functions shape MushroomBiting/MushroomToxin
## already establish. CreatureMarker/DecomposerMarker each drive their own
## DebuffStack-tracked `active_mushroom_debuffs` array off these lookups,
## the identical pattern SpellStatusEffects already proved for
## `active_spell_debuffs` -- this module deliberately does NOT duplicate
## DebuffStack's own apply/advance/stacks_of state machine, it only
## decides what stacks of a given debuff_id actually mean.

const MushroomSpecies = preload("res://src/world/mushroom_species.gd")
const MushroomToxin = preload("res://src/gameplay/mushroom_toxin.gd")

const DISORIENTED_ID := "mushroom_disoriented"
const WEAKENED_ID := "mushroom_weakened"

## Same cap DebuffStack callers (VenomModel, SpellStatusEffects) already
## use -- a re-bite while already affected intensifies rather than
## stacking without bound.
const MAX_STACKS := 3

## Real psilocybin/ibotenic-acid intoxication measurably outlasts an
## instant-damage-tick debuff (MushroomToxin.DURATION_SECONDS, 8.0) --
## real disorientation from a psychoactive dose lingers for a real while,
## not an instant burst.
const DISORIENTED_DURATION_SECONDS := 45.0
## Real amatoxin poisoning is a progressive illness, not a quick knockdown
## -- a real, somewhat longer window than the disoriented effect's.
const WEAKENED_DURATION_SECONDS := 60.0

## Wobble magnitude at fly_agaric's own reference severity (MushroomToxin.
## severity_for("fly_agaric") == 1.0) -- a real, visible stagger (60
## degrees of heading swing) without reading as spinning in place.
const BASE_WOBBLE_RADIANS := PI / 3.0

## How often wobble_direction re-rolls a new erratic angle -- fast enough
## to read as stumbling/erratic, not a slow, steady drift.
const WOBBLE_CHANGE_INTERVAL_SECONDS := 0.5

## Movement-speed penalty at death_cap's own reference severity
## (MushroomToxin.severity_for("death_cap")) -- meaningfully slower
## without fully immobilizing (that's what `root`/`freeze` are for, see
## SpellStatusEffects), mirroring DiseaseModel.
## HERD_MOVEMENT_PENALTY_AT_FULL_SEVERITY's own real "makes you prey, not
## paralyzed" shape.
const WEAKENED_SPEED_PENALTY_AT_REFERENCE := 0.5

## Real, but deliberately small and uncommon -- pinned so the cumulative
## chance across one full WEAKENED_DURATION_SECONDS window at 1 stack
## lands around 5-15% (see test_cumulative_death_chance_over_one_full_
## weakened_window_is_a_real_but_uncommon_risk): a genuine, reachable
## hazard from eating Death Cap, not an accidental instant kill, and not
## so rare it can never matter -- the same "a real hazard, not a coin
## flip, but not certain either" design intent DiseaseModel's own
## predator/carrion death chances (0.05/0.09 per second) already
## establish, scaled down here since this is a single bite's dose, not a
## contracted, ongoing disease state.
const DEATH_CAP_DEATH_CHANCE_PER_SECOND := 0.0015


## Which real effect (if any) `species_id` causes -- "" for a non-toxic
## species (or an unrecognized id), matching this codebase's existing
## fallback convention.
static func effect_kind_for(species_id: String) -> String:
	if MushroomSpecies.is_psychoactive(species_id):
		return DISORIENTED_ID
	if MushroomSpecies.is_toxic(species_id):
		return WEAKENED_ID
	return ""


## Real seconds the effect `species_id` causes should last -- 0.0 for a
## non-toxic species.
static func duration_for(species_id: String) -> float:
	match effect_kind_for(species_id):
		DISORIENTED_ID:
			return DISORIENTED_DURATION_SECONDS
		WEAKENED_ID:
			return WEAKENED_DURATION_SECONDS
		_:
			return 0.0


## How far (radians, symmetric around the intended heading) a disoriented
## eater's movement direction wobbles -- 0.0 for a non-psychoactive
## species. Scales BASE_WOBBLE_RADIANS by MushroomToxin.severity_for,
## reusing the exact real ordering already pinned there (Fly Agaric's own
## ibotenic-acid/muscimol ataxia is genuinely more dramatic than
## Psilocybe's milder perceptual/motor effect) rather than inventing a
## second severity table.
static func wobble_radians_for(species_id: String) -> float:
	if effect_kind_for(species_id) != DISORIENTED_ID:
		return 0.0
	var reference := MushroomToxin.severity_for("fly_agaric")
	if reference <= 0.0:
		return 0.0
	return BASE_WOBBLE_RADIANS * (MushroomToxin.severity_for(species_id) / reference)


## `direction` rotated by a deterministic, erratic angle in
## [-wobble_radians, wobble_radians] -- pure and seed/time driven, so the
## SAME (direction, wobble_radians, seed_value) pair at the SAME
## `elapsed_time` interval always wobbles identically, but a genuinely
## different angle each WOBBLE_CHANGE_INTERVAL_SECONDS window (the
## "erratic", not "a fixed bias", the report's own "how they walk" asks
## for). Preserves `direction`'s own length (Vector2.rotated does not
## rescale) -- a wobble changes HEADING, not speed. A zero-length
## direction or zero wobble_radians passes through unchanged -- nothing
## sensible to rotate either way.
static func wobble_direction(direction: Vector2, wobble_radians: float, seed_value: int, elapsed_time: float) -> Vector2:
	if direction.length_squared() < 0.000001 or wobble_radians <= 0.0:
		return direction
	var interval_index := int(elapsed_time / WOBBLE_CHANGE_INTERVAL_SECONDS)
	var angle_fraction := float(hash("%d_%d_mushroom_wobble" % [seed_value, interval_index]) % 10000) / 10000.0
	var angle := lerpf(-wobble_radians, wobble_radians, angle_fraction)
	return direction.rotated(angle)


## Movement-speed multiplier while weakened -- 1.0 (no effect at all) for
## a species that doesn't cause the weakened effect. Scales
## WEAKENED_SPEED_PENALTY_AT_REFERENCE by MushroomToxin.severity_for
## relative to death_cap's own reference severity, clamped to [0, 1] so a
## hypothetical future weakened-shaped species milder than death_cap
## never derives a penalty bigger than the reference itself, and the
## result never goes negative.
static func weakened_speed_multiplier_for(species_id: String) -> float:
	if effect_kind_for(species_id) != WEAKENED_ID:
		return 1.0
	var reference := MushroomToxin.severity_for("death_cap")
	if reference <= 0.0:
		return 1.0
	var relative_severity := clampf(MushroomToxin.severity_for(species_id) / reference, 0.0, 1.0)
	return 1.0 - WEAKENED_SPEED_PENALTY_AT_REFERENCE * relative_severity


## Whether `species_id` can actually kill the eater -- true only for
## death_cap today. Deliberately consulted ONLY by CreatureMarker (a real
## mammal, e.g. a boar): real insects are documented as considerably more
## amatoxin-tolerant than mammals (famously, fungus gnat larvae develop
## IN death cap fruiting bodies largely unaffected), so DecomposerMarker
## (an ant/bug) applies the identical Weakened slowdown but never calls
## death_chance_per_second at all -- a deliberate, real-world-grounded
## asymmetry, not an oversight.
static func is_lethal_capable(species_id: String) -> bool:
	return species_id == "death_cap"


## Real per-second death chance while weakened by `species_id`, at
## `stacks` active stacks (capped at MAX_STACKS, same shape
## MushroomToxin.damage_per_second scales by stacks) -- 0.0 for anything
## not is_lethal_capable. See DEATH_CAP_DEATH_CHANCE_PER_SECOND's own doc
## comment for the real balance reasoning behind the base number.
static func death_chance_per_second(species_id: String, stacks: int = 1) -> float:
	if not is_lethal_capable(species_id):
		return 0.0
	return DEATH_CAP_DEATH_CHANCE_PER_SECOND * float(clampi(stacks, 0, MAX_STACKS))


## Deterministic hash-fraction roll against `chance` -- the identical
## pattern DiseaseModel.attempt_transmit/Sickness.attempt_infect already
## use, so the same (chance, seed_value) pair always yields the same
## result. A tiny, self-contained duplicate of that one-line roll rather
## than borrowing a disease-named helper for a non-disease event -- this
## module stays fully self-contained.
static func attempt_death(chance: float, seed_value: int) -> bool:
	var roll := float(absi(hash("%d_mushroom_death" % seed_value)) % 10000) / 10000.0
	return roll < chance
