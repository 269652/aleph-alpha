extends GutTest

## CompanionItemCatalogView: renders EVERY authored item
## (ItemCatalog.known_ids()) plus this save's crafted items, each annotated
## with whether the save currently holds it (inventory/equipment/hotbar),
## searchable by name/id and paginated -- see
## docs/concept/companion_server.md's Item Catalog section. Deliberately
## NOT filtered down to only-held items by default: no discovery/spoiler
## tracking exists for items in this codebase (docs/concept/item_identity.md
## is about content-addressing crafted items, not visibility), so the
## unfiltered, paginated list is the honest default -- search narrows it,
## it never replaces the full reference.
##
## Three of these tests used to assert on an item found by scanning the
## WHOLE unpaginated table (fish/leather_chest/a crafted id) -- now that the
## table only ever renders one page, those three pass an explicit `q` filter
## so they find their target on page 1 regardless of the catalog's raw
## insertion order or its length, rather than depending on insertion-order
## luck the way the pre-pagination versions accidentally did.

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
	# Restricted to actual TABLE DATA rows -- now that the search box echoes
	# the current query back into its own value="..." attribute, a search
	# for the same text as a row's own content would otherwise let that
	# earlier, unrelated line win a naive "first line containing needle"
	# scan instead of the real row.
	for line in html.split("\n"):
		if line.begins_with("<tr><td>") and line.contains(needle):
			return line
	return ""


func _data_row_count(html: String) -> int:
	var count := 0
	for line in html.split("\n"):
		if line.begins_with("<tr><td>"):
			count += 1
	return count


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
	var html := CompanionItemCatalogView.render(
		_fixture_save_dict(), ItemCatalog.new(), {"q": "Leather Chest"}
	)
	assert_true(_row_containing(html, "Leather Chest").contains("have"))


func test_marks_an_item_never_held_as_not_had():
	var html := CompanionItemCatalogView.render(_fixture_save_dict(), ItemCatalog.new(), {"q": "Fish"})
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
	var html := CompanionItemCatalogView.render(save_dict, catalog, {"q": crafted_id})
	assert_true(html.contains(crafted_id))


# -- linking to the PDP --------------------------------------------------


func test_an_items_name_links_to_its_detail_page():
	var html := CompanionItemCatalogView.render(_fixture_save_dict(), ItemCatalog.new())
	assert_true(html.contains('<a href="/items/iron_sword">Iron Sword</a>'))


# -- search ----------------------------------------------------------------


func test_search_filters_by_display_name_case_insensitively():
	var html := CompanionItemCatalogView.render(_fixture_save_dict(), ItemCatalog.new(), {"q": "iron sw"})
	assert_true(html.contains("Iron Sword"))
	assert_false(html.contains("Iron Axe"))


func test_search_matches_by_raw_item_id_too():
	var html := CompanionItemCatalogView.render(
		_fixture_save_dict(), ItemCatalog.new(), {"q": "iron_sword"}
	)
	assert_true(html.contains("Iron Sword"))


func test_a_search_with_no_matches_renders_a_valid_empty_page_not_a_crash():
	var html := CompanionItemCatalogView.render(
		_fixture_save_dict(), ItemCatalog.new(), {"q": "zzz_no_such_item_zzz"}
	)
	assert_eq(_data_row_count(html), 0)
	assert_true(html.contains("Page 1 of 1"))


func test_the_search_box_echoes_the_query_html_escaped():
	# A search containing a raw "<" must not let the input's own value
	# attribute be broken out of -- the classic reflected-value hazard any
	# page that echoes user input back into HTML has to guard against.
	var html := CompanionItemCatalogView.render(
		_fixture_save_dict(), ItemCatalog.new(), {"q": "<script>"}
	)
	assert_false(html.contains('value="<script>"'))
	assert_true(html.contains("&lt;script&gt;"))


# -- pagination --------------------------------------------------------------


func test_a_page_shows_at_most_items_per_page_rows():
	var html := CompanionItemCatalogView.render(_fixture_save_dict(), ItemCatalog.new())
	assert_eq(_data_row_count(html), CompanionItemCatalogView.ITEMS_PER_PAGE)


func test_page_two_shows_different_items_than_page_one():
	var page_one := CompanionItemCatalogView.render(_fixture_save_dict(), ItemCatalog.new())
	var page_two := CompanionItemCatalogView.render(
		_fixture_save_dict(), ItemCatalog.new(), {"page": "2"}
	)
	assert_ne(page_one, page_two)


func test_an_out_of_range_page_clamps_instead_of_rendering_empty():
	var html := CompanionItemCatalogView.render(
		_fixture_save_dict(), ItemCatalog.new(), {"page": "9999"}
	)
	assert_true(_data_row_count(html) > 0)


func test_the_page_href_helper_url_encodes_an_ampersand_in_the_search_term():
	# An unescaped "&" in the search term would inject a second, bogus query
	# parameter instead of surviving as a literal character inside q's own
	# value -- exactly the bug HTML-attribute-escaping alone would not
	# catch (xml_escape leaves "&" as a literal ampersand, which is correct
	# for HTML text but wrong inside a URL query component).
	var href: String = CompanionItemCatalogView._page_href("fish & chips", 2)
	# Exactly one "&" must survive: the one separating q=... from page=2,
	# never a second one leaked in from the search term itself.
	assert_eq(href.count("&"), 1)
	assert_true(href.ends_with("&page=2"))
