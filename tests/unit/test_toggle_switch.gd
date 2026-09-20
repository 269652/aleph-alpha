extends GutTest

## The iOS-style two-state switch (see docs/concept/hud.md "The planner toggle
## is a switch, because it has two states").
##
## Geometry and colour only -- the parts that can be silently wrong. The slide
## animation is deliberately untested: what matters is where the knob comes to
## REST, not how it gets there.

const ToggleSwitch = preload("res://src/ui/toggle_switch.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")


func _knob_x(on: bool) -> float:
	return ToggleSwitch.knob_x_for(
		on, ToggleSwitch.TRACK_SIZE.x, ToggleSwitch.KNOB_DIAMETER, ToggleSwitch.KNOB_PADDING
	)


## The classic off-by-a-padding bug: a knob that overhangs the track at one
## end, which only shows in one of the two states.
func test_the_knob_sits_fully_inside_the_track_when_off():
	assert_gte(_knob_x(false), 0.0)
	assert_lte(_knob_x(false) + ToggleSwitch.KNOB_DIAMETER, ToggleSwitch.TRACK_SIZE.x)


func test_the_knob_sits_fully_inside_the_track_when_on():
	assert_gte(_knob_x(true), 0.0)
	assert_lte(_knob_x(true) + ToggleSwitch.KNOB_DIAMETER, ToggleSwitch.TRACK_SIZE.x)


func test_turning_it_on_moves_the_knob_to_the_other_end():
	assert_gt(_knob_x(true), _knob_x(false), "on must sit to the right of off")


## Symmetric: the gap left of the knob when off equals the gap right of it
## when on. Neither end is special.
func test_the_two_rest_positions_are_symmetric():
	var left_gap := _knob_x(false)
	var right_gap := ToggleSwitch.TRACK_SIZE.x - (_knob_x(true) + ToggleSwitch.KNOB_DIAMETER)
	assert_almost_eq(left_gap, right_gap, 0.0001)


func test_the_travel_is_the_track_less_the_knob_and_both_paddings():
	assert_almost_eq(
		_knob_x(true) - _knob_x(false),
		ToggleSwitch.TRACK_SIZE.x - ToggleSwitch.KNOB_DIAMETER - 2.0 * ToggleSwitch.KNOB_PADDING,
		0.0001
	)


## A pill, not a small rounded button -- that shape is what makes it read as
## a switch at all.
func test_the_track_is_a_pill():
	assert_almost_eq(
		ToggleSwitch.track_corner_radius(), ToggleSwitch.TRACK_SIZE.y / 2.0, 0.0001
	)


## The knob has to fit the track's height with room to spare on both sides.
func test_the_knob_is_shorter_than_the_track_it_slides_in():
	assert_lt(ToggleSwitch.KNOB_DIAMETER, ToggleSwitch.TRACK_SIZE.y)


## The theme's own existing on/off pair, not a third palette invented here.
func test_on_is_the_themes_accent():
	assert_eq(ToggleSwitch.track_color_for(true), UiTheme.ACCENT)


func test_off_is_the_themes_plain_button_colour():
	assert_eq(ToggleSwitch.track_color_for(false), UiTheme.BUTTON_NORMAL)


## A switch whose two states look alike is not a switch.
func test_the_two_states_are_visibly_different():
	assert_gt(
		absf(ToggleSwitch.track_color_for(true).v - ToggleSwitch.track_color_for(false).v),
		0.25,
		"on and off must differ in luminance, not just in hue"
	)


## The knob reads against both track colours, so it is the one part that does
## not change with the state.
func test_the_knob_looks_the_same_in_both_states():
	assert_eq(ToggleSwitch.knob_color_for(true), ToggleSwitch.knob_color_for(false))


## A container stretches its children to the row's height by default, and a
## stretched track is no longer a pill: the radius is half of TRACK_SIZE.y,
## so a taller track turns the semicircular ends into merely-rounded corners.
## Caught in a render (tools/probe_hud_layout.gd), invisible to every
## geometry test above, which all measure the CONSTANTS rather than the node.
func test_the_switch_keeps_its_own_height_inside_a_row():
	var switch = ToggleSwitch.new()
	autofree(switch)
	assert_eq(
		switch.size_flags_vertical, Control.SIZE_SHRINK_CENTER,
		"a stretched track stops being a pill"
	)
	assert_eq(switch.custom_minimum_size, ToggleSwitch.TRACK_SIZE)
