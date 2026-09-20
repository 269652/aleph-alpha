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


## Golden vs. red accents for positive vs. negative Karma (asked directly) --
## NEGATIVE is this theme's first formal "bad" counterpart to ACCENT's warm
## gold "good". Pinned the same way ACCENT's own hue/saturation are: a
## distinct, clearly-red, clearly-saturated hue, not a muddy or washed-out one.
func test_negative_is_a_saturated_red_distinct_from_the_accent():
	assert_gt(UiTheme.NEGATIVE.s, 0.3, "the negative colour should be a distinct saturated hue")
	assert_lt(UiTheme.NEGATIVE.h, 0.05, "should read as red, not orange/gold like the accent")
	assert_gt(absf(UiTheme.NEGATIVE.h - UiTheme.ACCENT.h), 0.05, "must be a visibly different hue from the accent")


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


## A slim HUD card (docs/concept/hud.md pillar 1): the same opaque, bordered,
## rounded card, with less padding. A 10px XP bar inside the full-margin panel
## would be a 34px card holding 10px of content -- mostly empty card. Same
## colour and same border, so "legible" is still one decision made once.
func test_the_compact_card_is_the_same_card_with_less_padding():
	var compact := ui.compact_panel_stylebox()
	var full := ui.panel_stylebox()
	assert_eq(compact.bg_color, full.bg_color)
	assert_eq(compact.border_color, full.border_color)
	assert_eq(compact.corner_radius_top_left, full.corner_radius_top_left)
	assert_lt(compact.content_margin_left, full.content_margin_left)


## Still padded, though -- a card with no inner margin is a box drawn tight
## around its text, which reads as a bug rather than as a card.
func test_the_compact_card_still_has_inner_padding():
	assert_gt(ui.compact_panel_stylebox().content_margin_left, 0.0)


## Opaque enough to read over snow, which is the whole point of pillar 1 and
## the pin test_world_hud.gd already makes for the message banners.
func test_the_compact_card_is_opaque_enough_to_read_over_snow():
	assert_gt(ui.compact_panel_stylebox().bg_color.a, 0.9)


## The minimap's own frame (asked for directly: "add a border and
## borderradius of 4px to the minimap"). The map IS the background, so unlike
## every other card in this theme this one draws no fill -- only the shared
## border, at the radius that was asked for.
func test_the_map_frame_draws_a_border_and_no_fill():
	var frame: StyleBoxFlat = ui.map_frame_stylebox()
	assert_true(frame is StyleBoxFlat)
	assert_eq(frame.bg_color.a, 0.0, "a fill would hide the map it frames")
	assert_eq(frame.border_color, UiTheme.PANEL_BORDER, "the shared border, not its own")
	assert_eq(frame.border_width_left, UiTheme.BORDER_WIDTH)


## Four, not the theme's own six: a map is read for the shapes in it, and the
## more its corners are rounded the more of the actual map they eat.
func test_the_map_frame_is_rounded_to_the_asked_for_four_pixels():
	assert_eq(UiTheme.MAP_CORNER_RADIUS, 4)
	assert_eq(ui.map_frame_stylebox().corner_radius_top_left, UiTheme.MAP_CORNER_RADIUS)
	assert_lt(UiTheme.MAP_CORNER_RADIUS, UiTheme.CORNER_RADIUS)


## The clipper that rounds the map texture's own corners has to use the SAME
## shape as the frame drawn over it, or the border and the masked edge would
## not line up.
func test_the_clipper_matches_the_frame_it_sits_under():
	assert_eq(
		ui.map_clip_stylebox().corner_radius_top_left,
		ui.map_frame_stylebox().corner_radius_top_left
	)
	assert_gt(ui.map_clip_stylebox().bg_color.a, 0.0, "a mask must actually be drawn to mask")


## A toggled control that is ON must read as on at a glance.
##
## Measured, not assumed: the build palette's first render
## (tools/probe_build_palette.gd) showed the armed slot and the open tab
## drawn in BUTTON_PRESSED, which differs from BUTTON_NORMAL by about 5% of
## value -- invisible over the card's own dark background. A menu whose
## selection cannot be seen is a menu with no selection.
##
## So "selected" gets its own stylebox rather than a slightly darker fill:
## the gold ACCENT the rest of this theme already uses for "this one",
## carried as a thicker border, over a background that is LIGHTER than the
## unselected one rather than darker.
func test_a_selected_control_is_marked_in_the_accent_not_by_a_shade():
	var selected := ui.selected_button_stylebox()
	var normal := ui.button_stylebox("normal")
	assert_eq(selected.border_color, UiTheme.ACCENT, "selection is the accent's job")
	assert_gt(
		selected.border_width_top, normal.border_width_top,
		"and it is drawn thicker than an ordinary border"
	)
	assert_gt(
		selected.bg_color.v, normal.bg_color.v,
		"a selected control lifts out of the card rather than sinking into it"
	)


## The whole point of the change: selected must be further from normal than
## pressed ever was, or it is the same invisible difference with a new name.
func test_selected_is_further_from_normal_than_the_old_pressed_shade_was():
	var normal := ui.button_stylebox("normal")
	var selected := ui.selected_button_stylebox()
	var pressed := ui.button_stylebox("pressed")
	assert_gt(
		absf(selected.bg_color.v - normal.bg_color.v),
		absf(pressed.bg_color.v - normal.bg_color.v),
		"the measured 5% that could not be seen is the floor to beat"
	)


func test_a_selected_control_keeps_the_rest_of_the_themes_shape():
	var selected := ui.selected_button_stylebox()
	assert_eq(selected.corner_radius_top_left, UiTheme.CORNER_RADIUS)
	assert_eq(selected.content_margin_left, UiTheme.BUTTON_MARGIN)
