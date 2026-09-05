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
const CharacterSheetPortraitScene = preload("res://src/rendering/character_sheet_portrait_scene.gd")
const HeroAppearance = preload("res://src/rendering/hero_appearance.gd")

var catalog := ItemCatalog.new()


func _fixture_save_dict() -> Dictionary:
	return {
		"character_class": "warrior",
		"appearance": HeroAppearance.new().appearance_for("warrior", 7),
		"dna_seed": 7,
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


## The portrait -- see CharacterSheetPortraitScene -- is embedded directly as
## a data URI rather than a second HTTP request: Tier 1 serves exactly one
## response per page, and a base64 data: src needs no extra route/dispatch
## case at all.
func test_shows_a_portrait_image():
	var html := CompanionCharacterSheetView.render(_fixture_save_dict(), catalog)
	assert_true(html.contains("<img"))
	assert_true(html.contains("data:image/png;base64,"))


## The embedded portrait must actually BE the hero's own saved look, not a
## generic placeholder -- compared byte-for-byte against calling
## CharacterSheetPortraitScene directly with the same appearance dict.
func test_the_portrait_reflects_the_saved_appearance():
	var save_dict := _fixture_save_dict()
	var html := CompanionCharacterSheetView.render(save_dict, catalog)
	var expected := Marshalls.raw_to_base64(
		CharacterSheetPortraitScene.new().generate_png_bytes(save_dict["appearance"])
	)
	assert_true(html.contains(expected))


## A save from before "appearance" was persisted (or any hand-built fixture
## missing it) should still render a real, non-broken portrait -- derived
## fresh from the same (class, seed) HeroAppearance would have rolled
## originally -- rather than showing nothing or crashing.
func test_falls_back_to_a_derived_appearance_when_none_is_saved():
	var save_dict := _fixture_save_dict()
	save_dict.erase("appearance")
	save_dict["dna_seed"] = 7
	var html := CompanionCharacterSheetView.render(save_dict, catalog)
	var expected := Marshalls.raw_to_base64(
		CharacterSheetPortraitScene.new().generate_png_bytes(
			HeroAppearance.new().appearance_for("warrior", 7)
		)
	)
	assert_true(html.contains(expected))
