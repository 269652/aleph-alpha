extends PanelContainer

## The skill-tree spend window (see concept/progression.md). Hidden until
## toggled (toggle_skills, default L). Shows the player's unspent points, a row
## per small stat node (allocate to spend its cost and gain its bonus), and a
## row per keystone (gated behind a minimum allocated-node count). Purely glue:
## the rules live in the tested SkillTree/KeystonePassive/ExperienceTrack; the
## Player applies allocations. Rows below what the player can afford/reach are
## greyed and non-interactive.

const SkillTree = preload("res://src/gameplay/skill_tree.gd")
const SkillWeb = preload("res://src/gameplay/skill_web.gd")
const KeystonePassive = preload("res://src/gameplay/keystone_passive.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")
const SkillWebView = preload("res://scenes/skill_web_view.gd")

## Emitted when the player clicks an allocatable node / keystone. World routes
## it to the local Player, then refreshes.
signal node_allocated(node_id: String)
signal keystone_unlocked(keystone_id: String)
## Free respec (docs/concept/classes.md) -- right-click on an owned node in the
## web view. World routes it to Player.refund_skill.
signal node_refunded(node_id: String)

## The graph is the primary way to spend a point (docs/concept/skills.md); the
## flat list stays reachable behind a tab, since a scrolling list of named rows
## is the readable fallback a canvas of circles cannot be.
const MODE_WEB := "web"
const MODE_LIST := "list"

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
## The project's own design viewport (display/window/size/*), which with the
## canvas_items stretch mode IS the coordinate space this window is laid out in.
## Read as a constant here and pinned against ProjectSettings by
## test_the_windows_design_viewport_is_the_projects_own -- the first version of
## this window was sized against a 960x540 figure copied out of a stale comment
## in world.gd and so gave the map barely half the room it had.
const DESIGN_VIEWPORT := Vector2(1280, 720)

## Gap left between the window and the screen edge on every side. Small: the web
## wants the room, and this is a full-attention modal, not a HUD panel.
const SCREEN_MARGIN := 20.0

## The web is a MAP -- it gets the whole screen bar the margin. The list tab's
## widest row (625px, measured; see
## test_the_widest_skill_row_fits_the_windows_own_declared_width) fits inside
## this several times over.
const WINDOW_SIZE := DESIGN_VIEWPORT - Vector2(SCREEN_MARGIN, SCREEN_MARGIN) * 2.0

## The room World actually gives this window: it anchors it PRESET_CENTER, so
## the usable box is the design viewport less a hair. Stated HERE, once, and
## read by the test that used to restate it.
const WORLD_AVAILABLE_BOX := DESIGN_VIEWPORT - Vector2(8.0, 8.0)

## Height reserved for the title, the unspent-points line, the tab row, the
## detail line, the separations between them and the panel margins -- everything
## that is not canvas. A declared RESERVE rather than a measurement, held honest
## by test_the_reserved_chrome_really_does_hold_the_windows_own_chrome, which
## measures the window's real minimum against WINDOW_SIZE.
const CHROME_HEIGHT := 150.0

## Everything left over goes to the map.
const CANVAS_HEIGHT := WINDOW_SIZE.y - CHROME_HEIGHT
const LIST_HEIGHT := CANVAS_HEIGHT

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
	# The web's wider vocabulary (see SkillWeb's wedge tables). Written out
	# rather than left to the snake_case fallback wherever Title Case alone
	# reads as an identifier ("Max Mana") instead of as a stat.
	"max_mana": "Maximum Mana",
	"max_stamina": "Maximum Stamina",
	"knockback_resist": "Knockback Resistance",
	"spell_efficiency": "Spell Efficiency",
	"spell_power": "Spell Power",
	"spell_atom_tier": "Spell Atom Tier",
	"scent_range": "Scent Range",
	"throw_force": "Throwing Force",
	"pet_loyalty": "Pet Loyalty",
	"pet_health": "Pet Health",
	"taming_affinity": "Taming Affinity",
	"mining_yield": "Mining Yield",
	"ore_yield": "Ore Yield",
	"smelting_yield": "Smelting Yield",
	"craft_quality": "Craft Quality",
	"wound_recovery": "Wound Recovery",
	"disease_resistance": "Disease Resistance",
	"venom_resistance": "Venom Resistance",
	"hire_capacity": "Hire Capacity",
	"trade_margin": "Trade Margin",
	"contract_throughput": "Contract Throughput",
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
	"apex_predator": "Apex Predator",
	"archmage": "Archmage",
	"deep_lore": "Deep Lore",
	"alpha_bond": "Alpha Bond",
	"menagerie": "Menagerie",
	"grand_workshop": "Grand Workshop",
	"deep_delver": "Deep Delver",
	"lifebloom": "Lifebloom",
	"guildmaster": "Guildmaster",
	"grand_charter": "Grand Charter",
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
var _scroll: ScrollContainer
## The graph canvas (see SkillWebView). Public so World and tests can drive it.
var web_view: SkillWebView
var mode := MODE_WEB
var _detail_label: Label
var _tab_buttons: Dictionary = {}
var _web := SkillWeb.new()


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

	root.add_child(_build_tabs())

	web_view = SkillWebView.new()
	web_view.custom_minimum_size = Vector2(
		WINDOW_SIZE.x - 2.0 * UiTheme.CONTENT_MARGIN, CANVAS_HEIGHT)
	web_view.node_clicked.connect(_on_web_node_clicked)
	web_view.node_refund_requested.connect(func(node_id): node_refunded.emit(node_id))
	root.add_child(web_view)

	_scroll = ScrollContainer.new()
	_scroll.custom_minimum_size = Vector2(0, LIST_HEIGHT)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_list)

	_detail_label = Label.new()
	_detail_label.modulate = Color(1, 1, 1, 0.85)
	root.add_child(_detail_label)

	set_mode(MODE_WEB)


