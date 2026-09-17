extends RefCounted

## Pure frame-timing math for the boot intro splash (see
## docs/concept/intro_splash.md, IntroSplashSheet, scenes/intro_splash.gd).
## A frame index is a deterministic function of elapsed real seconds --
## no state, no scene tree -- so IntroSplash (the thin Node that actually
## displays a texture) never has to reason about pacing itself, and this
## stays fully headless-testable the same way LeafLitterRenderer's own
## static timing functions are (see that file's own doc comment).

## 120 frames: the sheet is a 20-column x 6-row contact sheet (see
## IntroSplashSheet). Cross-pinned to what the sheet really yields by
## test_frame_count_matches_the_sequencer, which is what catches the art
## being replaced with a differently-shaped one -- as it was twice in one
## day (8x5 -> 20x6).
const FRAME_COUNT := 120

## The rate the sheet itself declares: every cell carries its own timestamp,
## and they run 0.00s to 4.96s in steps of 1/24 -- 24fps, five seconds.
##
## It was 10fps while the art was a hand-illustrated 40-frame sheet, chosen
## deliberately chunky so a smooth readback would not fight this game's
## 16-bit house style (docs/concept/pixel_art_engine.md). That reasoning
## does not carry over: this art is a photoreal globe rendered at 24, and
## playing it at 10 would both stutter its own rotation and stretch a
## five-second intro to twelve. Honouring the timing the art was authored
## at is the one number that cannot be wrong.
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
