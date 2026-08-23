extends GutTest

## MainMenu: the start screen and character creator. Covers the creator's
## state machine (class pick + appearance cycling -> the authored appearance
## handed to World), not the pixel layout.

const MainMenu = preload("res://scenes/main_menu.gd")
const HeroAppearance = preload("res://src/rendering/hero_appearance.gd")
const PlayerSave = preload("res://src/gameplay/player_save.gd")

## Isolates the Load Game button's save-detection from the real save file
## (see docs/concept/persistence.md) -- MainMenu.save_path is overridable for
## exactly this reason, set before add_child() triggers _ready().
const TEST_SAVE_PATH := "user://test_main_menu_save.bin"
## Isolates the DNA reroll budget's persistence (see HeroDna's 24h reset)
## from the real file the same way.
const TEST_REROLL_SAVE_PATH := "user://test_main_menu_rerolls.bin"

var menu: MainMenu


func before_each():
	menu = MainMenu.new()
	menu.save_path = TEST_SAVE_PATH
	menu.reroll_save_path = TEST_REROLL_SAVE_PATH
	add_child(menu)


func after_each():
	menu.free()
	for path in [TEST_SAVE_PATH, TEST_REROLL_SAVE_PATH]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


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
	menu.reroll_save_path = TEST_REROLL_SAVE_PATH
	add_child(menu)

	assert_not_null(_root_load_button())


func test_pressing_load_game_emits_load_requested():
	var file := FileAccess.open(TEST_SAVE_PATH, FileAccess.WRITE)
	file.store_var({"health": 80.0})
	file.close()

	menu.free()
	menu = MainMenu.new()
	menu.save_path = TEST_SAVE_PATH
	menu.reroll_save_path = TEST_REROLL_SAVE_PATH
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


## Begin must hand World the class, the authored look, AND the rolled DNA's
## stat swing, so the spawned player actually wears/plays what the creator
## previewed.
func test_start_requested_carries_the_chosen_class_appearance_and_dna():
	menu._select_class("mage")
	menu._cycle_axis("hair_style", 2)
	var expected := menu.current_appearance()
	var expected_dna := menu.current_dna()

	var received := []
	menu.start_requested.connect(func(mode, chosen_class, appearance, dna_stat_modifiers):
		received.append([mode, chosen_class, appearance, dna_stat_modifiers]))
	menu.start_requested.emit(
		"single", menu._selected_class, menu.current_appearance(), menu.current_dna().stat_modifiers
	)

	assert_eq(received.size(), 1)
	assert_eq(received[0][1], "mage")
	assert_eq(received[0][2].hair_style, expected.hair_style)
	assert_eq(received[0][2].tunic, HeroAppearance.CLASS_PALETTES["mage"].tunic)
	assert_eq(received[0][3], expected_dna.stat_modifiers)


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


# -- DNA (see HeroDna / docs/concept/dna.md) ----------------------------------
#
# "you can randomize the base DNA of your character which influences
# stats/visuals ... slight chance of spawning a rare (better) character DNA
# ... rare DNA should still be balanced ... but it should still be a
# 'awesome, nice' moment to get one" -- genotype (HeroDna.roll) is a single
# seed the creator's appearance is ALSO derived from, so rerolling DNA
# rerolls both stats and looks together, never independently.

const HeroDna = preload("res://src/gameplay/hero_dna.gd")


func test_default_dna_is_deterministic_before_any_reroll():
	assert_eq(menu.current_dna(), menu.current_dna())


func test_reroll_dna_changes_the_seed_and_therefore_the_appearance_together():
	var appearance_before := menu.current_appearance()
	var dna_before := menu.current_dna()

	# A reroll landing on the exact same seed is astronomically unlikely but
	# not literally impossible with randi() -- loop a few times so this test
	# can't flake.
	var changed := false
	for i in 5:
		menu._reroll_dna()
		if menu.current_dna() != dna_before:
			changed = true
			break
	assert_true(changed, "rerolling should eventually change the rolled genome")
	# Appearance must have moved together with it -- same one seed drives both.
	assert_ne(menu.current_appearance(), appearance_before)


