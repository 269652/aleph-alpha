extends RefCounted

## Renders most of Player.to_save_dict() as HTML -- see
## docs/concept/companion_server.md's Character Sheet pillar ("mirrors
## Player.to_save_dict() field-for-field... no new state"). Scoped to what
## actually reads as a character sheet -- class/health/wallet/XP/equipment/
## skill allocations/hotbar/portrait -- not literally every save key:
## position, dna_seed, and the raw skill_points_paid ledger have no legible
## place on a sheet and are left for a future pass if ever wanted.
## Equipment and hotbar show real display names via ItemCatalog, never a
## raw item id, matching every other player-facing surface in this game.

const CompanionPageShell = preload("res://src/companion_server/companion_page_shell.gd")
const ItemCatalog = preload("res://src/gameplay/item_catalog.gd")
const CharacterSheetPortraitScene = preload("res://src/rendering/character_sheet_portrait_scene.gd")
const HeroAppearance = preload("res://src/rendering/hero_appearance.gd")


static func render(save_dict: Dictionary, catalog: ItemCatalog) -> String:
	var character_class: String = save_dict.get("character_class", "")
	var health = save_dict.get("health", 0.0)
	var max_health = save_dict.get("max_health", 0.0)
	var wallet_balance = save_dict.get("wallet_balance", 0.0)
	var level = save_dict.get("experience_level", 0)
	var total_xp = save_dict.get("experience_total_xp", 0)
	var unspent_points = save_dict.get("experience_unspent_points", 0)
	var equipment: Dictionary = save_dict.get("equipment", {})
	var allocated_nodes: Dictionary = save_dict.get("allocated_nodes", {})
	var unlocked_keystones: Dictionary = save_dict.get("unlocked_keystones", {})
	var hotbar: Array = save_dict.get("hotbar", [])

	var body := _portrait_img_tag(save_dict, character_class)
	body += "<p><strong>Class:</strong> %s</p>" % character_class
	body += "<p><strong>Health:</strong> %s / %s</p>" % [str(health), str(max_health)]
	body += "<p><strong>Wallet:</strong> %s gold</p>" % str(wallet_balance)
	body += "<p><strong>Level %s</strong> -- %s total XP, %s unspent</p>" % [
		str(level), str(total_xp), str(unspent_points)
	]

	body += "<h2>Equipment</h2><ul>"
	for slot in equipment:
		var item_id: String = equipment[slot]
		body += "<li>%s: %s</li>" % [String(slot), _display_name(item_id, catalog)]
	body += "</ul>"

	body += "<h2>Hotbar</h2><ul>"
	for item_id in hotbar:
		if String(item_id) == "":
			continue
		body += "<li>%s</li>" % _display_name(item_id, catalog)
	body += "</ul>"

	body += "<h2>Skill allocations</h2><ul>"
	for node_id in allocated_nodes:
		body += "<li>%s</li>" % String(node_id)
	for keystone_id in unlocked_keystones:
		body += "<li>%s (keystone)</li>" % String(keystone_id)
	body += "</ul>"

	return CompanionPageShell.wrap("Character Sheet", body)


static func _display_name(item_id: String, catalog: ItemCatalog) -> String:
	if not catalog.has(item_id):
		return item_id
	return catalog.make(item_id).display_name


## A small standing-portrait scene (CharacterSheetPortraitScene), embedded
## directly as a base64 data: URI rather than a second route -- Tier 1
## serves exactly one HTTP response per page (see companion_server.gd's own
## doc comment), and a data: src needs no extra dispatch case at all.
##
## Saved appearance is preferred; a save from before "appearance" was
## persisted (or any hand-built fixture missing it, e.g. an empty {} save
## dict) instead gets a fresh one derived from the same (class, dna_seed)
## HeroAppearance would have rolled originally -- real, presentable art
## either way, never a broken/blank image.
static func _portrait_img_tag(save_dict: Dictionary, character_class: String) -> String:
	var appearance: Dictionary = save_dict.get("appearance", {})
	if appearance.is_empty():
		appearance = HeroAppearance.new().appearance_for(character_class, save_dict.get("dna_seed", 0))
	var png_bytes := CharacterSheetPortraitScene.new().generate_png_bytes(appearance)
	var data_uri := "data:image/png;base64,%s" % Marshalls.raw_to_base64(png_bytes)
	return '<img class="portrait" src="%s" alt="Character portrait">' % data_uri
