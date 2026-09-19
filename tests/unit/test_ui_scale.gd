extends GutTest

## The UI scale setting (see docs/concept/hud.md "UI scale"): every font size
## in the HUD used to be a hardcoded override between 9 and 28, chosen against
## one developer's monitor.
##
## Same shape as the settings models beside it -- AudioSettings.sanitize_volume
## and SimulationSettings.sanitize_density: a float, sanitised, with the
## default being exactly today's behaviour.

const UiScale = preload("res://src/ui/ui_scale.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")


## The default is 1.0 and 1.0 is a no-op, so a player who never touches the
## slider sees precisely the HUD that shipped.
func test_the_default_scale_changes_nothing():
	assert_eq(UiScale.DEFAULT_SCALE, 1.0)
	assert_eq(UiScale.font_size(14, UiScale.DEFAULT_SCALE), 14)


func test_a_bigger_scale_makes_a_bigger_font():
	assert_eq(UiScale.font_size(14, 1.5), 21)


func test_a_smaller_scale_makes_a_smaller_font():
	assert_eq(UiScale.font_size(20, 0.75), 15)


## A fractional result is rounded, not truncated -- 9 * 1.25 is 11.25, and a
## floor would quietly lose a sixth of the smallest label in the HUD.
func test_a_fractional_size_rounds_rather_than_truncates():
	assert_eq(UiScale.font_size(9, 1.25), 11)


## The smallest label in the HUD today is 9pt. At the smallest scale it must
## still be a readable size rather than rounding toward nothing -- a label
## scaled to 0 is an invisible label, which is worse than a small one.
func test_the_smallest_scale_never_rounds_a_label_away():
	var smallest := UiScale.font_size(9, UiScale.MIN_SCALE)
	assert_gte(smallest, UiScale.MIN_FONT_SIZE)
	assert_gte(UiScale.MIN_FONT_SIZE, 6, "a font this small is already illegible")


func test_a_scale_below_the_floor_clamps_to_it():
	assert_eq(UiScale.sanitize(0.1), UiScale.MIN_SCALE)


func test_a_scale_above_the_ceiling_clamps_to_it():
	assert_eq(UiScale.sanitize(9.0), UiScale.MAX_SCALE)


## The same NaN fallback AudioSettings.sanitize_volume makes: an unreadable
## settings file reads as the default, never as a zero-size HUD.
func test_an_unreadable_setting_falls_back_to_the_default():
	assert_eq(UiScale.sanitize(NAN), UiScale.DEFAULT_SCALE)


func test_the_range_actually_spans_smaller_and_larger_than_today():
	assert_lt(UiScale.MIN_SCALE, UiScale.DEFAULT_SCALE)
	assert_gt(UiScale.MAX_SCALE, UiScale.DEFAULT_SCALE)


## font_size is the ONLY way a size is applied, so a sanitise is never
## something a caller can forget to do first.
func test_font_size_sanitises_the_scale_it_is_given():
	assert_eq(UiScale.font_size(14, 99.0), UiScale.font_size(14, UiScale.MAX_SCALE))
	assert_eq(UiScale.font_size(14, NAN), 14)


# -- the theme the scale feeds ----------------------------------------------

## build_theme(scale) covers every widget that does NOT override its own font
## size; the ones that do register their base size with World instead.
func test_a_scaled_theme_scales_the_default_font_size():
	var theme := UiTheme.new().build_theme(1.5)
	assert_eq(theme.default_font_size, UiScale.font_size(UiTheme.BASE_FONT_SIZE, 1.5))


func test_a_scaled_theme_scales_its_labels_and_buttons_too():
	var theme := UiTheme.new().build_theme(1.5)
	var expected := UiScale.font_size(UiTheme.BASE_FONT_SIZE, 1.5)
	assert_eq(theme.get_font_size("font_size", "Label"), expected)
	assert_eq(theme.get_font_size("font_size", "Button"), expected)


## An unscaled build_theme() is still exactly the theme that shipped, so the
## setting is additive rather than a rewrite of the look.
func test_an_unscaled_theme_is_the_theme_that_shipped():
	var theme := UiTheme.new().build_theme()
	assert_eq(theme.default_font_size, UiTheme.BASE_FONT_SIZE)
	assert_eq(theme.get_font_size("font_size", "Label"), UiTheme.BASE_FONT_SIZE)
