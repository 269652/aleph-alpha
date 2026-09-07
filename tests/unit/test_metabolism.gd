extends GutTest

## Metabolism (see docs/concept/metabolism.md): the shared, species/instance-
## agnostic caloric-balance core every creature type's own live mass runs
## on. Same stateful-instance-plus-advance(delta) shape SurvivalMeters/
## CreatureNeeds already establish, generalizing the real Kleiber's-law
## math MushroomBiting.satiation_seconds_for already derived a satiation
## EXPONENT from into a real, direct BMR/calorie/mass model.

const Metabolism = preload("res://src/gameplay/metabolism.gd")
const CreatureMass = preload("res://src/world/creature_mass.gd")
const SeasonCycle = preload("res://src/world/season_cycle.gd")


# -- Kleiber's law: BMR ~ mass^0.75 -------------------------------------------

## 1kg lands on the coefficient exactly (1.0^0.75 == 1.0) -- a clean anchor
## point, not an arbitrary probe.
func test_bmr_at_one_kilogram_is_the_kleiber_coefficient():
	assert_almost_eq(Metabolism.bmr_kcal_per_day(1.0), Metabolism.KLEIBER_COEFFICIENT_KCAL_PER_DAY, 0.0001)


## 16 = 2^4 is chosen specifically so 16^0.75 lands on a clean integer (8),
## letting this pin an exact real-world-derived value instead of a fuzzy
## approximation.
func test_bmr_follows_kleibers_law_at_a_clean_mass():
	assert_almost_eq(Metabolism.bmr_kcal_per_day(16.0), Metabolism.KLEIBER_COEFFICIENT_KCAL_PER_DAY * 8.0, 0.001)


## The actual real-world claim Kleiber's law makes: a bigger animal burns
## MORE in absolute terms but LESS per kilogram of its own body than a
## smaller one. Mouse vs horse (CreatureMass's own real reference figures)
## rather than invented numbers.
func test_smaller_animals_burn_more_per_kilogram_of_their_own_mass():
	var mouse_mass := CreatureMass.mass_kg_for("mouse")
	var horse_mass := CreatureMass.mass_kg_for("horse")
	var mouse_bmr := Metabolism.bmr_kcal_per_day(mouse_mass)
	var horse_bmr := Metabolism.bmr_kcal_per_day(horse_mass)
	assert_gt(horse_bmr, mouse_bmr, "a horse burns more in absolute terms")
	assert_gt(mouse_bmr / mouse_mass, horse_bmr / horse_mass, "a mouse burns more per kg of its own body")


func test_bmr_increases_less_than_linearly_with_mass():
	var base := Metabolism.bmr_kcal_per_day(10.0)
	var doubled := Metabolism.bmr_kcal_per_day(20.0)
	assert_gt(doubled, base)
	assert_lt(doubled, base * 2.0, "doubling mass must not double BMR (mass^0.75, not mass^1)")


# -- activity tiers, real MET-ordered -----------------------------------------

func test_activity_tiers_are_ordered_like_real_met_values():
	var resting := Metabolism.activity_multiplier_for(Metabolism.ACTIVITY_RESTING)
	var feeding := Metabolism.activity_multiplier_for(Metabolism.ACTIVITY_FEEDING)
	var moving := Metabolism.activity_multiplier_for(Metabolism.ACTIVITY_MOVING)
	var exertion := Metabolism.activity_multiplier_for(Metabolism.ACTIVITY_EXERTION)
	assert_lt(resting, feeding)
	assert_lt(feeding, moving)
	assert_lt(moving, exertion)


## Resting is the real MET baseline: by definition 1x BMR.
func test_resting_multiplier_is_exactly_one():
	assert_almost_eq(Metabolism.activity_multiplier_for(Metabolism.ACTIVITY_RESTING), 1.0, 0.0001)


## An unrecognized activity string (a typo, or a creature integration that
## hasn't mapped its own phase yet) must fail SAFE to the baseline rate,
## never to the most expensive tier.
func test_unknown_activity_defaults_to_resting():
	assert_almost_eq(
		Metabolism.activity_multiplier_for("not_a_real_activity"),
		Metabolism.activity_multiplier_for(Metabolism.ACTIVITY_RESTING),
		0.0001
	)


