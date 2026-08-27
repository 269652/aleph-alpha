extends GutTest

## Taming: catching an animal with a lasso, holding it while it fights, and
## winning it over by feeding it when it is hungry (see docs/concept/taming.md).
##
## Pure logic only -- no engine, no nodes -- so the whole capture-and-trust
## cycle is testable headlessly, the same split GrazerForaging and
## GroundForageBehavior use.

const Taming = preload("res://src/gameplay/taming.gd")
const Player = preload("res://scenes/player.gd")


# -- breaking free ----------------------------------------------------------

## A healthy animal fights the rope far harder than a spent one. Stated as a
## RATIO between the two rather than as an absolute threshold: attempts
## repeat, so what a single per-attempt number means to the player is nothing
## on its own -- see hold_chance and the tests at the bottom of this file.
func test_a_full_strength_animal_fights_harder_than_a_spent_one():
	assert_gt(
		Taming.break_free_chance(1.0), Taming.break_free_chance(0.15) * 2.0,
		"condition has to matter a lot, or picking a weak animal is pointless"
	)


## Monotonic in condition: there is never a health value where being HEALTHIER
## makes an animal easier to hold.
func test_being_healthier_never_makes_an_animal_easier_to_hold():
	var previous := -1.0
	for step in 21:
		var chance: float = Taming.break_free_chance(float(step) / 20.0)
		assert_gte(chance, previous, "chance must not dip as condition rises")
		previous = chance


func test_break_free_chance_stays_a_probability():
	for step in 21:
		assert_between(Taming.break_free_chance(float(step) / 20.0), 0.0, 1.0)
	assert_between(Taming.break_free_chance(-5.0), 0.0, 1.0, "nonsense condition is still safe")
	assert_between(Taming.break_free_chance(99.0), 0.0, 1.0)


## Each struggle costs the animal, so a long hold is winnable rather than a
## coin flip repeated forever. Measured in FATIGUE now rather than in health:
## fighting a rope tires an animal, it does not wound it.
func test_every_struggle_wears_the_animal_down():
	var fatigue := 0.0
	var attempts := 0
	while fatigue < 0.8 and attempts < 100:
		fatigue = Taming.fatigue_after_struggle(fatigue)
		attempts += 1
	assert_lt(attempts, 100, "struggling must actually tire an animal out")
	assert_gt(attempts, 1, "but not in a single attempt")


func test_struggling_never_drives_an_animal_past_exhaustion():
	var fatigue := 0.0
	for _i in 50:
		fatigue = Taming.fatigue_after_struggle(fatigue)
	assert_lte(fatigue, 1.0)


# -- trust ------------------------------------------------------------------

func test_a_freshly_caught_animal_trusts_nobody():
	assert_eq(Taming.starting_trust(), 0.0)


## The core rule: food only counts when the animal actually wants it. This is
## what stops taming being a matter of spamming carrots at a full animal, and
## it is what paces taming across real time, since hunger rises on its own
## schedule (CreatureNeeds).
func test_feeding_a_hungry_animal_earns_trust():
	assert_gt(Taming.trust_after_feeding(0.0, true), 0.0)


func test_feeding_an_animal_that_is_not_hungry_earns_nothing():
	assert_eq(Taming.trust_after_feeding(0.4, false), 0.4)


## "You need to feed it every time it gets hungry for like 5 times or so."
func test_it_takes_several_hungry_feeds_to_tame_an_animal():
	var trust: float = Taming.starting_trust()
	var feeds := 0
	while not Taming.is_tame(trust) and feeds < 50:
		trust = Taming.trust_after_feeding(trust, true)
		feeds += 1
	assert_between(feeds, 4, 8, "a handful of meals, not one and not a grind")


func test_trust_never_climbs_past_tame():
	var trust := 0.0
	for _i in 40:
		trust = Taming.trust_after_feeding(trust, true)
	assert_lte(trust, Taming.TAME_TRUST)


## Neglect is not neutral: an animal left tied and hungry loses faith in you.
func test_a_neglected_animal_loses_trust():
	var trust: float = Taming.TAME_TRUST * 0.5
	assert_lt(Taming.trust_after_neglect(trust, Taming.NEGLECT_SECONDS), trust)


