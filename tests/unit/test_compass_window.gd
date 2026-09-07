extends GutTest

## CompassWindow: the HUD widget itself (docs/concept/wayfinding.md's
## Compass item, in-world UI gap). Pure, headless-testable pieces only --
## needle_rotation_radians/reading_text -- the same split TorchGlow's own
## glow_intensity has from its shader: a Control's actual on-screen render
## can't be asserted headless, so the tuned mapping is a named, pinned
## function the real widget calls, not inline math scattered in _ready().

const CompassWindow = preload("res://scenes/compass_window.gd")


# -- needle_rotation_radians: a straight degrees->radians conversion, no
# sign flip -- Godot's Control.rotation is clockwise-positive in screen
# space, exactly matching Compass.bearing_degrees' own clockwise-positive
# convention, so 0 degrees (bearing dead ahead) must leave the needle
# pointing straight up, unrotated.

func test_needle_rotation_is_zero_for_a_zero_degree_reading():
	assert_almost_eq(CompassWindow.needle_rotation_radians(0.0), 0.0, 0.0001)


func test_needle_rotation_is_a_quarter_turn_for_a_ninety_degree_reading():
	assert_almost_eq(CompassWindow.needle_rotation_radians(90.0), PI / 2.0, 0.0001)


func test_needle_rotation_is_a_half_turn_for_a_one_eighty_degree_reading():
	assert_almost_eq(CompassWindow.needle_rotation_radians(180.0), PI, 0.0001)


# -- reading_text: the readout label's own text, pure formatting

func test_reading_text_reports_a_whole_degree_and_the_target():
	assert_eq(CompassWindow.reading_text(134.0), "134° to home")


func test_reading_text_rounds_to_the_nearest_whole_degree():
	assert_eq(CompassWindow.reading_text(89.6), "90° to home")


func test_reading_text_rounds_a_rough_readings_exact_forty_five_cleanly():
	# A rough compass's own reading is already snapped to a 45-degree step
	# (see Compass.rough_reading) -- confirms the label doesn't reintroduce
	# fractional noise on an already-whole number.
	assert_eq(CompassWindow.reading_text(45.0), "45° to home")
