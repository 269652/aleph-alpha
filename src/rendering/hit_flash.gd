extends RefCounted

## What a creature looks like for the instant after a blow lands on it
## (docs/concept/feedback.md, "Being hurt is a verb too").
##
## Measured before this existed: `grep -rni "hit_flash|damage_flash|
## flash_timer|FLASH_DURATION"` over `src/`, `scenes/` and `tests/` returned
## ZERO hits. The feedback doc's own opening diagnosis -- "grep for a hit
## flash, a damage number, a floating text node or a level-up toast anywhere
## under scenes/ or src/ returns nothing" -- was still true of the flash
## months later. `CreatureMarker.take_damage`'s one visual call,
## `_begin_one_shot("hurt")`, is a guaranteed no-op for every species
## shipping today, because no illustrated sheet carries a "hurt" row.
##
## Pure: a RefCounted of static functions. The marker owns the clock and the
## `modulate` it writes; this owns the rule.
##
## The hard part is NOT the flash. A `CreatureMarker` IS the `Sprite2D`, and
## its `modulate` already has two owners -- the one-shot coat tint written
## in `_ready`, and the disease tint rewritten every stepped frame for
## anything not SUSCEPTIBLE. So this COMPOSES: it takes whatever the body
## would be wearing and leans it, rather than replacing it and restoring a
## guess afterwards.

const Answerback = preload("res://src/gameplay/answerback.gd")

## How long a struck body stays lit.
##
## The same reflex floor the player's own hurt answer is gated at
## (Answerback.REFLEX_INTERVAL_SECONDS, one real walking stride): shorter
## than a footfall is a flicker nobody registers, and longer would merge two
## blows into one on anything that can be hit twice in quick succession. The
## two halves of an exchange read on one clock, which is the point.
const SECONDS := Answerback.REFLEX_INTERVAL_SECONDS

## How far toward the flash colour a struck body goes at the instant of the
## blow. Deliberately NOT all the way, and pinned by test at both ends:
##
## - below 1.0, because a creature repainted flat red loses its silhouette,
##   its coat tell and its disease pallor in the same frame, and a player
##   who cannot tell WHICH animal they just hit has been handed a worse
##   picture rather than a better one;
## - above 0.0, because a flash nobody can see is the silence this whole
##   mechanism exists to remove.
const PEAK_BLEND := 0.65


## The colour a struck body leans toward: not this module's own opinion, but
## the one the feedback table already hands the number that floats off the
## very same blow, so the animal and the receipt agree.
static func colour() -> Color:
	return Answerback.flash_color_for(Answerback.FLASH_HIT)


## The tint a creature wears with `remaining_seconds` left on its flash,
## over `base` -- whatever it would be wearing otherwise: its own coat, or
## its disease pallor.
##
## Exactly `base` once the flash has run out, so a caller can write this
## unconditionally and never has to remember what to restore.
static func tint(base: Color, remaining_seconds: float) -> Color:
	if remaining_seconds <= 0.0:
		return base
	var strength := clampf(remaining_seconds / SECONDS, 0.0, 1.0) * PEAK_BLEND
	return base.lerp(colour(), strength)
