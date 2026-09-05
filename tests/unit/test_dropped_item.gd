extends GutTest

## Focused spec for the one thing capture_dsl.md adds to DroppedItem: a
## loaded glass_bottle renders as a live BottledCreatureView instead of the
## ordinary flat icon (docs/concept/capture_dsl.md's "Rendering a bottled
## catch" -- "the world-DROPPED item, not the inventory icon or hand-held
## view"). Does not attempt to backfill coverage of DroppedItem's
## pre-existing behavior, which this change does not touch.

const DroppedItem = preload("res://src/rendering/dropped_item.gd")
const BottledCreatureView = preload("res://src/rendering/bottled_creature_view.gd")
const ItemStack = preload("res://src/gameplay/item_stack.gd")
const Item = preload("res://src/gameplay/item.gd")

const ItemCatalog = preload("res://src/gameplay/item_catalog.gd")
var _item_catalog := ItemCatalog.new()


func _dropped(item: Item, count: int = 1) -> DroppedItem:
	var node := DroppedItem.new()
	node.item_stack = ItemStack.new(item, count)
	add_child_autofree(node)
	return node


func test_a_loaded_glass_bottle_gets_a_bottled_creature_view():
	var bottle := _item_catalog.make("glass_bottle")
	bottle.captive_species = "monarch"
	var node := _dropped(bottle)

	var view = _find_bottled_view(node)
	assert_not_null(view, "a loaded glass_bottle should show a live BottledCreatureView")
	assert_eq(view.species, "monarch")


func test_an_empty_glass_bottle_uses_the_ordinary_flat_icon():
	var bottle := _item_catalog.make("glass_bottle")
	var node := _dropped(bottle)

	assert_null(_find_bottled_view(node), "an empty bottle is an ordinary dropped item, not a live view")
	assert_not_null(node.texture)


func test_an_ordinary_item_is_unaffected():
	var node := _dropped(_item_catalog.make("carrot"))
	assert_null(_find_bottled_view(node))
	assert_not_null(node.texture)


func _find_bottled_view(node: DroppedItem) -> Variant:
	for child in node.get_children():
		if child is BottledCreatureView:
			return child
	return null
