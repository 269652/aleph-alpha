extends RefCounted

## Which keypresses gameplay is allowed to act on, given what is on screen.
##
## Reproduced repeatedly in a live session (see
## docs/playtests/2026-09-02-approach-and-substrate-session.md, finding 4):
## with the dev console OPEN but its `LineEdit` no longer holding keyboard
## focus -- which any alt-tab away and back will do -- every character typed
## fell through to `World._unhandled_input`. Typing `/give lasso 1` opened the
## skill tree on the `l`, `/give carrot 20` opened crafting on the `c`, and the
## `i` opened the inventory.
##
## `ConsoleFocus.is_open` already existed and `Player` already respected it to
## suppress WASD -- but the WINDOW hotkeys in `World._unhandled_input` did not
## consult it at all, because while the LineEdit holds focus it swallows the
## keys and the bug is invisible.
##
## The console re-grabbing focus (DevConsole) fixes the cause; this fixes the
## CLASS: the console is a modal text surface, so while it is open no keystroke
## is a gameplay hotkey, focused or not.
##
## Pure logic so the rule is testable without standing up the whole World
## scene, mirroring EscapeAction exactly.


## Whether a keypress should be treated as a gameplay hotkey (inventory,
## crafting, skills, hotbar) right now.
static func accepts_gameplay_hotkeys(console_open: bool) -> bool:
	return not console_open


## The console's own toggle is always live -- otherwise a console that has lost
## focus could not be closed from the keyboard at all, and this guard would be
## a soft lock rather than a fix.
static func accepts_console_toggle(_console_open: bool) -> bool:
	return true


## So is Escape, which is the other way out (see EscapeAction, whose highest
## priority is exactly "close the console").
static func accepts_escape(_console_open: bool) -> bool:
	return true


## The surfaces a keypress can name. World applies these; this module decides
## which one (if any) a given press means right now.
const SURFACE_NONE := ""
const SURFACE_CONSOLE := "console"
const SURFACE_INVENTORY := "inventory"
const SURFACE_CRAFTING := "crafting"
const SURFACE_SKILLS := "skills"
const SURFACE_SETTINGS := "settings"
const SURFACE_HOTBAR := "hotbar"

## Which input action opens which surface. The action names are World's own
## (CONSOLE_TOGGLE_ACTION and friends); kept here so the routing table is one
## thing rather than an if/elif chain inside a scene.
const ACTION_SURFACES := {
	"toggle_console": SURFACE_CONSOLE,
	"toggle_inventory": SURFACE_INVENTORY,
	"toggle_crafting": SURFACE_CRAFTING,
	"toggle_skills": SURFACE_SKILLS,
	"toggle_settings": SURFACE_SETTINGS,
}

## Which surface (if any) this action means, given what is on screen.
##
## The console's own toggle and Escape always get through -- they are the two
## ways OUT, and gating them would turn this guard into a soft lock. Everything
## else is dead while the console is open, focused or not.
static func surface_for(action_name: String, console_open: bool) -> String:
	var surface: String = ACTION_SURFACES.get(action_name, SURFACE_NONE)
	if surface == SURFACE_NONE:
		return SURFACE_NONE
	if surface == SURFACE_CONSOLE or surface == SURFACE_SETTINGS:
		return surface
	return surface if accepts_gameplay_hotkeys(console_open) else SURFACE_NONE
