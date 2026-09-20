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


# -- an affordance hint is wrong in planner mode, not merely covered --------

## Reported live with a screenshot: the build palette open, with "Tree",
## "Chop (Space)" and a held-item card drawn straight over it.
##
## The tempting reading is z-order -- do not draw a hint over the palette.
## But "Chop (Space)" is not a label that landed in a bad place: in planner
## mode there is no chopping, the hotbar is gone, and the key it names does
## something else. The hint is WRONG, not covered, and would still be wrong
## in an empty corner of the screen.
func test_planner_mode_advertises_no_action_it_does_not_offer():
	assert_false(ViewMode.shows_world_hints(ViewMode.Mode.PLANNER))


func test_rpg_mode_still_shows_its_own_affordances():
	assert_true(ViewMode.shows_world_hints(ViewMode.Mode.RPG))


## A hint is exactly what the hotbar is: the player's own hands. The two
## travel together, which is why the held-item card reads shows_hotbar and
## not a third predicate of its own.
func test_hints_and_the_hotbar_agree_in_both_modes():
	for mode in [ViewMode.Mode.RPG, ViewMode.Mode.PLANNER]:
		assert_eq(
			ViewMode.shows_world_hints(mode), ViewMode.shows_hotbar(mode),
			"an affordance hint belongs to the mode that offers the affordance"
		)


## Readouts are explicitly NOT swept in with the hints: they report what is
## true rather than offering an action, and the mode laying out a settlement
## is the one that most needs to know where it is.
func test_readouts_are_not_hints_and_survive_planner_mode():
	assert_true(ViewMode.shows_readouts(ViewMode.Mode.PLANNER))
	assert_ne(
		ViewMode.shows_world_hints(ViewMode.Mode.PLANNER),
		ViewMode.shows_readouts(ViewMode.Mode.PLANNER),
		"the two rules must actually differ, or one of them is redundant"
	)
