extends RefCounted

## Renders every authored item (ItemCatalog.known_ids()) plus this save's
## own crafted items, each row annotated with whether the save currently
## holds it, searchable by name/id and paginated -- see
## docs/concept/companion_server.md's Item Catalog section. Deliberately
## NOT filtered down to only-held items by default: no discovery/spoiler
## tracking exists for items in this codebase (item_identity.md is about
## content-addressing crafted items, not visibility), so the unfiltered,
## paginated list is the honest default -- search narrows it, it never
## replaces the full reference (pillar 4, "one data source, reused").

const CompanionPageShell = preload("res://src/companion_server/companion_page_shell.gd")
const CompanionPagination = preload("res://src/companion_server/companion_pagination.gd")
const CompanionHtml = preload("res://src/companion_server/companion_html.gd")
const ItemCatalog = preload("res://src/gameplay/item_catalog.gd")

## Tuned/pinned per CLAUDE.md's no-eyeballed-constants rule -- pinned by
## test_a_page_shows_at_most_items_per_page_rows.
const ITEMS_PER_PAGE := 20


static func render(save_dict: Dictionary, catalog: ItemCatalog, query: Dictionary = {}) -> String:
	var held := _held_ids(save_dict)
	var all_ids := _all_item_ids(save_dict, catalog)
	var search: String = query.get("q", "")
	var matching := all_ids
	if search != "":
		matching = all_ids.filter(func(item_id): return _matches(item_id, catalog, search))
	var page := int(query.get("page", "1"))
	var paged := CompanionPagination.paginate(matching, page, ITEMS_PER_PAGE)

	var body := _search_form(search)
	body += "<table>\n<tr><th>ID</th><th>Item</th><th>Kind</th><th>Max stack</th>" \
		+ "<th>Damage</th><th>Armor</th><th>Mass (kg)</th><th></th></tr>\n"
	for item_id in paged.items:
		body += _row(catalog.make(item_id), held.has(item_id))
	body += "</table>"
	body += _pagination_controls(search, paged.page, paged.total_pages)

	return CompanionPageShell.wrap("Item Catalog", body)


static func _all_item_ids(save_dict: Dictionary, catalog: ItemCatalog) -> Array:
	var ids := catalog.known_ids()
	# A crafted (content-addressed) id this save actually has isn't in
	# known_ids() (deliberately -- see ItemCatalog.known_ids()'s own doc
	# comment about not printing a screenful of asm_<hex> ids), but a
	# crafted item THIS SAVE holds is still real content worth showing.
	for item_id in save_dict.get("crafted_items", {}):
		if catalog.has(item_id):
			ids.append(item_id)
	return ids


static func _matches(item_id: String, catalog: ItemCatalog, search: String) -> bool:
	return catalog.make(item_id).display_name.findn(search) != -1 or item_id.findn(search) != -1


static func _search_form(search: String) -> String:
	return ('<form action="/items" method="get">' \
		+ '<input type="text" name="q" value="%s" placeholder="Search items...">' \
		+ '<button type="submit">Search</button></form>') % CompanionHtml.escape(search)


static func _pagination_controls(search: String, page: int, total_pages: int) -> String:
	var controls := "<p>"
	if page > 1:
		controls += '<a href="%s">&laquo; Prev</a> ' % _page_href(search, page - 1)
	controls += "Page %d of %d" % [page, total_pages]
	if page < total_pages:
		controls += ' <a href="%s">Next &raquo;</a>' % _page_href(search, page + 1)
	controls += "</p>"
	return controls


## URL-QUERY-encodes the search term for a Prev/Next href -- deliberately
## String.uri_encode(), never CompanionHtml.escape(). Those are two
## different operations for two different contexts: escape() is for HTML
## ATTRIBUTE TEXT (the search box's own value=""), where a literal "&"
## must stay a literal "&" for the browser to display. uri_encode() is for
## a URL QUERY COMPONENT, where a literal "&" would be misread as the
## separator into a second, bogus parameter. uri_encode() already
## percent-encodes "&"/'"'/etc., so the composed href is safe by
## construction without a second escaping pass -- conflating the two here
## is exactly what would corrupt a Prev/Next link for a search containing
## "&" (pinned by test_the_page_href_helper_url_encodes_an_ampersand_in_the_search_term).
static func _page_href(search: String, page: int) -> String:
	return "/items?q=%s&page=%d" % [search.uri_encode(), page]


static func _row(item, has_it: bool) -> String:
	return ("<tr><td>%s</td><td><a href=\"/items/%s\">%s</a></td><td>%s</td><td>%s</td>" \
		+ "<td>%s</td><td>%s</td><td>%s</td><td>%s</td></tr>\n") % [
		item.id,
		item.id,
		item.display_name,
		item.kind,
		str(item.max_stack),
		str(item.weapon_damage),
		str(item.armor),
		str(item.mass_kg),
		"have" if has_it else "",
	]


## Every item id this save currently has a physical claim on -- inventory
## stacks, worn equipment, and the hotbar. Not crafted_items -- those are
## looked up by id directly in _all_item_ids(), since a crafted id's
## presence in the save IS its "have".
static func _held_ids(save_dict: Dictionary) -> Dictionary:
	var held := {}
	for entry in save_dict.get("inventory", []):
		held[entry.id] = true
	var equipment: Dictionary = save_dict.get("equipment", {})
	for slot in equipment:
		held[equipment[slot]] = true
	for item_id in save_dict.get("hotbar", []):
		if String(item_id) != "":
			held[item_id] = true
	return held