# -- calorie burn over time ---------------------------------------------------

func test_calories_burned_scales_linearly_with_delta_seconds():
	var one_second := Metabolism.calories_burned(10.0, Metabolism.ACTIVITY_RESTING, 1.0)
	var ten_seconds := Metabolism.calories_burned(10.0, Metabolism.ACTIVITY_RESTING, 10.0)
	assert_almost_eq(ten_seconds, one_second * 10.0, 0.0001)


func test_calories_burned_scales_with_the_activity_multiplier():
	var resting := Metabolism.calories_burned(10.0, Metabolism.ACTIVITY_RESTING, 60.0)
	var exertion := Metabolism.calories_burned(10.0, Metabolism.ACTIVITY_EXERTION, 60.0)
	assert_almost_eq(
		exertion / resting,
		Metabolism.activity_multiplier_for(Metabolism.ACTIVITY_EXERTION),
		0.001
	)


## Burning at rest for one full WORLD day (the same clock every other body
## clock in this project already keeps -- SurvivalMeters/BirdDigestion/
## CreatureNeeds) costs exactly one day's worth of BMR -- the real
## definition of "basal metabolic rate", not an approximation of it.
func test_resting_for_one_world_day_costs_exactly_one_days_bmr():
	var mass_kg := 20.0
	var burned := Metabolism.calories_burned(mass_kg, Metabolism.ACTIVITY_RESTING, SeasonCycle.SECONDS_PER_DAY)
	assert_almost_eq(burned, Metabolism.bmr_kcal_per_day(mass_kg), 0.01)


# -- the live instance: current_mass_kg is the ONE tracked value -------------

func test_a_fresh_instance_starts_at_exactly_its_seed_mass():
	var metabolism := Metabolism.new(12.5)
	assert_almost_eq(metabolism.current_mass_kg, 12.5, 0.0001)


func test_advancing_with_no_food_and_no_time_does_nothing():
	var metabolism := Metabolism.new(12.5)
	metabolism.advance(0.0, Metabolism.ACTIVITY_RESTING)
	assert_almost_eq(metabolism.current_mass_kg, 12.5, 0.0001)


func test_advancing_time_with_nothing_eaten_loses_mass():
	var metabolism := Metabolism.new(12.5)
	metabolism.advance(SeasonCycle.SECONDS_PER_DAY, Metabolism.ACTIVITY_RESTING)
	assert_lt(metabolism.current_mass_kg, 12.5)


func test_feeding_real_food_mass_gains_mass():
	var metabolism := Metabolism.new(12.5)
	metabolism.feed_mass_kg(1.0)
	assert_gt(metabolism.current_mass_kg, 12.5)


func test_feeding_zero_or_negative_food_mass_does_nothing():
	var metabolism := Metabolism.new(12.5)
	metabolism.feed_mass_kg(0.0)
	metabolism.feed_mass_kg(-5.0)
	assert_almost_eq(metabolism.current_mass_kg, 12.5, 0.0001)


## The real energy-balance claim this whole system exists to model: eating
## back exactly what you just burned leaves your mass unchanged -- neither
## gain nor loss, the real definition of caloric balance.
func test_eating_exactly_what_was_burned_leaves_mass_unchanged():
	var seed_mass := 12.5
	var metabolism := Metabolism.new(seed_mass)
	var burned_kcal := Metabolism.calories_burned(seed_mass, Metabolism.ACTIVITY_MOVING, 3600.0)
	metabolism.advance(3600.0, Metabolism.ACTIVITY_MOVING)
	metabolism.feed_mass_kg(burned_kcal / Metabolism.CALORIES_PER_KG_FOOD)
	assert_almost_eq(metabolism.current_mass_kg, seed_mass, 0.0001)


# -- real starvation floor and overfeeding ceiling ---------------------------

