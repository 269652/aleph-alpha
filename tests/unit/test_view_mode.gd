extends GutTest

## The two view modes and what each one puts on screen (see ViewMode,
## docs/concept/planner_mode.md). Asked directly: "a view toggle to the top
## besides the minimap which toggles RPG Mode (hotbar) with a Planner mode".
##
## Pure: no World, no HUD nodes, so every branch is reachable headlessly --
## the same "pure model, thin Node" split AudioSettings and EscapeAction
## already use.

const ViewMode = preload("res://src/gameplay/view_mode.gd")


func test_the_game_starts_in_rpg_mode():
	assert_eq(ViewMode.DEFAULT, ViewMode.Mode.RPG, "planner mode is something the player opts into")


func test_toggling_swaps_the_two_modes_and_nothing_else():
	assert_eq(ViewMode.toggled(ViewMode.Mode.RPG), ViewMode.Mode.PLANNER)
	assert_eq(ViewMode.toggled(ViewMode.Mode.PLANNER), ViewMode.Mode.RPG)


## The hotbar IS rpg mode's controls and the palette IS the planner's, so
## they are never both up: two competing click targets over the same world
## is exactly the confusion the toggle exists to remove.
func test_the_hotbar_and_the_palette_are_never_both_shown():
	for mode in [ViewMode.Mode.RPG, ViewMode.Mode.PLANNER]:
		assert_ne(
			ViewMode.shows_hotbar(mode), ViewMode.shows_palette(mode),
			"exactly one set of controls belongs to each mode"
		)


func test_rpg_mode_shows_the_hotbar():
	assert_true(ViewMode.shows_hotbar(ViewMode.Mode.RPG))
	assert_false(ViewMode.shows_palette(ViewMode.Mode.RPG))


func test_planner_mode_shows_the_palette():
	assert_true(ViewMode.shows_palette(ViewMode.Mode.PLANNER))
	assert_false(ViewMode.shows_hotbar(ViewMode.Mode.PLANNER))


## Pillar 4: the toggle changes what the player COMMANDS, never what the
## world DOES. Unlike the settings overlay, which really does pause the
## tree, planner mode leaves time, creatures and weather running -- you are
## laying out a place that is still alive around you.
func test_neither_mode_pauses_the_world():
	for mode in [ViewMode.Mode.RPG, ViewMode.Mode.PLANNER]:
		assert_false(ViewMode.pauses_world(mode), "planning is not a pause screen")


## The build cursor is the planner's whole point, and must not be live in
## rpg mode -- a stray click while swinging a sword must never plan a house.
func test_only_planner_mode_arms_the_build_cursor():
	assert_true(ViewMode.arms_build_cursor(ViewMode.Mode.PLANNER))
	assert_false(ViewMode.arms_build_cursor(ViewMode.Mode.RPG))


## Readouts belong to the player, not to a mode: the minimap is how you
## know where you are while laying something out, so hiding it in the mode
## that needs it most would be perverse.
func test_the_minimap_and_the_meters_survive_both_modes():
	for mode in [ViewMode.Mode.RPG, ViewMode.Mode.PLANNER]:
		assert_true(ViewMode.shows_readouts(mode), "readouts are not controls")


func test_the_label_names_the_mode_the_button_would_switch_to():
	assert_string_contains(ViewMode.toggle_label(ViewMode.Mode.RPG).to_lower(), "planner")
	assert_string_contains(ViewMode.toggle_label(ViewMode.Mode.PLANNER).to_lower(), "rpg")
