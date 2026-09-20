extends SceneTree

## Dev tool: renders the real HUD cards to a PNG so the layout can be LOOKED
## at rather than reasoned about (see docs/concept/hud.md).
##
## Calls World's own builders -- the same _build_world_clock_card,
## _build_condition_chips, _build_held_item_card, _build_xp_bar,
## _build_land_sense_label, _build_survival_bar, _build_karma_display and
## _build_diagnostics_strip the game calls -- so what this renders is the real
## thing at the real offsets, not a mock-up that can drift from them.
##
## World is instantiated but never added to the tree, so its _ready (license
## gate, chunk manager, ~52s of art warming) never runs. Its $UI CanvasLayer is
## reparented into a SubViewport of the design size instead.
##
## Usage:
##   xvfb-run -a godot --path . --rendering-driver opengl3 \
##       -s tools/probe_hud_layout.gd [-- <scale> [busy|calm|dead]]
##
## `busy` (the default) fills every card, which is what catches clipping and
## overlap. `calm` is the opposite and catches the other failure: a card that
## should have hidden itself leaving a blank card standing. `dead` shows the
## death card over both.
##
## Output: tools/hud_renders/hud_<scale>_<state>.png (gitignored via
## tools/*_renders/).

const ViewMode = preload("res://src/gameplay/view_mode.gd")

const OUT_DIR := "res://tools/hud_renders"
const DESIGN_SIZE := Vector2i(1280, 720)


func _initialize() -> void:
	var scale := 1.0
	var state := "busy"
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		scale = float(args[0])
	if args.size() > 1:
		state = args[1]

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))

	var viewport := SubViewport.new()
	viewport.size = DESIGN_SIZE
	viewport.transparent_bg = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)

	# Something to read the cards OVER -- the whole point of pillar 1 is that
	# they stay legible over terrain, and a black background would hide a failure.
	var ground := ColorRect.new()
	ground.color = Color(0.72, 0.78, 0.62)
	ground.size = Vector2(DESIGN_SIZE)
	viewport.add_child(ground)

	var world = load("res://scenes/world.tscn").instantiate()
	var ui: CanvasLayer = world.get_node("UI")
	# A real map texture, so the rounded clip has something to actually round.
	var map: TextureRect = ui.get_node("Minimap")
	map.texture = _fake_map()
	# World's @onready members never resolve here (its _ready never runs), so
	# the handful the HUD builders read are wired by hand -- the same paths
	# world.gd itself declares them with.
	world._ui = ui
	world._player_health_bg = ui.get_node("PlayerHealthBar/Background")
	world._player_health_fill = ui.get_node("PlayerHealthBar/Fill")
	world._player_health_label = ui.get_node("PlayerHealthBar/Label")
	world._minimap = ui.get_node("Minimap")
	world._ui_scale = scale
	world._apply_ui_scale()

	# Same order _ready uses -- a VBox column draws its children in the order
	# they were added, so the order IS the layout.
	world._build_hud_columns()
	world._build_xp_bar()
	world._build_land_sense_label()
	world._build_creature_panels_container()
	world._build_condition_chips()
	world._build_survival_bar()
	world._build_world_clock_card()
	world._build_karma_display()
	world._build_settlement_card()
	world._build_held_item_card()
	world._build_diagnostics_strip()
	world._build_death_label()
	# The minimap's frame and the planner switch beside it -- the two things
	# a render is the only real check of (a clip mask and a knob's rest
	# position do not show up in any unit test).
	world._build_minimap_frame()
	world._build_view_mode_toggle()

	if state == "planner":
		world._view_mode = ViewMode.Mode.PLANNER
	if state == "calm":
		_fill_in_calm(world)
	else:
		_fill_in(world, scale)
	if state == "planner":
		# The palette is built directly rather than through World's own
		# builder, which reaches for _chunk_manager for real labour hours --
		# a whole generated world this probe deliberately does not have. The
		# VIEW is the same class the game builds; only the two numbers it is
		# not allowed to invent are stubbed.
		var palette = load("res://src/ui/blueprint_palette_view.gd").new()
		world._blueprint_palette = palette
		ui.add_child(palette)
		palette.configure(
			world._ui_theme,
			func(_blueprint_id: String) -> float: return 6.0,
			func(item_id: String) -> String: return String(item_id).capitalize()
		)
		# The same refit-on-growth wiring World does: the view's minimum size
		# changes once its slots have laid themselves out, and without this
		# the render clips the palette's own footer.
		palette.minimum_size_changed.connect(world._fit_blueprint_palette)
		world._fit_blueprint_palette()
		# Through World's own _apply_view_mode, so what the render shows is
		# what the game decides -- not a second opinion the probe holds.
		world._apply_view_mode()
	world._death_card.visible = state == "dead"

	world.remove_child(ui)
	viewport.add_child(ui)

	await process_frame
	await process_frame
	var image := viewport.get_texture().get_image()
	var path := "%s/hud_%s_%s.png" % [OUT_DIR, str(scale).replace(".", "_"), state]
	image.save_png(ProjectSettings.globalize_path(path))
	print("wrote ", path, "  (", image.get_width(), "x", image.get_height(), ")")
	quit()


