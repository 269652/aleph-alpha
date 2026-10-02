extends RefCounted

## What the Escape key should do, given which UI surfaces are currently open.
##
## Escape is "close whatever is in my way, innermost first" -- only opening
## the pause/settings menu when nothing else is open. Pure logic so the
## priority order is testable without standing up the whole World scene (see
## World._unhandled_input, which applies the returned action).
##
## Priority rationale: the dev console captures the keyboard, so it's the
## most "modal" thing on screen and closes first; then any gameplay window
## (inventory/crafting/skills, which can be open together and all close at
## once); then the settings menu itself; and only with a clear screen does
## Escape open settings.

const CLOSE_CONSOLE := "close_console"
const CLOSE_WINDOWS := "close_windows"
const CLOSE_SETTINGS := "close_settings"
const CLEAR_TARGET := "clear_target"
const OPEN_SETTINGS := "open_settings"


## `has_explicit_target` (docs/concept/spell_runtime.md, "Explicit target
## selection") slots in after settings and before the final fallback: with
## nothing else open, Escape clears a live explicit spell target before it
## ever opens Settings. Defaults to false so every pre-existing call (none
## of which knew about a target) is unaffected.
static func action_for(
	console_open: bool, any_window_open: bool, settings_open: bool, has_explicit_target: bool = false
) -> String:
	if console_open:
		return CLOSE_CONSOLE
	if any_window_open:
		return CLOSE_WINDOWS
	if settings_open:
		return CLOSE_SETTINGS
	if has_explicit_target:
		return CLEAR_TARGET
	return OPEN_SETTINGS
