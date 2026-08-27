extends RefCounted

## Which spinner glyph the loading overlay (see scenes/loading_overlay.gd)
## should show for how long it's been visible.
##
## Pure logic, tested (test_loading_spinner.gd) rather than eyeballed --
## CLAUDE.md: tuned values/thresholds must be tested, never an eyeballed
## comment. FRAME_INTERVAL_SECONDS is exactly that kind of tuned value.
##
## This glyph alone is still indeterminate (no built-in concept of "percent
## done") -- but the loading screen it drives is no longer stuck showing
## ONLY this: EarthChunkManager.update_with_progress (see its own doc
## comment) now yields a frame between each chunk it loads, so
## LoadingOverlay.set_progress can show a REAL "N / M chunks" count
## alongside this spinner, and this glyph can now actually be seen to
## animate across that whole stretch instead of freezing on one frame for
## the entire real duration -- the old design's honest limit (see
## docs/concept/persistence.md's "Loading screens" section for the full
## history of both passes; the plain `EarthChunkManager.update()` most
## callers still use is unchanged and remains fully synchronous).

const FRAMES := ["|", "/", "-", "\\"]
const FRAME_INTERVAL_SECONDS := 0.15


static func frame_for_elapsed(elapsed_seconds: float) -> String:
	var clamped := maxf(elapsed_seconds, 0.0)
	var index := int(clamped / FRAME_INTERVAL_SECONDS) % FRAMES.size()
	return FRAMES[index]