func test_reroll_dna_is_capped_at_max_free_rerolls():
	var seeds_seen := {}
	for i in HeroDna.MAX_FREE_REROLLS + 10:
		menu._reroll_dna()
		seeds_seen[menu._dna_seed] = true
	# Can't assert an exact count (a reroll can land on its own previous seed
	# by chance), but the reroll counter itself must have clamped, not kept
	# climbing past the limit's worth of actual attempts.
	assert_eq(menu._rerolls_used, HeroDna.MAX_FREE_REROLLS)


## Common/rare stay balanced; legendary is a deliberate net-positive
## exception (see HeroDna's own tests for the exhaustive version of this) --
## this just checks MainMenu actually surfaces whatever HeroDna rolled
## rather than reimplementing/breaking the invariant on its own end.
func test_current_dna_matches_whatever_heros_dna_itself_rolled_for_the_seed():
	for i in 10:
		menu._reroll_dna()
		assert_eq(menu.current_dna(), HeroDna.new().roll(menu._dna_seed))


# -- reroll budget: real-world-day gated, persisted across menu sessions ----
#
# Follow-up ask: "rerolls should reset every 24h real world hours so you
# have to wait a whole day if your rerolls are empty forcing the player to
# make wise choices".

func test_reroll_budget_persists_across_a_fresh_menu_instance():
	for i in HeroDna.MAX_FREE_REROLLS:
		menu._reroll_dna()
	assert_eq(menu._rerolls_used, HeroDna.MAX_FREE_REROLLS)

	menu.free()
	menu = MainMenu.new()
	menu.save_path = TEST_SAVE_PATH
	menu.reroll_save_path = TEST_REROLL_SAVE_PATH
	add_child(menu)

	assert_eq(menu._rerolls_used, HeroDna.MAX_FREE_REROLLS, "budget must survive reopening the menu")
	assert_false(menu._dna.can_reroll(menu._rerolls_used, menu._seconds_since_last_reset(), false))


## A save file whose last_reset_unix is already a full day+ in the past
## (simulating real time having passed while the game was closed) must
## refresh the budget on load, not just on the next reroll attempt.
func test_reroll_budget_refreshes_on_load_after_a_simulated_day_has_passed():
	var player_save := PlayerSave.new()
	player_save.save(
		{
			"rerolls_used": HeroDna.MAX_FREE_REROLLS,
			"last_reset_unix": int(Time.get_unix_time_from_system() - HeroDna.RESET_INTERVAL_SECONDS - 60.0),
		},
		TEST_REROLL_SAVE_PATH
	)

	menu.free()
	menu = MainMenu.new()
	menu.save_path = TEST_SAVE_PATH
	menu.reroll_save_path = TEST_REROLL_SAVE_PATH
	add_child(menu)

	assert_eq(menu._rerolls_used, 0, "a full real-world day should have refreshed the budget")
	assert_true(menu._dna.can_reroll(menu._rerolls_used, menu._seconds_since_last_reset(), false))


## The mirror case: a save file whose reset was only an hour ago must NOT
## refresh, however many rerolls are already spent.
func test_reroll_budget_does_not_refresh_within_the_same_day():
	var player_save := PlayerSave.new()
	player_save.save(
		{
			"rerolls_used": HeroDna.MAX_FREE_REROLLS,
			"last_reset_unix": int(Time.get_unix_time_from_system() - 3600.0),
		},
		TEST_REROLL_SAVE_PATH
	)

	menu.free()
	menu = MainMenu.new()
	menu.save_path = TEST_SAVE_PATH
	menu.reroll_save_path = TEST_REROLL_SAVE_PATH
	add_child(menu)

	assert_eq(menu._rerolls_used, HeroDna.MAX_FREE_REROLLS)
	assert_false(menu._dna.can_reroll(menu._rerolls_used, menu._seconds_since_last_reset(), false))
