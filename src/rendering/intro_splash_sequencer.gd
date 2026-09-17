extends RefCounted

## Pure frame-timing math for the boot intro splash (see
## docs/concept/intro_splash.md, IntroSplashSheet, scenes/intro_splash.gd).
## A frame index is a deterministic function of elapsed real seconds --
## no state, no scene tree -- so IntroSplash (the thin Node that actually
## displays a texture) never has to reason about pacing itself, and this
## stays fully headless-testable the same way LeafLitterRenderer's own
## static timing functions are (see that file's own doc comment).

## 120 frames: a 20-column x 6-row contact sheet (see IntroSplashSheet).
## Pinned against the sheet's own real grid by
## test_the_sheets_real_grid_is_the_one_the_slicing_assumes, so the two can
## never silently disagree about how many frames exist -- which is exactly
## what the previous art swap left behind (40 here against 120 on the
## sheet, so two thirds of the animation simply never played).
const FRAME_COUNT := 120

## The sheet STATES its own frame rate, so this is read off the art rather
## than chosen: every cell carries its own timestamp burned in by the
## export, running 0.00s, 0.04s, 0.08s ... 4.96s -- steps of 1/24 s across
## all 120 cells, i.e. 24fps and a 5.0s sequence.
##
## This replaces a deliberately chunky 10.0, whose reasoning was that a
## fast readback would fight a hand-illustrated PIXEL-ART sheet (see
## docs/concept/pixel_art_engine.md). That reasoning was sound for the art
## it was written against and simply does not apply to this one: the
## replacement is a rendered 24fps animation of a rotating globe, not
## pixel art, and playing its 120 frames at 10fps would stretch a 5-second
## intro to 12 seconds.
const FPS := 24.0


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
