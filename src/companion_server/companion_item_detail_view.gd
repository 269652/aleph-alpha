extends RefCounted

## A per-item "PDP" (product detail page): what the item is, how it's
## itself crafted (its own recipe, if any), and every recipe it's used as
## an ingredient in -- see docs/concept/companion_server.md's Item Catalog
## section.
##
## Crafted-from/Used-in only ever consult CraftingRecipeBook, which knows
## nothing about a save's own asm_-prefixed crafted items
## (recipe_for_output()'s own doc comment confirms outputs are keyed by
## authored ids only) -- rendering a crafted item's real part/joint
## assembly graph (CraftedItemRegistry.get_assembly) is a real, larger
## follow-up, not attempted this pass. Both empty-state messages are
## worded to stay honest whether the item is a raw material the recipe
## book was simply never taught about, or a crafted item it structurally
## cannot know about -- neither implies the other is true.
##
## Deliberately does not take a save_dict / show "have" status this pass --
## every other view foregrounds ownership; this one is a reference page,
## a scope choice rather than an oversight.

const CompanionPageShell = preload("res://src/companion_server/companion_page_shell.gd")
const ItemCatalog = preload("res://src/gameplay/item_catalog.gd")
const CraftingRecipeBook = preload("res://src/gameplay/crafting_recipe_book.gd")
const MaterialProperties = preload("res://src/gameplay/material_properties.gd")

const _NO_RECIPE_PRODUCES := "No recipe in the crafting book produces this item."
const _NO_RECIPE_USES := "No recipe in the crafting book uses this item."


static func render(item_id: String, catalog: ItemCatalog, recipe_book: CraftingRecipeBook) -> String:
	if not catalog.has(item_id):
		return CompanionPageShell.wrap("Item Catalog", "<p>No such item: %s</p>" % item_id)

	var item = catalog.make(item_id)
	var body := "<p>%s</p>" % _description(item_id, item, catalog)

	body += "<h2>Stats</h2><ul>"
	body += "<li>Kind: %s</li>" % item.kind
	body += "<li>Max stack: %s</li>" % str(item.max_stack)
	if item.weapon_damage > 0.0:
		body += "<li>Damage: %s</li>" % str(item.weapon_damage)
	if item.armor > 0.0:
		body += "<li>Armor: %s (%s slot)</li>" % [str(item.armor), item.equip_slot]
	if item.mass_kg > 0.0:
		body += "<li>Mass: %s kg</li>" % str(item.mass_kg)
	body += "</ul>"

	body += "<h2>Crafted from</h2>" + _crafted_from(item_id, catalog, recipe_book)
	body += "<h2>Used in</h2>" + _used_in(item_id, catalog, recipe_book)

	return CompanionPageShell.wrap(item.display_name, body)


static func _description(item_id: String, item, catalog: ItemCatalog) -> String:
	var material := catalog.material_of(item_id)
	if material == "":
		return "A %s item." % item.kind
	var descriptors := MaterialProperties.new().descriptors_for(material)
	var adjective := (", ".join(descriptors) + " ") if not descriptors.is_empty() else ""
	return "A %s%s made of %s." % [adjective, item.kind, material]


static func _crafted_from(item_id: String, catalog: ItemCatalog, recipe_book: CraftingRecipeBook) -> String:
	var recipe_id := recipe_book.recipe_for_output(item_id)
	if recipe_id == "":
		return "<p>%s</p>" % _NO_RECIPE_PRODUCES
	var rows := []
	for input in recipe_book.recipe_inputs(recipe_id):
		rows.append(_ingredient_row(input.item_id, int(input.count), catalog))
	return "<ul>" + "".join(rows) + "</ul>"


## Recipes are matched by scanning every recipe's own inputs -- there is no
## reverse lookup for "what uses this item" in crafting_recipe_book.gd
## itself (a fixed data table, not a query engine; see
## companion_item_catalog_view.gd's own _held_ids() for the same
## view-layer-derived-structure shape). Deduped by OUTPUT item id
## (recipe_for_output()'s own doc comment confirms no two recipes share an
## output today, so this can never actually collide against real data --
## the guard is here so a future recipe added to the book can't silently
## double-list itself).
static func _used_in(item_id: String, catalog: ItemCatalog, recipe_book: CraftingRecipeBook) -> String:
	var rows := []
	var seen_outputs := {}
	for recipe_id in recipe_book.recipe_ids():
		for input in recipe_book.recipe_inputs(recipe_id):
			if input.item_id != item_id:
				continue
			var output := recipe_book.recipe_output(recipe_id)
			if seen_outputs.has(output.item_id):
				continue
			seen_outputs[output.item_id] = true
			rows.append(_ingredient_row(output.item_id, int(input.count), catalog))
			break
	if rows.is_empty():
		return "<p>%s</p>" % _NO_RECIPE_USES
	return "<ul>" + "".join(rows) + "</ul>"


## Guards has() before make() -- matching companion_item_catalog_view.gd's
## own existing convention for a crafted/unknown id -- rather than assuming
## the recipe table can never drift from the catalog.
static func _ingredient_row(other_id: String, count: int, catalog: ItemCatalog) -> String:
	var name := other_id
	if catalog.has(other_id):
		name = catalog.make(other_id).display_name
	return '<li><a href="/items/%s">%s</a> x%d</li>' % [other_id, name, count]
