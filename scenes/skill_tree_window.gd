extends PanelContainer

## The skill-tree spend window (see concept/progression.md). Hidden until
## toggled (toggle_skills, default L). Shows the player's unspent points, a row
## per small stat node (allocate to spend its cost and gain its bonus), and a
## row per keystone (gated behind a minimum allocated-node count). Purely glue:
## the rules live in the tested SkillTree/KeystonePassive/ExperienceTrack; the
## Player applies allocations. Rows below what the player can afford/reach are
## greyed and non-interactive.

const SkillTree = preload("res://src/gameplay/skill_tree.gd")
const KeystonePassive = preload("res://src/gameplay/keystone_passive.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")

## Emitted when the player clicks an allocatable node / keystone. World routes
## it to the local Player, then refreshes.
signal node_allocated(node_id: String)
signal keystone_unlocked(keystone_id: String)

const KEYSTONE_POINT_COST := 2

## Wide enough for the widest row this window's own tables can produce, plus
## UiTheme's panel margins on both sides -- measured, not eyeballed: the
## land_sense keystone row (its written description is the longest string
## either table holds) needs 625px at the engine's default font, so the usable
## width has to clear that. Pinned from BOTH sides -- by
## test_the_widest_skill_row_fits_the_windows_own_declared_width (not narrower
## than its own content) and by
## test_the_window_still_fits_the_room_world_actually_gives_it (not so wide it
## runs off-screen instead).
##
## It declared 320 while that row needed 625, and the ScrollContainer below
## scrolls only vertically, so the surplus was simply cut off -- reported as
## "left-aligned in half the panel".
const WINDOW_SIZE := Vector2(660, 400)
## Leaves room for the title, the unspent-points line and the panel margins
## inside WINDOW_SIZE.y.
const LIST_HEIGHT := 300.0

## Player-facing name per internal stat key. skill_tree.gd/keystone_passive.gd
## store only the key ("max_health"), so without this table the identifier
## itself reached the player verbatim: "Vitality 1 +10.0 max_health (1 pt)".
## Keystones use the same stat vocabulary and read this same table rather than
## a second one that could drift.
const STAT_LABELS := {
	"max_health": "Maximum Health",
	"stamina_regen": "Stamina Regeneration",
	"attack_damage": "Attack Damage",
	"meat_yield": "Meat Yield",
	"carpentry_level": "Carpentry",
}

## Rank numerals for node_title. The index IS the rank, so [0] is unused.
const RANK_NUMERALS := ["", "I", "II", "III", "IV", "V"]

## Player-facing name per keystone id. STORED rather than derived, unlike node
## titles: "berserkers_fury".capitalize() gives "Berserkers Fury" and no amount
## of munging an identifier can put the apostrophe back.
const KEYSTONE_TITLES := {
	"berserkers_fury": "Berserker's Fury",
	"iron_skin": "Iron Skin",
	"swift_current": "Swift Current",
	"land_sense": "Land Sense",
}


## `stat_name`'s player-facing label. Falls back to Godot's own snake_case ->
## Title Case for a stat added to the tables without an entry here, so a
## missing label degrades to something readable instead of leaking a raw key.
static func stat_label(stat_name: String) -> String:
	return STAT_LABELS.get(stat_name, stat_name.capitalize())


## A node's player-facing title: branch name plus a rank numeral --
## "vitality_2" -> "Vitality II". The rank suffix is purely mechanical (every
## branch is _1/_2), so it is derived rather than written out twelve times;
## the branch words themselves all Title-Case cleanly. Keystones are the
## opposite case and carry a written name instead (see KEYSTONE_TITLES).
static func node_title(node_id: String) -> String:
	var parts := node_id.rsplit("_", true, 1)
	if parts.size() == 2 and String(parts[1]).is_valid_int():
		var rank := int(parts[1])
		if rank > 0 and rank < RANK_NUMERALS.size():
			return "%s %s" % [String(parts[0]).capitalize(), RANK_NUMERALS[rank]]
	return node_id.capitalize()


static func keystone_title(keystone_id: String) -> String:
	return String(KEYSTONE_TITLES.get(keystone_id, keystone_id.capitalize()))


## A bonus amount without a pointless trailing ".0": +10, not +10.0.
static func _amount(value: float) -> String:
	return String.num(value, 1).trim_suffix(".0")

