extends GutTest

const CharacterPreviewStageScene = preload("res://scenes/character_preview_stage.tscn")
const HeroAppearance = preload("res://src/rendering/hero_appearance.gd")

## main_menu.gd builds the whole create-screen subtree detached and attaches
## it to the live tree afterward (_select_class/_refresh_appearance run
## during _build_create_screen, before the built Control is added anywhere)
## -- apply_appearance/equip_weapon must not crash when called on a stage
## that hasn't entered the tree yet (_character_view is still null then),
## and must actually take effect once it does (mirrors CharacterView's own
## _pending_appearance pattern -- see CharacterPreviewStage's doc comment).
func test_appearance_and_weapon_requested_before_ready_apply_once_ready():
	var stage = CharacterPreviewStageScene.instantiate()
	var appearance := HeroAppearance.new().appearance_for("mage", 0)
	var weapon_texture := ImageTexture.create_from_image(Image.create(4, 4, false, Image.FORMAT_RGBA8))

	stage.apply_appearance(appearance)  # must not crash: not in the tree yet
	stage.equip_weapon(weapon_texture)  # must not crash: not in the tree yet

	add_child(stage)  # now _ready runs

	var tool_slot: Sprite2D = stage.get_node("CharacterView").get_node("ToolSlot")
	assert_eq(tool_slot.texture, weapon_texture, "the pre-ready equip should have taken effect")
	assert_true(tool_slot.visible)

	var body: Sprite2D = stage.get_node("CharacterView").get_node("Body")
	assert_not_null(body.texture, "the pre-ready appearance should have taken effect")

	remove_child(stage)
	stage.free()
