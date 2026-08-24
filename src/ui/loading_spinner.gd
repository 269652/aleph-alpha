extends RefCounted

## Which indeterminate-spinner glyph the loading overlay (see
## scenes/loading_overlay.gd) should show for how long it's been visible.
##
## Pure logic, tested (test_loading_spinner.gd) rather than eyeballed --
## CLAUDE.md: tuned values/thresholds must be tested, never an eyeballed
## comment. FRAME_INTERVAL_SECONDS is exactly that kind of tuned value.
##
## Deliberately indeterminate, not a real percentage: the loading screen this
## drives covers World's New Game / Load Game / Join stall, whose actual cost
## is EarthChunkManager.update()'s first call for a fresh chunk radius --
## fully synchronous, no `await` anywhere in its own call chain (confirmed by
## inspection), so nothing outside it can observe real interim progress
## without restructuring EarthChunkManager/TerrainRenderer internals, which is
## out of scope for a loading SCREEN (see World._show_loading_overlay).
## Real measured cost in this dev sandbox: ~39s for that single update() call
## (see docs/progress.md).

const FRAMES := ["|", "/", "-", "\\"]
const FRAME_INTERVAL_SECONDS := 0.15


static func frame_for_elapsed(elapsed_seconds: float) -> String:
	var clamped := maxf(elapsed_seconds, 0.0)
	var index := int(clamped / FRAME_INTERVAL_SECONDS) % FRAMES.size()
	return FRAMES[index]