var _skill_tree := SkillTree.new()
var _keystones := KeystonePassive.new()
var _points_label: Label
var _list: VBoxContainer


func _ready() -> void:
	visible = false
	custom_minimum_size = WINDOW_SIZE
	# Fully opaque, deliberately: a window you read text off is a surface, not
	# a HUD overlay, and the shared UiTheme.PANEL_BG is very slightly
	# see-through (alpha 0.98) -- as is Godot's own default panel (0.6) when
	# no theme has been assigned yet. Built from UiTheme's own stylebox so
	# this stays the same rounded, bordered panel as every other window,
	# differing only in that the world cannot show through it.
	var opaque := UiTheme.new().panel_stylebox()
	opaque.bg_color = Color(UiTheme.PANEL_BG, 1.0)
	add_theme_stylebox_override("panel", opaque)

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
	scroll.custom_minimum_size = Vector2(0, LIST_HEIGHT)
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
		# refresh() can run synchronously from inside a row's OWN gui_input
		# handler (click -> node_allocated/keystone_unlocked -> World ->
		# refresh, all on the same call stack -- see _row's gui_input
		# connection): that row's Control is still "locked"
		# (mid-signal-emission on itself), and Object.free() refuses to free
		# a locked object. remove_child() detaches it immediately (safe even
		# while locked) without erroring; queue_free() defers the actual
		# deletion until after the call stack unwinds. Same fix as
		# InventoryWindow.refresh.
		_list.remove_child(child)
		child.queue_free()

	_list.add_child(_heading("Stat Nodes"))
	for node_id in _skill_tree.node_ids():
		var info := _skill_tree.node_info(node_id)
		var is_allocated: bool = allocated.get(node_id, false)
		var affordable: bool = int(info["point_cost"]) <= unspent_points
		var title := "%s   +%s %s" % [
			node_title(node_id), _amount(info["bonus_amount"]), stat_label(info["stat_name"])
		]
		_list.add_child(_row(title, "%d pt" % int(info["point_cost"]),
			is_allocated, affordable and not is_allocated,
			func(): node_allocated.emit(node_id)))

	_list.add_child(_heading("Keystones"))
	var node_count: int = allocated.size()
	for keystone_id in _keystones.keystone_ids():
		var info := _keystones.keystone_info(keystone_id)
		var is_unlocked: bool = unlocked.get(keystone_id, false)
		var gated: bool = _keystones.can_unlock(keystone_id, node_count)
		var can_buy: bool = gated and not is_unlocked and unspent_points >= KEYSTONE_POINT_COST
		_list.add_child(_row(
			_keystone_label(keystone_id, info),
			"%d nodes · %d pt" % [int(info["required_node_count"]), KEYSTONE_POINT_COST],
			is_unlocked, can_buy,
			func(): keystone_unlocked.emit(keystone_id)))


## A keystone row's label: the ordinary "+bonus stat" phrasing for a stat
## keystone, or its own real `description` for a REVEAL keystone (empty
## stat_name -- see KeystonePassive._KEYSTONES's own doc comment, e.g.
## land_sense) whose payoff is real information becoming visible, not a
## number going up.
func _keystone_label(keystone_id: String, info: Dictionary) -> String:
	if info["stat_name"] == "":
		return "%s — %s" % [keystone_title(keystone_id), info.get("description", "")]
	return "%s   +%s %s" % [
		keystone_title(keystone_id), _amount(info["bonus_amount"]), stat_label(info["stat_name"])
	]


func _heading(text: String) -> Label:
	var l := Label.new()
	l.text = "— %s —" % text
	l.modulate = Color(1, 1, 1, 0.6)
	return l


## A clickable (when `interactive`) row; shows a check when already `owned`, and
## greys out when neither owned nor interactive.
##
## The title expands to fill the row and the cost sits right-aligned in its own
## Label, so the list reads as a real two-column table instead of one long
## run-on string with its cost buried in parentheses at the end.
func _row(text: String, cost_text: String, owned: bool, interactive: bool,
		on_click: Callable) -> Control:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var label := Label.new()
	label.text = ("✓ " if owned else "") + text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var cost := Label.new()
	cost.text = cost_text
	cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	cost.modulate = Color(1, 1, 1, 0.75)
	row.add_child(cost)
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
