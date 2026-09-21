extends GutTest

## docs/concept/feedback.md: the `flash` field of a feedback row, which
## `World._on_player_answered` read and threw away -- it drew the line and
## the floating number and ignored the third thing the table told it.
##
## This is the screen's own answer to a blow landing on the character, and
## it is deliberately the ONLY thing in the table that tints the whole
## screen: every other FLASH_HIT row (attack, kick, destroy, cast) is harm
## the player DEALT, and a screen that goes red when you chop a tree teaches
## a player that red means nothing.

const HurtFlash = preload("res://src/ui/hurt_flash.gd")
const Answerback = preload("res://src/gameplay/answerback.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")


# -- only harm to the player tints the screen -----------------------------

func test_being_hurt_flashes_the_screen():
	assert_true(HurtFlash.flashes_for(Answerback.HURT))


## The trap this module exists to avoid. Four rows in the table carry
## FLASH_HIT and only one of them is about the player.
func test_harm_the_player_deals_does_not_flash_the_screen():
	for action in ["attack", "kick", "destroy", "cast"]:
		assert_false(
			HurtFlash.flashes_for(action),
			"%s is harm the player DEALT -- the screen is not what was hit" % action
		)


func test_nothing_else_flashes_the_screen_either():
	for action in Answerback.answered_actions():
		if action == Answerback.HURT:
			continue
		assert_false(HurtFlash.flashes_for(action), "%s must not tint the screen" % action)


# -- how red, and for how long --------------------------------------------

## The colour is not this module's own: it is the same warm red every other
## negative reading in this UI uses (docs/concept/hud.md's good/bad pair).
func test_the_red_is_the_uis_own_negative():
	var colour: Color = HurtFlash.peak_colour_for(1.0)
	assert_almost_eq(colour.r, UiTheme.NEGATIVE.r, 0.0001)
	assert_almost_eq(colour.g, UiTheme.NEGATIVE.g, 0.0001)
	assert_almost_eq(colour.b, UiTheme.NEGATIVE.b, 0.0001)


## A harder blow is a harder flash. The fraction is of the WHOLE health
## bar, so the scale means something a player can read: this is how much of
## you that just took.
func test_a_harder_blow_flashes_harder():
	assert_gt(HurtFlash.peak_colour_for(0.5).a, HurtFlash.peak_colour_for(0.1).a)


func test_a_blow_that_empties_the_bar_is_the_strongest_it_ever_gets():
	assert_almost_eq(HurtFlash.peak_colour_for(1.0).a, HurtFlash.PEAK_ALPHA, 0.0001)
	assert_almost_eq(HurtFlash.peak_colour_for(9.0).a, HurtFlash.PEAK_ALPHA, 0.0001)


## And a scratch still registers. A flash a player cannot see is the same
## silence this whole doc exists to remove.
func test_the_faintest_scratch_still_shows():
	assert_almost_eq(HurtFlash.peak_colour_for(0.0).a, HurtFlash.FAINTEST_ALPHA, 0.0001)
	assert_gt(HurtFlash.FAINTEST_ALPHA, 0.0, "a flash nobody can see is silence")


## You must still be able to see the animal that is biting you. A flash
## that hides it turns feedback into a handicap.
func test_even_a_killing_blow_leaves_the_screen_readable():
	assert_lt(HurtFlash.PEAK_ALPHA, 0.5, "the world stays visible through it")
	assert_gt(HurtFlash.PEAK_ALPHA, HurtFlash.FAINTEST_ALPHA)


## One flash is always gone before the next blow can raise another, so two
## can never stack into a solid wall of red. Not a chosen duration: the
## interval the hurt answer is itself gated at.
func test_a_flash_is_over_before_the_next_blow_can_answer():
	assert_almost_eq(
		HurtFlash.SECONDS, Answerback.interval_for(Answerback.HURT), 0.0001
	)
