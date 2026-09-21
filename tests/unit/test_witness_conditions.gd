extends GutTest

## docs/concept/spell_weaving.md's acquisition table, as a rule.
##
## The doc has specified seven phenomena and their real sources since the
## Weave shipped. Three had call sites; four -- the storm, the dark, the hard
## climb and being hunted -- were "specified and tabled but have no call site
## yet", which its own status list said out loud. Four of the twenty-five
## atoms were therefore unobtainable in ordinary play, and `fear`,
## `shock_damage`, `illuminate` and `slow` could only ever be handed over by
## the dev console.
##
## This module is the missing half: one pure decision, from facts the
## player's own step already has, about what THIS moment teaches. Every
## threshold is read from the module that owns it rather than chosen here.

const WitnessConditions = preload("res://src/gameplay/witness_conditions.gd")
const SpellMote = preload("res://src/gameplay/spell_mote.gd")
const SurvivalMeters = preload("res://src/gameplay/survival_meters.gd")
const TerrainPassability = preload("res://src/gameplay/terrain_passability.gd")
const WeatherModel = preload("res://src/world/weather_model.gd")
const HudReadouts = preload("res://src/ui/hud_readouts.gd")


## Broad daylight, clear sky, flat ground, fed, warm, unhunted, standing
## still: a moment that teaches nothing at all.
func _quiet_moment() -> Dictionary:
	return {
		"freezing": false,
		"at_a_fire": false,
		"weather": "clear",
		"starving": false,
		"sun_elevation_deg": 45.0,
		"slope_deg": 0.0,
		"moving": false,
		"hunted": false,
	}


func _with(changes: Dictionary) -> Dictionary:
	var facts := _quiet_moment()
	for key in changes:
		facts[key] = changes[key]
	return facts


# -- an ordinary moment teaches nothing ----------------------------------

func test_a_quiet_moment_teaches_nothing():
	assert_eq(WitnessConditions.taught_by(_quiet_moment()), [])


func test_missing_facts_teach_nothing_rather_than_crashing():
	assert_eq(WitnessConditions.taught_by({}), [])


# -- the four that had no call site --------------------------------------

func test_a_storm_teaches_what_a_storm_teaches():
	var taught := WitnessConditions.taught_by(_with({"weather": WitnessConditions.STORM_STATE}))
	assert_true(taught.has(SpellMote.PHENOMENON_CAUGHT_IN_A_STORM))


func test_the_storm_state_is_the_weather_models_own():
	assert_true(
		WeatherModel.STATES.has(WitnessConditions.STORM_STATE),
		"a state the weather can never be in would teach nothing for ever"
	)


## The doc's own source: `is_starving` after dark. Either alone is an
## ordinary hardship; together they are the thing that teaches light.
func test_starving_after_dark_teaches_light_and_neither_alone_does():
	var dark := WitnessConditions.DARK_BELOW_SUN_ELEVATION_DEG - 1.0
	assert_true(
		WitnessConditions.taught_by(
			_with({"starving": true, "sun_elevation_deg": dark})
		).has(SpellMote.PHENOMENON_HUNGRY_IN_THE_DARK)
	)
	assert_false(
		WitnessConditions.taught_by(_with({"starving": true})).has(
			SpellMote.PHENOMENON_HUNGRY_IN_THE_DARK
		),
		"hungry in daylight is just hungry"
	)
	assert_false(
		WitnessConditions.taught_by(_with({"sun_elevation_deg": dark})).has(
			SpellMote.PHENOMENON_HUNGRY_IN_THE_DARK
		),
		"and a fed character out at night is just out at night"
	)


## Dark is civil twilight -- the same astronomical definition
## docs/concept/arrival.md already derived FIRST_LIGHT_HOUR from, rather
## than a second opinion about when it gets dark.
func test_dark_is_the_huds_own_civil_twilight():
	assert_eq(
		WitnessConditions.DARK_BELOW_SUN_ELEVATION_DEG, HudReadouts.CIVIL_TWILIGHT_DEGREES
	)


## Ground that "fought back" is ground the world itself slows you on --
## TerrainPassability's own soft threshold, where the multiplier first
## bites, not a number picked here.
func test_climbing_ground_that_fights_back_teaches_slow():
	var steep := TerrainPassability.SOFT_THRESHOLD_DEG + 1.0
	assert_lt(
		TerrainPassability.speed_multiplier(steep), 1.0,
		"precondition: this slope really does fight back"
	)
	assert_true(
		WitnessConditions.taught_by(_with({"slope_deg": steep, "moving": true})).has(
			SpellMote.PHENOMENON_CLIMBED_HARD_GROUND
		)
	)