## A real starving animal does not mathematically starve to zero or
## negative mass -- it bottoms out. Simulated with an enormous delta
## (months of continuous fasting) rather than looping advance() many times.
func test_prolonged_starvation_never_drops_below_the_real_floor():
	var seed_mass := 10.0
	var metabolism := Metabolism.new(seed_mass)
	metabolism.advance(SeasonCycle.SECONDS_PER_DAY * 365.0, Metabolism.ACTIVITY_EXERTION)
	assert_almost_eq(metabolism.current_mass_kg, seed_mass * Metabolism.MIN_MASS_FRACTION_OF_SEED, 0.0001)


## A real animal fed far beyond its needs accumulates fat but does not
## balloon indefinitely -- it caps at a real, named ceiling.
func test_massive_overfeeding_never_exceeds_the_real_ceiling():
	var seed_mass := 10.0
	var metabolism := Metabolism.new(seed_mass)
	for _i in 50:
		metabolism.feed_mass_kg(seed_mass)
	assert_almost_eq(metabolism.current_mass_kg, seed_mass * Metabolism.MAX_MASS_FRACTION_OF_SEED, 0.0001)


func test_starvation_floor_is_a_real_partial_loss_not_zero_or_full_loss():
	assert_gt(Metabolism.MIN_MASS_FRACTION_OF_SEED, 0.0, "a starved animal is thin, not massless")
	assert_lt(Metabolism.MIN_MASS_FRACTION_OF_SEED, 1.0, "the floor must actually allow real mass loss")


func test_overfeeding_ceiling_is_a_real_partial_gain_not_unbounded():
	assert_gt(Metabolism.MAX_MASS_FRACTION_OF_SEED, 1.0, "the ceiling must actually allow real mass gain")
	assert_lt(Metabolism.MAX_MASS_FRACTION_OF_SEED, 3.0, "a well-fed animal does not balloon to multiple times its healthy size")


# -- food-mass to calorie conversion ------------------------------------------

func test_calories_from_food_mass_scales_linearly_with_mass():
	assert_almost_eq(
		Metabolism.calories_from_food_mass_kg(2.0),
		Metabolism.calories_from_food_mass_kg(1.0) * 2.0,
		0.0001
	)


func test_calories_from_zero_food_mass_is_zero():
	assert_almost_eq(Metabolism.calories_from_food_mass_kg(0.0), 0.0, 0.0001)


# -- feeding from an existing hunger-relief fraction (wildlife bites) --------
#
# Wildlife's existing bite call sites (CreatureNeeds.feed_amount, the
# fruit/mushroom NutrientRelease "sugar" fraction) already produce a real,
# 0..1-scaled fraction of a full daily hunger meter -- not a raw food mass.
# feed_hunger_relief lets every one of those existing call sites feed the
# same real Metabolism instance without a separate per-food-type mass
# table: relieving a WHOLE day's hunger (relief_fraction 1.0) is grounded
# against this creature's OWN real BMR for one day, so a big animal's "one
# full meal" implies more real calories than a small one's for free.

func test_feeding_a_whole_days_hunger_relief_gains_exactly_one_days_bmr_worth_of_mass():
	var seed_mass := 20.0
	var metabolism := Metabolism.new(seed_mass)
	metabolism.feed_hunger_relief(1.0)
	var expected_gain := Metabolism.mass_delta_kg_for_calories(Metabolism.bmr_kcal_per_day(seed_mass))
	assert_almost_eq(metabolism.current_mass_kg, seed_mass + expected_gain, 0.0001)


func test_feeding_half_a_days_hunger_relief_gains_half_as_much_mass():
	var whole := Metabolism.new(20.0)
	whole.feed_hunger_relief(1.0)
	var half := Metabolism.new(20.0)
	half.feed_hunger_relief(0.5)
	var whole_gain := whole.current_mass_kg - 20.0
	var half_gain := half.current_mass_kg - 20.0
	assert_almost_eq(half_gain, whole_gain * 0.5, 0.0001)


func test_feeding_zero_or_negative_hunger_relief_does_nothing():
	var metabolism := Metabolism.new(20.0)
	metabolism.feed_hunger_relief(0.0)
	metabolism.feed_hunger_relief(-1.0)
	assert_almost_eq(metabolism.current_mass_kg, 20.0, 0.0001)
