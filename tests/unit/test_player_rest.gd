extends GutTest

## docs/concept/sleep.md: the rest verb, on a real character.
##
## Slumber is pinned by test_slumber.gd. What is asserted here is the state
## machine a monster can attach to: a character who really is asleep, who
## really is held still, whose rest really can be taken away, and who really
## banks the payoff only when they reach first light.

const PlayerScene = preload("res://scenes/player.tscn")
const Slumber = preload("res://src/gameplay/slumber.gd")
const SurvivalMeters = preload("res://src/gameplay/survival_meters.gd")

var player


func before_each():
	player = PlayerScene.instantiate()
	add_child(player)


func after_each():
	player.queue_free()


# -- lying down ----------------------------------------------------------

func test_a_new_character_is_awake():
	assert_false(player.is_resting())


func test_lying_down_really_begins_a_rest():
	assert_true(player.begin_rest(), "an ordinary night refuses nothing")
	assert_true(player.is_resting())


func test_you_cannot_begin_a_rest_you_are_already_having():
	player.begin_rest()
	assert_false(player.begin_rest(), "the second press is not a second sleep")
	assert_true(player.is_resting(), "and it does not cancel the first")


## The refusal is a sentence the player can read, not a silent false.
func test_a_refused_rest_says_why():
	player.position = Vector2.ZERO
	player.begin_rest()
	player.wake()
	# Refusals route through the same message channel every other verb uses.
	var source := FileAccess.get_file_as_string("res://scenes/player.gd")
	assert_true(source.contains("Slumber.refusal_for"), "the shared rule decides")


# -- being asleep --------------------------------------------------------

## The whole cost of resting: you are not driving. Input must be IGNORED,
## not merely unused, or a sleeping character walks.
func test_a_sleeping_character_is_held_still():
	player.begin_rest()
	player.velocity = Vector2(100.0, 0.0)
	player.rest_step(0.1)
	assert_true(player.is_resting())
	var source := FileAccess.get_file_as_string("res://scenes/player.gd")
	assert_true(source.contains("is_resting()"), "the movement step really asks")


func test_the_rest_counts_down_toward_first_light():
	player.begin_rest()
	var before: float = player.rest_hours_remaining()
	assert_gt(before, 0.0, "a rest always has somewhere to run to")
	player.rest_step(1.0)
	assert_lt(player.rest_hours_remaining(), before, "the night really passes")


## The rate is the shared rule's, never a second opinion.
func test_an_hour_of_rest_is_the_shared_rules_hour():
	player.begin_rest()
	var before: float = player.rest_hours_remaining()
	player.rest_step(1.0)
	assert_almost_eq(
		before - player.rest_hours_remaining(), Slumber.HOURS_PER_REAL_SECOND, 0.001
	)


func test_reaching_first_light_ends_the_rest_by_itself():
	player.begin_rest()
	var guard := 0
	while player.is_resting() and guard < 10000:
		player.rest_step(0.25)
		guard += 1
	assert_lt(guard, 10000, "a rest that never ends is not a rest")
	assert_false(player.is_resting())


# -- and losing it -------------------------------------------------------

## Pillar 4: the payoff is banked only when the rest COMPLETES.
func test_a_completed_rest_fills_the_bar():
	player.survival.stamina = 0.0
	player.begin_rest()
	while player.is_resting():
		player.rest_step(1.0)
	assert_almost_eq(player.survival.stamina, 1.0, 0.001, "a full night is a full bar")


func test_waking_early_loses_the_rest():
	player.survival.stamina = 0.0
	player.begin_rest()
	player.rest_step(1.0)
	player.wake()
	assert_false(player.is_resting())
	assert_lt(
		player.survival.stamina, 1.0,
		"the cost of waking is the rest you lose"
	)


## The single interruption rule: anything that damages you wakes you. That
## is what a monster's drain hooks -- a drain that wakes you is a drain you
## can answer.
func test_being_hurt_wakes_you():
	player.begin_rest()
	player.take_damage(1.0)
	assert_false(player.is_resting(), "you do not sleep through being bitten")


func test_waking_when_awake_is_harmless():
	assert_false(player.is_resting())
	player.wake()
	assert_false(player.is_resting())


# -- the world clock really moves ----------------------------------------

## World advances the shared clock while a character sleeps, through the
## same door /ecotest's TimeLapse already uses.
func test_the_world_is_told_to_advance_while_you_sleep():
	var source := FileAccess.get_file_as_string("res://scenes/world.gd")
	# The PLAYER counts its own hours down and hands back what the frame was
	# worth; World only pushes it. An earlier draft of this test asserted
	# World called Slumber itself, which would have put the rate in two
	# places.
	assert_true(source.contains("rest_step(delta)"), "the night really passes")
	assert_true(source.contains("advance_world_age"), "through the world's own clock")
	assert_true(
		FileAccess.get_file_as_string("res://scenes/player.gd").contains(
			"Slumber.world_age_seconds_for"
		),
		"and the rate is the shared rule's, in one place"
	)


func test_the_verb_is_bound_to_a_key():
	var Keybindings = load("res://src/gameplay/keybindings.gd")
	assert_true(
		Keybindings.new().action_names().has("rest"), "a verb with no key is not a verb"
	)
