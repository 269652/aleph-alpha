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
## The negative counterpart to ACCENT (asked directly: "golden and red
## accents for positive vs negative karma") -- this theme's first formal
## good/bad pair. A warm, saturated red, distinct in hue from ACCENT's
## gold rather than merely darker/desaturated, so the two read as opposite
## judgements at a glance, not two shades of the same thing.
const NEGATIVE := Color(0.85, 0.25, 0.25)
const TEXT := Color(0.92, 0.93, 0.96)
const TEXT_MUTED := Color(0.62, 0.65, 0.72)

## Button states.
const BUTTON_NORMAL := Color(0.19, 0.21, 0.27, 1.0)
const BUTTON_HOVER := Color(0.27, 0.30, 0.38, 1.0)
const BUTTON_PRESSED := Color(0.14, 0.15, 0.2, 1.0)

## The player's own UI scale (see docs/concept/hud.md "UI scale"), applied to
## every font size this theme sets.
const UiScale = preload("res://src/ui/ui_scale.gd")

const CORNER_RADIUS := 6
## The minimap's own corner radius (asked for directly: "add a border and
## borderradius of 4px to the minimap"). Deliberately tighter than the
## theme's own 6: a map is read for the shapes in it, and the more its
## corners are rounded the more of the actual map they eat.
const MAP_CORNER_RADIUS := 4
const BORDER_WIDTH := 1
const BASE_FONT_SIZE := 14
const TITLE_FONT_SIZE := 22
const CONTENT_MARGIN := 12.0
## The slim HUD card's padding (see compact_panel_stylebox).
const COMPACT_CONTENT_MARGIN := 5.0
const BUTTON_MARGIN := 8.0


## A rounded, bordered panel background (the base for every window/menu panel).
func panel_stylebox() -> StyleBoxFlat:
	return _flat(PANEL_BG, CONTENT_MARGIN, PANEL_BORDER, BORDER_WIDTH)


## The same card with less padding, for the slim HUD readouts -- the XP bar,
## the land-sense line, the charge meter (docs/concept/hud.md pillar 1).
##
## A 10px XP bar inside the full-margin panel is a 34px card holding 10px of
## content, which is mostly empty card stacked three deep down the left edge.
## Same bg, same border, same radius: "legible over every terrain" stays one
## decision made once, and only the padding differs.
func compact_panel_stylebox() -> StyleBoxFlat:
	return _flat(PANEL_BG, COMPACT_CONTENT_MARGIN, PANEL_BORDER, BORDER_WIDTH)


## The minimap's frame: the shared border at the shared width, no fill, at
## MAP_CORNER_RADIUS. See docs/concept/hud.md "The minimap is framed like
## every other card".
##
## No fill because the MAP is the background -- this is the one stylebox in
## the theme that draws only an edge. It is applied to a Panel drawn AFTER
## the map (later sibling = later draw), not to the map's own parent: a
## stylebox's border is drawn under its children, so the map would cover the
## inner half of it.
func map_frame_stylebox() -> StyleBoxFlat:
	var frame := _flat(Color(0, 0, 0, 0), 0.0, PANEL_BORDER, BORDER_WIDTH)
	frame.set_corner_radius_all(MAP_CORNER_RADIUS)
	return frame


## The mask that rounds the map TEXTURE's own corners -- the same shape as
## the frame above, on a Panel with clip_children = CLIP_CHILDREN_ONLY. Its
## colour never reaches the screen (the panel is used as a mask, not drawn),
## but it must be opaque: a mask is the shape that was actually drawn.
func map_clip_stylebox() -> StyleBoxFlat:
	var clip := _flat(PANEL_BG, 0.0, PANEL_BG, 0)
	clip.set_corner_radius_all(MAP_CORNER_RADIUS)
	return clip


## A rounded button background for the given state ("normal"/"hover"/"pressed").
func button_stylebox(state: String) -> StyleBoxFlat:
	var color := BUTTON_NORMAL
	match state:
		"hover":
			color = BUTTON_HOVER
		"pressed":
			color = BUTTON_PRESSED
	return _flat(color, BUTTON_MARGIN, PANEL_BORDER, BORDER_WIDTH)


