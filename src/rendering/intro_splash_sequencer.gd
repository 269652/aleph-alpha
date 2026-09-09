extends RefCounted

## Pure frame-timing math for the boot intro splash (see
## docs/concept/intro_splash.md, IntroSplashSheet, scenes/intro_splash.gd).
## A frame index is a deterministic function of elapsed real seconds --
## no state, no scene tree -- so IntroSplash (the thin Node that actually
## displays a texture) never has to reason about pacing itself, and this
## stays fully headless-testable the same way LeafLitterRenderer's own
## static timing functions are (see that file's own doc comment).

## 45 frames: a 9-column x 5-row illustrated sheet (see IntroSplashSheet) --
## a fifth row (a pure sparkle/starburst flourish, no globe) added on top
## of the original 8x4/32-frame sheet's own layout, which also grew from
## 8 to 9 columns in the same pass (see docs/concept/intro_splash.md's
## own "A fifteenth pass" for the real, measured grid this reflects).
const FRAME_COUNT := 45

## Deliberately chunky, not smooth -- a fast 24-30fps readback would fight
## the sheet's own hand-illustrated pixel-art style (see
## docs/concept/pixel_art_engine.md: "16-bit-styled game"), the same
## "hard-edged steps, not a continuous blend" reasoning that governs every
## other pixel-art timing constant in this codebase.
const FPS := 10.0


## Which of the FRAME_COUNT frames should be showing after `elapsed_seconds`
## of real playback -- clamped to the last frame once the sequence has
## fully played out, rather than wrapping (this is a one-shot logo intro,
## never a loop).
static func frame_index_at(elapsed_seconds: float) -> int:
	return clampi(int(elapsed_seconds * FPS), 0, FRAME_COUNT - 1)


## How long the full, un-skipped sequence takes to play once through.
static func duration_seconds() -> float:
	return float(FRAME_COUNT) / FPS


## Whether the sequence has fully played out (including its own final held
## frame -- see docs/concept/intro_splash.md) by `elapsed_seconds`.
static func is_finished(elapsed_seconds: float) -> bool:
	return elapsed_seconds >= duration_seconds()
