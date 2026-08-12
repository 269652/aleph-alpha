extends PanelContainer

## The inventory + character screen (toggle I). Left: an equipment paperdoll --
## a small rendered character flanked by armor/weapon slots you can click to
## unequip. Right: a grid of item slots (icon + count); click an item to
## equip/wear it (armor/weapon) or eat it (food). PoE/Valheim/Hammerwatch shape.
## Purely glue: what an item does is decided by the tested Player.activate_item_id
## / equip_armor; World routes the signals.

const ProceduralItemSprite = preload("res://src/rendering/procedural_item_sprite.gd")
const ProceduralCharacterSprite = preload("res://src/rendering/procedural_character_sprite.gd")
const Equipment = preload("res://src/gameplay/equipment.gd")

## Clicking an inventory item (equip/eat) vs. clicking a worn slot (unequip).
signal item_clicked(item_id: String)
signal unequip_requested(slot: String)

const SLOT_SIZE := 52.0
const ICON_SIZE := 40.0
## Paperdoll equipment slots are deliberately smaller than item-grid slots:
## five of them stack vertically next to the character preview, and at the
## grid's 52px they overflow the window's anchor box (the reported
## bottom-clipped-off-screen bug -- see test_inventory_window.gd's fits-the-
## anchor-box test pinning this).
const EQUIP_SLOT_SIZE := 40.0
const EQUIP_ICON_SIZE := 30.0
const GRID_COLUMNS := 6

## Display labels for the paperdoll slots.
const SLOT_LABELS := {
	"head": "Head", "chest": "Chest", "legs": "Legs", "feet": "Feet", "weapon": "Weapon",
}

## Human-readable label per Item.kind, shown as a tooltip's second line (see
## _build_item_slot) -- "real game" tooltips show what an item IS, not just
## its name, e.g. "Campfire / Placeable" makes it obvious at a glance that
## it's something you build, not something you eat or wear.
const KIND_LABELS := {
	"weapon": "Weapon", "tool": "Tool", "armor": "Armor", "food": "Food",
	"potion": "Potion", "placeable": "Placeable", "material": "Material",
}

var _item_sprite := ProceduralItemSprite.new()
var _char_sprite := ProceduralCharacterSprite.new()
var _grid: GridContainer
var _paperdoll_icons: Dictionary = {}  # slot -> TextureRect
var _armor_label: Label
## A cheap signature of the last refresh() call's inputs -- see refresh's doc
## comment: World calls refresh() every frame while the window is visible
## (not just on an actual inventory change), so without this every item
## slot's Control is destroyed and recreated every frame, which starves
## Godot's native hover-tooltip timer (it needs the SAME Control instance
## under the mouse continuously) -- the reported "no info on hover" bug.
var _last_refresh_signature := ""


func _ready() -> void:
	visible = false
	# Must stay <= World._build_inventory_window's anchor box (600x460) or the
	# window's bottom clips off-screen -- pinned by test_inventory_window.gd's
	# fits-the-anchor-box test, which measures the real combined minimum with a
	# full paperdoll + full item grid, not just this declared floor.
	custom_minimum_size = Vector2(600, 440)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	add_child(root)

	var title := Label.new()
	title.text = "Character"
	title.add_theme_font_size_override("font_size", 18)
	root.add_child(title)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 16)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(columns)

	columns.add_child(_build_paperdoll())
	columns.add_child(_build_inventory_column())


func toggle() -> void:
	visible = not visible


func _build_paperdoll() -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	col.custom_minimum_size = Vector2(200, 0)

	var heading := Label.new()
	heading.text = "Equipment"
	col.add_child(heading)

	# Character preview: head over torso, from the same procedural sprite used
	# in the world. Compact (see EQUIP_SLOT_SIZE's doc comment) so the whole
	# paperdoll column fits the window's anchor box.
	var preview := VBoxContainer.new()
	preview.alignment = BoxContainer.ALIGNMENT_CENTER
	var head := TextureRect.new()
	head.texture = _char_sprite.generate_head_texture(Vector2i(16, 16), Color(0.85, 0.68, 0.55), Color(0.1, 0.1, 0.12))
	head.custom_minimum_size = Vector2(36, 36)
	head.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.add_child(head)
	var body := TextureRect.new()
	body.texture = _char_sprite.generate_body_part_texture(Vector2i(14, 20), Color(0.3, 0.45, 0.8))
	body.custom_minimum_size = Vector2(36, 44)
	body.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.add_child(body)
	col.add_child(preview)

	for slot in Equipment.SLOTS:
		col.add_child(_build_slot_row(slot))

	_armor_label = Label.new()
	_armor_label.modulate = Color(0.7, 0.85, 0.7)
	col.add_child(_armor_label)
	return col