## Two plain buttons rather than a TabContainer: the panels differ in nothing
## but visibility, and a TabContainer would take ownership of the layout the
## rest of this window already sets up.
func _build_tabs() -> Control:
	var row := HBoxContainer.new()
	for tab in [MODE_WEB, MODE_LIST]:
		var button := Button.new()
		button.text = "Web" if tab == MODE_WEB else "List"
		button.toggle_mode = true
		button.pressed.connect(set_mode.bind(tab))
		row.add_child(button)
		_tab_buttons[tab] = button
	return row


## Points this window at ONE character's web (see SkillWebView.configure) and
## opens on their own class's start node -- a map that opens on someone else's
## corner of it is a map you have to find yourself on first.
func configure_web(web: SkillWeb, archetype: String, resonance: Dictionary,
		dna_seed: int) -> void:
	_web = web
	web_view.configure(web, archetype, resonance, dna_seed)
	web_view.focus_on(web.start_node_for(archetype))


func set_mode(new_mode: String) -> void:
	mode = new_mode
	web_view.visible = mode == MODE_WEB
	_scroll.visible = mode == MODE_LIST
	for tab in _tab_buttons:
		(_tab_buttons[tab] as Button).button_pressed = tab == mode


## The web has no separate notion of a keystone allocation -- keystones are
## ordinary nodes on it -- but World routes the two differently (a keystone also
## has to clear KeystonePassive's node-count gate in Player.unlock_keystone), so
## the click is sorted here rather than there.
func _on_web_node_clicked(node_id: String) -> void:
	if _web.node_info(node_id).get("kind", "") == SkillWeb.KIND_KEYSTONE:
		keystone_unlocked.emit(node_id)
	else:
		node_allocated.emit(node_id)


func toggle() -> void:
	visible = not visible


func is_open() -> bool:
	return visible


## Rebuilds the rows from the player's current allocation + unspent points.
## `allocated` and `unlocked` are the player's node/keystone -> true maps.
func refresh(unspent_points: int, allocated: Dictionary, unlocked: Dictionary) -> void:
	_points_label.text = "Unspent points: %d" % unspent_points
	# Keystones are ordinary nodes on the web but the Player still tracks them in
	# their own map (persistence, the land_sense HUD readout), and a save written
	# before keystones moved onto the web has them ONLY there -- so the view is
	# handed the union rather than allocated alone, or such a build would show a
	# hole where its keystone is.
	var owned := allocated.duplicate()
	for keystone_id in unlocked:
		if unlocked[keystone_id]:
			owned[keystone_id] = true
	web_view.set_allocation(owned, unspent_points)
	_refresh_detail()
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



## The line under the canvas: what the last-clicked node is, grants and costs
## THIS character (see SkillWebView.node_label). Falls back to an instruction
## rather than to an empty line -- a blank strip under a graph of 84 circles
## teaches the player nothing about how to use it.
func _refresh_detail() -> void:
	var selected := web_view.selected_node_id
	if selected == "":
		_detail_label.text = "Click a node to inspect it · right-click one you own to refund it"
		return
	_detail_label.text = "%s   [%s]" % [
		web_view.node_label(selected), _state_word(web_view.state_of(selected))]


func _state_word(state: String) -> String:
	match state:
		SkillWebView.STATE_ALLOCATED:
			return "owned"
		SkillWebView.STATE_TAKEABLE:
			return "available"
		SkillWebView.STATE_UNAFFORDABLE:
			return "not enough points"
		_:
			return "no path yet"


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