## The background of a toggled control that is ON -- the armed slot in the
## build palette, the open tab beside it.
##
## Its own stylebox rather than BUTTON_PRESSED, measured: the palette's
## first render (tools/probe_build_palette.gd) drew the armed slot in
## BUTTON_PRESSED, which differs from BUTTON_NORMAL by about 5% of value
## and is simply invisible over this theme's dark card. Selection is what
## ACCENT already means everywhere else in this UI, so it is carried in the
## border -- thicker than an ordinary one -- over a background that LIFTS
## out of the card rather than sinking into it. Pinned by
## test_a_selected_control_is_marked_in_the_accent_not_by_a_shade.
const BUTTON_SELECTED := Color(0.40, 0.34, 0.20, 1.0)
const SELECTED_BORDER_WIDTH := 2


func selected_button_stylebox() -> StyleBoxFlat:
	return _flat(BUTTON_SELECTED, BUTTON_MARGIN, ACCENT, SELECTED_BORDER_WIDTH)


## The background for hover tooltips (e.g. InventoryWindow's item slots).
## Deliberately near-black rather than PANEL_BG -- a tooltip floats *above*
## everything else and needs to read as a distinct top layer, not blend into
## whatever panel it's hovering over, with the gold ACCENT as a thin border
## so it pops instead of looking like Godot's plain default engine tooltip.
func tooltip_stylebox() -> StyleBoxFlat:
	return _flat(Color(0.05, 0.05, 0.07, 0.98), 8.0, ACCENT, BORDER_WIDTH)


## Builds the Theme resource assigned to every UI root Control (menus, windows,
## HUD). Styles PanelContainer/Button/Label/LineEdit consistently.
##
## `scale` is the player's UI scale (see UiScale). It covers every widget that
## does NOT override its own font size; the HUD widgets that do register their
## base size with World._scaled_font instead. The default of 1.0 is a no-op, so
## an unscaled build_theme() is still exactly the theme that shipped.
func build_theme(scale: float = UiScale.DEFAULT_SCALE) -> Theme:
	var theme := Theme.new()
	apply_scale(theme, scale)

	theme.set_stylebox("panel", "PanelContainer", panel_stylebox())

	theme.set_stylebox("normal", "Button", button_stylebox("normal"))
	theme.set_stylebox("hover", "Button", button_stylebox("hover"))
	theme.set_stylebox("pressed", "Button", button_stylebox("pressed"))
	theme.set_stylebox("focus", "Button", button_stylebox("hover"))
	theme.set_color("font_color", "Button", TEXT)
	theme.set_color("font_hover_color", "Button", ACCENT)

	theme.set_color("font_color", "Label", TEXT)

	var field := _flat(Color(0.09, 0.1, 0.13, 1.0), 6.0, PANEL_BORDER, BORDER_WIDTH)
	theme.set_stylebox("normal", "LineEdit", field)
	theme.set_color("font_color", "LineEdit", TEXT)
	theme.set_color("font_placeholder_color", "LineEdit", TEXT_MUTED)

	theme.set_stylebox("panel", "TooltipPanel", tooltip_stylebox())
	theme.set_color("font_color", "TooltipLabel", TEXT)

	return theme


## Re-applies `scale` to a theme ALREADY IN USE.
##
## A Theme is a Resource shared by reference -- every window and HUD card holds
## the same one -- so moving the scale slider has to mutate that object rather
## than hand out a freshly built replacement, which would leave every node
## already in the tree on the old sizes until a restart. This is also the one
## place that knows WHICH font sizes this theme sets, so build_theme delegates
## to it rather than keeping a second copy of that list.
func apply_scale(theme: Theme, scale: float) -> void:
	var font_size := UiScale.font_size(BASE_FONT_SIZE, scale)
	theme.default_font_size = font_size
	theme.set_font_size("font_size", "Button", font_size)
	theme.set_font_size("font_size", "Label", font_size)
	theme.set_font_size("font_size", "TooltipLabel", font_size)


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
