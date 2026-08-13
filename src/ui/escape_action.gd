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
const OPEN_SETTINGS := "open_settings"


static func action_for(console_open: bool, any_window_open: bool, settings_open: bool) -> String:
	if console_open:
		return CLOSE_CONSOLE
	if any_window_open:
		return CLOSE_WINDOWS
	if settings_open:
		return CLOSE_SETTINGS
	return OPEN_SETTINGS
