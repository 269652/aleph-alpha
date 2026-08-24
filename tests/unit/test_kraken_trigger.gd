extends GutTest

## KrakenTrigger (docs/concept/easter_eggs.md's Kraken): the collection's one
## deliberately higher-stakes, CONDITION-triggered (not coordinate-triggered)
## entry -- open ocean, night, and active storm weather (WeatherModel), all
## at once, anywhere on the map.
##
## Every input is a plain, already-computed primitive (a bool/String/float),
## never a live system/node reference -- see the module's own doc comment for
## what a real caller (scenes/world.gd) would pass in -- so this whole suite
## exercises the pure decision logic with no node/scene/chunk manager
## involved, same shape as EasterEggSightings/EasterEggCreatures' own tests.

const KrakenTrigger = preload("res://src/gameplay/kraken_trigger.gd")
const EasterEggCreatures = preload("res://src/gameplay/easter_egg_creatures.gd")

var trigger: KrakenTrigger


func before_each():
	trigger = KrakenTrigger.new()


# -- is_open_ocean: the depth threshold --------------------------------------

func test_is_open_ocean_false_at_sea_level():
	assert_false(trigger.is_open_ocean(0.0))


func test_is_open_ocean_false_just_below_the_threshold():
	assert_false(trigger.is_open_ocean(KrakenTrigger.OPEN_OCEAN_MIN_DEPTH - 0.01))


func test_is_open_ocean_true_at_the_threshold():
	assert_true(trigger.is_open_ocean(KrakenTrigger.OPEN_OCEAN_MIN_DEPTH))


func test_is_open_ocean_true_at_the_ocean_floor():
	assert_true(trigger.is_open_ocean(1.0))


# -- is_eligible: all three real-world conditions, at once -------------------

func test_is_eligible_false_if_not_night():
	assert_false(trigger.is_eligible(false, "storm", 1.0))


func test_is_eligible_false_if_weather_is_not_storm():
	for weather in ["clear", "cloudy", "rain"]:
		assert_false(trigger.is_eligible(true, weather, 1.0), weather)


func test_is_eligible_false_if_not_open_ocean():
	assert_false(trigger.is_eligible(true, "storm", 0.0))


func test_is_eligible_true_when_all_three_conditions_hold():
	assert_true(trigger.is_eligible(true, "storm", 1.0))


# -- check: is_eligible plus the rarity roll ----------------------------------

func test_check_false_when_not_eligible_even_with_a_guaranteed_roll():
	assert_false(trigger.check(false, "storm", 1.0, 0.0))
	assert_false(trigger.check(true, "clear", 1.0, 0.0))
	assert_false(trigger.check(true, "storm", 0.0, 0.0))


func test_check_false_when_roll_does_not_clear_the_chance_threshold():
	# A roll of exactly 1.0 clears no threshold in [0, 1).
	assert_false(trigger.check(true, "storm", 1.0, 1.0))


func test_check_true_when_eligible_and_roll_clears_the_threshold():
	assert_true(trigger.check(true, "storm", 1.0, 0.0))


func test_a_kraken_check_has_no_persistent_state():
	# Same "zero mechanical presence beyond the decision itself" shape as
	# EasterEggSightings/EasterEggCreatures -- calling check twice with the
	# same inputs is exactly as valid as calling it once.
	var first := trigger.check(true, "storm", 1.0, 0.0)
	var second := trigger.check(true, "storm", 1.0, 0.0)
	assert_eq(first, second)


# -- CHANCE_PER_CHECK: vanishingly rare, relative to every other cameo -------

func test_chance_per_check_is_a_real_probability():
	assert_gt(KrakenTrigger.CHANCE_PER_CHECK, 0.0)
	assert_lt(KrakenTrigger.CHANCE_PER_CHECK, 1.0)


## Doc: "vanishingly rare" -- operationalized the same way Squallmaw's own
## rarity was pinned (see test_easter_egg_creatures.gd's matching test):
## strictly rarer than every other coordinate-triggered cameo in the
## project, including the project's previous rarest entry (squallmaw), by a
## wide margin, not just numerically smaller.
func test_kraken_is_far_rarer_than_squallmaw_the_projects_previous_rarest_cameo():
	var squallmaw_chance: float = EasterEggCreatures.SIGHTINGS["squallmaw"]["chance_per_check"]
	assert_lt(KrakenTrigger.CHANCE_PER_CHECK * 5.0, squallmaw_chance)
