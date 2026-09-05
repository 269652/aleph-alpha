extends GutTest

## CompanionCharacterSheetView: renders most of Player.to_save_dict() as HTML
## (see docs/concept/companion_server.md's Character Sheet pillar: "mirrors
## Player.to_save_dict() field-for-field... no new state"). Scoped to what
## actually reads as a character sheet -- class/health/wallet/XP/equipment/
## skill allocations/hotbar -- not literally every save key (position,
## appearance, dna_seed, and the raw skill_points_paid ledger have no
## legible place on a sheet and are left for a future pass if ever wanted).
## Equipment and hotbar show real display names (via ItemCatalog), never a
## raw item id, matching every other player-facing surface in this game.

const CompanionCharacterSheetView = preload("res://src/companion_server/companion_character_sheet_view.gd")
const ItemCatalog = preload("res://src/gameplay/item_catalog.gd")

var catalog := ItemCatalog.new()


func _fixture_save_dict() -> Dictionary:
	return {
		"character_class": "warrior",
		"health": 42.0,
		"max_health": 100.0,
		"wallet_balance": 37.5,
		"experience_level": 4,
		"experience_total_xp": 812,
		"experience_unspent_points": 2,
		"equipment": {"chest": "leather_chest", "head": "iron_helm"},
		"allocated_nodes": {"vitality_1": true},
		"unlocked_keystones": {},
		"hotbar": ["iron_sword", "", ""],
	}


func test_shows_the_character_class():
	var html := CompanionCharacterSheetView.render(_fixture_save_dict(), catalog)
	assert_true(html.contains("warrior"))


func test_shows_the_wallet_balance():
	var html := CompanionCharacterSheetView.render(_fixture_save_dict(), catalog)
	assert_true(html.contains("37.5"))


func test_shows_the_experience_level_and_total_xp():
	var html := CompanionCharacterSheetView.render(_fixture_save_dict(), catalog)
	assert_true(html.contains("4"))
	assert_true(html.contains("812"))


func test_shows_health_over_max_health():
	var html := CompanionCharacterSheetView.render(_fixture_save_dict(), catalog)
	assert_true(html.contains("42"))
	assert_true(html.contains("100"))


func test_shows_each_equipped_slots_real_display_name_not_the_raw_item_id():
	var html := CompanionCharacterSheetView.render(_fixture_save_dict(), catalog)
	assert_true(html.contains("Leather Chest"))
	assert_true(html.contains("Iron Helm"))
	assert_false(html.contains("leather_chest"))


func test_shows_the_hotbars_real_display_names():
	var html := CompanionCharacterSheetView.render(_fixture_save_dict(), catalog)
	assert_true(html.contains("Iron Sword"))


func test_shows_allocated_skill_nodes():
	var html := CompanionCharacterSheetView.render(_fixture_save_dict(), catalog)
	assert_true(html.contains("vitality_1"))


func test_empty_equipment_and_hotbar_render_without_crashing():
	var save_dict := _fixture_save_dict()
	save_dict.equipment = {}
	save_dict.hotbar = []
	var html := CompanionCharacterSheetView.render(save_dict, catalog)
	assert_true(html.length() > 0)


func test_a_missing_key_falls_back_to_a_sensible_default_rather_than_crashing():
	# A hand-built/partial fixture (or a pre-companion-server save) may lack
	# keys this view wants -- must degrade gracefully, never error.
	var html := CompanionCharacterSheetView.render({}, catalog)
	assert_true(html.length() > 0)
