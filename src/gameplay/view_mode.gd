extends RefCounted

## The two views of the same world, and what each one puts on screen -- see
## docs/concept/planner_mode.md.
##
## RPG mode is the game as it has always been: a character, a hotbar,
## things picked up and swung. PLANNER mode lifts the player out of their
## own hands and lets them lay out what the place should become, Anno-style
## -- pavement here, a house there -- without building any of it.
##
## Pure, and deliberately so: the mode decides what the HUD shows, so
## making that a function of the mode rather than a pile of `visible =`
## assignments scattered through World is what lets it be tested at all.
## The same "pure model, thin Node" split AudioSettings, EscapeAction and
## NatureSoundscape already use.
##
## Nothing here knows about a Button, a hotbar slot, or a CanvasLayer;
## World reads these answers and does the showing.

enum Mode { RPG, PLANNER }

## The game opens in the mode it has always had. Planner mode is something
## the player deliberately switches into, never where they land.
const DEFAULT := Mode.RPG


## The other mode. A toggle rather than a cycle -- there are two, and a
## player pressing the button wants the other one, not the next one.
static func toggled(mode: int) -> int:
	return Mode.RPG if mode == Mode.PLANNER else Mode.PLANNER


## The hotbar IS rpg mode's controls, and the palette IS the planner's.
## They are never both up (pinned by
## test_the_hotbar_and_the_palette_are_never_both_shown): two competing
## click targets over the same world is the exact confusion this toggle
## exists to remove.
static func shows_hotbar(mode: int) -> bool:
	return mode == Mode.RPG


static func shows_palette(mode: int) -> bool:
	return mode == Mode.PLANNER


## Readouts -- the minimap, the meters, the message stack -- belong to the
## player rather than to a mode. The minimap is how you know where you are
## while laying something out, so hiding it in the mode that needs it most
## would be perverse.
static func shows_readouts(_mode: int) -> bool:
	return true


## Whether the world's own affordance HINTS -- the "Talk (G)"/"Chop (Space)"
## prompt, the hover tooltip, the charge meter -- may be drawn.
##
## Reported live with a screenshot: the build palette open, with "Tree",
## "Chop (Space)" and a held-item card drawn straight over it. The tempting
## reading is z-order, but "Chop (Space)" is not a label that landed in a bad
## place: in planner mode there is no chopping, the hotbar is gone, and the
## key it names does something else. The hint is WRONG, not covered, and
## would still be wrong drawn in an empty corner of the screen.
##
## So this tracks shows_hotbar exactly (pinned by
## test_hints_and_the_hotbar_agree_in_both_modes): a hint advertises an
## action, and the player's hands are where those actions live. Readouts are
## deliberately NOT swept in -- see shows_readouts above, which stays true in
## both modes because it reports what is TRUE rather than offering an action.
static func shows_world_hints(mode: int) -> bool:
	return mode == Mode.RPG


## Whether a click on the world plants a blueprint. False in rpg mode on
## purpose: a stray click while swinging a sword must never plan a house.
static func arms_build_cursor(mode: int) -> bool:
	return mode == Mode.PLANNER


## Neither mode pauses anything (docs/concept/planner_mode.md's pillar 4).
## The toggle changes what the player COMMANDS, never what the world DOES
## -- unlike the settings overlay, which really does set
## `get_tree().paused` (see docs/concept/hud.md). You lay a settlement out
## while it is still alive around you: time runs, creatures walk, weather
## turns.
##
## Stated as a function returning a constant rather than left unwritten so
## the claim is pinned by a test (test_neither_mode_pauses_the_world)
## instead of living only in a comment -- a later "planner mode should
## pause" change then has to argue with a red test and this doc, which is
## the point.
static func pauses_world(_mode: int) -> bool:
	return false


## What the toggle button says. Names the mode it would switch TO, not the
## one you are in: a button is a thing you press to get somewhere, and
## labelling it with where you already are is the classic ambiguity.
## What the planner SWITCH is captioned (see docs/concept/hud.md "The planner
## toggle is a switch"). Constant, unlike toggle_label below: a switch shows
## what IS, so its caption names the thing it controls and the switch itself
## carries the state. The old caption read "Planner Mode" while you were in
## RPG mode, which a player could read either way and nothing on screen
## settled.
const SWITCH_LABEL := "Planner"


## What a BUTTON that flips the mode should be captioned -- the mode you get
## by pressing it. Kept for callers that really do describe the action (the
## key-binding row still does); the HUD switch uses SWITCH_LABEL instead.
static func toggle_label(mode: int) -> String:
	return "Planner Mode" if mode == Mode.RPG else "RPG Mode"
