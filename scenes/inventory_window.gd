extends PanelContainer

## The inventory + character screen (toggle I). Left: an equipment paperdoll --
## a small rendered character flanked by armor/weapon slots you can
## right-click to unequip. Right: a grid of item slots (icon + count);
## right-click an item to equip/wear it (armor/weapon) or eat it (food);
## left-click and drag to reorder within the grid, drop onto a HUD hotbar
## slot to bind it, or drop onto the world to throw it away.
## PoE/Valheim/Hammerwatch shape. Purely glue: what an item does is decided
## by the tested Player.activate_item_id/equip_armor; World routes the
## signals.
##
## Deliberately RIGHT-click for the destructive "use it now" action, not
## left: left is also the drag gesture (see DragSlot), and Godot's
## _get_drag_data only ever triggers off the LEFT button. Wiring "use" to
## left too meant a click that was actually the START of a drag (mouse-down
## before it moved past the drag threshold) fired activate_item_id on press,
## the same instant -- a food item you meant to pick up and move quietly ate
## itself, and a weapon you meant to drag onto the hotbar re-equipped in
## place first. Reported as "a click on a carrot makes it vanish". Right
## never starts a drag in Godot, so it can't collide with one.

const ProceduralItemSprite = preload("res://src/rendering/procedural_item_sprite.gd")
## The real character rig, the same one the player/NPCs/character creator use
## -- the equipment paperdoll renders it rather than a second, flatter
## approximation of a person (see _build_character_preview).
const CharacterViewScene = preload("res://scenes/character_view.tscn")
const Equipment = preload("res://src/gameplay/equipment.gd")
const DragSlot = preload("res://src/ui/drag_slot.gd")
## Only for naming/describing the material an item's real mass was derived
## from in its tooltip (see _material_line) -- this window never builds Items,
## World hands it the real ones.
const ItemCatalog = preload("res://src/gameplay/item_catalog.gd")
const MaterialProperties = preload("res://src/gameplay/material_properties.gd")
## Food really goes off in your pack (see ItemStack.freshness / Inventory's
## own ageing) -- these turn that into the two lines a tooltip can show.
const FruitSpoilage = preload("res://src/gameplay/fruit_spoilage.gd")
const SeasonCycle = preload("res://src/world/season_cycle.gd")

## Clicking an inventory item (equip/eat) vs. clicking a worn slot (unequip).
signal item_clicked(item_id: String)
signal unequip_requested(slot: String)
## Dragging one inventory item onto another slot (reorder). `to_index` is a
## grid position; World applies it to the real Inventory (see
## Inventory.swap_slots/move_to_end).
signal items_reordered(from_index: int, to_index: int)

## Payload "source" tag for a drag that started in the inventory grid -- the
## HUD hotbar checks this so it only accepts inventory drags (see
## World._build_hotbar_slots).
const DRAG_SOURCE_INVENTORY := "inventory"

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

## The paperdoll preview's height, in screen pixels. NOT a free choice: 84 is
## exactly what the flat head+torso stack this replaced occupied (36 head + the
## column's 4px separation + 44 body), so swapping the real rig in cannot grow
## this window's minimum height past World._build_inventory_window's 600x460
## anchor box -- the bottom-clipped-off-screen bug class that
## test_window_minimum_size_fits_the_anchor_box_world_gives_it pins against.
const PAPERDOLL_VIEW_HEIGHT := 84

