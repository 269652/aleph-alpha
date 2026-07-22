extends PanelContainer

## The start-up main menu (see concept/progression.md character creation). Shown
## over the world before anything spawns; the world stays paused until the player
## chooses. Screens: root (New Game / Host / Join / Settings / Quit), class-pick
## (New Game + Host both route through it), and a join screen (IP entry). Purely
## glue -- World owns actually spawning the player, starting ENet, and applying
## the chosen class's stat lens (ClassArchetype).

const ClassArchetype = preload("res://src/gameplay/class_archetype.gd")
const ProceduralCharacterSprite = preload("res://src/rendering/procedural_character_sprite.gd")

## A body tint per class so the character preview reads differently per pick.
const CLASS_BODY_COLORS := {
	"warrior": Color(0.6, 0.2, 0.2),
	"mage": Color(0.3, 0.3, 0.7),
	"ranger": Color(0.25, 0.5, 0.28),
	"beastmaster": Color(0.5, 0.4, 0.2),
	"artisan": Color(0.55, 0.45, 0.3),
	"herbalist": Color(0.35, 0.55, 0.45),
	"overseer": Color(0.45, 0.4, 0.5),
}

## Human-readable blurbs for the archetypes (ClassArchetype has the stats).
const CLASS_BLURBS := {
	"warrior": "Warrior — tanky melee bruiser. High health & attack.",
	"mage": "Mage — glass-cannon caster. Big mana, frail.",
	"ranger": "Ranger — agile skirmisher. Balanced, stamina-heavy.",
	"beastmaster": "Beastmaster — tamer/support. Rounded stats.",
	"artisan": "Artisan — crafter. Sturdy, high stamina.",
	"herbalist": "Herbalist — medic/caster. Mana over might.",
	"overseer": "Overseer — organizer. Modest mana.",
}

## Emitted once the player has committed to a start mode + class.
## mode is "single" or "host"; class_name is a ClassArchetype name.
signal start_requested(mode: String, chosen_class: String)
## Emitted to join a remote host at `address`.
signal join_requested(address: String)

var _archetypes := ClassArchetype.new()
var _root_screen: Control
var _class_screen: Control
var _join_screen: Control
var _pending_mode := "single"
var _selected_class := "warrior"
var _class_detail: Label
var _char_sprite := ProceduralCharacterSprite.new()
var _preview_body: TextureRect


func _ready() -> void:
	set_anchors_preset(Control.PRESET_CENTER)
	custom_minimum_size = Vector2(440, 380)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	add_child(margin)

	var stack := Control.new()
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(stack)

	_root_screen = _build_root_screen()
	_class_screen = _build_class_screen()
	_join_screen = _build_join_screen()
	for s in [_root_screen, _class_screen, _join_screen]:
		s.set_anchors_preset(Control.PRESET_FULL_RECT)
		stack.add_child(s)
	_show(_root_screen)


func _build_root_screen() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)

	var title := Label.new()
	title.text = "Aleph Alfa"
	title.add_theme_font_size_override("font_size", 28)
	box.add_child(title)

	box.add_child(_menu_button("New Game (Single-Player)", func():
		_pending_mode = "single"
		_show(_class_screen)))
	box.add_child(_menu_button("Host Game (LAN / multiplayer)", func():
		_pending_mode = "host"
		_show(_class_screen)))
	box.add_child(_menu_button("Join Game…", func(): _show(_join_screen)))
	box.add_child(_menu_button("Quit", func(): get_tree().quit()))
	return box


func _build_class_screen() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)

	var title := Label.new()
	title.text = "Choose your class"
	title.add_theme_font_size_override("font_size", 20)
	box.add_child(title)

	# Two columns: the class buttons on the left, a live pixel-art character
	# preview on the right that re-tints per selected class.
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 20)
	box.add_child(cols)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(left)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 6)
	left.add_child(grid)
	for archetype in _archetypes.archetype_names():
		var b := Button.new()
		b.text = archetype.capitalize()
		b.pressed.connect(func(): _select_class(archetype))
		grid.add_child(b)

	_class_detail = Label.new()
	_class_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_class_detail.custom_minimum_size = Vector2(0, 60)
	left.add_child(_class_detail)

	cols.add_child(_build_character_preview())
	_select_class(_selected_class)

	var row := HBoxContainer.new()
	row.add_child(_menu_button("Back", func(): _show(_root_screen)))
	row.add_child(_menu_button("Start", func():
		start_requested.emit(_pending_mode, _selected_class)))
	box.add_child(row)
	return box


## The class character preview: a fixed head over a class-tinted torso, using
## the same procedural sprite as the in-world player.
func _build_character_preview() -> Control:
	var frame := VBoxContainer.new()
	frame.alignment = BoxContainer.ALIGNMENT_CENTER
	frame.custom_minimum_size = Vector2(120, 0)

	var head := TextureRect.new()
	head.texture = _char_sprite.generate_head_texture(Vector2i(16, 16), Color(0.85, 0.68, 0.55), Color(0.1, 0.1, 0.12))
	head.custom_minimum_size = Vector2(64, 64)
	head.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	frame.add_child(head)

	_preview_body = TextureRect.new()
	_preview_body.custom_minimum_size = Vector2(64, 84)
	_preview_body.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	frame.add_child(_preview_body)
	return frame


func _build_join_screen() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)

	var title := Label.new()
	title.text = "Join a host"
	title.add_theme_font_size_override("font_size", 20)
	box.add_child(title)

	var hint := Label.new()
	hint.text = "Enter the host's address (LAN IP, or a tunnel host for internet play)."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.modulate = Color(1, 1, 1, 0.6)
	box.add_child(hint)

	var field := LineEdit.new()
	field.placeholder_text = "127.0.0.1"
	box.add_child(field)

	var row := HBoxContainer.new()
	row.add_child(_menu_button("Back", func(): _show(_root_screen)))
	row.add_child(_menu_button("Connect", func():
		var addr: String = field.text.strip_edges()
		join_requested.emit(addr if addr != "" else "127.0.0.1")))
	box.add_child(row)
	return box


func _select_class(archetype: String) -> void:
	_selected_class = archetype
	var stats: Dictionary = _archetypes.stats_for(archetype)
	_class_detail.text = "%s\n(HP %+d, ATK %+d, Mana %+d, Stamina %+d)" % [
		CLASS_BLURBS.get(archetype, archetype),
		int(stats.get("max_health", 0.0)),
		int(stats.get("attack_damage", 0.0)),
		int(stats.get("max_mana", 0.0)),
		int(stats.get("max_stamina", 0.0)),
	]
	if _preview_body != null:
		var tint: Color = CLASS_BODY_COLORS.get(archetype, Color(0.3, 0.45, 0.8))
		_preview_body.texture = _char_sprite.generate_body_part_texture(Vector2i(14, 20), tint)


func _menu_button(text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(180, 34)
	b.pressed.connect(on_press)
	return b


func _show(screen: Control) -> void:
	for s in [_root_screen, _class_screen, _join_screen]:
		s.visible = s == screen


## Called by World to hide the menu once a game has started.
func close() -> void:
	visible = false
