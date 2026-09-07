extends GutTest

## MushroomEffect (see docs/concept/mushrooms.md's "Toxic effects:
## disorientation and illness", docs/concept/soil_fauna.md's "Progressive,
## mass-scaled bites, and real toxic effects").
##
## Reported live, directly: "i just saw a bug eat a psylo and it didn't do
## anything to it." Two genuinely different real effects, not one "bad
## status" reskinned by severity alone: real psilocybin/ibotenic-acid
## mushrooms (MushroomSpecies.is_psychoactive) cause genuine motor-
## coordination impairment/disorientation; Death Cap's real amatoxin
## poisoning is a categorically different hazard -- a progressive illness
## with a real, small, mammal-scale chance of death, no perceptual
## component at all.
##
## Pure and content-driven, no engine dependencies -- the same
## constants-plus-static-functions shape MushroomBiting/MushroomToxin
## already establish.

const MushroomEffect = preload("res://src/gameplay/mushroom_effect.gd")
const MushroomSpecies = preload("res://src/world/mushroom_species.gd")
const MushroomToxin = preload("res://src/gameplay/mushroom_toxin.gd")


# -- which real effect kind a species causes ---------------------------------

func test_psychoactive_species_cause_the_disoriented_effect():
	assert_eq(MushroomEffect.effect_kind_for("fly_agaric"), MushroomEffect.DISORIENTED_ID)
	assert_eq(MushroomEffect.effect_kind_for("psylo"), MushroomEffect.DISORIENTED_ID)


## Death Cap is toxic but NOT psychoactive -- a real, categorically
## different hazard shape (see MushroomSpecies.is_psychoactive's own doc
## comment).
func test_death_cap_causes_the_weakened_effect_not_disoriented():
	assert_eq(MushroomEffect.effect_kind_for("death_cap"), MushroomEffect.WEAKENED_ID)


func test_non_toxic_species_cause_no_effect_at_all():
	assert_eq(MushroomEffect.effect_kind_for("false_death_cap"), "")
	assert_eq(MushroomEffect.effect_kind_for("champignon"), "")


func test_an_unknown_species_causes_no_effect():
	assert_eq(MushroomEffect.effect_kind_for("portobello"), "")


# -- disorientation: erratic movement, scaled by real severity ---------------

## Reuses MushroomToxin.severity_for's own real ordering (Fly Agaric's
## ibotenic-acid/muscimol ataxia is genuinely more dramatic than
## Psilocybe's milder perceptual/motor effect) rather than inventing a
## second severity table.
func test_fly_agaric_wobbles_more_than_psylo():
	assert_gt(MushroomEffect.wobble_radians_for("fly_agaric"), MushroomEffect.wobble_radians_for("psylo"))
	assert_gt(MushroomEffect.wobble_radians_for("psylo"), 0.0)


func test_a_non_psychoactive_species_has_no_wobble():
	assert_eq(MushroomEffect.wobble_radians_for("death_cap"), 0.0)
	assert_eq(MushroomEffect.wobble_radians_for("champignon"), 0.0)


## A real, bounded swing -- never a full reversal or more (which would
## read as spinning in place, not stumbling).
func test_wobble_radians_never_exceeds_a_half_turn():
	for id in MushroomSpecies.IDS:
		assert_lte(MushroomEffect.wobble_radians_for(id), PI)


## Pure rotation: preserves length, deterministic per (seed, interval),
## and actually changes across intervals -- "erratic", not a fixed bias.
func test_wobble_direction_preserves_length():
	var direction := Vector2(10.0, 0.0)
	var wobbled := MushroomEffect.wobble_direction(direction, PI / 4.0, 5, 0.0)
	assert_almost_eq(wobbled.length(), direction.length(), 0.01)


func test_wobble_direction_is_deterministic_for_the_same_inputs():
	var a := MushroomEffect.wobble_direction(Vector2(10.0, 0.0), PI / 4.0, 5, 1.0)
	var b := MushroomEffect.wobble_direction(Vector2(10.0, 0.0), PI / 4.0, 5, 1.0)
	assert_eq(a, b)


func test_wobble_direction_changes_across_intervals():
	var seen := {}
	var t := 0.0
	while t < MushroomEffect.WOBBLE_CHANGE_INTERVAL_SECONDS * 20.0:
		seen[MushroomEffect.wobble_direction(Vector2(10.0, 0.0), PI / 3.0, 5, t)] = true
		t += MushroomEffect.WOBBLE_CHANGE_INTERVAL_SECONDS
	assert_gt(seen.size(), 1, "an erratic wobble should pick more than one heading over time")


func test_zero_wobble_radians_leaves_direction_unchanged():
	var direction := Vector2(10.0, 0.0)
	assert_eq(MushroomEffect.wobble_direction(direction, 0.0, 5, 3.0), direction)


func test_wobble_direction_leaves_a_zero_vector_unchanged():
	assert_eq(MushroomEffect.wobble_direction(Vector2.ZERO, PI / 4.0, 5, 3.0), Vector2.ZERO)


# -- weakened: a real movement-speed penalty, scaled by real severity -------

