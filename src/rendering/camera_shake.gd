extends RefCounted

## The camera's own answer to a blow the player just landed (docs/concept/
## feedback.md's shape, extended: HitFlash/HurtFlash answer "something was
## hit"/"you were hit", this answers "you hit something HARD"). Pure: a
## RefCounted of static functions over pinned game-feel constants --
## Player owns the Camera2D and the per-frame clock (scenes/player.gd's
## own `_shake_elapsed_seconds`/`_shake_severity`), this owns the rule.
## Mirrors HitFlash's exact split (`tint(base, remaining_seconds,
## severity)`), just keyed by elapsed time instead of remaining, since a
## camera offset composes to Vector2.ZERO rather than onto a base colour.
##
## SECONDS/PEAK_OFFSET_PX are a game-feel choice, not a derived invariant
## (nothing about "should a hard hit shake the camera 6px for 0.35s" is
## objectively provable the way CombatPacing's "must land two bites" is) --
## the same untested-constant precedent SpellEffectMarker's own GROW_
## DURATION/HOLD_DURATION/FADE_DURATION already set. What IS tested here is
## the pure function itself: deterministic, decaying, severity-scaled,
## never spilling past its own duration (test_camera_shake.gd).

## How long a shake takes to decay to nothing.
const SECONDS := 0.35

## The camera's offset in pixels for a full-severity (1.0) shake, at the
## instant it lands.
const PEAK_OFFSET_PX := 6.0

## The x/y jitter's own frequencies against elapsed time -- two different,
## non-harmonic values so the shake reads as a jolt rather than a clean
## circular wobble. Deterministic in elapsed time, not seeded randomness,
## so the same inputs always reproduce the same offset (no RNG to stub in
## a test).
const _FREQUENCY_X := 47.0
const _FREQUENCY_Y := 61.0
const _PHASE_Y := 1.7


## The camera offset `elapsed_seconds` into a shake that landed at
## `severity` (0..1, how hard the blow hit -- 1.0 the hardest this cast
## type can register) -- decaying linearly to Vector2.ZERO by SECONDS.
## Exactly ZERO once `elapsed_seconds` is outside [0, SECONDS) or severity
## is non-positive, so a caller can write this unconditionally every frame
## without a separate "is a shake even active" check.
static func offset_at(elapsed_seconds: float, severity: float) -> Vector2:
	if elapsed_seconds < 0.0 or elapsed_seconds >= SECONDS or severity <= 0.0:
		return Vector2.ZERO
	var decay := 1.0 - elapsed_seconds / SECONDS
	var magnitude := PEAK_OFFSET_PX * clampf(severity, 0.0, 1.0) * decay
	return Vector2(
		sin(elapsed_seconds * _FREQUENCY_X) * magnitude,
		sin(elapsed_seconds * _FREQUENCY_Y + _PHASE_Y) * magnitude
	)
