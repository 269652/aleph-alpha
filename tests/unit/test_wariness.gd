extends GutTest

## An animal that has just fled is harder to approach than one that never
## noticed you, and it gets over it (see docs/concept/animal_husbandry.md "The
## approach" -> "Wariness, and how a spooked animal recovers").
##
## A ramp, not a flag -- the same "thresholds are ramps or hysteresis, never
## hard switches" rule ecosystem_dynamics.md enforces everywhere else.
##
## The input for the decay is NOTHING: wariness falls by being left alone. It
## is the one mechanic in the game whose correct play is to walk away.

const Wariness = preload("res://src/gameplay/wariness.gd")
const GrazerForaging = preload("res://src/gameplay/grazer_foraging.gd")


func test_a_fresh_animal_starts_calm():
	assert_eq(Wariness.INITIAL, 0.0)


func test_being_spooked_raises_it():
	assert_gt(Wariness.after_spook(0.0), 0.0)


## Repeated spooks compound rather than resetting to one fixed "spooked"
## value -- an animal you have chased four times is warier than one you
## startled once.
func test_repeated_spooks_compound():
	var once := Wariness.after_spook(0.0)
	var twice := Wariness.after_spook(once)
	assert_gt(twice, once)


## ...but never past the top of its range, or one afternoon of bad approaches
## would make an animal permanently unapproachable.
func test_wariness_never_leaves_its_range():
	var value := 0.0
	for spook in 50:
		value = Wariness.after_spook(value)
		assert_between(value, 0.0, 1.0)
	for step in 500:
		value = Wariness.after_calm(value, 1.0)
		assert_between(value, 0.0, 1.0)


func test_leaving_an_animal_alone_calms_it():
	var spooked := Wariness.after_spook(0.0)
	assert_lt(Wariness.after_calm(spooked, 1.0), spooked)


func test_calm_never_goes_negative():
	assert_eq(Wariness.after_calm(0.0, 10_000.0), 0.0)


## The recovery time is not an eyeballed number of seconds: it is expressed
## against the grazing cycle, so an animal that has been spooked once is
## approachable again after a few ordinary grazing bouts -- long enough that
## chasing costs you something, short enough that the world does not remember
## a mistake forever.
func test_a_spooked_grazer_is_approachable_again_within_a_few_grazing_bouts():
	var bout := GrazerForaging.GRAZE_SECONDS + GrazerForaging.REGRAZE_SECONDS
	var value := Wariness.after_spook(0.0)
	var still_wary_after_one_bout := Wariness.after_calm(value, bout)
	assert_gt(still_wary_after_one_bout, 0.0, "one bout should not wipe it")

	var recovered := Wariness.after_calm(value, bout * Wariness.RECOVERY_BOUTS)
	assert_almost_eq(recovered, 0.0, 0.05, "a few bouts should very nearly clear it")


## Decay is per-second, so the same elapsed time split across two steps has to
## land in the same place as one step -- otherwise the frame rate changes how
## fast an animal forgives you.
func test_decay_is_frame_rate_independent():
	var spooked := Wariness.after_spook(Wariness.after_spook(0.0))
	var one_step := Wariness.after_calm(spooked, 4.0)
	var two_steps := Wariness.after_calm(Wariness.after_calm(spooked, 2.0), 2.0)
	assert_almost_eq(one_step, two_steps, 0.0001)


# -- the scent channel -------------------------------------------------------
#
# See WindScent / FlightDistance.smells_player. A whiff of the player does not
# make an animal bolt -- it makes it jumpy, which is what wariness IS.


func test_catching_the_players_scent_makes_an_animal_jumpier():
	assert_gt(Wariness.after_scent(0.0, 1.0), 0.0)


## A whiff is gentler than being startled outright: standing upwind for a
## moment must not cost as much as being chased.
func test_a_moment_of_scent_is_gentler_than_a_spook():
	assert_lt(Wariness.after_scent(0.0, 1.0), Wariness.after_spook(0.0))


## ...but standing upwind of an animal for a whole grazing bout costs real
## patience, or the wind is decoration.
func test_a_grazing_bout_spent_upwind_costs_half_an_animals_patience():
	var bout := GrazerForaging.GRAZE_SECONDS + GrazerForaging.REGRAZE_SECONDS
	assert_almost_eq(Wariness.after_scent(0.0, bout), 0.5, 0.05)


func test_scent_never_leaves_its_range():
	var value := 0.0
	for step in 200:
		value = Wariness.after_scent(value, 5.0)
		assert_between(value, 0.0, 1.0)


func test_scent_is_frame_rate_independent():
	var one_step := Wariness.after_scent(0.2, 4.0)
	var two_steps := Wariness.after_scent(Wariness.after_scent(0.2, 2.0), 2.0)
	assert_almost_eq(one_step, two_steps, 0.0001)


## An exponential decay never actually reaches zero, and "not quite zero
## forever" is a real trap: anything reading `wariness > 0.0` as "has been
## spooked" would latch on the first fright and never let go.
func test_an_animal_left_alone_long_enough_is_actually_calm_not_nearly_calm():
	var value := Wariness.after_spook(Wariness.after_spook(0.0))
	value = Wariness.after_calm(value, Wariness.HALF_LIFE_SECONDS * 20.0)
	assert_eq(value, 0.0)
