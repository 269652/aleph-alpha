extends GutTest

const UiTheme = preload("res://src/ui/ui_theme.gd")

var ui: UiTheme


func before_each():
	ui = UiTheme.new()


func test_palette_is_a_dark_theme_with_light_text():
	assert_lt(UiTheme.PANEL_BG.v, 0.35, "panels should be dark")
	assert_gt(UiTheme.TEXT.v, 0.8, "text should be light")


func test_accent_is_a_saturated_colour():
	assert_gt(UiTheme.ACCENT.s, 0.3, "the accent should be a distinct saturated hue")


func test_panel_stylebox_is_rounded_and_dark():
	var sb := ui.panel_stylebox()
	assert_true(sb is StyleBoxFlat)
	assert_eq(sb.corner_radius_top_left, UiTheme.CORNER_RADIUS)
	assert_eq(sb.bg_color, UiTheme.PANEL_BG)
	assert_gt(sb.content_margin_left, 0.0, "panels should have inner padding")


func test_button_hover_is_brighter_than_normal():
	var normal := ui.button_stylebox("normal")
	var hover := ui.button_stylebox("hover")
	assert_true(normal is StyleBoxFlat and hover is StyleBoxFlat)
	assert_gt(hover.bg_color.v, normal.bg_color.v, "hover should visibly light up")


func test_button_stylebox_is_rounded():
	assert_eq(ui.button_stylebox("normal").corner_radius_top_left, UiTheme.CORNER_RADIUS)


func test_build_theme_styles_panels_buttons_and_labels():
	var theme := ui.build_theme()
	assert_true(theme.has_stylebox("panel", "PanelContainer"))
	assert_true(theme.get_stylebox("panel", "PanelContainer") is StyleBoxFlat)
	assert_eq(theme.get_color("font_color", "Label"), UiTheme.TEXT)
	assert_eq(theme.get_font_size("font_size", "Button"), UiTheme.BASE_FONT_SIZE)
	assert_true(theme.get_stylebox("normal", "Button") is StyleBoxFlat)
	assert_true(theme.get_stylebox("hover", "Button") is StyleBoxFlat)


func test_build_theme_is_deterministic_shape():
	# Two builds produce equivalent key styling so callers can rebuild freely.
	var a := ui.build_theme()
	var b := ui.build_theme()
	assert_eq(
		(a.get_stylebox("panel", "PanelContainer") as StyleBoxFlat).bg_color,
		(b.get_stylebox("panel", "PanelContainer") as StyleBoxFlat).bg_color
	)


## Item/slot hover tooltips (e.g. InventoryWindow's item grid) previously had
## no theme entry at all, so Godot fell back to its plain default engine
## tooltip -- easy to miss and visually inconsistent against this game's dark
## custom theme. Tooltips now get real, on-brand styling.
func test_build_theme_styles_tooltips_to_match_the_rest_of_the_ui():
	var theme := ui.build_theme()
	assert_true(theme.has_stylebox("panel", "TooltipPanel"))
	var tooltip_sb := theme.get_stylebox("panel", "TooltipPanel") as StyleBoxFlat
	assert_true(tooltip_sb is StyleBoxFlat)
	assert_lt(tooltip_sb.bg_color.v, 0.35, "tooltip background should be dark, matching the rest of the UI")
	assert_eq(theme.get_color("font_color", "TooltipLabel"), UiTheme.TEXT)
