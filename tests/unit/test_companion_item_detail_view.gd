extends GutTest

## CompanionItemDetailView: a per-item "PDP" -- what the item is, how it's
## crafted (its own recipe, if any), and every recipe it's used as an
## ingredient in. See docs/concept/companion_server.md's Item Catalog
## section.
##
## Crafted-from/Used-in only ever consult CraftingRecipeBook, which knows
## nothing about a save's own asm_-prefixed crafted items
## (recipe_for_output()'s own doc comment confirms outputs are keyed by
## authored ids only) -- a crafted item's real part/joint assembly graph
## (CraftedItemRegistry.get_assembly) is a real, larger follow-up, not
## rendered this pass. Both empty-state messages are worded to stay
## honest whether the item is a raw material the recipe book was simply
## never taught about, or a crafted item it structurally cannot know
## about -- neither implies the other is true.
##
## Deliberately does not take a save_dict / show "have" status this pass --
## every other view foregrounds ownership; this one is a reference page.

const CompanionItemDetailView = preload("res://src/companion_server/companion_item_detail_view.gd")
const ItemCatalog = preload("res://src/gameplay/item_catalog.gd")
const CraftingRecipeBook = preload("res://src/gameplay/crafting_recipe_book.gd")

var catalog := ItemCatalog.new()
var recipe_book := CraftingRecipeBook.new()


func test_an_unknown_item_id_degrades_to_a_friendly_page_not_a_crash():
	var html := CompanionItemDetailView.render("not_a_real_item_zzz", catalog, recipe_book)
	assert_true(html.length() > 0)
	assert_true(html.contains("No such item") or html.contains("no such item"))


func test_a_known_items_real_stats_render():
	var html := CompanionItemDetailView.render("iron_sword", catalog, recipe_book)
	assert_true(html.contains("Iron Sword"))
	assert_true(html.contains("weapon"))
	assert_true(html.contains("15"))  # weapon_damage
	assert_true(html.contains("1.2"))  # real mass_kg


func test_an_item_with_a_real_recipe_shows_what_it_is_crafted_from():
	# iron_helm's own recipe: 2x iron_ingot, nothing else.
	var html := CompanionItemDetailView.render("iron_helm", catalog, recipe_book)
	assert_true(html.contains("Iron Ingot"))
	assert_true(html.contains('<a href="/items/iron_ingot">'))


func test_a_raw_material_with_no_recipe_shows_the_neutral_crafted_from_empty_state():
	# "fang" is never a recipe's output anywhere in crafting_recipe_book.gd.
	var html := CompanionItemDetailView.render("fang", catalog, recipe_book)
	assert_true(html.contains("No recipe in the crafting book produces this item"))


func test_an_item_never_consumed_by_any_recipe_shows_the_neutral_used_in_empty_state():
	# "fang" is also never a recipe's input anywhere.
	var html := CompanionItemDetailView.render("fang", catalog, recipe_book)
	assert_true(html.contains("No recipe in the crafting book uses this item"))


func test_an_item_used_by_several_recipes_lists_all_of_them_under_used_in():
	# wood is a real input to torch, wooden_club, campfire, saw and storage.
	var html := CompanionItemDetailView.render("wood", catalog, recipe_book)
	assert_true(html.contains('<a href="/items/torch">'))
	assert_true(html.contains('<a href="/items/wooden_club">'))
	assert_true(html.contains('<a href="/items/campfire">'))