## How much of the preview's height the character fills -- headroom so head
## and feet aren't flush against the frame. A framing choice for this preview,
## named rather than baked into the zoom expression (see
## _build_character_preview).
const PAPERDOLL_FILL_FRACTION := 0.9

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
var _catalog := ItemCatalog.new()
var _materials := MaterialProperties.new()
var _grid: GridContainer
## The paperdoll's real character rig (see _build_character_preview).
var _preview_view: CharacterView
## The look currently worn by _preview_view. CharacterView.apply_appearance
## REGENERATES every part texture, and World calls refresh()/apply_appearance
## every frame while this window is open, so an unchanged look must be a
## no-op (see apply_appearance).
var _preview_appearance: Dictionary = {}
var _paperdoll_icons: Dictionary = {}  # slot -> TextureRect
var _armor_label: Label
## A cheap signature of the last refresh() call's inputs -- see refresh's doc
## comment: World calls refresh() every frame while the window is visible
## (not just on an actual inventory change), so without this every item
## slot's Control is destroyed and recreated every frame, which starves
## Godot's native hover-tooltip timer (it needs the SAME Control instance
## under the mouse continuously) -- the reported "no info on hover" bug.
var _last_refresh_signature := ""
## The world season the last refresh() was given, or "" for "the caller didn't
## tell us" -- see refresh(). Food spoilage can only be resolved against a
## season, so with "" the tooltip's freshness/shelf-life lines are omitted.
var _season := ""


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

	var preview := CenterContainer.new()
	preview.add_child(_build_character_preview())
	col.add_child(preview)

	for slot in Equipment.SLOTS:
		col.add_child(_build_slot_row(slot))

	_armor_label = Label.new()
	_armor_label.modulate = Color(0.7, 0.85, 0.7)
	col.add_child(_armor_label)
	return col


## The paperdoll's character: the SAME CharacterView rig the player, every NPC
## and the character creator's preview already use (see CharacterPreviewStage's
## own doc comment on why -- one rig, not a second one that can silently
## drift), inside a SubViewport because a Node2D takes no part in Control
## layout at all. Copies main_menu.gd's _build_diorama_view wiring.
##
## This replaces a hand-built 36x36 head TextureRect stacked on a flat blue
## 36x44 rectangle: no torso art, no arms, no legs, and no relationship
## whatsoever to the look the player authored in the character creator --
## reported as "a floating head above a blue box", while the same character
## rendered correctly two feet away in the live world.
func _build_character_preview() -> Control:
	var view_size := Vector2i(_paperdoll_view_width(), PAPERDOLL_VIEW_HEIGHT)

	var container := SubViewportContainer.new()
	container.custom_minimum_size = Vector2(view_size)
	container.stretch = true
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var viewport := SubViewport.new()
	viewport.size = view_size
	viewport.transparent_bg = true
	# UPDATE_ALWAYS, like the character creator's diorama: the rig's idle/arm
	# animation runs from CharacterView._process and would otherwise freeze.
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	container.add_child(viewport)

	# CharacterView's own origin IS its feet (pinned by test_character_view.gd's
	# feet-anchoring test) and it scales ITSELF to CharacterView.SCALE in
	# _ready, so its real on-screen height falls straight out of the rig's own
	# published geometry -- no eyeballed zoom number, and it self-corrects if
	# SCALE or the .tscn layout ever change.
	var character_height: float = -CharacterView.HEAD_TOP_Y * CharacterView.SCALE
	var camera := Camera2D.new()
	camera.zoom = Vector2.ONE * (
		float(PAPERDOLL_VIEW_HEIGHT) * PAPERDOLL_FILL_FRACTION / character_height
	)
	# Frame the character's vertical mid-point, not its feet.
	camera.position = Vector2(0.0, -character_height * 0.5)
	viewport.add_child(camera)

	_preview_view = CharacterViewScene.instantiate()
	viewport.add_child(_preview_view)
	return container


## The preview viewport's width: the character's OWN aspect at
## PAPERDOLL_VIEW_HEIGHT (its shoulder width over its total height, both from
## CharacterView's published geometry), rounded up -- an independently chosen
## width would either crop the shoulders or pad the column with dead space.
func _paperdoll_view_width() -> int:
	var aspect := float(CharacterView.BODY_SIZE.x) / -CharacterView.HEAD_TOP_Y
	return int(ceil(PAPERDOLL_VIEW_HEIGHT * aspect))


