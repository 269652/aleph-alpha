extends RefCounted

## The red the screen goes when something lands on the character
## (docs/concept/feedback.md, "Being hurt is a verb too").
##
## Measured before this: `World._on_player_answered` read a feedback row's
## `message` and its `float_text` and threw the `flash` field away entirely
## -- the table told it three things about every act and it drew two. So
## nothing in this game had ever flashed, which is exactly what that doc's
## own diagnosis said when it grepped for a hit flash and found none.
##
## Pure: a RefCounted of static functions over two pinned constants. World
## owns the ColorRect and the tween; this owns the rule.

const UiTheme = preload("res://src/ui/ui_theme.gd")
const Answerback = preload("res://src/gameplay/answerback.gd")

## How long the screen holds it.
##
## NOT a chosen duration: exactly the interval the hurt answer is itself
## gated at, so a flash is always gone before the next blow can raise
## another and two can never stack into a solid wall of red. The gate is in
## turn the reflex floor, which is provably faster than the fastest bite in
## the game (see Answerback.HURT), so nothing is ever lost to it either.
const SECONDS := Answerback.REFLEX_INTERVAL_SECONDS

## What a blow that took the WHOLE health bar looks like, and what a scratch
## looks like. Both pinned by test rather than eyeballed
## (test_hurt_flash.gd), at both ends and for the reason each end exists:
##
## - the peak stays under half, because the animal biting you is on the same
##   screen and a flash that hides it turns feedback into a handicap;
## - the faintest is above zero, because a flash nobody can see is the
##   silence this whole mechanism was built to remove.
##
## Between them it reads as a scale rather than a binary: how much of you
## that just took.
const FAINTEST_ALPHA := 0.12
const PEAK_ALPHA := 0.45


## Whether this answer is about harm landing on the PLAYER, and therefore
## the one thing in the table the whole screen answers for.
##
## Four rows carry FLASH_HIT -- attack, kick, destroy, cast -- and three of
## them are harm the player DEALT. A screen that goes red when you chop a
## tree teaches a player that red means nothing, which is worse than no
## flash at all.
static func flashes_for(action_id: String) -> bool:
	return action_id == Answerback.HURT


## The colour at the instant the blow lands, from what fraction of the whole
## health bar it cost. The fade to nothing belongs to the caller's tween.
##
## The hue is never this module's own: `UiTheme.NEGATIVE` is the warm red
## every other negative reading in this UI already uses
## (docs/concept/hud.md's warm-gold/red good-bad pair), so a hurt here and a
## loss there are one decision.
static func peak_colour_for(damage_fraction: float) -> Color:
	var strength := clampf(damage_fraction, 0.0, 1.0)
	var colour := UiTheme.NEGATIVE
	colour.a = lerpf(FAINTEST_ALPHA, PEAK_ALPHA, strength)
	return colour
