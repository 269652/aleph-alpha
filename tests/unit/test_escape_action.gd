extends GutTest

## EscapeAction: what Escape does given which surfaces are open (see
## World._unhandled_input). "Close whatever is in my way, innermost first;
## only open settings when the screen is clear."

const EscapeAction = preload("res://src/ui/escape_action.gd")


func test_opens_settings_when_nothing_is_open():
	assert_eq(EscapeAction.action_for(false, false, false), EscapeAction.OPEN_SETTINGS)


func test_closes_settings_when_only_settings_is_open():
	assert_eq(EscapeAction.action_for(false, false, true), EscapeAction.CLOSE_SETTINGS)


func test_closes_a_gameplay_window_rather_than_opening_settings():
	assert_eq(EscapeAction.action_for(false, true, false), EscapeAction.CLOSE_WINDOWS)


## The console captures the keyboard, so it's the most modal surface and
## wins over everything else.
func test_console_closes_first_when_several_things_are_open():
	assert_eq(EscapeAction.action_for(true, true, true), EscapeAction.CLOSE_CONSOLE)


func test_windows_close_before_settings():
	assert_eq(EscapeAction.action_for(false, true, true), EscapeAction.CLOSE_WINDOWS)


## Escape must never both close something AND open the settings menu in one
## press -- the reported double-fire (closing the console also popped the
## paused settings menu open).
func test_never_opens_settings_while_anything_is_open():
	for console_open in [true, false]:
		for window_open in [true, false]:
			for settings_open in [true, false]:
				if not (console_open or window_open or settings_open):
					continue
				assert_ne(
					EscapeAction.action_for(console_open, window_open, settings_open),
					EscapeAction.OPEN_SETTINGS,
					"escape opened settings while something was already open (%s/%s/%s)"
						% [console_open, window_open, settings_open]
				)
