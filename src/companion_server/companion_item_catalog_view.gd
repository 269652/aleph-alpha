extends RefCounted

## Renders every authored item (ItemCatalog.known_ids()) plus this save's
## own crafted items, each row annotated with whether the save currently
## holds it -- see docs/concept/companion_server.md's Item Catalog section.
## Deliberately NOT filtered down to only-held items: no discovery/spoiler
## tracking exists for items in this codebase (item_identity.md is about
## content-addressing crafted items, not visibility), so showing the full
## authored reference, annotated, is the option that invents no new
## persisted state -- pillar 4, "one data source, reused".

const CompanionPageShell = preload("res://src/companion_server/companion_page_shell.gd")
const ItemCatalog = preload("res://src/gameplay/item_catalog.gd")


static func render(save_dict: Dictionary, catalog: ItemCatalog) -> String:
	var held := _held_ids(save_dict)

	var body := "<table>\n<tr><th>ID</th><th>Item</th><th>Kind</th><th>Max stack</th>" \
		+ "<th>Damage</th><th>Armor</th><th>Mass (kg)</th><th></th></tr>\n"
	for item_id in catalog.known_ids():
		body += _row(catalog.make(item_id), held.has(item_id))
	# A crafted (content-addressed) id this save actually has isn't in
	# known_ids() (deliberately -- see ItemCatalog.known_ids()'s own doc
	# comment about not printing a screenful of asm_<hex> ids), but a
	# crafted item THIS SAVE holds is still real content worth showing.
	for item_id in save_dict.get("crafted_items", {}):
		if catalog.has(item_id):
			body += _row(catalog.make(item_id), true)
	body += "</table>"

	return CompanionPageShell.wrap("Item Catalog", body)


static func _row(item, has_it: bool) -> String:
	return ("<tr><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td>" \
		+ "<td>%s</td><td>%s</td></tr>\n") % [
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
## looked up by id directly in render(), since a crafted id's presence in
## the save IS its "have".
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
