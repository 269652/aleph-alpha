extends RefCounted

## The single source of truth for the game's UI look (see the UI polish pass).
## A dark, rounded, accent-driven theme applied to every menu/window/HUD panel
## via `build_theme()`. The palette and stylebox metrics are pinned by
## test_ui_theme.gd so the look stays consistent and legible rather than being
## eyeballed per-panel.

## Palette. Dark slate panels, light text, a warm gold accent, plus semantic
## bar colours reused by the HUD meters.
const WINDOW_BG := Color(0.11, 0.12, 0.16, 0.96)
const PANEL_BG := Color(0.15, 0.16, 0.21, 0.98)
const PANEL_BORDER := Color(0.32, 0.34, 0.42, 0.9)
const ACCENT := Color(0.95, 0.72, 0.25)  # warm gold
const TEXT := Color(0.92, 0.93, 0.96)
const TEXT_MUTED := Color(0.62, 0.65, 0.72)

## Button states.
const BUTTON_NORMAL := Color(0.19, 0.21, 0.27, 1.0)
const BUTTON_HOVER := Color(0.27, 0.30, 0.38, 1.0)
const BUTTON_PRESSED := Color(0.14, 0.15, 0.2, 1.0)

const CORNER_RADIUS := 6
const BORDER_WIDTH := 1
const BASE_FONT_SIZE := 14
const TITLE_FONT_SIZE := 22
const CONTENT_MARGIN := 12.0
const BUTTON_MARGIN := 8.0


## A rounded, bordered panel background (the base for every window/menu panel).
func panel_stylebox() -> StyleBoxFlat:
	return _flat(PANEL_BG, CONTENT_MARGIN, PANEL_BORDER, BORDER_WIDTH)


## A rounded button background for the given state ("normal"/"hover"/"pressed").
func button_stylebox(state: String) -> StyleBoxFlat:
	var color := BUTTON_NORMAL
	match state:
		"hover":
			color = BUTTON_HOVER
		"pressed":
			color = BUTTON_PRESSED
	return _flat(color, BUTTON_MARGIN, PANEL_BORDER, BORDER_WIDTH)


## Builds the Theme resource assigned to every UI root Control (menus, windows,
## HUD). Styles PanelContainer/Button/Label/LineEdit consistently.
func build_theme() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = BASE_FONT_SIZE

	theme.set_stylebox("panel", "PanelContainer", panel_stylebox())

	theme.set_stylebox("normal", "Button", button_stylebox("normal"))
	theme.set_stylebox("hover", "Button", button_stylebox("hover"))
	theme.set_stylebox("pressed", "Button", button_stylebox("pressed"))
	theme.set_stylebox("focus", "Button", button_stylebox("hover"))
	theme.set_color("font_color", "Button", TEXT)
	theme.set_color("font_hover_color", "Button", ACCENT)
	theme.set_font_size("font_size", "Button", BASE_FONT_SIZE)

	theme.set_color("font_color", "Label", TEXT)
	theme.set_font_size("font_size", "Label", BASE_FONT_SIZE)

	var field := _flat(Color(0.09, 0.1, 0.13, 1.0), 6.0, PANEL_BORDER, BORDER_WIDTH)
	theme.set_stylebox("normal", "LineEdit", field)
	theme.set_color("font_color", "LineEdit", TEXT)
	theme.set_color("font_placeholder_color", "LineEdit", TEXT_MUTED)

	return theme


func _flat(bg: Color, margin: float, border: Color, border_width: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(CORNER_RADIUS)
	sb.set_border_width_all(border_width)
	sb.border_color = border
	sb.content_margin_left = margin
	sb.content_margin_right = margin
	sb.content_margin_top = margin
	sb.content_margin_bottom = margin
	return sb
