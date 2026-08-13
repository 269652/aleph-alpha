extends PanelContainer

## The start-up main menu and character creator (see concept/progression.md
## character creation). Shown over the world before anything spawns; the world
## stays paused until the player chooses. Screens: root (New Game / Host /
## Join / Quit), character creation (New Game + Host both route through it),
## and a join screen (IP entry).
##
## The creation screen is a real character creator: pick a class on the left,
## cycle five appearance axes on the right (skin, hair color, hair style,
## beard, eyes -- see HeroAppearance.AXES), and watch a live full-body
## portrait update in the middle. Purely glue -- World owns actually spawning
## the player, starting ENet, and applying the chosen class's stat lens
## (ClassArchetype); HeroAppearance/ProceduralCharacterSprite own the look.

const ClassArchetype = preload("res://src/gameplay/class_archetype.gd")
const ProceduralCharacterSprite = preload("res://src/rendering/procedural_character_sprite.gd")
const HeroAppearance = preload("res://src/rendering/hero_appearance.gd")

## Human-readable blurbs for the archetypes (ClassArchetype has the stats).
const CLASS_BLURBS := {
	"warrior": "Tanky melee bruiser. High health and attack.",
	"mage": "Glass-cannon caster. Big mana pool, frail body.",
	"ranger": "Agile skirmisher. Balanced, stamina-heavy.",
	"beastmaster": "Tamer and support. Rounded stats.",
	"artisan": "Crafter. Sturdy, with deep stamina.",
	"herbalist": "Medic and caster. Mana over might.",
	"overseer": "Organizer. Modest mana, steady all round.",
}

## Friendly labels for the appearance axes, in display order.
const AXIS_LABELS := {
	"skin": "Skin",
	"hair_color": "Hair Colour",
	"hair_style": "Hair Style",
	"beard": "Beard",
	"eyes": "Eyes",
}

## The portrait renders at ProceduralCharacterSprite.PORTRAIT_SIZE and is
## scaled up by this much -- nearest-neighbour, so it stays crisp pixel art.
const PORTRAIT_SCALE := 5

const PANEL_SIZE := Vector2(760, 520)

## Emitted once the player has committed to a start mode + class.
## mode is "single" or "host"; chosen_class is a ClassArchetype name.
## `appearance` is the authored look (see HeroAppearance).
signal start_requested(mode: String, chosen_class: String, appearance: Dictionary)
## Emitted to join a remote host at `address`.
signal join_requested(address: String)

var _archetypes := ClassArchetype.new()
var _appearance_maker := HeroAppearance.new()
var _char_sprite := ProceduralCharacterSprite.new()

var _root_screen: Control
var _create_screen: Control
var _join_screen: Control

var _pending_mode := "single"
var _selected_class := "warrior"
## axis name -> chosen option index (see HeroAppearance.appearance_from_choices).
var _choices: Dictionary = {}

var _class_detail: Label
var _class_buttons: Dictionary = {}  # archetype -> Button
var _portrait: TextureRect
var _axis_value_labels: Dictionary = {}  # axis -> Label


func _ready() -> void:
	custom_minimum_size = PANEL_SIZE
	_choices = _appearance_maker.choices_from_appearance(
		_appearance_maker.appearance_for(_selected_class, 0)
	)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 22)
	add_child(margin)

	var stack := Control.new()
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(stack)

	_root_screen = _build_root_screen()
	_create_screen = _build_create_screen()
	_join_screen = _build_join_screen()
	for s in [_root_screen, _create_screen, _join_screen]:
		s.set_anchors_preset(Control.PRESET_FULL_RECT)
		stack.add_child(s)
	_show(_root_screen)

	# PRESET_CENTER alone only re-anchors the reference point to 0.5/0.5/0.5/
	# 0.5 -- Godot's set_anchor recomputes offsets to PRESERVE the control's
	# CURRENT on-screen rect under the new anchor fraction, it does not derive
	# offsets from size (verified against control.cpp). Since MainMenu is
	# never otherwise positioned, that left it pinned to the parent's
	# top-left corner regardless of when size was set. Centering needs the
	# four offsets explicitly set to a symmetric half-size box around the
	# anchor point -- the same pattern every other centered popup in this
	# codebase uses (SettingsOverlay/InventoryWindow/DevConsole, wired in
	# world.gd) -- pinned by
	# test_panel_is_actually_centered_not_pinned_to_a_corner.
	set_anchors_preset(Control.PRESET_CENTER)
	offset_left = -PANEL_SIZE.x / 2.0
	offset_top = -PANEL_SIZE.y / 2.0
	offset_right = PANEL_SIZE.x / 2.0
	offset_bottom = PANEL_SIZE.y / 2.0