func test_a_short_wait_is_not_neglect():
	var trust: float = Taming.TAME_TRUST * 0.5
	assert_almost_eq(Taming.trust_after_neglect(trust, 1.0), trust, 0.001)


func test_neglect_cannot_push_trust_below_nothing():
	assert_gte(Taming.trust_after_neglect(0.0, Taming.NEGLECT_SECONDS * 10.0), 0.0)


# -- what a tamed animal will do --------------------------------------------

func test_an_untamed_animal_takes_no_orders():
	assert_false(Taming.accepts_orders(Taming.TAME_TRUST * 0.9))


func test_a_tamed_animal_takes_orders():
	assert_true(Taming.accepts_orders(Taming.TAME_TRUST))


## Only animals that could plausibly carry a person are mounts. A tamed boar
## follows and stays; it is not a horse.
func test_only_a_ridable_species_can_be_mounted():
	assert_true(Taming.can_be_mounted("horse"))
	assert_false(Taming.can_be_mounted("boar"))
	assert_false(Taming.can_be_mounted("mouse"))


func test_an_untamed_horse_is_still_not_a_mount():
	assert_false(Taming.is_mountable("horse", Taming.TAME_TRUST * 0.5))
	assert_true(Taming.is_mountable("horse", Taming.TAME_TRUST))


## Predators are not tameable with a rope and a carrot.
func test_a_predator_cannot_be_lassoed_into_a_pet():
	assert_false(Taming.can_be_tamed("lynx", true))
	assert_true(Taming.can_be_tamed("horse", false))


# -- orders a tamed animal takes ---------------------------------------------

func test_the_orders_are_follow_and_stay():
	assert_ne(Taming.ORDER_FOLLOW, Taming.ORDER_STAY)


## Cycling is what a single key press does, so it has to come back round.
func test_cycling_an_order_returns_to_where_it_started():
	var order: int = Taming.ORDER_FOLLOW
	order = Taming.next_order(order)
	assert_eq(order, Taming.ORDER_STAY)
	assert_eq(Taming.next_order(order), Taming.ORDER_FOLLOW)


## Riding is the point of taming a horse: it has to actually be faster than
## walking, or the whole loop buys the player nothing. A horse at a working
## trot covers ground appreciably faster than a person walks, but this is a
## world to travel through rather than to blur past.
func test_riding_is_faster_than_walking():
	assert_gt(Taming.MOUNTED_SPEED, Player.BASE_SPEED)
	assert_lt(Taming.MOUNTED_SPEED, Player.BASE_SPEED * 3.0)


## Mounted speed is not one flat number for every horse -- pets.md's own
## pillar is that the same fitness that makes a wild animal strong in the
## ecosystem sim is what makes it good to keep, so a fitter (stronger, more
## agile) individual horse is genuinely faster to ride than an average one.
## MOUNTED_SPEED itself stays the baseline: the population's median
## fitness_score (0.5, since AnimalFitness's traits are each drawn uniformly
## in [0,1]) must still land exactly on it, so mounting an "ordinary" horse
## is unchanged from before this individual variation existed.
func test_mounted_speed_at_the_population_median_fitness_is_the_flat_baseline():
	assert_eq(Taming.mounted_speed_for(0.5), Taming.MOUNTED_SPEED)


## A fitter horse rides faster; a less fit one, slower -- real-world grounded
## in a fitter individual's own greater physical capability.
func test_mounted_speed_scales_up_for_a_fitter_horse_and_down_for_a_less_fit_one():
	assert_gt(Taming.mounted_speed_for(1.0), Taming.MOUNTED_SPEED)
	assert_lt(Taming.mounted_speed_for(0.0), Taming.MOUNTED_SPEED)


## Never rises the wrong way: there is no fitness value where a FITTER horse
## is slower than a less fit one.
func test_mounted_speed_is_monotonic_in_fitness():
	var previous := -1.0
	for step in 21:
		var speed: float = Taming.mounted_speed_for(float(step) / 20.0)
		assert_gte(speed, previous - 0.0001, "mounted speed must not fall as fitness rises")
		previous = speed


## A real, bounded range: even the least fit horse a player can actually tame
## is still genuinely worth riding over walking, and even the fittest horse in
## the world never becomes absurd -- both ends pinned against the same
## walking-speed ratio test_riding_is_faster_than_walking already uses.
func test_mounted_speed_stays_within_a_real_bounded_range():
	assert_gt(
		Taming.mounted_speed_for(0.0), Player.BASE_SPEED,
		"even a minimally-fit horse must still be worth riding"
	)
	assert_lt(
		Taming.mounted_speed_for(1.0), Player.BASE_SPEED * 3.0,
		"even a maximally-fit horse must not become absurdly fast"
	)


