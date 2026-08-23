extends PanelContainer

## A real crafting menu: hidden until toggled (see World's toggle_crafting
## action, default C). Centered, card-based grid -- one card per recipe (see
## CraftingRecipeBook), grouped into sections by the output item's kind
## (Weapons/Tools/Armor/Structures/Cooking/Materials) so 13+ recipes read as
## a scannable catalog instead of a wall of near-identical rows. Each card
## shows a real item thumbnail, the output name (+ count when more than one
## is produced), and every required material with a live have/need count,
## colored green when you have enough and red when you're short. Clicking an
## affordable card emits craft_requested; World calls Player.craft() and
## refreshes. Purely glue -- recipe data/affordability come from the tested
## CraftingRecipeBook and the player's inventory counts.

const ProceduralItemSprite = preload("res://src/rendering/procedural_item_sprite.gd")
const CraftingRecipeBook = preload("res://src/gameplay/crafting_recipe_book.gd")
const ItemCatalog = preload("res://src/gameplay/item_catalog.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")

signal craft_requested(recipe_id: String)

const CARD_ICON_SIZE := 36.0
const MATERIAL_ICON_SIZE := 18.0
const CARD_MIN_SIZE := Vector2(176, 88)
const GRID_COLUMNS := 3

## Material have/need text color -- green reads as "you're covered", red as
## "this is what's stopping you", the two things a glance at a card should
## answer instantly.
const SUFFICIENT_COLOR := Color(0.55, 0.85, 0.55)
const SHORTFALL_COLOR := Color(0.92, 0.45, 0.4)

## Section order: rough crafting-progression feel (things you fight/work
## with, then wear, then build, then consume, then raw stock) rather than
## alphabetical -- alphabetical would split e.g. armor pieces from weapons
## for no reason a player would find intuitive. Any kind not listed here
## (a future recipe output of a kind not yet seen) still gets a section, just
## appended after these.
const _SECTION_ORDER := ["weapon", "tool", "armor", "placeable", "food", "material"]
const _SECTION_LABELS := {
	"weapon": "Weapons", "tool": "Tools", "armor": "Armor",
	"placeable": "Structures", "food": "Cooking", "material": "Materials",
}

var _recipe_book := CraftingRecipeBook.new()
var _item_catalog := ItemCatalog.new()
var _item_sprite_generator := ProceduralItemSprite.new()
var _sections_container: VBoxContainer

## recipe_id -> the card Control (also test/debug introspection).
var _cards: Dictionary = {}
## recipe_id -> {item_id -> the have/need Label} (also test introspection).
var _material_labels: Dictionary = {}

## A cheap fingerprint of the last refresh() call's inventory_counts -- see
## refresh's own doc comment: World calls refresh() every frame while the
## window is visible (not just on an actual inventory change), so without
## this every card's Control would be destroyed and recreated every frame,
## starving Godot's native hover tooltip (it needs the SAME Control instance
## under the mouse continuously) -- the same bug class InventoryWindow had.
var _last_refresh_signature := ""


func _ready() -> void:
	visible = false
	# A fixed window footprint regardless of recipe count -- the scroll
	# container below absorbs overflow instead of the window growing to fit
	# every section, which is what let the old flat list run off-screen once
	# there were enough recipes.
	custom_minimum_size = Vector2(600, 520)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	add_child(root)

	var title := Label.new()
	title.text = "Crafting"
	title.add_theme_font_size_override("font_size", UiTheme.TITLE_FONT_SIZE)
	root.add_child(title)

	var hint := Label.new()
	hint.text = "Click a recipe you can afford to craft it."
	hint.modulate = Color(1, 1, 1, 0.6)
	root.add_child(hint)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)

	_sections_container = VBoxContainer.new()
	_sections_container.add_theme_constant_override("separation", 12)
	_sections_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_sections_container)


func toggle() -> void:
	visible = not visible


func is_open() -> bool:
	return visible


## Rebuilds the recipe grid against `inventory_counts` (item_id -> total
## held) -- a no-op when nothing relevant has changed since the last call
## (see _last_refresh_signature). Cheap enough (a handful of recipes) to
## redo in full on every real change; only runs while the window is visible
## (see World._client_process).
func refresh(inventory_counts: Dictionary) -> void:
	var signature := _signature_for(inventory_counts)
	if signature == _last_refresh_signature:
		return
	_last_refresh_signature = signature

	for child in _sections_container.get_children():
		# refresh() can run synchronously from inside a card's OWN gui_input
		# handler (click -> craft_requested -> World -> refresh, all on the
		# same call stack -- see _on_card_gui_input): that card's Control is
		# still "locked" (mid-signal-emission on itself), and Object.free()
		# refuses to free a locked object ("Attempted to free a locked
		# object"). remove_child() detaches it immediately (safe even while
		# locked) without erroring; queue_free() defers the actual deletion
		# until after the call stack unwinds. Same fix as
		# InventoryWindow.refresh.
		_sections_container.remove_child(child)
		child.queue_free()
	_cards.clear()
	_material_labels.clear()

	var groups := _grouped_recipe_ids()
	for kind in _SECTION_ORDER:
		if groups.has(kind):
			_add_section(kind, groups[kind], inventory_counts)
	for kind in groups:
		if not (kind in _SECTION_ORDER):
			_add_section(kind, groups[kind], inventory_counts)


## Every recipe_id, grouped by its output item's kind (weapon/tool/armor/
## placeable/food/material -- see ItemCatalog), for the section headers.
func _grouped_recipe_ids() -> Dictionary:
	var groups := {}
	for recipe_id in _recipe_book.recipe_ids():
		var output := _recipe_book.recipe_output(recipe_id)
		var kind := _item_catalog.make(output["item_id"]).kind
		if not groups.has(kind):
			groups[kind] = []
		groups[kind].append(recipe_id)
	return groups