# -- root ---------------------------------------------------------------------

func _build_root_screen() -> Control:
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 6)

	box.add_child(_title_label("ALEPH ALFA", 44))
	var tagline := _muted_label("A living world, simulated from the ground up.")
	tagline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(tagline)
	box.add_child(_spacer(28))

	var buttons := VBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 10)
	box.add_child(buttons)

	buttons.add_child(_menu_button("New Game", func():
		_pending_mode = "single"
		_show(_create_screen), true))
	buttons.add_child(_menu_button("Host Game (LAN)", func():
		_pending_mode = "host"
		_show(_create_screen)))
	buttons.add_child(_menu_button("Join Game", func(): _show(_join_screen)))
	buttons.add_child(_menu_button("Quit", func(): get_tree().quit()))
	return box


# -- character creation -------------------------------------------------------

func _build_create_screen() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)

	box.add_child(_title_label("Create your character", 26))
	box.add_child(_separator())

	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 22)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(cols)

	cols.add_child(_build_class_column())
	cols.add_child(_build_portrait_column())
	cols.add_child(_build_appearance_column())

	box.add_child(_separator())
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_child(_menu_button("Back", func(): _show(_root_screen)))
	row.add_child(_menu_button("Begin", func():
		start_requested.emit(_pending_mode, _selected_class, current_appearance()), true))
	box.add_child(row)

	_select_class(_selected_class)
	return box


func _build_class_column() -> Control:
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(210, 0)
	col.add_theme_constant_override("separation", 6)
	col.add_child(_section_label("CLASS"))

	for archetype in _archetypes.archetype_names():
		var b := Button.new()
		b.text = archetype.capitalize()
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(0, 28)
		b.pressed.connect(func(): _select_class(archetype))
		_class_buttons[archetype] = b
		col.add_child(b)

	_class_detail = _muted_label("")
	_class_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_class_detail.custom_minimum_size = Vector2(0, 72)
	col.add_child(_class_detail)
	return col


## The live full-body preview -- the whole point of the creator screen.
func _build_portrait_column() -> Control:
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 8)

	var frame := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.08, 0.11, 0.9)
	style.set_border_width_all(1)
	style.border_color = Color(1, 1, 1, 0.14)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(10)
	frame.add_theme_stylebox_override("panel", style)
	frame.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

	_portrait = TextureRect.new()
	_portrait.custom_minimum_size = Vector2(
		ProceduralCharacterSprite.PORTRAIT_SIZE * PORTRAIT_SCALE
	)
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	# Pixel art must not blur when scaled up.
	_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	frame.add_child(_portrait)
	col.add_child(frame)

	col.add_child(_menu_button("Randomise", func(): _randomise_appearance()))
	return col


func _build_appearance_column() -> Control:
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(220, 0)
	col.add_theme_constant_override("separation", 6)
	col.add_child(_section_label("APPEARANCE"))

	for axis in HeroAppearance.AXES:
		col.add_child(_build_axis_row(axis))
	return col


## One "◀  Label: value  ▶" row cycling a single appearance axis.
func _build_axis_row(axis: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)

	row.add_child(_arrow_button("<", func(): _cycle_axis(axis, -1)))

	var value := Label.new()
	value.text = ""
	value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value.add_theme_font_size_override("font_size", 12)
	_axis_value_labels[axis] = value
	row.add_child(value)

	row.add_child(_arrow_button(">", func(): _cycle_axis(axis, 1)))
	return row


