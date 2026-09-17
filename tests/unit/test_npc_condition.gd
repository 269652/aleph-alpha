extends GutTest

## A villager's own stamina and fitness (docs/concept/npc.md, "A hunter runs,
## and the run is paid for in stamina").
##
## Not a parallel invention: these are the player's own two meters in the
## player's own shape, reusing SurvivalMeters' constants by direct reference,
## for the one villager whose work is a chase rather than a walk.

const NpcCondition = preload("res://src/world/npc_condition.gd")
const SurvivalMeters = preload("res://src/gameplay/survival_meters.gd")
const ConditionPenalty = preload("res://src/gameplay/condition_penalty.gd")
const Metabolism = preload("res://src/gameplay/metabolism.gd")

const FED := 0.0

var condition


func before_each():
	condition = NpcCondition.new()


func test_a_fresh_villager_starts_rested_and_fit():
	assert_eq(condition.stamina, 1.0)
	assert_eq(condition.fitness, 1.0)


func test_running_spends_stamina():
	condition.advance(1.0, FED, true)
	assert_lt(condition.stamina, 1.0, "a run has to cost something")
	assert_almost_eq(condition.stamina, 1.0 - NpcCondition.RUN_STAMINA_PER_SECOND, 0.0001)


## The cost of a run is NOT a fresh eyeballed number: walking is
## Metabolism's ACTIVITY_MOVING tier and running is ACTIVITY_EXERTION, both
## already real MET-style multipliers this game burns calories at, so the
## run's cost is the meter's own break-even rate times that real ratio.
func test_a_run_costs_what_this_games_own_activity_tiers_say_it_does():
	var expected: float = SurvivalMeters.STAMINA_REGEN_PER_SECOND * (
		Metabolism.activity_multiplier_for(Metabolism.ACTIVITY_EXERTION)
		/ Metabolism.activity_multiplier_for(Metabolism.ACTIVITY_MOVING)
	)
	assert_almost_eq(NpcCondition.RUN_STAMINA_PER_SECOND, expected, 0.000001)
	assert_gt(NpcCondition.RUN_STAMINA_PER_SECOND, SurvivalMeters.STAMINA_REGEN_PER_SECOND,
		"running has to outpace resting, or nobody ever tires")


func test_not_running_gets_the_wind_back_at_the_players_own_rate():
	condition.stamina = 0.5
	condition.advance(1.0, FED, false)
	assert_almost_eq(condition.stamina, 0.5 + SurvivalMeters.STAMINA_REGEN_PER_SECOND, 0.0001)


## The whole point of the request: "recovers based on fitness".
func test_recovery_slows_with_condition():
	condition.stamina = 0.5
	condition.fitness = 0.0
	condition.advance(1.0, FED, false)
	var unfit_gain: float = condition.stamina - 0.5

	var fit = NpcCondition.new()
	fit.stamina = 0.5
	fit.advance(1.0, FED, false)
	var fit_gain: float = fit.stamina - 0.5

	assert_lt(unfit_gain, fit_gain, "a starved body has to be slower to recover")
	assert_almost_eq(
		unfit_gain, fit_gain * ConditionPenalty.WORST_STAMINA_REGEN_MULTIPLIER, 0.0001,
		"and by exactly the shared condition curve, not a second one"
	)


## Fitness is the same accumulator of neglect it is for the player, fed by
## the villager's own hunger and crossing at the player's own threshold.
func test_fitness_falls_while_starving_and_recovers_once_fed():
	condition.advance(1.0, SurvivalMeters.STARVING_THRESHOLD, false)
	assert_almost_eq(condition.fitness, 1.0 - SurvivalMeters.FITNESS_DROP_PER_SECOND, 0.0001)

	condition.fitness = 0.5
	condition.advance(1.0, FED, false)
	assert_almost_eq(condition.fitness, 0.5 + SurvivalMeters.FITNESS_RECOVER_PER_SECOND, 0.0001)


func test_merely_peckish_is_not_starving():
	condition.advance(1.0, SurvivalMeters.STARVING_THRESHOLD - 0.01, false)
	assert_gt(condition.fitness, 1.0 - SurvivalMeters.FITNESS_DROP_PER_SECOND, "only real starvation costs condition")


func test_a_rested_villager_can_run_and_a_blown_one_cannot():
	assert_true(condition.can_run(), "a rested hunter runs")
	condition.stamina = SurvivalMeters.EXHAUSTED_THRESHOLD
	condition.advance(0.1, FED, true)
	assert_false(condition.can_run(), "at the player's own exhaustion line they drop to a walk")


## Latched, not a flicker: without this, one frame of recovery lifts stamina
## a hair over the line and the hunter breaks into a run again on the very
## next frame, alternating every frame for as long as the chase lasts. Same
## "come well back over it, not just over it" asymmetry
## ConstructionStartHysteresis already uses -- and pinned to full recovery so
## it needs no second tuned constant.
func test_exhaustion_is_latched_until_the_wind_is_fully_back():
	condition.stamina = SurvivalMeters.EXHAUSTED_THRESHOLD
	condition.advance(0.1, FED, true)
	assert_false(condition.can_run(), "precondition: blown")

	# 16 real seconds at the player's own regen rate is the full climb from
	# the exhaustion line back to 1.0; this runs well past it on purpose.
	for i in 300:
		condition.advance(0.1, FED, false)
		if condition.stamina < 1.0:
			assert_false(condition.can_run(), "still winded at stamina %f" % condition.stamina)
	assert_eq(condition.stamina, 1.0, "precondition: this really did recover fully")
	assert_true(condition.can_run(), "fully rested, they run again")


func test_meters_never_leave_their_own_range():
	for i in 200:
		condition.advance(1.0, 1.0, true)
	assert_gte(condition.stamina, 0.0)
	assert_gte(condition.fitness, 0.0)
	for i in 400:
		condition.advance(1.0, FED, false)
	assert_lte(condition.stamina, 1.0)
	assert_lte(condition.fitness, 1.0)
