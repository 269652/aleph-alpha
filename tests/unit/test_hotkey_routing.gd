extends GutTest

## Which keypresses gameplay is allowed to act on, given what is on screen.
##
## Reproduced repeatedly in a live session
## (docs/playtests/2026-09-02-approach-and-substrate-session.md, finding 4):
## with the console OPEN but its `LineEdit` no longer holding keyboard focus --
## which any alt-tab away and back will do -- every character typed fell
## through to `World._unhandled_input`. Typing `/give lasso 1` opened the skill
## tree on the `l`, `/give carrot 20` opened crafting on the `c`, and the `i`
## opened the inventory.
##
## Two things were wrong and this is the one that makes the whole CLASS of bug
## impossible: the console is a modal text surface, so while it is open no
## keystroke is a gameplay hotkey, focused or not. Pure logic so the rule is
## testable without standing up World, mirroring EscapeAction exactly.

const HotkeyRouting = preload("res://src/ui/hotkey_routing.gd")


func test_an_ordinary_keypress_is_a_gameplay_hotkey():
	assert_true(HotkeyRouting.accepts_gameplay_hotkeys(false))


## The bug, stated as a rule.
func test_nothing_typed_at_an_open_console_is_a_gameplay_hotkey():
	assert_false(HotkeyRouting.accepts_gameplay_hotkeys(true))


## The console's own toggle still works while it is open, or it could never be
## closed from the keyboard -- which would turn this guard into a soft lock.
func test_the_console_can_always_be_closed_again():
	assert_true(HotkeyRouting.accepts_console_toggle(true))
	assert_true(HotkeyRouting.accepts_console_toggle(false))


## ...and so does Escape, which is the other way out (see EscapeAction, whose
## first priority is exactly this).
func test_escape_always_gets_through():
	assert_true(HotkeyRouting.accepts_escape(true))
	assert_true(HotkeyRouting.accepts_escape(false))


# -- the dispatch itself -----------------------------------------------------
# World._unhandled_input becomes a thin applier of this, the same way it
# already is for EscapeAction -- which is what makes the routing testable at
# all rather than living inside an if/elif chain in a scene.


const CONSOLE := "toggle_console"
const INVENTORY := "toggle_inventory"


func test_a_hotkey_names_the_surface_it_opens():
	assert_eq(HotkeyRouting.surface_for(INVENTORY, false), HotkeyRouting.SURFACE_INVENTORY)


func test_the_console_key_opens_the_console():
	assert_eq(HotkeyRouting.surface_for(CONSOLE, false), HotkeyRouting.SURFACE_CONSOLE)


## The bug: with the console open, a window hotkey names NOTHING.
func test_a_window_hotkey_is_dead_while_the_console_is_open():
	assert_eq(HotkeyRouting.surface_for(INVENTORY, true), HotkeyRouting.SURFACE_NONE)


## ...but the console key still closes it, or the guard is a soft lock.
func test_the_console_key_still_works_while_the_console_is_open():
	assert_eq(HotkeyRouting.surface_for(CONSOLE, true), HotkeyRouting.SURFACE_CONSOLE)


func test_an_unknown_action_names_nothing():
	assert_eq(HotkeyRouting.surface_for("wander_off", false), HotkeyRouting.SURFACE_NONE)


## Every surface the router can name has to be one World actually knows how to
## open -- a typo here would be a key that silently does nothing.
func test_every_named_surface_is_a_real_one():
	var known := [
		HotkeyRouting.SURFACE_NONE,
		HotkeyRouting.SURFACE_CONSOLE,
		HotkeyRouting.SURFACE_INVENTORY,
		HotkeyRouting.SURFACE_CRAFTING,
		HotkeyRouting.SURFACE_SKILLS,
		HotkeyRouting.SURFACE_SETTINGS,
		HotkeyRouting.SURFACE_HOTBAR,
	]
	for action in HotkeyRouting.ACTION_SURFACES.values():
		assert_true(known.has(action), "%s is not a surface World can open" % action)
