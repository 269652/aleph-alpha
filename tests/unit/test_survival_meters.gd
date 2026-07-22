extends GutTest

const SurvivalMeters = preload("res://src/gameplay/survival_meters.gd")

var meters: SurvivalMeters


func before_each():
	meters = SurvivalMeters.new()


func test_starts_sated_hydrated_energized_and_fit():
	assert_eq(meters.hunger, 0.0)
	assert_eq(meters.thirst, 0.0)
	assert_eq(meters.stamina, 1.0)
	assert_eq(meters.fitness, 1.0)
	assert_false(meters.is_hungry())
	assert_false(meters.is_thirsty())
	assert_false(meters.is_exhausted())
	assert_false(meters.is_starving())
	assert_false(meters.is_dehydrated())


func test_hunger_and_thirst_rise_over_time():
	meters.advance(1.0)
	assert_gt(meters.hunger, 0.0)
	assert_gt(meters.thirst, 0.0)


func test_hunger_and_thirst_clamp_at_one():
	meters.advance(100000.0)
	assert_eq(meters.hunger, 1.0)
	assert_eq(meters.thirst, 1.0)


func test_eating_reduces_hunger():
	meters.advance(10.0)
	var before := meters.hunger
	meters.eat(0.1)
	assert_lt(meters.hunger, before)


func test_eating_clamps_at_zero():
	meters.eat(0.5)
	assert_eq(meters.hunger, 0.0)


func test_drinking_reduces_thirst():
	meters.advance(10.0)
	var before := meters.thirst
	meters.drink(0.1)
	assert_lt(meters.thirst, before)


func test_drinking_clamps_at_zero():
	meters.drink(0.5)
	assert_eq(meters.thirst, 0.0)


func test_spending_stamina_reduces_it():
	meters.spend_stamina(0.3)
	assert_almost_eq(meters.stamina, 0.7, 0.0001)


func test_spending_stamina_clamps_at_zero():
	meters.spend_stamina(5.0)
	assert_eq(meters.stamina, 0.0)


func test_resting_restores_stamina():
	meters.spend_stamina(0.5)
	meters.rest(0.2)
	assert_almost_eq(meters.stamina, 0.7, 0.0001)


func test_resting_clamps_at_one():
	meters.rest(5.0)
	assert_eq(meters.stamina, 1.0)


func test_stamina_regenerates_over_time_via_advance():
	meters.spend_stamina(0.5)
	var before := meters.stamina
	meters.advance(1.0)
	assert_gt(meters.stamina, before)


func test_fitness_drops_while_starving():
	while not meters.is_starving():
		meters.advance(1.0)
	var before := meters.fitness
	meters.advance(1.0)
	assert_lt(meters.fitness, before)


func test_fitness_drops_while_dehydrated():
	while not meters.is_dehydrated():
		meters.advance(1.0)
	var before := meters.fitness
	meters.advance(1.0)
	assert_lt(meters.fitness, before)


func test_fitness_recovers_when_not_starving_or_dehydrated():
	while not meters.is_starving():
		meters.advance(1.0)
	meters.advance(1.0)
	assert_lt(meters.fitness, 1.0)
	meters.eat(1.0)
	meters.drink(1.0)
	var before := meters.fitness
	meters.advance(1.0)
	assert_gt(meters.fitness, before)


func test_becomes_hungry_once_past_the_threshold():
	assert_false(meters.is_hungry())
	while meters.hunger < SurvivalMeters.HUNGRY_THRESHOLD:
		meters.advance(1.0)
	assert_true(meters.is_hungry())


func test_becomes_thirsty_once_past_the_threshold():
	assert_false(meters.is_thirsty())
	while meters.thirst < SurvivalMeters.THIRSTY_THRESHOLD:
		meters.advance(1.0)
	assert_true(meters.is_thirsty())


func test_becomes_exhausted_once_past_the_threshold():
	assert_false(meters.is_exhausted())
	meters.spend_stamina(1.0 - SurvivalMeters.EXHAUSTED_THRESHOLD)
	assert_true(meters.is_exhausted())


func test_becomes_starving_once_past_the_threshold():
	assert_false(meters.is_starving())
	while meters.hunger < SurvivalMeters.STARVING_THRESHOLD:
		meters.advance(1.0)
	assert_true(meters.is_starving())


func test_becomes_dehydrated_once_past_the_threshold():
	assert_false(meters.is_dehydrated())
	while meters.thirst < SurvivalMeters.DEHYDRATED_THRESHOLD:
		meters.advance(1.0)
	assert_true(meters.is_dehydrated())


func test_warmth_starts_comfortable():
	assert_eq(meters.warmth, 1.0)


func test_regulate_temperature_drifts_toward_a_cold_ambient():
	# Freezing ambient, dry: warmth should fall over time toward it.
	for i in 200:
		meters.regulate_temperature(0.0, 0.0, 0.1)
	assert_lt(meters.warmth, 0.3, "prolonged cold ambient should chill the player")


func test_regulate_temperature_holds_warm_in_warm_ambient():
	for i in 50:
		meters.regulate_temperature(1.0, 0.0, 0.1)
	assert_gt(meters.warmth, 0.9, "a warm dry ambient keeps the player comfortable")


func test_wetness_makes_the_same_ambient_colder():
	var dry := SurvivalMeters.new()
	var wet := SurvivalMeters.new()
	for i in 100:
		dry.regulate_temperature(0.6, 0.0, 0.1)
		wet.regulate_temperature(0.6, 1.0, 0.1)
	assert_lt(wet.warmth, dry.warmth, "being soaked chills you at the same ambient")


func test_is_cold_and_is_freezing_gate_on_warmth():
	meters.warmth = 0.35
	assert_true(meters.is_cold())
	assert_false(meters.is_freezing())
	meters.warmth = 0.1
	assert_true(meters.is_freezing())
	assert_true(meters.is_cold(), "freezing is also cold")
	meters.warmth = 0.9
	assert_false(meters.is_cold())


func test_cold_accelerates_fitness_loss():
	meters.warmth = 0.1  # freezing
	var before := meters.fitness
	meters.advance(2.0)
	assert_lt(meters.fitness, before, "cold exposure should degrade condition like starvation does")


func test_meters_drain_slowly_enough_for_a_short_excursion():
	# A minute of play must not push the player into hungry/thirsty territory
	# (the earlier tuning drained them in ~20s, which felt broken).
	meters.advance(60.0)
	assert_false(meters.is_hungry(), "shouldn't be hungry after only a minute")
	assert_false(meters.is_thirsty(), "shouldn't be thirsty after only a minute")
	# ...but thirst still outpaces hunger, and both are non-trivial over time.
	assert_gt(meters.thirst, meters.hunger)