func _build_slot_row(slot: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var box := PanelContainer.new()
	box.custom_minimum_size = Vector2(EQUIP_SLOT_SIZE, EQUIP_SLOT_SIZE)
	box.mouse_filter = Control.MOUSE_FILTER_STOP
	box.gui_input.connect(_on_slot_gui_input.bind(slot))
	box.tooltip_text = "Click to unequip"
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(EQUIP_ICON_SIZE, EQUIP_ICON_SIZE)
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(icon)
	_paperdoll_icons[slot] = icon
	row.add_child(box)

	var label := Label.new()
	label.text = SLOT_LABELS.get(slot, slot.capitalize())
	row.add_child(label)
	return row


func _build_inventory_column() -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var heading := Label.new()
	heading.text = "Inventory  (click to use / equip)"
	col.add_child(heading)

	_grid = GridContainer.new()
	_grid.columns = GRID_COLUMNS
	_grid.add_theme_constant_override("h_separation", 6)
	_grid.add_theme_constant_override("v_separation", 6)
	col.add_child(_grid)
	return col


## Rebuilds the item grid from `stacks` and the paperdoll from `equipped`
## (slot -> Item) and `total_armor`. The grid always shows `slot_count` slot
## frames -- leading ones filled with items, the rest as dim empty frames --
## so the inventory reads as a real fixed-capacity container (Diablo/Terraria
## style) instead of a loose pile of icons floating in empty panel space.
## World calls this every frame while the window is visible, not just on an
## actual change -- a no-op early-out when nothing changed since the last
## call keeps that cheap AND keeps each slot's Control instance stable across
## frames, which real hover tooltips need (see _last_refresh_signature).
func refresh(stacks: Array, equipped: Dictionary, total_armor: float, slot_count: int = 12) -> void:
	var signature := _signature_for(stacks, equipped, total_armor, slot_count)
	if signature == _last_refresh_signature:
		return
	_last_refresh_signature = signature

	for child in _grid.get_children():
		# refresh() can run synchronously from inside a slot's OWN gui_input
		# handler (click -> item_clicked -> World -> Player -> refresh, all
		# on the same call stack -- see _on_item_gui_input): that slot's
		# Control is still "locked" (mid-signal-emission on itself), and
		# Object.free() refuses to free a locked object ("Attempted to free
		# a locked object"). remove_child() detaches it immediately (safe
		# even while locked) without erroring, so the grid rebuild below
		# still completes correctly; queue_free() defers the actual
		# deletion until after the call stack unwinds.
		_grid.remove_child(child)
		child.queue_free()
	for i in slot_count:
		if i < stacks.size():
			_grid.add_child(_build_item_slot(stacks[i]))
		else:
			_grid.add_child(_build_empty_slot())

	for slot in _paperdoll_icons:
		var icon: TextureRect = _paperdoll_icons[slot]
		var item = equipped.get(slot)
		icon.texture = _item_sprite.generate_texture(item.id) if item != null else null
	_armor_label.text = "Armor: %d" % int(total_armor)


## A cheap string fingerprint of everything refresh()'s output depends on --
## two calls with an identical signature would rebuild an identical grid, so
## the second one can just be skipped.
func _signature_for(stacks: Array, equipped: Dictionary, total_armor: float, slot_count: int) -> String:
	var stack_parts: Array = []
	for stack in stacks:
		stack_parts.append("%s:%d" % [stack.item.id, stack.count])

	var equipped_slots := equipped.keys()
	equipped_slots.sort()
	var equipped_parts: Array = []
	for slot in equipped_slots:
		equipped_parts.append("%s=%s" % [slot, equipped[slot].id])

	return "%s|%s|%.2f|%d" % [
		"|".join(stack_parts), "|".join(equipped_parts), total_armor, slot_count
	]


## A dimmed, non-interactive slot frame marking unused inventory capacity.
func _build_empty_slot() -> Control:
	var box := PanelContainer.new()
	box.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
	box.self_modulate = Color(1, 1, 1, 0.35)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return box


func _build_item_slot(stack) -> Control:
	var box := PanelContainer.new()
	box.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
	box.mouse_filter = Control.MOUSE_FILTER_STOP
	box.gui_input.connect(_on_item_gui_input.bind(stack.item.id))
	box.tooltip_text = _item_tooltip_text(stack)
	box.mouse_entered.connect(func(): box.modulate = Color(1.15, 1.15, 1.15))
	box.mouse_exited.connect(func(): box.modulate = Color(1, 1, 1))

	var icon := TextureRect.new()
	icon.texture = _item_sprite.generate_texture(stack.item.id)
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(icon)

	if stack.count > 1:
		var count := Label.new()
		count.text = str(stack.count)
		count.add_theme_font_size_override("font_size", 10)
		count.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		count.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(count)
	return box


## "Iron Sword" -> "Iron Sword\nWeapon" (name, then kind), and a stack count
## line when there's more than one -- so hovering tells you what an item is,
## not just its name, matching Diablo/Terraria-style tooltips rather than
## Godot's plain default hover text.
func _item_tooltip_text(stack) -> String:
	var lines := [stack.item.display_name, KIND_LABELS.get(stack.item.kind, stack.item.kind.capitalize())]
	if stack.count > 1:
		lines.append("x%d" % stack.count)
	return "\n".join(lines)


func _on_item_gui_input(event: InputEvent, item_id: String) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		item_clicked.emit(item_id)


func _on_slot_gui_input(event: InputEvent, slot: String) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		unequip_requested.emit(slot)
