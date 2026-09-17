extends RefCounted

## Pure frame-timing math for the boot intro splash (see
## docs/concept/intro_splash.md, IntroSplashSheet, scenes/intro_splash.gd).
## A frame index is a deterministic function of elapsed real seconds --
## no state, no scene tree -- so IntroSplash (the thin Node that actually
## displays a texture) never has to reason about pacing itself, and this
## stays fully headless-testable the same way LeafLitterRenderer's own
## static timing functions are (see that file's own doc comment).

## 50 frames: the sheet is a 10-column x 5-row contact sheet (see
## IntroSplashSheet). Cross-pinned to what the sheet really yields by
## test_frame_count_matches_the_sequencer, and to the grid MEASURED off the
## file by test_the_frame_count_is_exactly_the_grid_the_sheet_really_has --
## the first one alone could not catch the third swap, because a wrong grid
## and a wrong count agree with each other.
##
## The art has now been replaced three times in a day (8x5 -> 20x6 -> 10x5),
## each time with a different shape.
const FRAME_COUNT := 50

## The rate the sheet itself declares: every cell carries its own timestamp,
## and on the sheet on disk they read 0.00s, 0.10s, 0.90s ... 4.80s, 4.90s
## -- a tenth of a second apart, so 10fps and five seconds.
##
## Read off the captions in the file, not assumed. It was 24fps for the
## previous sheet, whose captions really did step by 1/24 across 120 frames
## for the same five seconds; the replacement halves the frame rate and
## doubles the cell size for the same run, and leaving 24 here played the
## whole intro in just over two seconds. Honouring the timing the art was
## authored at is the one number that cannot be wrong, which is why it is
## read from the art each time rather than carried over.
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
