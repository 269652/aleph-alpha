extends GutTest

## CraftingWindow: the recipe menu (toggle C). Overhauled from a plain list of
## thin text rows into a centered, card-based grid -- one card per recipe,
## grouped into sections by the output item's kind (Weapons/Tools/Armor/
## Structures/Cooking/Materials), each card showing a real thumbnail, the
## output name/count, and every required material with a live have/need
## count (green when you have enough, red when you're short). Recipe data/
## affordability still come entirely from the tested CraftingRecipeBook and
## the player's inventory counts -- this file covers layout/interaction glue,
## the same class of bug test_inventory_window.gd pins for InventoryWindow.

const CraftingWindow = preload("res://scenes/crafting_window.gd")
const CraftingRecipeBook = preload("res://src/gameplay/crafting_recipe_book.gd")
const ItemCatalog = preload("res://src/gameplay/item_catalog.gd")

## Keep in sync with World._build_crafting_window's offsets, the same
## contract test_inventory_window.gd pins for InventoryWindow -- if the
## window's real minimum size exceeds this box, Godot expands it past the
## anchor offsets and content clips off-screen.
const WORLD_ANCHOR_BOX := Vector2(640, 560)

var window: CraftingWindow
var _recipe_book := CraftingRecipeBook.new()
var _catalog := ItemCatalog.new()


func before_each():
	window = CraftingWindow.new()
	add_child(window)


func after_each():
	window.free()


func _full_counts() -> Dictionary:
	var counts := {}
	for item_id in _catalog.known_ids():
		counts[item_id] = 999
	return counts


func test_window_minimum_size_fits_the_anchor_box_world_gives_it():
	window.refresh(_full_counts())
	var min_size := window.get_combined_minimum_size()
	assert_lte(min_size.x, WORLD_ANCHOR_BOX.x, "window min width must fit World's anchor box")
	assert_lte(min_size.y, WORLD_ANCHOR_BOX.y, "window min height must fit World's anchor box or content clips off-screen")


func test_refresh_builds_one_card_per_recipe():
	window.refresh({})
	assert_eq(window._cards.size(), _recipe_book.recipe_ids().size())


## Every represented output kind (weapon/tool/armor/placeable/food/material)
## gets its own section header -- a flat 13-recipe list read as a wall of
## near-identical rows before this, with nothing to scan by.
func test_every_recipe_kind_gets_its_own_section_header():
	window.refresh({})
	var header_texts := []
	for child in window._sections_container.get_children():
		if child is Label:
			header_texts.append(child.text)
	var represented_kinds := {}
	for recipe_id in _recipe_book.recipe_ids():
		var output := _recipe_book.recipe_output(recipe_id)
		represented_kinds[_catalog.make(output["item_id"]).kind] = true
	assert_eq(header_texts.size(), represented_kinds.size())


func test_card_shows_the_output_icon_and_display_name():
	window.refresh({})
	var card = window._cards["torch"]
	var icon := card.get_meta("icon") as TextureRect
	assert_not_null(icon.texture)
	var name_label := card.get_meta("name_label") as Label
	assert_string_contains(name_label.text, "Torch")


func test_card_shows_output_count_when_more_than_one_is_produced():
	window.refresh({})
	# torch's recipe produces 2.
	var card = window._cards["torch"]
	var name_label := card.get_meta("name_label") as Label
	assert_string_contains(name_label.text, "x2")


func test_card_omits_output_count_badge_when_only_one_is_produced():
	window.refresh({})
	# wooden_club's recipe produces exactly 1.
	var card = window._cards["wooden_club"]
	var name_label := card.get_meta("name_label") as Label
	assert_false("x1" in name_label.text)


func test_card_lists_every_required_material_with_have_over_need():
	window.refresh({"wood": 1, "hide": 0})
	var labels: Dictionary = window._material_labels["torch"]
	assert_eq(labels["wood"].text, "1/1")
	assert_eq(labels["hide"].text, "0/1")


