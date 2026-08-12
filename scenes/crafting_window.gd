extends PanelContainer

## A real crafting menu: hidden until toggled (see World's toggle_crafting
## action, default C). One row per recipe (see CraftingRecipeBook) showing the
## output item, its input requirements, and whether the player can currently
## afford it (greyed out if not). Clicking a craftable row emits craft_requested;
## World calls Player.craft() and refreshes. Replaces the console-only /craft.
## Purely glue -- recipe data/affordability come from the tested
## CraftingRecipeBook and the player's inventory counts.

const ProceduralItemSprite = preload("res://src/rendering/procedural_item_sprite.gd")
const CraftingRecipeBook = preload("res://src/gameplay/crafting_recipe_book.gd")
const ItemCatalog = preload("res://src/gameplay/item_catalog.gd")

signal craft_requested(recipe_id: String)

const ICON_SIZE := 22.0

var _recipe_book := CraftingRecipeBook.new()
var _item_catalog := ItemCatalog.new()
var _item_sprite_generator := ProceduralItemSprite.new()
var _list: VBoxContainer


func _ready() -> void:
	visible = false
	custom_minimum_size = Vector2(300, 240)

	var root := VBoxContainer.new()
	add_child(root)

	var title := Label.new()
	title.text = "Crafting"
	title.add_theme_font_size_override("font_size", 16)
	root.add_child(title)

	var hint := Label.new()
	hint.text = "Click a recipe you can afford to craft it."
	hint.modulate = Color(1, 1, 1, 0.6)
	root.add_child(hint)

	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 4)
	root.add_child(_list)


func toggle() -> void:
	visible = not visible


func is_open() -> bool:
	return visible


## Rebuilds the recipe rows against `inventory_counts` (item_id -> total held).
## Cheap enough (a handful of recipes) to redo every refresh; only runs while
## the window is visible (see World._client_process).
func refresh(inventory_counts: Dictionary) -> void:
	for child in _list.get_children():
		# refresh() can run synchronously from inside a row's OWN gui_input
		# handler (click -> craft_requested -> World -> refresh, all on the
		# same call stack -- see _on_row_gui_input): that row's Control is
		# still "locked" (mid-signal-emission on itself), and Object.free()
		# refuses to free a locked object ("Attempted to free a locked
		# object"). remove_child() detaches it immediately (safe even while
		# locked) without erroring; queue_free() defers the actual deletion
		# until after the call stack unwinds. Same fix as
		# InventoryWindow.refresh.
		_list.remove_child(child)
		child.queue_free()
	for recipe_id in _recipe_book.recipe_ids():
		_list.add_child(_build_row(recipe_id, inventory_counts))


func _build_row(recipe_id: String, counts: Dictionary) -> Control:
	var affordable := _recipe_book.can_craft(recipe_id, counts)

	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	if affordable:
		row.gui_input.connect(_on_row_gui_input.bind(recipe_id))
	else:
		row.modulate = Color(1, 1, 1, 0.45)

	var output := _recipe_book.recipe_output(recipe_id)
	var icon := TextureRect.new()
	icon.texture = _item_sprite_generator.generate_texture(output.get("item_id", recipe_id))
	icon.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon)

	var label := Label.new()
	label.text = "%s — %s" % [_display_name(output.get("item_id", recipe_id)), _inputs_text(recipe_id)]
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(label)
	return row


func _inputs_text(recipe_id: String) -> String:
	var parts := []
	for input in _recipe_book.recipe_inputs(recipe_id):
		parts.append("%dx %s" % [input["count"], _display_name(input["item_id"])])
	return ", ".join(parts)


func _display_name(item_id: String) -> String:
	if _item_catalog.has(item_id):
		return _item_catalog.make(item_id).display_name
	return item_id


func _on_row_gui_input(event: InputEvent, recipe_id: String) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		craft_requested.emit(recipe_id)