## Dresses the paperdoll with the local player's real authored look (see
## HeroAppearance / Player.appearance) -- a passthrough mirroring
## CharacterPreviewStage.apply_appearance, which does exactly this for the
## character creator's preview.
##
## Skips an unchanged look: apply_appearance regenerates every part texture,
## and World calls this every frame while the window is open.
func apply_appearance(appearance: Dictionary) -> void:
	if appearance == _preview_appearance:
		return
	_preview_appearance = appearance
	_preview_view.apply_appearance(appearance)


func _build_slot_row(slot: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var box := PanelContainer.new()
	box.custom_minimum_size = Vector2(EQUIP_SLOT_SIZE, EQUIP_SLOT_SIZE)
	box.mouse_filter = Control.MOUSE_FILTER_STOP
	box.gui_input.connect(_on_slot_gui_input.bind(slot))
	box.tooltip_text = "Right-click to unequip"
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
	heading.text = "Inventory  (right-click to use / equip · drag to move)"
	# Wrap against a FIXED width rather than the label's own natural size --
	# autowrap alone, with no minimum width set, collapses the label's
	# horizontal minimum toward zero and wraps nearly character-by-character
	# into an enormous height instead. 300px matches the grid column's own
	# rough width, so this reads as a normal two-line hint (see
	# test_window_minimum_size_fits_the_anchor_box_world_gives_it, which
	# pins the window's overall min size against World's anchor box).
	heading.custom_minimum_size = Vector2(300, 0)
	heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
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
##
## `season` is the world's current season (see EarthChunkManager.current_
## season). Food spoilage is season-dependent by construction (FruitSpoilage),
## so a caller that doesn't know the season passes "" and the freshness/shelf-
## life lines are omitted rather than resolved against a guessed one.
func refresh(stacks: Array, equipped: Dictionary, total_armor: float, slot_count: int = 12,
		season: String = "") -> void:
	var signature := _signature_for(stacks, equipped, total_armor, slot_count, season)
	if signature == _last_refresh_signature:
		return
	_last_refresh_signature = signature
	_season = season  # read back by _build_item_slot -> _item_tooltip_text

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
			_grid.add_child(_build_item_slot(stacks[i], i))
		else:
			_grid.add_child(_build_empty_slot(i))

	for slot in _paperdoll_icons:
		var icon: TextureRect = _paperdoll_icons[slot]
		var item = equipped.get(slot)
		icon.texture = _item_sprite.generate_texture(item.id) if item != null else null

	# Put the equipped weapon in the paperdoll character's actual hand, the
	# same way Player.equip_item does for the world rig -- the slot frame
	# beside the character already showed the icon, but the character itself
	# stood there empty-handed.
	var worn_weapon = equipped.get("weapon")
	if worn_weapon != null:
		_preview_view.equip_weapon(_item_sprite.generate_texture(worn_weapon.id))
	else:
		_preview_view.unequip_slot("tool")

	_armor_label.text = "Armor: %d" % int(total_armor)


## A cheap string fingerprint of everything refresh()'s output depends on --
## two calls with an identical signature would rebuild an identical grid, so
## the second one can just be skipped.
##
## Freshness is CONTINUOUS, so it enters here QUANTIZED to the whole percent
## the tooltip actually displays. Feeding the raw float in would change the
## signature every single frame a food stack ages, rebuilding every slot
## Control every frame and re-breaking Godot's native hover tooltip -- the
## exact bug _last_refresh_signature exists to prevent (see its own doc
## comment). Quantized, the grid rebuilds only when a DISPLAYED number really
## changes: for the fastest-rotting food that is roughly once every 260 world
## seconds (cherry in summer keeps 1.8 days = 25920s, so 1% of it), which no
## hover can notice.
func _signature_for(stacks: Array, equipped: Dictionary, total_armor: float, slot_count: int,
		season: String) -> String:
	var stack_parts: Array = []
	for stack in stacks:
		stack_parts.append("%s:%d:%d" % [
			stack.item.id, stack.count, _freshness_percent(stack, season)
		])

	var equipped_slots := equipped.keys()
	equipped_slots.sort()
	var equipped_parts: Array = []
	for slot in equipped_slots:
		equipped_parts.append("%s=%s" % [slot, equipped[slot].id])

	return "%s|%s|%.2f|%d|%s" % [
		"|".join(stack_parts), "|".join(equipped_parts), total_armor, slot_count, season
	]


## This stack's soundness as the whole percent the tooltip shows, or -1 when
## there is no season to resolve it against (see refresh's `season`) or the
## item is not food -- FruitSpoilage only means anything for food.
func _freshness_percent(stack, season: String) -> int:
	if season == "" or stack.item.kind != "food":
		return -1
	# ROUNDED, not truncated. Truncation moves the displayed percent on the
	# very first tick of ageing (a freshness of 0.999998 truncates to 99%),
	# which would defeat the whole point of quantizing -- see _signature_for.
	return roundi(stack.freshness(season) * 100.0)


## A dimmed slot frame marking unused inventory capacity. Accepts drops (so
## you can drag an item into empty space to move it to the end) but is never
## itself a drag source.
func _build_empty_slot(grid_index: int) -> Control:
	var box := DragSlot.new()
	box.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
	box.self_modulate = Color(1, 1, 1, 0.35)
	box.mouse_filter = Control.MOUSE_FILTER_STOP
	box.can_accept = func(payload): return _is_inventory_payload(payload)
	box.dropped = func(payload): items_reordered.emit(int(payload["index"]), grid_index)
	return box


func _build_item_slot(stack, grid_index: int) -> Control:
	var box := DragSlot.new()
	box.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
	box.mouse_filter = Control.MOUSE_FILTER_STOP
	box.gui_input.connect(_on_item_gui_input.bind(stack.item.id))
	box.tooltip_text = _item_tooltip_text(stack)
	box.mouse_entered.connect(func(): box.modulate = Color(1.15, 1.15, 1.15))
	box.mouse_exited.connect(func(): box.modulate = Color(1, 1, 1))

	# Drag this item out (onto another inventory slot to reorder, or onto a
	# HUD hotbar slot to bind it to a number key -- see World).
	var item_id: String = stack.item.id
	box.drag_payload = {"source": DRAG_SOURCE_INVENTORY, "index": grid_index, "item_id": item_id}
	box.make_preview = func(): return _drag_preview_for(item_id)
	box.can_accept = func(payload): return _is_inventory_payload(payload)
	box.dropped = func(payload): items_reordered.emit(int(payload["index"]), grid_index)

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


## True for a drag that started in this window's item grid (see
## _build_item_slot's payload) -- guards against accepting unrelated drags.
func _is_inventory_payload(payload) -> bool:
	return payload is Dictionary and payload.get("source", "") == DRAG_SOURCE_INVENTORY


## The little icon that follows the cursor while dragging.
func _drag_preview_for(item_id: String) -> Control:
	var preview := TextureRect.new()
	preview.texture = _item_sprite.generate_texture(item_id)
	preview.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
	preview.size = Vector2(ICON_SIZE, ICON_SIZE)
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.modulate = Color(1, 1, 1, 0.8)
	return preview


## "Iron Sword" -> its name, its kind, and then every stat this item ACTUALLY
## models -- so hovering tells you what an item IS and what it does, matching
## Diablo/Terraria-style tooltips rather than Godot's plain default hover text.
##
## docs/concept/materials.md's whole pitch is that an item's numbers emerge
## from its material and geometry rather than being authored per recipe --
## mass_kg is literally MaterialProperties.mass_kg_for(material, volume_cm3),
## real density x real volume (see ItemCatalog._WEAPON_MATERIAL_AND_VOLUME) --
## and none of that reached the player while the tooltip said only
## "Raw Meat / Food / x5".
##
## Every stat line is CONDITIONAL, on item.gd's own "0.0 means not modeled
## yet" convention (see Item.mass_kg's doc comment): a tooltip printing
## "0.00 kg" for an item nobody has estimated a volume for would be stating a
## measurement the game has never made. Omission is the honest rendering of
## "not modeled", so raw meat still shows just name/kind/count while an iron
## sword shows its real 1.20 kg.
func _item_tooltip_text(stack) -> String:
	var item = stack.item
	var lines := [item.display_name, KIND_LABELS.get(item.kind, item.kind.capitalize())]

	var material_line := _material_line(item.id)
	if material_line != "":
		lines.append(material_line)
	if item.mass_kg > 0.0:
		lines.append("Weight: %.2f kg" % item.mass_kg)
	if item.weapon_damage > 0.0:
		lines.append("Damage: %s" % _number(item.weapon_damage))
	if item.armor > 0.0:
		# SLOT_LABELS is this window's existing paperdoll slot naming -- reuse
		# it rather than keeping a second head/chest/legs/feet table.
		lines.append("Armor: %s (%s)" % [
			_number(item.armor), SLOT_LABELS.get(item.equip_slot, item.equip_slot.capitalize())
		])

	var percent := _freshness_percent(stack, _season)
	if percent >= 0:
		lines.append("Freshness: %d%%" % percent)
		# The REAL shelf life this food has in the season the player is
		# actually standing in -- a nut in its shell keeps 8x as long as soft
		# fruit and winter triples both (FruitSpoilage.KEEPING_MULTIPLIER /
		# SEASON_KEEPING), which is the whole reason to cache nuts and eat
		# cherries first. Inventory really does age every stack, but none of
		# that was visible anywhere in the game.
		var days := FruitSpoilage.edible_seconds(item.id, _season) / SeasonCycle.SECONDS_PER_DAY
		lines.append("Keeps %.1f days in %s" % [days, _season])

	if item.max_stack > 1:
		lines.append("Stack: %d / %d" % [stack.count, item.max_stack])
	elif stack.count > 1:
		lines.append("x%d" % stack.count)
	return "\n".join(lines)


## "Iron — hard, keen": the real material this item's derived mass came from,
## described in WORDS.
##
## Words, not the property vector's scalars, because docs/concept/materials.md's
## "Learning an emergent system" says so outright -- descriptors + discovery is
## the default and "a deeper inspect surfacing raw numbers for min-maxers" is
## explicitly deferred. The thresholds behind the words are
## MaterialProperties' own calibrated constants, two of which the game had
## already fixed for fracture and buoyancy.
##
## "" for an item with no material modeled -- today that is everything except
## the three weapon-kind items (see ItemCatalog._WEAPON_MATERIAL_AND_VOLUME,
## whose own doc comment already flags widening it as a follow-up), so most
## tooltips carry no material line at all rather than a guessed one.
func _material_line(item_id: String) -> String:
	var material := _catalog.material_of(item_id)
	if material == "":
		return ""
	var words := _materials.descriptors_for(material)
	if words.is_empty():
		return material.capitalize()
	return "%s — %s" % [material.capitalize(), ", ".join(words)]


## A stat number without a pointless trailing ".0" -- an iron sword deals
## "15" damage, not "15.0", while a 1.5 stays 1.5. String.num(v, 1) rather
## than str(v): str(1.2012) would leak full precision.
static func _number(value: float) -> String:
	return String.num(value, 1).trim_suffix(".0")


## Right-click (not left -- see the class doc comment on why) triggers
## use/equip. `event.pressed` alone, not release: matches this window's
## previous click semantics and Godot's right button never enters a drag
## regardless, so there's no press/release ambiguity to resolve here.
func _on_item_gui_input(event: InputEvent, item_id: String) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		item_clicked.emit(item_id)


func _on_slot_gui_input(event: InputEvent, slot: String) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		unequip_requested.emit(slot)