## death_cap IS the reference severity for the weakened shape -- exactly
## the pinned penalty at its own severity.
func test_death_cap_weakened_multiplier_is_pinned():
	assert_almost_eq(
		MushroomEffect.weakened_speed_multiplier_for("death_cap"),
		1.0 - MushroomEffect.WEAKENED_SPEED_PENALTY_AT_REFERENCE,
		0.001
	)


func test_a_non_weakened_species_has_no_speed_penalty():
	assert_almost_eq(MushroomEffect.weakened_speed_multiplier_for("fly_agaric"), 1.0, 0.001)
	assert_almost_eq(MushroomEffect.weakened_speed_multiplier_for("champignon"), 1.0, 0.001)


## Never a negative or zero multiplier -- weakened, not paralyzed/reversed.
func test_weakened_speed_multiplier_never_drops_below_a_real_floor():
	for id in MushroomSpecies.IDS:
		assert_gt(MushroomEffect.weakened_speed_multiplier_for(id), 0.0, id)
		assert_lte(MushroomEffect.weakened_speed_multiplier_for(id), 1.0, id)


# -- lethality: real, small, and deliberately mammal-only --------------------
#
# Real insects (famously, fungus gnat larvae that develop IN death cap
# fruiting bodies) are documented as considerably more tolerant of
# amatoxins than mammals are -- this module exposes the death chance as a
# pure function; DecomposerMarker (an insect) simply never calls it,
# CreatureMarker (a boar, a real mammal) does. See
# docs/concept/soil_fauna.md's own writeup for the full reasoning.

func test_only_death_cap_is_lethal_capable():
	assert_true(MushroomEffect.is_lethal_capable("death_cap"))
	assert_false(MushroomEffect.is_lethal_capable("fly_agaric"))
	assert_false(MushroomEffect.is_lethal_capable("psylo"))
	assert_false(MushroomEffect.is_lethal_capable("champignon"))


func test_death_chance_per_second_is_zero_for_non_lethal_species():
	assert_eq(MushroomEffect.death_chance_per_second("fly_agaric"), 0.0)
	assert_eq(MushroomEffect.death_chance_per_second("champignon"), 0.0)


func test_death_cap_death_chance_per_second_is_pinned():
	assert_almost_eq(
		MushroomEffect.death_chance_per_second("death_cap"),
		MushroomEffect.DEATH_CAP_DEATH_CHANCE_PER_SECOND,
		0.00001
	)


## A real, reachable, but deliberately uncommon outcome -- not an
## accidental instant kill, and not so rare it can never matter. Pinned
## as a cumulative-probability RANGE across one full WEAKENED_DURATION_
## SECONDS window at 1 stack, the real quantity that actually matters for
## balance, not just the raw per-second number in isolation.
func test_cumulative_death_chance_over_one_full_weakened_window_is_a_real_but_uncommon_risk():
	var survive_one_second := 1.0 - MushroomEffect.death_chance_per_second("death_cap")
	var survival_probability := pow(survive_one_second, MushroomEffect.WEAKENED_DURATION_SECONDS)
	var death_probability := 1.0 - survival_probability
	assert_gt(death_probability, 0.03, "should be a real, non-negligible risk")
	assert_lt(death_probability, 0.20, "should not be common -- one mushroom bite is not usually fatal")


## More stacks (repeated toxic bites while already affected -- mirrors
## DebuffStack's own MAX_STACKS convention) raise the per-tick chance,
## capped at MAX_STACKS, same shape MushroomToxin.damage_per_second uses.
func test_death_chance_scales_with_stacks_and_caps_at_max_stacks():
	var one_stack := MushroomEffect.death_chance_per_second("death_cap", 1)
	var two_stacks := MushroomEffect.death_chance_per_second("death_cap", 2)
	var over_cap := MushroomEffect.death_chance_per_second("death_cap", MushroomEffect.MAX_STACKS + 5)
	assert_almost_eq(two_stacks, one_stack * 2.0, 0.00001)
	assert_almost_eq(over_cap, one_stack * float(MushroomEffect.MAX_STACKS), 0.00001)


# -- attempt_death: deterministic roll, same shape DiseaseModel.attempt_transmit uses --

func test_attempt_death_is_deterministic_for_the_same_seed():
	assert_eq(MushroomEffect.attempt_death(0.5, 42), MushroomEffect.attempt_death(0.5, 42))


func test_attempt_death_never_succeeds_at_zero_chance():
	for seed_value in range(20):
		assert_false(MushroomEffect.attempt_death(0.0, seed_value))


func test_attempt_death_always_succeeds_at_full_chance():
	for seed_value in range(20):
		assert_true(MushroomEffect.attempt_death(1.0, seed_value))


# -- durations: real, and distinct enough to read as two different effects --

func test_disoriented_and_weakened_durations_are_both_real_and_positive():
	assert_gt(MushroomEffect.DISORIENTED_DURATION_SECONDS, 0.0)
	assert_gt(MushroomEffect.WEAKENED_DURATION_SECONDS, 0.0)


func test_duration_for_matches_the_effect_kind():
	assert_almost_eq(MushroomEffect.duration_for("psylo"), MushroomEffect.DISORIENTED_DURATION_SECONDS, 0.001)
	assert_almost_eq(MushroomEffect.duration_for("death_cap"), MushroomEffect.WEAKENED_DURATION_SECONDS, 0.001)
	assert_eq(MushroomEffect.duration_for("false_death_cap"), 0.0)
