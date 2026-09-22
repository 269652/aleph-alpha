extends RefCounted

## The rear-up a predator does before it strikes (docs/concept/
## predator_profiles.md, "The tell itself").
##
## `SpeciesBite` has carried a per-species `windup_seconds` column since it
## was written -- fairness-tested, balanced against the player's own dodge,
## and COMPLETELY DEAD: a bite landed on the frame a creature crossed
## ATTACK_RANGE, so the whole fairness model was arithmetic about something
## that never happened. This is what a player finally sees.
##
## It is drawn in code rather than animated, and that is forced rather than
## lazy. The complete creature action vocabulary is walk / idle / attack /
## eat / drink / swim, and for every illustrated species `"attack"` already
## falls back to the WALK row -- an attacking boar is pixel-identical to a
## walking one. There is no rear-up frame to play and none to borrow.
##
## It is a SHAPE and not a colour, and that is forced too. A CreatureMarker
## IS its Sprite2D, and that one 24-pixel body already says three things
## through `modulate`: warm-brighter is a good coat (coat_tint_for), pale
## green is sick (SICK_MODULATE_COLOR), red is just-hit (HitFlash). A fourth
## meaning would make the body say everything and therefore nothing -- and
## the obvious hue for "about to hurt you" is the one already spoken for by
## "you just hurt it".
##
## Pure: a RefCounted of static functions. The marker owns the clock; this
## owns the shape.

## How far the body rises the instant it plants, and the instant before the
## jaws close. Both pinned by test (test_bite_tell.gd) at both ends:
##
## - the onset is above zero, because a tell that fades IN is a tell whose
##   first frames say nothing, and those are the frames a player is meant
##   to react on;
## - the peak is below half, because it is still the same animal -- a
##   creature that doubles in size is a different creature, not a warning.
##
## Between them it BUILDS, which is what gives the last quarter second -- the
## window a dodge actually has to be pressed in -- a different look from the
## first.
const ONSET_RISE := 0.10
const PEAK_RISE := 0.30

## How much of that rise goes sideways. An animal gathering itself to strike
## gets TALLER; one that swelled in both directions would read as inflating
## rather than rearing.
const WIDTH_SHARE := 0.35


## How far into the rear-up a creature with `remaining_seconds` left on a
## `total_seconds` windup is, as a fraction of its own body.
##
## Zero whenever there is nothing to show -- no windup running, or a species
## with no bite and therefore no telegraph owed -- so a caller can fold this
## in unconditionally with no branch of its own.
static func rise(remaining_seconds: float, total_seconds: float) -> float:
	if remaining_seconds <= 0.0 or total_seconds <= 0.0:
		return 0.0
	var progress := clampf(1.0 - remaining_seconds / total_seconds, 0.0, 1.0)
	return lerpf(ONSET_RISE, PEAK_RISE, progress)


## That rise as a multiplier on the creature's own scale -- exactly
## Vector2.ONE when nothing is coming, so the caller never needs to restore
## anything.
static func scale_multiplier(remaining_seconds: float, total_seconds: float) -> Vector2:
	var height := rise(remaining_seconds, total_seconds)
	return Vector2(1.0 + height * WIDTH_SHARE, 1.0 + height)