func _add_section(kind: String, recipe_ids: Array, counts: Dictionary) -> void:
	var header := Label.new()
	header.text = _SECTION_LABELS.get(kind, kind.capitalize())
	header.add_theme_font_size_override("font_size", UiTheme.BASE_FONT_SIZE + 2)
	header.add_theme_color_override("font_color", UiTheme.ACCENT)
	_sections_container.add_child(header)

	var grid := GridContainer.new()
	grid.columns = GRID_COLUMNS
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	_sections_container.add_child(grid)

	for recipe_id in recipe_ids:
		var card := _build_card(recipe_id, counts)
		grid.add_child(card)
		_cards[recipe_id] = card


## One recipe's card: thumbnail + name (+ output count badge), then every
## required material as a small icon+have/need chip. Affordable cards invite
## the click (pointing-hand cursor, a light hover highlight); unaffordable
## ones read as unavailable at a glance (dimmed, no hover/click) rather than
## needing the player to click and get nothing.
func _build_card(recipe_id: String, counts: Dictionary) -> Control:
	var affordable := _recipe_book.can_craft(recipe_id, counts)
	var output := _recipe_book.recipe_output(recipe_id)
	var item_id: String = output.get("item_id", recipe_id)

	var card := PanelContainer.new()
	card.custom_minimum_size = CARD_MIN_SIZE
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.tooltip_text = _card_tooltip_text(item_id, recipe_id, counts)
	if affordable:
		card.gui_input.connect(_on_card_gui_input.bind(recipe_id))
		card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		card.mouse_entered.connect(func(): card.modulate = Color(1.12, 1.12, 1.12))
		card.mouse_exited.connect(func(): card.modulate = Color(1, 1, 1))
	else:
		card.modulate = Color(1, 1, 1, 0.45)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 4)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(content)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 6)
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(header)

	var icon := TextureRect.new()
	icon.texture = _item_sprite_generator.generate_texture(item_id)
	icon.custom_minimum_size = Vector2(CARD_ICON_SIZE, CARD_ICON_SIZE)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(icon)
	card.set_meta("icon", icon)

	var name_label := Label.new()
	name_label.text = _card_title_text(item_id, output)
	name_label.add_theme_font_size_override("font_size", UiTheme.BASE_FONT_SIZE + 1)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(name_label)
	card.set_meta("name_label", name_label)

	var materials := HFlowContainer.new()
	materials.add_theme_constant_override("h_separation", 8)
	materials.add_theme_constant_override("v_separation", 2)
	materials.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(materials)

	var chip_labels := {}
	for input in _recipe_book.recipe_inputs(recipe_id):
		var chip := _build_material_chip(input, counts)
		materials.add_child(chip["container"])
		chip_labels[input["item_id"]] = chip["label"]
	_material_labels[recipe_id] = chip_labels

	return card


## "Torch" for a single-output recipe, "Torch  x2" when the recipe produces
## more than one -- otherwise a 2-for-1 recipe reads identically to a 1-for-1
## one and the player only finds out by crafting it.
func _card_title_text(item_id: String, output: Dictionary) -> String:
	var count := int(output.get("count", 1))
	if count > 1:
		return "%s  x%d" % [_display_name(item_id), count]
	return _display_name(item_id)


## One "icon + have/need" material chip, colored to answer "am I covered on
## this?" without reading the numbers.
func _build_material_chip(input: Dictionary, counts: Dictionary) -> Dictionary:
	var item_id: String = input["item_id"]
	var needed: int = input["count"]
	var have: int = counts.get(item_id, 0)

	var chip := HBoxContainer.new()
	chip.add_theme_constant_override("separation", 3)
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.tooltip_text = _display_name(item_id)

	var icon := TextureRect.new()
	icon.texture = _item_sprite_generator.generate_texture(item_id)
	icon.custom_minimum_size = Vector2(MATERIAL_ICON_SIZE, MATERIAL_ICON_SIZE)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(icon)

	var label := Label.new()
	label.text = "%d/%d" % [have, needed]
	label.add_theme_font_size_override("font_size", UiTheme.BASE_FONT_SIZE - 2)
	label.add_theme_color_override("font_color", SUFFICIENT_COLOR if have >= needed else SHORTFALL_COLOR)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(label)

	return {"container": chip, "label": label}


func _card_tooltip_text(item_id: String, recipe_id: String, counts: Dictionary) -> String:
	var lines := [_display_name(item_id)]
	for input in _recipe_book.recipe_inputs(recipe_id):
		var have: int = counts.get(input["item_id"], 0)
		lines.append("%d/%d %s" % [have, input["count"], _display_name(input["item_id"])])
	return "\n".join(lines)


func _display_name(item_id: String) -> String:
	if _item_catalog.has(item_id):
		return _item_catalog.make(item_id).display_name
	return item_id


## A cheap string fingerprint of everything refresh()'s output depends on --
## two calls with an identical signature would rebuild an identical grid, so
## the second one can just be skipped (see refresh's own doc comment). Always
## prefixed with the key count: with empty `counts`, joining zero parts would
## otherwise produce "" -- exactly _last_refresh_signature's initial value --
## which silently no-op'd the very first refresh({}) call ever made.
func _signature_for(counts: Dictionary) -> String:
	var keys := counts.keys()
	keys.sort()
	var parts: Array = []
	for key in keys:
		parts.append("%s:%d" % [key, int(counts[key])])
	return "%d|%s" % [keys.size(), "|".join(parts)]


func _on_card_gui_input(event: InputEvent, recipe_id: String) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		craft_requested.emit(recipe_id)
