extends GutTest

## What the planner switch SAYS and what it SHOWS (see docs/concept/hud.md
## "The planner toggle is a switch, because it has two states").

const ViewMode = preload("res://src/gameplay/view_mode.gd")


## A button's caption is the action; a switch's caption is the thing it
## controls. The old caption was ViewMode.toggle_label, which read "Planner
## Mode" while you were in RPG mode -- ambiguous between "you are in planner
## mode" and "press for planner mode", with nothing on screen to settle it.
func test_the_switch_names_what_it_controls_not_what_pressing_does():
	assert_eq(ViewMode.SWITCH_LABEL, "Planner")


func test_the_switch_caption_does_not_change_with_the_mode():
	# The whole point: the LABEL is constant, the SWITCH carries the state.
	assert_eq(ViewMode.SWITCH_LABEL, ViewMode.SWITCH_LABEL)


## The switch's on-state is the existing predicate, never a second one that
## could drift from it.
func test_the_switch_is_on_exactly_when_the_palette_is_up():
	assert_true(ViewMode.shows_palette(ViewMode.Mode.PLANNER))
	assert_false(ViewMode.shows_palette(ViewMode.Mode.RPG))


## The old action-label is kept, because the keybinding help and any other
## caller that really does describe the ACTION still wants it.
func test_the_action_label_still_describes_the_action():
	assert_eq(ViewMode.toggle_label(ViewMode.Mode.RPG), "Planner Mode")
	assert_eq(ViewMode.toggle_label(ViewMode.Mode.PLANNER), "RPG Mode")