# -- what the player actually experiences: holding the animal ----------------
#
# The tuned quantity was the chance of breaking free on ONE attempt, which is
# not a thing anybody experiences. Attempts repeat every STRUGGLE_INTERVAL, so
# a 0.85 per-attempt chance compounded to ~99.9% escape within a few seconds
# and every horse and deer got away every time (reported: "both horses and
# deer always break free"). What matters is the chance of holding the animal
# across the WHOLE struggle, so that is what is pinned here and what the
# constants are chosen to produce.

## Shape, not rate: the authority on the real rate is
## test_the_measured_catch_rate_matches_the_model over in test_creature_marker,
## which runs sixty real animals through a real capture. hold_chance reads
## optimistic against it (see its doc comment).
func test_a_healthy_animal_can_actually_be_held_sometimes():
	var odds: float = Taming.hold_chance(1.0)
	assert_gt(odds, 0.15, "catching a full-strength horse must be possible, not a lottery")
	assert_lt(odds, 0.7, "but it should be far from a sure thing")


func test_a_worn_down_animal_is_usually_held():
	assert_gt(Taming.hold_chance(0.15), 0.6, "wearing an animal down has to pay off")


## Monotonic the right way round: a healthier animal is never easier to keep.
func test_a_healthier_animal_is_never_easier_to_hold():
	var previous := 2.0
	for step in 21:
		var odds: float = Taming.hold_chance(float(step) / 20.0)
		assert_lte(odds, previous + 0.0001, "hold odds must not rise with condition")
		previous = odds


func test_hold_chance_stays_a_probability():
	for step in 21:
		assert_between(Taming.hold_chance(float(step) / 20.0), 0.0, 1.0)


## Fighting the rope tires an animal; it does not injure it. The spec has
## always said stamina (see docs/concept/taming.md), and an animal that hurt
## itself every time it struggled would leave the player with a nearly-dead
## horse as the prize for a successful catch.
func test_a_struggling_animal_tires_rather_than_wounds_itself():
	var fatigue := 0.0
	for _i in 4:
		fatigue = Taming.fatigue_after_struggle(fatigue)
	assert_gt(fatigue, 0.0, "fighting the rope has to cost something")
	assert_lte(fatigue, 1.0)


func test_a_rested_animal_recovers_its_fight():
	var tired: float = Taming.fatigue_after_struggle(0.0)
	assert_lt(
		Taming.fatigue_after_rest(tired, Taming.FATIGUE_RECOVERY_SECONDS), tired,
		"an animal that got away and rested is not permanently broken"
	)


func test_resting_cannot_drive_fatigue_below_nothing():
	assert_gte(Taming.fatigue_after_rest(0.0, 10000.0), 0.0)


## The effective condition an animal fights at combines how healthy it is with
## how tired it already is.
func test_a_tired_animal_fights_as_though_it_were_weaker():
	assert_lt(Taming.effective_condition(1.0, 0.5), Taming.effective_condition(1.0, 0.0))
	assert_eq(Taming.effective_condition(1.0, 0.0), 1.0)


## An animal that has fought the rope to exhaustion stops fighting it. That is
## how breaking an animal actually works, and mechanically it is what makes
## the rest of taming possible: without it the animal keeps rolling the floor
## chance forever, so a horse tied to a tree while the player goes looking for
## carrots is certain to be gone when they get back.
func test_an_exhausted_animal_gives_up_rather_than_fighting_forever():
	assert_true(Taming.has_given_up(1.0))
	assert_false(Taming.has_given_up(0.5), "it is tired, not finished")


## Which makes the whole struggle a decided question rather than an open one:
## either it gets away while it still has fight in it, or it is yours.
func test_the_struggle_resolves_one_way_or_the_other():
	var fatigue := 0.0
	var struggles := 0
	while not Taming.has_given_up(fatigue) and struggles < 100:
		fatigue = Taming.fatigue_after_struggle(fatigue)
		struggles += 1
	assert_lt(struggles, 100, "the fight has to end")
