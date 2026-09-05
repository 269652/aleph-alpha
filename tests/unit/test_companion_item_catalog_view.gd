extends GutTest

## CompanionItemCatalogView: renders EVERY authored item
## (ItemCatalog.known_ids()) plus this save's crafted items, each annotated
## with whether the save currently holds it (inventory/equipment/hotbar) --
## see docs/concept/companion_server.md's Item Catalog section. Deliberately
## NOT filtered down to only-held items: no discovery/spoiler tracking exists
## for items in this codebase (docs/concept/item_identity.md is about
## content-addressing crafted items, not visibility), so showing the full
## authored reference, annotated, is the option that invents no new
## persisted state -- pillar 4, "one data source, reused".

const CompanionItemCatalogView = preload("res://src/companion_server/companion_item_catalog_view.gd")
const ItemCatalog = preload("res://src/gameplay/item_catalog.gd")
const CraftedItemRegistry = preload("res://src/gameplay/crafted_item_registry.gd")


## Same shape test_item_catalog.gd/test_crafted_item_registry.gd already
## build, so this test agrees with those about what an assembly looks like.
func _sword() -> Dictionary:
	return {
		"pattern": "sword",
		"parts": [
			{"material": "iron", "geometry": "blade", "role": "edge", "length_cm": 70.0},
			{"material": "wood", "geometry": "rod", "role": "grip", "length_cm": 12.0},
		],
		"joints": [{"kind": "tang", "a": 0, "b": 1}],
	}


func _fixture_save_dict() -> Dictionary:
	return {
		"inventory": [{"id": "wood", "count": 12}],
		"equipment": {"chest": "leather_chest"},
		"hotbar": ["iron_sword", "", ""],
		"crafted_items": {},
	}


func _row_containing(html: String, needle: String) -> String:
	for line in html.split("\n"):
		if line.contains(needle):
			return line
	return ""


func test_lists_a_known_authored_items_display_name():
	var html := CompanionItemCatalogView.render(_fixture_save_dict(), ItemCatalog.new())
	assert_true(html.contains("Iron Sword"))


func test_shows_a_weapons_real_damage_and_mass():
	var html := CompanionItemCatalogView.render(_fixture_save_dict(), ItemCatalog.new())
	var row := _row_containing(html, "Iron Sword")
	assert_true(row.contains("15"))  # iron_sword's weapon_damage, item_catalog.gd
	assert_true(row.contains("1.2"))  # iron_sword's real mass_kg (~1.2), item_catalog.gd


func test_marks_an_item_held_in_the_hotbar_as_had():
	var html := CompanionItemCatalogView.render(_fixture_save_dict(), ItemCatalog.new())
	assert_true(_row_containing(html, "Iron Sword").contains("have"))


func test_marks_an_item_held_only_in_inventory_as_had():
	var html := CompanionItemCatalogView.render(_fixture_save_dict(), ItemCatalog.new())
	assert_true(_row_containing(html, "Wood").contains("have"))


func test_marks_an_item_held_in_equipment_as_had():
	var html := CompanionItemCatalogView.render(_fixture_save_dict(), ItemCatalog.new())
	assert_true(_row_containing(html, "Leather Chest").contains("have"))


func test_marks_an_item_never_held_as_not_had():
	var html := CompanionItemCatalogView.render(_fixture_save_dict(), ItemCatalog.new())
	var row := _row_containing(html, "Fish")
	assert_true(row != "")
	assert_false(row.contains("have"))


func test_a_crafted_item_from_this_saves_registry_also_appears():
	var registry := CraftedItemRegistry.new()
	var crafted_id := registry.register(_sword())
	var save_dict := _fixture_save_dict()
	save_dict.crafted_items = registry.to_dicts()
	var catalog := ItemCatalog.new()
	catalog.use_crafted_registry(CraftedItemRegistry.from_dicts(save_dict.crafted_items))
	var html := CompanionItemCatalogView.render(save_dict, catalog)
	assert_true(html.contains(crafted_id))
