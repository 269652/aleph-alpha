extends GutTest

## Open wounds (docs/concept/survival.md, "The four triggers" -> "Open wounds,
## not just HP", and docs/concept/olfaction.md's blood trail).
##
## A gash on the player and a gash on a deer are mechanically the same real
## thing, so one model answers both: how much a wound bleeds, how fast it
## clots, what it costs you to move with, and when an unbound one turns
## septic.
##
## Shaped exactly like VenomModel -- a per-stack `*_per_second` rule over the
## generic DebuffStack -- rather than as a bespoke module, per the doc.

const WoundModel = preload("res://src/gameplay/wound_model.gd")
const VenomModel = preload("res://src/gameplay/venom_model.gd")
const DebuffStack = preload("res://src/gameplay/debuff_stack.gd")


# -- the bleed ---------------------------------------------------------------


func test_an_unwounded_body_does_not_bleed():
	assert_eq(WoundModel.damage_per_second(0), 0.0)


func test_more_wounds_bleed_more():
	assert_gt(WoundModel.damage_per_second(2), WoundModel.damage_per_second(1))


func test_wounds_stack_only_so_far():
	assert_eq(
		WoundModel.damage_per_second(WoundModel.MAX_STACKS + 5),
		WoundModel.damage_per_second(WoundModel.MAX_STACKS)
	)


## A wound is the SLOW threat, venom the acute one: venom is a dose that is
## either survived or not within seconds, a gash is something you carry.
## Pinned as an ordering against the game's existing damage-over-time so the
## two cannot drift into being the same thing.
func test_a_wound_bleeds_slower_and_lasts_longer_than_venom():
	assert_lt(
		WoundModel.DAMAGE_PER_SECOND_PER_STACK,
		VenomModel.DAMAGE_PER_SECOND_PER_STACK,
		"a gash hurts as fast as snake venom"
	)
	assert_gt(
		WoundModel.DURATION_SECONDS,
		VenomModel.DURATION_SECONDS,
		"a gash clots as fast as venom wears off"
	)


## Only a real hit opens one. Every scratch leaving a bleeding wound would make
## the mechanic noise rather than a threat -- the doc's own wording is "a hit
## above a real damage threshold".
func test_a_scratch_does_not_open_a_wound():
	assert_false(WoundModel.opens_a_wound(WoundModel.MIN_DAMAGE_TO_WOUND * 0.5))


func test_a_real_blow_opens_a_wound():
	assert_true(WoundModel.opens_a_wound(WoundModel.MIN_DAMAGE_TO_WOUND))


# -- what it costs to move with ----------------------------------------------


## The reason tracking a wounded animal is worth doing: the thing at the end of
## the trail is catchable. Blood loss is a real performance cost long before it
## is fatal.
func test_a_wounded_animal_is_slower():
	assert_lt(WoundModel.speed_multiplier(1), 1.0)
	assert_lt(WoundModel.speed_multiplier(2), WoundModel.speed_multiplier(1))


func test_an_unwounded_animal_is_not_slowed():
	assert_eq(WoundModel.speed_multiplier(0), 1.0)


## Never immobilised, however badly hurt -- the same "debuffs, not death" rule
## ConditionPenalty follows for the player.
func test_a_wound_never_stops_you_dead():
	assert_gt(WoundModel.speed_multiplier(WoundModel.MAX_STACKS * 4), 0.0)


# -- and when it goes septic -------------------------------------------------


## An untreated wound is a real infection vector -- the actual mechanism behind
## wound sepsis. It has to be a DURATION, though: a wound is not infected the
## moment it is opened.
func test_a_fresh_wound_is_not_infected():
	assert_eq(WoundModel.infection_exposure(0.0), 0.0)


func test_leaving_a_wound_unbound_eventually_risks_infection():
	assert_gt(WoundModel.infection_exposure(WoundModel.SECONDS_UNTIL_SEPSIS), 0.0)


func test_the_longer_it_goes_unbound_the_worse_it_gets():
	assert_gt(
		WoundModel.infection_exposure(WoundModel.SECONDS_UNTIL_SEPSIS * 2.0),
		WoundModel.infection_exposure(WoundModel.SECONDS_UNTIL_SEPSIS)
	)


func test_infection_exposure_never_leaves_its_range():
	for seconds in [0.0, 1.0, 100.0, 100000.0]:
		assert_between(WoundModel.infection_exposure(seconds), 0.0, 1.0)


## Sepsis takes longer to arrive than the bleed takes to clot, or a wound that
## is simply left alone would always go septic and bandaging would be the only
## legal move rather than the good one.
func test_a_wound_clots_before_it_turns_septic():
	assert_lt(WoundModel.DURATION_SECONDS, WoundModel.SECONDS_UNTIL_SEPSIS)


func test_the_sickness_it_causes_is_named():
	assert_ne(WoundModel.SICKNESS_ID, "")


# -- it rides the generic stack ----------------------------------------------


## Not a bespoke module: the state lives in DebuffStack exactly as venom's
## does, so the two compose instead of being two parallel damage systems.
func test_a_wound_lives_in_the_generic_debuff_stack():
	var stack := DebuffStack.new()
	var active := stack.apply([], WoundModel.DEBUFF_ID, WoundModel.DURATION_SECONDS, WoundModel.MAX_STACKS)
	active = stack.apply(active, VenomModel.DEBUFF_ID, VenomModel.DURATION_SECONDS, VenomModel.MAX_STACKS)
	assert_eq(stack.stacks_of(active, WoundModel.DEBUFF_ID), 1)
	assert_eq(stack.stacks_of(active, VenomModel.DEBUFF_ID), 1)


func test_a_wound_clots_on_its_own_if_it_is_left_alone():
	var stack := DebuffStack.new()
	var active := stack.apply([], WoundModel.DEBUFF_ID, WoundModel.DURATION_SECONDS, WoundModel.MAX_STACKS)
	active = stack.advance(active, WoundModel.DURATION_SECONDS + 1.0)
	assert_eq(stack.stacks_of(active, WoundModel.DEBUFF_ID), 0)