## Plausible mid-game content in every card, so the render shows real widths
## rather than empty boxes.
func _fill_in(world, scale: float) -> void:
	var HudReadouts = load("res://src/ui/hud_readouts.gd")
	var UiTheme = load("res://src/ui/ui_theme.gd")
	var UiScale = load("res://src/ui/ui_scale.gd")

	var clock: PackedStringArray = HudReadouts.world_clock_lines(
		18, 7, HudReadouts.day_phase(3.4, 18), "Autumn", "Rain", "wading", 0.55, 42
	)
	for i in world._clock_labels.size():
		world._clock_labels[i].text = clock[i]

	var diagnostics: PackedStringArray = HudReadouts.diagnostics_lines(87, 48.0, 7.9, 3.4)
	for i in world._diagnostics_labels.size():
		world._diagnostics_labels[i].text = diagnostics[i]
	world._diagnostics_card.visible = true

	var meters = load("res://src/gameplay/survival_meters.gd").new()
	meters.hunger = 0.9  # severe
	meters.thirst = 0.6  # warning
	meters.warmth = 0.3  # warning
	for chip in HudReadouts.condition_chips(meters, "wading"):
		var card := PanelContainer.new()
		var label := Label.new()
		label.text = String(chip["text"])
		label.add_theme_color_override("font_color", chip["color"])
		label.add_theme_font_size_override(
			"font_size", UiScale.font_size(UiTheme.BASE_FONT_SIZE - 2, scale)
		)
		card.add_child(label)
		world._condition_chips_row.add_child(card)

	# Planner mode ON here and off in the calm render, so one run of the probe
	# at each state shows both halves of the switch.
	world._view_mode_switch.set_on(true)
	world._held_item_label.text = HudReadouts.held_item_line("Stone Axe", "worn")
	# Whether the card is SHOWN is the mode's call, not the probe's -- that is
	# exactly the bug this render has to be able to catch (reported live: the
	# card drawn over the build palette).
	world._held_item_card.visible = ViewMode.shows_hotbar(world._view_mode)

	world._hunger_label.text = world.meter_label_text("Food", 0.1)
	world._thirst_label.text = world.meter_label_text("Water", 0.4)
	world._stamina_label.text = world.meter_label_text("Stamina", 0.75)
	world._warmth_label.text = world.meter_label_text("Cold", 0.3)
	world._wallet_label.text = "42 gold"

	world._player_health_label.text = "HP 62 / 100"
	world._player_health_fill.size.x = 0.62 * world.SURVIVAL_BAR_WIDTH
	world._xp_label.text = "Lv 7 — Warrior  (2 pts)"
	world._xp_fill.size.x = 0.4 * world.SURVIVAL_BAR_WIDTH

	world._land_sense_card.visible = true
	world._land_sense_label.text = "Land health 61%  ·  Vegetation 48%"

	world._karma_label.text = world.karma_display_text(12)
	world._karma_label.add_theme_color_override("font_color", world.karma_display_color(12))

	# A real, grown settlement -- the longest text every row can hold, which
	# is what catches this card clipping or overflowing its column.
	var SettlementReadout = load("res://src/ui/settlement_readout.gd")
	var settlement := {
		"tier": "city", "households": 12, "housed": 11, "happiness": 0.68,
		"needs": {"food": 0.2, "shelter": 0.9, "work": 0.8, "income": 0.7, "community": 0.6},
		"gold": 1284, "feeds": 17, "building": "house_large",
	}
	world._settlement_card.visible = true
	world._settlement_title.text = SettlementReadout.title_for(settlement)
	var settlement_lines: Array = SettlementReadout.lines_for(settlement)
	for i in world._settlement_labels.size():
		world._settlement_labels[i].text = String(settlement_lines[i])


## Nothing wrong, nothing in hand, the keystone not unlocked, F3 not pressed --
## the other failure mode. Every card that has nothing to say must be GONE, not
## blank: an empty chip row, no held-item card, no land-sense card, no
## diagnostics strip, and the cards that remain closed up against each other.
func _fill_in_calm(world) -> void:
	world._hunger_label.text = world.meter_label_text("Food", 0.92)
	world._thirst_label.text = world.meter_label_text("Water", 0.88)
	world._stamina_label.text = world.meter_label_text("Stamina", 1.0)
	world._warmth_label.text = world.meter_label_text("Warmth", 0.95)
	world._wallet_label.text = "Gold: 3"
	world._player_health_label.text = "HP 100 / 100"
	world._xp_label.text = "Lv 1 — Warrior"
	world._xp_fill.size.x = 0.05 * world.SURVIVAL_BAR_WIDTH
	world._karma_label.text = world.karma_display_text(0)
	world._karma_label.add_theme_color_override("font_color", world.karma_display_color(0))
	# Out in open country: the settlement card must be GONE, not blank.
	world._settlement_card.visible = false

	var HudReadouts = load("res://src/ui/hud_readouts.gd")
	var clock: PackedStringArray = HudReadouts.world_clock_lines(
		9, 15, HudReadouts.day_phase(34.0, 9), "Spring", "Clear", "walking", 1.0, 144
	)
	for i in world._clock_labels.size():
		world._clock_labels[i].text = clock[i]


## A plausible map image: a green field with a blue river down it, so the
## rounded corners are visible against the page behind them. Generated rather
## than loaded -- MinimapRenderer needs a whole EarthChunkManager, and what is
## being looked at here is the FRAME, not the cartography.
func _fake_map() -> ImageTexture:
	var image := Image.create(162, 162, false, Image.FORMAT_RGB8)
	image.fill(Color(0.35, 0.5, 0.25))
	for y in image.get_height():
		var x := 70 + int(14.0 * sin(float(y) / 22.0))
		for w in 9:
			image.set_pixel(x + w, y, Color(0.25, 0.45, 0.75))
	return ImageTexture.create_from_image(image)