func test_material_chip_is_colored_green_when_owned_enough():
	window.refresh({"wood": 5, "hide": 5})
	var label: Label = window._material_labels["torch"]["wood"]
	assert_eq(label.get_theme_color("font_color"), CraftingWindow.SUFFICIENT_COLOR)


func test_material_chip_is_colored_red_when_short():
	window.refresh({"wood": 0, "hide": 0})
	var label: Label = window._material_labels["torch"]["wood"]
	assert_eq(label.get_theme_color("font_color"), CraftingWindow.SHORTFALL_COLOR)


func test_affordable_card_is_not_dimmed_and_shows_a_pointing_cursor():
	window.refresh(_full_counts())
	var card = window._cards["torch"]
	assert_eq(card.modulate.a, 1.0)
	assert_eq(card.mouse_default_cursor_shape, Control.CURSOR_POINTING_HAND)


func test_unaffordable_card_is_dimmed():
	window.refresh({})
	var card = window._cards["torch"]
	assert_lt(card.modulate.a, 1.0)


func test_clicking_an_affordable_card_emits_craft_requested():
	window.refresh(_full_counts())
	var received := []
	window.craft_requested.connect(func(recipe_id): received.append(recipe_id))

	var card = window._cards["torch"]
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	card.gui_input.emit(event)

	assert_eq(received, ["torch"])


func test_clicking_an_unaffordable_card_does_nothing():
	window.refresh({})
	var received := []
	window.craft_requested.connect(func(recipe_id): received.append(recipe_id))

	var card = window._cards["torch"]
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	card.gui_input.emit(event)

	assert_eq(received, [])


# -- refresh() must be a no-op when called repeatedly with unchanged data ----
#
# World calls refresh() every frame while the window is visible, not just on
# an actual inventory change (see World._update_crafting_window) -- same
# class of bug test_inventory_window.gd pins: without a no-op guard, every
# card's Control is destroyed and recreated every frame, which starves
# Godot's native hover tooltip (it needs the SAME Control instance under the
# mouse continuously to complete its timer).

func test_repeated_identical_refresh_keeps_the_same_card_instance():
	window.refresh({"wood": 1, "hide": 1})
	var first_card = window._cards["torch"]

	window.refresh({"wood": 1, "hide": 1})  # identical inputs, e.g. next frame's poll

	assert_eq(window._cards["torch"], first_card, "an unchanged refresh should not recreate card Controls")


func test_refresh_with_different_counts_does_rebuild():
	window.refresh({"wood": 1, "hide": 1})
	var first_card = window._cards["torch"]

	window.refresh({"wood": 0, "hide": 1})  # a real change -- torch is no longer affordable

	assert_ne(window._cards["torch"], first_card, "a real inventory change must still rebuild the card")


## Reproduces the same class of bug test_inventory_window.gd pins (Godot log:
## "Attempted to free a locked object (calling or emitting)"): clicking a
## craftable card synchronously triggers World -> Player.craft() ->
## refresh() again, all still on that card Control's own gui_input call
## stack. The inner refresh() is given a genuinely DIFFERENT counts dict (one
## wood spent, as a real craft would do) so it forces an actual rebuild
## rather than being skipped by the no-op guard above -- otherwise this test
## would stop exercising the locked-object code path entirely.
func test_refresh_survives_being_called_from_within_a_cards_own_click_handler():
	var counts := _full_counts()
	window.refresh(counts)
	var card_count_before := window._cards.size()
	assert_gt(card_count_before, 0)

	window.craft_requested.connect(func(_recipe_id):
		var after_craft := counts.duplicate()
		after_craft["wood"] -= 1
		window.refresh(after_craft)
	)

	var card = window._cards["torch"]
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	card.gui_input.emit(event)  # what a real click ultimately does

	assert_eq(window._cards.size(), card_count_before, "the recipe grid should still show every card, not be corrupted")