func test_flat_ground_teaches_no_climb_however_hard_you_walk():
	var flat := TerrainPassability.SOFT_THRESHOLD_DEG - 1.0
	assert_eq(
		TerrainPassability.speed_multiplier(flat), 1.0, "precondition: this is easy ground"
	)
	assert_false(
		WitnessConditions.taught_by(_with({"slope_deg": flat, "moving": true})).has(
			SpellMote.PHENOMENON_CLIMBED_HARD_GROUND
		)
	)


## Standing on a cliff is not climbing it. You have to be going somewhere.
func test_standing_still_on_steep_ground_is_not_a_climb():
	var steep := TerrainPassability.SOFT_THRESHOLD_DEG + 20.0
	assert_false(
		WitnessConditions.taught_by(_with({"slope_deg": steep, "moving": false})).has(
			SpellMote.PHENOMENON_CLIMBED_HARD_GROUND
		)
	)


func test_being_hunted_teaches_fear():
	assert_true(
		WitnessConditions.taught_by(_with({"hunted": true})).has(SpellMote.PHENOMENON_HUNTED)
	)


# -- and the three that already had one ----------------------------------
#
# Folded into the same decision so there is ONE place that answers "what
# does this moment teach", rather than a table in the doc and a scatter of
# `if`s in the player's step.

func test_freezing_still_teaches_frost():
	assert_true(
		WitnessConditions.taught_by(_with({"freezing": true})).has(SpellMote.PHENOMENON_FROZE)
	)


func test_a_fire_still_teaches_fire():
	assert_true(
		WitnessConditions.taught_by(_with({"at_a_fire": true})).has(
			SpellMote.PHENOMENON_WARMED_AT_A_FIRE
		)
	)


## Envenomation is an EVENT, not a condition of the moment -- it is raised
## where the bite lands. It must not appear here, or a poisoned character
## would re-learn it every frame they stayed poisoned.
func test_envenomation_is_not_a_condition_of_the_moment():
	for phenomenon in WitnessConditions.taught_by(_with({
		"freezing": true, "at_a_fire": true, "weather": WitnessConditions.STORM_STATE,
		"starving": true, "sun_elevation_deg": -20.0, "slope_deg": 60.0,
		"moving": true, "hunted": true,
	})):
		assert_ne(
			phenomenon, SpellMote.PHENOMENON_ENVENOMATED,
			"venom is raised by the bite, not by standing somewhere"
		)


# -- the whole table is reachable ----------------------------------------

## The assertion that makes the Weave playable: every phenomenon the design
## table names is reachable from some real moment, so every atom it teaches
## can be come by without the dev console.
func test_every_condition_phenomenon_is_reachable_from_some_real_moment():
	var everything := WitnessConditions.taught_by(_with({
		"freezing": true, "at_a_fire": true, "weather": WitnessConditions.STORM_STATE,
		"starving": true, "sun_elevation_deg": -20.0, "slope_deg": 60.0,
		"moving": true, "hunted": true,
	}))
	for phenomenon in WitnessConditions.CONDITION_PHENOMENA:
		assert_true(
			everything.has(phenomenon), "%s is unreachable" % phenomenon
		)


## Two-way, like Answerback's drift test: nothing is reported that the mote
## table does not know how to teach.
func test_everything_reported_really_teaches_a_mote():
	var everything := WitnessConditions.taught_by(_with({
		"freezing": true, "at_a_fire": true, "weather": WitnessConditions.STORM_STATE,
		"starving": true, "sun_elevation_deg": -20.0, "slope_deg": 60.0,
		"moving": true, "hunted": true,
	}))
	for phenomenon in everything:
		assert_ne(
			SpellMote.first_witness_atom_for(String(phenomenon)), "",
			"%s teaches nothing" % phenomenon
		)


## Four of the twenty-five atoms were unobtainable before this existed.
func test_the_four_that_had_no_call_site_are_all_here():
	for phenomenon in [
		SpellMote.PHENOMENON_CAUGHT_IN_A_STORM,
		SpellMote.PHENOMENON_HUNGRY_IN_THE_DARK,
		SpellMote.PHENOMENON_CLIMBED_HARD_GROUND,
		SpellMote.PHENOMENON_HUNTED,
	]:
		assert_true(
			WitnessConditions.CONDITION_PHENOMENA.has(phenomenon),
			"%s is still unreachable" % phenomenon
		)
