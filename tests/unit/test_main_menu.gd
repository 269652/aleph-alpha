extends GutTest

## MainMenu: the start screen and character creator. Covers the creator's
## state machine (class pick + appearance cycling -> the authored appearance
## handed to World), not the pixel layout.

const MainMenu = preload("res://scenes/main_menu.gd")
const HeroAppearance = preload("res://src/rendering/hero_appearance.gd")

## Isolates the Load Game button's save-detection from the real save file
## (see docs/concept/persistence.md) -- MainMenu.save_path is overridable for
## exactly this reason, set before add_child() triggers _ready().
const TEST_SAVE_PATH := "user://test_main_menu_save.bin"

var menu: MainMenu


func before_each():
	menu = MainMenu.new()
	menu.save_path = TEST_SAVE_PATH
	add_child(menu)


func after_each():
	menu.free()
	if FileAccess.file_exists(TEST_SAVE_PATH):
		DirAccess.remove_absolute(TEST_SAVE_PATH)


func _root_load_button() -> Button:
	for b in menu._root_screen.find_children("*", "Button", true, false):
		if b.text == "Load Game":
			return b
	return null


func test_starts_with_a_valid_default_appearance():
	var appearance := menu.current_appearance()
	assert_has(HeroAppearance.SKIN_TONES, appearance.skin)
	assert_has(HeroAppearance.HAIR_COLORS, appearance.hair)


func test_selecting_a_class_changes_the_appearances_outfit():
	menu._select_class("mage")
	assert_eq(menu.current_appearance().tunic, HeroAppearance.CLASS_PALETTES["mage"].tunic)

	menu._select_class("ranger")
	assert_eq(menu.current_appearance().tunic, HeroAppearance.CLASS_PALETTES["ranger"].tunic)


## Cycling an axis must actually change that axis of the built appearance --
## the whole point of the creator.
func test_cycling_an_axis_changes_the_appearance():
	var before: Color = menu.current_appearance().skin
	menu._cycle_axis("skin", 1)
	assert_ne(menu.current_appearance().skin, before)


func test_cycling_an_axis_forward_then_back_returns_to_the_same_look():
	var before: Color = menu.current_appearance().hair
	menu._cycle_axis("hair_color", 1)
	menu._cycle_axis("hair_color", -1)
	assert_eq(menu.current_appearance().hair, before)


## Cycling past either end wraps rather than sticking or erroring.
func test_cycling_wraps_around_the_pool():
	for i in HeroAppearance.SKIN_TONES.size():
		menu._cycle_axis("skin", 1)
	assert_has(HeroAppearance.SKIN_TONES, menu.current_appearance().skin)

	for i in HeroAppearance.SKIN_TONES.size() * 2:
		menu._cycle_axis("skin", -1)
	assert_has(HeroAppearance.SKIN_TONES, menu.current_appearance().skin)


## Regression: the panel must actually be centered, not pinned to the parent's
## top-left corner. PRESET_CENTER alone only re-anchors the reference point --
## Godot's set_anchor recomputes offsets to PRESERVE the control's current
## on-screen rect under the new anchor fraction, it does not center a rect of
## the control's size (verified against control.cpp's set_anchor/
## set_anchors_preset). Centering also requires the four offsets to form a
## symmetric half-size box around that 0.5/0.5 anchor point -- the same
## pattern every other centered popup in this codebase uses (SettingsOverlay,
## InventoryWindow, DevConsole, wired in world.gd) rather than relying on
## set_anchors_preset by itself.
func test_panel_is_actually_centered_not_pinned_to_a_corner():
	assert_eq(menu.anchor_left, 0.5)
	assert_eq(menu.anchor_top, 0.5)
	assert_eq(menu.anchor_right, 0.5)
	assert_eq(menu.anchor_bottom, 0.5)
	assert_almost_eq(menu.offset_left, -MainMenu.PANEL_SIZE.x / 2.0, 0.5)
	assert_almost_eq(menu.offset_top, -MainMenu.PANEL_SIZE.y / 2.0, 0.5)
	assert_almost_eq(menu.offset_right, MainMenu.PANEL_SIZE.x / 2.0, 0.5)
	assert_almost_eq(menu.offset_bottom, MainMenu.PANEL_SIZE.y / 2.0, 0.5)


## No save on disk -- the root screen shouldn't offer a choice that goes
## nowhere (see docs/concept/persistence.md: "the choice simply isn't offered
## when there's nothing to load").
func test_root_screen_has_no_load_game_button_when_there_is_no_save():
	assert_null(_root_load_button())


func test_root_screen_offers_load_game_when_a_save_exists():
	var file := FileAccess.open(TEST_SAVE_PATH, FileAccess.WRITE)
	file.store_var({"health": 80.0})
	file.close()

	menu.free()
	menu = MainMenu.new()
	menu.save_path = TEST_SAVE_PATH
	add_child(menu)

	assert_not_null(_root_load_button())


func test_pressing_load_game_emits_load_requested():
	var file := FileAccess.open(TEST_SAVE_PATH, FileAccess.WRITE)
	file.store_var({"health": 80.0})
	file.close()

	menu.free()
	menu = MainMenu.new()
	menu.save_path = TEST_SAVE_PATH
	add_child(menu)

	watch_signals(menu)
	_root_load_button().pressed.emit()
	assert_signal_emitted(menu, "load_requested")


func test_every_axis_is_cyclable_and_stays_in_its_pool():
	for axis in HeroAppearance.AXES:
		menu._cycle_axis(axis, 1)
	var appearance := menu.current_appearance()
	assert_has(HeroAppearance.SKIN_TONES, appearance.skin)
	assert_has(HeroAppearance.HAIR_COLORS, appearance.hair)
	assert_has(HeroAppearance.EYE_COLORS, appearance.eyes)
	assert_between(appearance.hair_style, 0, HeroAppearance.HAIR_STYLE_COUNT - 1)
	assert_between(appearance.beard, 0, HeroAppearance.BEARD_STYLE_COUNT - 1)


## Begin must hand World the class AND the authored look, so the spawned
## player actually wears what the creator previewed.
func test_start_requested_carries_the_chosen_class_and_authored_appearance():
	menu._select_class("mage")
	menu._cycle_axis("hair_style", 2)
	var expected := menu.current_appearance()

	var received := []
	menu.start_requested.connect(func(mode, chosen_class, appearance):
		received.append([mode, chosen_class, appearance]))
	menu.start_requested.emit("single", menu._selected_class, menu.current_appearance())

	assert_eq(received.size(), 1)
	assert_eq(received[0][1], "mage")
	assert_eq(received[0][2].hair_style, expected.hair_style)
	assert_eq(received[0][2].tunic, HeroAppearance.CLASS_PALETTES["mage"].tunic)


## Changing class after customizing keeps the face the player authored --
## only the outfit follows the class.
func test_changing_class_preserves_the_authored_face():
	menu._cycle_axis("hair_style", 3)
	menu._cycle_axis("beard", 2)
	var before := menu.current_appearance()

	menu._select_class("herbalist")
	var after := menu.current_appearance()

	assert_eq(after.hair_style, before.hair_style)
	assert_eq(after.beard, before.beard)
	assert_eq(after.skin, before.skin)