func _arrow_button(glyph: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = glyph
	b.custom_minimum_size = Vector2(30, 26)
	b.pressed.connect(on_press)
	return b


func _cycle_axis(axis: String, step: int) -> void:
	_choices[axis] = int(_choices.get(axis, 0)) + step
	_refresh_appearance()


func _randomise_appearance() -> void:
	_choices = _appearance_maker.choices_from_appearance(
		_appearance_maker.appearance_for(_selected_class, randi())
	)
	_refresh_appearance()


## The look the player has authored so far -- handed to World on Begin.
func current_appearance() -> Dictionary:
	return _appearance_maker.appearance_from_choices(_selected_class, _choices)


func _refresh_appearance() -> void:
	var appearance := current_appearance()
	if _portrait != null:
		_portrait.texture = _char_sprite.generate_hero_portrait_texture(appearance)
	for axis in _axis_value_labels:
		var label: Label = _axis_value_labels[axis]
		label.text = "%s: %s" % [AXIS_LABELS.get(axis, axis), _axis_value_text(axis, appearance)]


## What a given axis currently reads as -- a name where one exists (hair/
## beard styles), otherwise a 1-based "3 / 6" position within its pool.
func _axis_value_text(axis: String, appearance: Dictionary) -> String:
	match axis:
		"hair_style":
			return String(appearance.hair_style_name).capitalize()
		"beard":
			return String(appearance.beard_name).capitalize()
		_:
			var count := _appearance_maker.option_count(axis)
			var indices := _appearance_maker.choices_from_appearance(appearance)
			return "%d / %d" % [int(indices.get(axis, 0)) + 1, count]


func _select_class(archetype: String) -> void:
	_selected_class = archetype
	var stats: Dictionary = _archetypes.stats_for(archetype)
	_class_detail.text = "%s\n\nHP %+d   ATK %+d\nMana %+d   Stam %+d" % [
		CLASS_BLURBS.get(archetype, archetype),
		int(stats.get("max_health", 0.0)),
		int(stats.get("attack_damage", 0.0)),
		int(stats.get("max_mana", 0.0)),
		int(stats.get("max_stamina", 0.0)),
	]
	# Highlight the picked class; dim the rest. (Loop var deliberately not
	# called `name` -- that shadows Node.name on this PanelContainer.)
	for class_id in _class_buttons:
		var button: Button = _class_buttons[class_id]
		button.modulate = Color(1, 1, 1) if class_id == archetype else Color(1, 1, 1, 0.55)
	_refresh_appearance()


# -- join ---------------------------------------------------------------------

func _build_join_screen() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)

	box.add_child(_title_label("Join a host", 26))
	box.add_child(_separator())

	var hint := _muted_label("Enter the host's address (a LAN IP, or a tunnel host for internet play).")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(hint)

	var field := LineEdit.new()
	field.placeholder_text = "127.0.0.1"
	field.custom_minimum_size = Vector2(0, 32)
	box.add_child(field)

	box.add_child(_spacer(8))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_child(_menu_button("Back", func(): _show(_root_screen)))
	row.add_child(_menu_button("Connect", func():
		var addr: String = field.text.strip_edges()
		join_requested.emit(addr if addr != "" else "127.0.0.1"), true))
	box.add_child(row)
	return box


# -- shared widgets -----------------------------------------------------------

func _title_label(text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


func _section_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 12)
	l.modulate = Color(1, 1, 1, 0.55)
	return l


func _muted_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.modulate = Color(1, 1, 1, 0.7)
	return l


func _separator() -> Control:
	var sep := HSeparator.new()
	sep.modulate = Color(1, 1, 1, 0.25)
	return sep


func _spacer(height: int) -> Control:
	var s := Control.new()
	s.custom_minimum_size = Vector2(0, height)
	return s


## `primary` marks the screen's main call to action, drawn wider.
func _menu_button(text: String, on_press: Callable, primary: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(240 if primary else 150, 38 if primary else 34)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.pressed.connect(on_press)
	return b


func _show(screen: Control) -> void:
	for s in [_root_screen, _create_screen, _join_screen]:
		s.visible = s == screen


## Called by World to hide the menu once a game has started.
func close() -> void:
	visible = false
