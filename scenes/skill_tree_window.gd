extends PanelContainer

## The skill-tree spend window (see concept/progression.md). Hidden until
## toggled (toggle_skills, default K). Shows the player's unspent points, a row
## per small stat node (allocate to spend its cost and gain its bonus), and a
## row per keystone (gated behind a minimum allocated-node count). Purely glue:
## the rules live in the tested SkillTree/KeystonePassive/ExperienceTrack; the
## Player applies allocations. Rows below what the player can afford/reach are
## greyed and non-interactive.

const SkillTree = preload("res://src/gameplay/skill_tree.gd")
const KeystonePassive = preload("res://src/gameplay/keystone_passive.gd")

## Emitted when the player clicks an allocatable node / keystone. World routes
## it to the local Player, then refreshes.
signal node_allocated(node_id: String)
signal keystone_unlocked(keystone_id: String)

const KEYSTONE_POINT_COST := 2

var _skill_tree := SkillTree.new()
var _keystones := KeystonePassive.new()
var _points_label: Label
var _list: VBoxContainer


func _ready() -> void:
	visible = false
	custom_minimum_size = Vector2(320, 300)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 4)
	add_child(root)

	var title := Label.new()
	title.text = "Skill Tree"
	title.add_theme_font_size_override("font_size", 16)
	root.add_child(title)

	_points_label = Label.new()
	root.add_child(_points_label)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 240)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)


func toggle() -> void:
	visible = not visible


func is_open() -> bool:
	return visible


## Rebuilds the rows from the player's current allocation + unspent points.
## `allocated` and `unlocked` are the player's node/keystone -> true maps.
func refresh(unspent_points: int, allocated: Dictionary, unlocked: Dictionary) -> void:
	_points_label.text = "Unspent points: %d" % unspent_points
	for child in _list.get_children():
		child.free()

	_list.add_child(_heading("Stat Nodes"))
	for node_id in _skill_tree.node_ids():
		var info := _skill_tree.node_info(node_id)
		var is_allocated: bool = allocated.get(node_id, false)
		var affordable: bool = int(info["point_cost"]) <= unspent_points
		var label := "%s  +%s %s  (%d pt)" % [
			node_id.capitalize(), str(info["bonus_amount"]), info["stat_name"], int(info["point_cost"])
		]
		_list.add_child(_row(label, is_allocated, affordable and not is_allocated,
			func(): node_allocated.emit(node_id)))

	_list.add_child(_heading("Keystones"))
	var node_count: int = allocated.size()
	for keystone_id in _keystones.keystone_ids():
		var info := _keystones.keystone_info(keystone_id)
		var is_unlocked: bool = unlocked.get(keystone_id, false)
		var gated: bool = _keystones.can_unlock(keystone_id, node_count)
		var can_buy: bool = gated and not is_unlocked and unspent_points >= KEYSTONE_POINT_COST
		var label := "%s  +%s %s  (needs %d nodes, %d pt)" % [
			keystone_id.capitalize(), str(info["bonus_amount"]), info["stat_name"],
			int(info["required_node_count"]), KEYSTONE_POINT_COST
		]
		_list.add_child(_row(label, is_unlocked, can_buy,
			func(): keystone_unlocked.emit(keystone_id)))


func _heading(text: String) -> Label:
	var l := Label.new()
	l.text = "— %s —" % text
	l.modulate = Color(1, 1, 1, 0.6)
	return l


## A clickable (when `interactive`) row; shows a check when already `owned`, and
## greys out when neither owned nor interactive.
func _row(text: String, owned: bool, interactive: bool, on_click: Callable) -> Control:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = ("✓ " if owned else "") + text
	row.add_child(label)
	if owned:
		row.modulate = Color(0.6, 0.9, 0.6)
	elif interactive:
		row.mouse_filter = Control.MOUSE_FILTER_STOP
		row.gui_input.connect(func(e):
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				on_click.call())
	else:
		row.modulate = Color(1, 1, 1, 0.4)
	return row
