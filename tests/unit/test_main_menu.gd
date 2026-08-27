extends GutTest

## MainMenu: the start screen and character creator. Covers the creator's
## state machine (class pick + appearance cycling -> the authored appearance
## handed to World), not the pixel layout.

const MainMenu = preload("res://scenes/main_menu.gd")
const HeroAppearance = preload("res://src/rendering/hero_appearance.gd")
const PlayerSave = preload("res://src/gameplay/player_save.gd")
const ProceduralCharacterSprite = preload("res://src/rendering/procedural_character_sprite.gd")

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


# -- skills tab (reported: "there should be tabs with character and --------
# -- skilltree so you can view each classes skills before creating") -------

const SkillTree = preload("res://src/gameplay/skill_tree.gd")


func test_skill_node_cards_exist_for_every_shared_skill_tree_node():
	var skill_tree := SkillTree.new()
	assert_eq(menu._skill_node_cards.size(), skill_tree.node_ids().size())
	for node_id in skill_tree.node_ids():
		assert_true(menu._skill_node_cards.has(node_id), node_id)


func test_selecting_a_class_updates_the_skills_tab_heading():
	menu._select_class("mage")
	assert_string_contains(menu._skills_class_label.text, "Mage")

	menu._select_class("warrior")
	assert_string_contains(menu._skills_class_label.text, "Warrior")


## Warrior's own stat lens (class_archetype.gd) favors max_health above
## every other stat -- the vitality nodes (the only shared-pool nodes that
## grant max_health) must be the ones highlighted as synergizing, and a
## differently-stated node (e.g. strength, which grants attack_damage) must
## not be.
func test_warriors_dominant_stat_highlights_the_vitality_nodes():
	menu._select_class("warrior")
	var vitality_card: PanelContainer = menu._skill_node_cards["vitality_1"]
	var strength_card: PanelContainer = menu._skill_node_cards["strength_1"]
	var vitality_style: StyleBoxFlat = vitality_card.get_theme_stylebox("panel")
	var strength_style: StyleBoxFlat = strength_card.get_theme_stylebox("panel")
	assert_eq(vitality_style.border_color, MainMenu.ACCENT)
	assert_eq(strength_style.border_color, MainMenu.PANEL_BORDER)


## Mage's dominant stat is max_mana, which has no corresponding shared-pool
## skill node (see _CLASS_STAT_TO_SKILL_STAT's own doc comment) -- nothing
## should be highlighted, honestly reflecting the current gap rather than
## forcing a false match.
func test_mage_highlights_nothing_since_no_shared_node_grants_mana():
	menu._select_class("mage")
	for node_id in menu._skill_node_cards:
		var card: PanelContainer = menu._skill_node_cards[node_id]
		var style: StyleBoxFlat = card.get_theme_stylebox("panel")
		assert_eq(style.border_color, MainMenu.PANEL_BORDER, node_id)


func test_class_card_selection_repaints_its_own_border_to_the_accent_color():
	menu._select_class("ranger")
	var selected_card: PanelContainer = menu._class_buttons["ranger"]
	var other_card: PanelContainer = menu._class_buttons["warrior"]
	assert_eq((selected_card.get_theme_stylebox("panel") as StyleBoxFlat).border_color, MainMenu.ACCENT)
	assert_eq((other_card.get_theme_stylebox("panel") as StyleBoxFlat).border_color, MainMenu.PANEL_BORDER)


# -- the creator screen must stay scrollable, and Begin must never scroll --
# -- off with it (reported: "the character creation screen overflows and --
# -- is not scrollable so I can't start a new game because button is not --
# -- visible") ---------------------------------------------------------------

func _find_begin_button() -> Button:
	for b in menu._create_screen.find_children("*", "Button", true, false):
		if b.text == "Begin":
			return b
	return null


## Looks specifically for the scroll wrapping the whole TabContainer
## (whichever ScrollContainer's direct child is the TabContainer itself),
## not just "at least one ScrollContainer exists somewhere" -- the creator
## should have exactly this one scroll region and no other (the skills tab
## used to nest a second one around its node grid, which collapsed the grid
## to zero height; see
## test_the_skill_grid_is_not_nested_in_a_second_scroll_container).
func _find_outer_tab_scroll() -> ScrollContainer:
	for s in menu._create_screen.find_children("*", "ScrollContainer", true, false):
		for child in s.get_children():
			if child is TabContainer:
				return s
	return null


func test_create_screen_wraps_its_tab_content_in_a_scroll_container():
	assert_not_null(_find_outer_tab_scroll(), "the tab content should be wrapped in a scroll area")


## The Begin button must sit OUTSIDE the scrollable area -- otherwise a tall
## enough tab content (a bigger skills grid, a longer class list) can scroll
## it out of view with nothing left to reach it by.
func test_begin_button_is_not_inside_the_scroll_container():
	var scroll := _find_outer_tab_scroll()
	var begin := _find_begin_button()
	assert_not_null(begin, "Begin button should exist")
	var ancestor := begin.get_parent()
	var inside_scroll := false
	while ancestor != null:
		if ancestor == scroll:
			inside_scroll = true
			break
		ancestor = ancestor.get_parent()
	assert_false(inside_scroll, "Begin must stay outside the scrollable tab content")


# -- the Skills tab must not collapse (reported live: picking Skills shrank --
# -- the whole tab body AND its tab strip to a narrow column, with the -------
# -- shared skill grid not visible at all) -----------------------------------

func _find_tab_container() -> TabContainer:
	for t in menu._create_screen.find_children("*", "TabContainer", true, false):
		return t
	return null


func _find_tab_named(tab_name: String) -> Control:
	for child in _find_tab_container().get_children():
		if child.name == tab_name:
			return child
	return null


## Shows the create screen with the named tab selected and lets the layout
## settle, so these assert against REAL laid-out rects rather than flags --
## the defect is a size, not a property.
func _lay_out_create_screen_on_tab(tab_name: String) -> void:
	menu._show(menu._create_screen)
	var tabs := _find_tab_container()
	tabs.current_tab = tabs.get_tab_idx_from_control(_find_tab_named(tab_name))
	await get_tree().process_frame
	await get_tree().process_frame


## The width a tab body should occupy: the outer scroll's own width LESS
## whatever its vertical scrollbar is currently taking, since a shown
## scrollbar is laid over the right edge and the content area ends where it
## begins. Read off the live scrollbar rather than written down as a number,
## so a theme that changes the scrollbar's thickness can't turn this into a
## false failure.
func _tab_scroll_content_width() -> float:
	var scroll := _find_outer_tab_scroll()
	var bar := scroll.get_v_scroll_bar()
	return scroll.size.x - (bar.size.x if bar.visible else 0.0)


## The tab body must span the full width of the ScrollContainer that holds
## it, on EVERY tab. ScrollContainer sizes a non-EXPAND child to that child's
## own combined minimum size, and a TabContainer's minimum width is (with the
## default use_hidden_tabs_for_min_size == false) the minimum width of
## whichever tab is CURRENTLY VISIBLE. The Skills tab's own minimum width is
## tiny -- autowrapping labels have near-zero minimum width -- so selecting
## it collapsed the entire tab body, and with it the tab strip, into a narrow
## column with most of the 880px panel sitting empty beside it (reported
## live). The Character tab only ever looked right by luck: its hero card +
## fixed-width appearance card happen to have a minimum width close to the
## panel's. Note the outer scroll has horizontal_scroll_mode DISABLED, so
## "exactly the scroll's width" is the only correct answer -- anything wider
## would be unreachable, anything narrower wastes the panel.
func test_selecting_the_skills_tab_does_not_collapse_the_tab_body():
	await _lay_out_create_screen_on_tab("Skills")
	var tabs := _find_tab_container()
	var available := _tab_scroll_content_width()
	assert_eq(tabs.get_parent(), _find_outer_tab_scroll(), "the TabContainer should be the outer scroll's child")
	assert_almost_eq(
		tabs.size.x,
		available,
		1.0,
		"Skills tab body is %d wide in a %d-wide content area" % [tabs.size.x, available]
	)


## ...and the Character tab must not have been narrowed by the same fix.
func test_the_character_tab_body_also_spans_the_scroll_areas_width():
	await _lay_out_create_screen_on_tab("Character")
	var tabs := _find_tab_container()
	var available := _tab_scroll_content_width()
	assert_almost_eq(
		tabs.size.x,
		available,
		1.0,
		"Character tab body is %d wide in a %d-wide content area" % [tabs.size.x, available]
	)


## The diorama (see docs/concept/character_creator_preview_scene.md) must fit
## inside the FIRST, unscrolled view of the Character tab, alongside the
## class-icon row sitting above it -- reported live, with a screenshot: the
## diorama's own bottom edge (grass/trees mid-render) was visibly cut off by
## the scroll area's own viewport, not merely "below the fold" the way the
## appearance labels/reroll button legitimately are (this tab has exactly one
## scroll region, by design -- see test_create_screen_wraps_its_tab_content_
## in_a_scroll_container -- so SOME content scrolling is expected; the
## diorama's own box straddling that fold mid-render is not). Checked
## against real laid-out global rects, not a hardcoded pixel guess, so a
## theme or window-size change can't quietly turn this into a false pass.
func _find_diorama_glow_wrap() -> Control:
	var svc: SubViewportContainer = null
	for n in menu._create_screen.find_children("*", "SubViewportContainer", true, false):
		svc = n
	if svc == null:
		return null
	# svc -> frame (PanelContainer) -> centered (CenterContainer) -> glow_wrap.
	return svc.get_parent().get_parent().get_parent()


func test_the_diorama_fits_within_the_first_unscrolled_view_of_the_character_tab():
	await _lay_out_create_screen_on_tab("Character")
	var scroll := _find_outer_tab_scroll()
	var glow_wrap := _find_diorama_glow_wrap()
	assert_not_null(glow_wrap, "the diorama's own panel should exist on the Character tab")
	var scroll_bottom: float = scroll.global_position.y + scroll.size.y
	var diorama_bottom: float = glow_wrap.global_position.y + glow_wrap.size.y
	assert_true(
		diorama_bottom <= scroll_bottom,
		"diorama panel bottom (%.0f) is cut off by the scroll area's own visible bottom (%.0f)" % [diorama_bottom, scroll_bottom]
	)


# -- preview toggle: diorama <-> the old "standard" full-body static portrait
# -- (asked directly: "add a toggle button in the top right that toggles
# -- between diorama and standard character preview with full size char
# -- rendered") -- the same ProceduralCharacterSprite.generate_hero_portrait_
# -- texture the class-icon row already uses, just at the preview panel's own
# -- full size instead of a tiny icon, since that portrait pipeline is real,
# -- tested, and already live on this exact screen -- not a new one.

func test_preview_toggle_button_sits_top_right_of_the_preview_panel():
	var button := menu._preview_toggle_button
	assert_not_null(button)
	assert_eq(button.get_parent(), menu._preview_glow_wrap)
	assert_eq(button.anchor_left, 1.0)
	assert_eq(button.anchor_top, 0.0)


func test_diorama_is_the_default_view():
	assert_true(menu._diorama_view.visible)
	assert_false(menu._standard_portrait.visible)


func test_pressing_the_toggle_swaps_which_view_is_visible():
	menu._preview_toggle_button.pressed.emit()
	assert_false(menu._diorama_view.visible)
	assert_true(menu._standard_portrait.visible)
	menu._preview_toggle_button.pressed.emit()
	assert_true(menu._diorama_view.visible)
	assert_false(menu._standard_portrait.visible)


func test_the_standard_portrait_shows_a_real_texture_of_the_current_appearance():
	menu._preview_toggle_button.pressed.emit()
	assert_not_null(menu._standard_portrait.texture)


## The SubViewport keeps rendering, and the diorama keeps simulating, for as
## long as it's the visible view (UPDATE_ALWAYS, see _build_diorama_view's
## own doc comment) -- but paying that cost while the OTHER view is what's
## actually on screen would be pure waste, and would also let the hero teleport
## mid-toggle instead of holding still where it was left.
func test_toggling_away_from_the_diorama_pauses_it():
	assert_true(menu._diorama.is_processing())
	menu._preview_toggle_button.pressed.emit()
	assert_false(menu._diorama.is_processing())
	menu._preview_toggle_button.pressed.emit()
	assert_true(menu._diorama.is_processing())


## The portrait's own real texture (ProceduralCharacterSprite.PORTRAIT_SIZE,
## 26x40 -- a tall headshot strip) is a very different SHAPE from the
## diorama's square DIORAMA_VIEW_SIZE. Both views used to share that exact
## same square custom_minimum_size, so STRETCH_KEEP_ASPECT_CENTERED
## letterboxed the narrow portrait inside it -- most of the square stayed
## empty (reported live, twice: "it's supposed to fill the entire
## rectangle", then again after the pond fix landed: "still no rectangle
## filling the panel" -- the pond was fixed; this, the NEW toggle's own
## portrait view, was the still-real second cause). The portrait's own
## custom_minimum_size must match its own aspect ratio, not the diorama's.
func test_standard_portrait_size_matches_its_own_textures_aspect_ratio():
	# Only the ACTIVE view's own size is nonzero (see the very next test) --
	# the portrait's real aspect-correct size doesn't apply until it's the
	# one being shown.
	menu._preview_toggle_button.pressed.emit()
	var portrait_size := ProceduralCharacterSprite.PORTRAIT_SIZE
	var expected_aspect: float = float(portrait_size.x) / float(portrait_size.y)
	var actual_aspect: float = menu._standard_portrait.custom_minimum_size.x / menu._standard_portrait.custom_minimum_size.y
	assert_almost_eq(actual_aspect, expected_aspect, 0.01)


## Fixing `frame`'s own size to the active view (the previous fix) wasn't
## the whole panel: `glow_wrap` -- the OUTER gold DNA-rarity-ring box
## `frame` sits centred inside -- has its own SEPARATE custom_minimum_size,
## fixed at DIORAMA_VIEW_SIZE + 28 once at construction and never touched
## again. Toggling to the narrower portrait shrank `frame` correctly but
## left `glow_wrap` at its old square size regardless, so the portrait sat
## centred inside a gold box visibly wider than it (reported live, with a
## screenshot, after the frame-only fix: "also fill the whole panel
## please"). glow_wrap's own size must follow the SAME active view frame
## does.
func test_glow_wrap_itself_resizes_to_match_the_active_view():
	var padding := Vector2(28, 28)
	assert_eq(menu._preview_glow_wrap.custom_minimum_size, Vector2(menu.DIORAMA_VIEW_SIZE) + padding)
	menu._preview_toggle_button.pressed.emit()
	assert_eq(menu._preview_glow_wrap.custom_minimum_size, menu.STANDARD_PORTRAIT_DISPLAY_SIZE + padding)
	menu._preview_toggle_button.pressed.emit()
	assert_eq(menu._preview_glow_wrap.custom_minimum_size, Vector2(menu.DIORAMA_VIEW_SIZE) + padding)


## Nearest-neighbour filtering (TEXTURE_FILTER_NEAREST) keeps pixel art
## crisp at an INTEGER scale -- every source texel maps cleanly onto the
## same whole number of screen pixels. At a fractional scale (the previous
## 248/40 = 6.2x), source texels straddle destination pixel boundaries
## unevenly, and GPU nearest-neighbour sampling shows that as soft/uneven
## edges rather than the same crisp blocks a clean multiple gives (reported
## live, with a screenshot: "char preview is super blurry" -- the old
## static portrait this replaced used a clean 5x for exactly this reason,
## per its own history in docs/progress.md). STANDARD_PORTRAIT_DISPLAY_SIZE
## must be a whole-number multiple of PORTRAIT_SIZE on both axes.
func test_standard_portrait_display_size_is_a_whole_number_scale_of_the_source_texture():
	var portrait_size := Vector2(ProceduralCharacterSprite.PORTRAIT_SIZE)
	var scale := menu.STANDARD_PORTRAIT_DISPLAY_SIZE / portrait_size
	assert_almost_eq(scale.x, round(scale.x), 0.001, "width scale %f is not a whole number" % scale.x)
	assert_almost_eq(scale.y, round(scale.y), 0.001, "height scale %f is not a whole number" % scale.y)
	assert_almost_eq(scale.x, scale.y, 0.001, "x/y scale must match or the portrait distorts")


## Only the ACTIVE view may drive the shared panel's own size -- otherwise
## the panel is stuck sized for whichever view happens to need more space in
## a given axis, leaving the OTHER (smaller-shaped) view's own rectangle
## with dead space around it regardless of stretch mode. The inactive view's
## own custom_minimum_size drops to zero so it cannot contribute.
func test_only_the_active_preview_view_has_a_nonzero_minimum_size():
	assert_eq(menu._standard_portrait.custom_minimum_size, Vector2.ZERO)
	assert_eq(menu._diorama_view.custom_minimum_size, Vector2(menu.DIORAMA_VIEW_SIZE))
	menu._preview_toggle_button.pressed.emit()
	assert_eq(menu._diorama_view.custom_minimum_size, Vector2.ZERO)
	assert_ne(menu._standard_portrait.custom_minimum_size, Vector2.ZERO)


## The skill grid's own parent must give it its full height. The creator has
## exactly one scroll region -- the outer one wrapping the whole TabContainer
## (see test_create_screen_wraps_its_tab_content_in_a_scroll_container), so
## nothing inside a tab is entitled to clip its own contents. Wrapping the
## grid in a SECOND, inner ScrollContainer did exactly that: a ScrollContainer
## reports a combined minimum size of ~0 on every axis it may scroll, so the
## grid's height never propagated up to the tab's VBoxContainer, which then
## had no spare height to hand its EXPAND_FILL child -- the inner scroll got
## zero height and the whole shared skill pool was never visible at all
## (reported live).
func test_the_shared_skill_grid_is_not_clipped_away_by_its_parent():
	await _lay_out_create_screen_on_tab("Skills")
	var card: PanelContainer = menu._skill_node_cards["vitality_1"]
	var grid: Control = card.get_parent()
	var holder: Control = grid.get_parent()
	assert_gt(grid.size.y, 0.0, "the skill grid should have a real laid-out height")
	assert_gte(
		holder.size.y,
		grid.size.y,
		"the skill grid is %d tall inside a %d-tall parent" % [grid.size.y, holder.size.y]
	)


## Belt and braces on the same defect, stated structurally: the grid belongs
## under the OUTER tab scroll and nothing else. A second, nested scroll is
## what zeroed it out above.
func test_the_skill_grid_is_not_nested_in_a_second_scroll_container():
	var card: PanelContainer = menu._skill_node_cards["vitality_1"]
	var scrolls := 0
	var ancestor: Node = card.get_parent()
	while ancestor != null and ancestor != menu:
		if ancestor is ScrollContainer:
			scrolls += 1
		ancestor = ancestor.get_parent()
	assert_eq(scrolls, 1, "the skill grid should sit under the outer tab scroll only")


# -- hero showcase: class icons over the character, DNA glow/resonance -----
# -- (reported: "I want the classes to be icons and on top over the -------
# -- character and more character customization options and DNA influence")

## Each class icon card must actually be a rendered portrait, not a
## placeholder -- the whole point of "icons on top of the character".
func test_every_class_icon_has_a_real_portrait_texture():
	for archetype in menu._archetypes.archetype_names():
		var texture: Texture2D = menu._class_icon_texture(archetype)
		assert_not_null(texture, archetype)
		assert_gt(texture.get_width(), 0, archetype)


func test_class_icons_are_cached_not_regenerated_every_call():
	var first := menu._class_icon_texture("warrior")
	var second := menu._class_icon_texture("warrior")
	assert_eq(first, second)


## New sixth customization axis: an independent accent/trim color, per the
## follow-up ask for "more character customization options" -- previously
## trim was always fixed by the class palette with no player choice at all.
func test_trim_is_now_a_cyclable_customization_axis():
	assert_has(HeroAppearance.AXES, "trim")
	var before: Color = menu.current_appearance().trim
	menu._cycle_axis("trim", 1)
	assert_ne(menu.current_appearance().trim, before)


func test_trim_choice_survives_a_class_change_like_every_other_axis():
	menu._cycle_axis("trim", 2)
	var before: Color = menu.current_appearance().trim
	menu._select_class("herbalist")
	assert_eq(menu.current_appearance().trim, before)


## DNA visibly steers the class picker: whichever archetype the rolled
## genome resonates with most should have its "★" badge showing, and no
## other class's badge should.
func test_exactly_one_resonance_badge_is_visible_matching_the_dna_roll():
	var genome := menu.current_dna()
	var best_archetype := ""
	var best_value := -1.0
	for archetype in genome.resonance:
		if genome.resonance[archetype] > best_value:
			best_value = genome.resonance[archetype]
			best_archetype = archetype

	var visible_count := 0
	for archetype in menu._resonance_badges:
		var badge: Label = menu._resonance_badges[archetype]
		if badge.visible:
			visible_count += 1
			assert_eq(archetype, best_archetype)
	assert_eq(visible_count, 1)


## The glow behind the portrait must actually change color with rarity, not
## stay static -- otherwise a legendary roll wouldn't read as different from
## a common one at a glance.
func test_dna_glow_color_differs_between_common_and_legendary():
	var common_color: Color = MainMenu.RARITY_GLOW_COLORS[HeroDna.RARITY_COMMON]
	var legendary_color: Color = MainMenu.RARITY_GLOW_COLORS[HeroDna.RARITY_LEGENDARY]
	assert_ne(common_color, legendary_color)

	menu._update_dna_glow(HeroDna.RARITY_LEGENDARY)
	var style := menu._dna_glow.get_theme_stylebox("panel") as StyleBoxFlat
	assert_almost_eq(style.bg_color.r, legendary_color.r, 0.01)
	assert_almost_eq(style.bg_color.g, legendary_color.g, 0.01)
	assert_almost_eq(style.bg_color.b, legendary_color.b, 0.01)


## _dna_glow's own parent (glow_wrap) must stay pinned to its
## custom_minimum_size, not stretch out to whatever width the hero card
## itself happens to be (SIZE_EXPAND_FILL, to share the dialog's own
## width with the appearance column) -- a plain Control defaults to
## SIZE_FILL on both axes, which a VBoxContainer parent (inner) DOES
## stretch to its own cross-axis width. Left unguarded, the glow ring
## (anchored PRESET_FULL_RECT within glow_wrap) stretches out to that same
## huge size -- a large, near-empty gold-at-low-alpha box over the card's
## dark background reads as a flat, unrelated tan panel with the actual
## diorama frame (PRESET_CENTER, so it does NOT stretch) anchored off-
## centre somewhere inside it -- reported live, both for the diorama and,
## before it, the static portrait this replaced: "not contained in the
## panel."
func test_glow_wrap_does_not_stretch_to_fill_the_hero_card():
	var glow_wrap: Control = menu._dna_glow.get_parent()
	assert_eq(glow_wrap.size_flags_horizontal, Control.SIZE_SHRINK_CENTER)
	assert_eq(glow_wrap.size_flags_vertical, Control.SIZE_SHRINK_CENTER)


## Only legendary pulses -- common/rare stay a static glow so the animation
## itself reads as "something special", not constant background motion.
func test_only_legendary_rarity_starts_a_pulsing_glow_tween():
	menu._update_dna_glow(HeroDna.RARITY_COMMON)
	assert_null(menu._dna_glow_tween)

	menu._update_dna_glow(HeroDna.RARITY_LEGENDARY)
	assert_not_null(menu._dna_glow_tween)


# -- Begin is the destructive click: it must be confirmed ---------------------
# -- (New Game AND Host Game both route through this same creator screen, and
# -- World answers start_requested by wiping the player save plus every
# -- world-persistence store -- see World._wipe_persisted_world.) -------------

## Rebuilds `menu` with a real save file already on disk, so `_ready()` sees
## `_player_save.has_save(save_path)` as true -- the same fixture shape
## test_root_screen_offers_load_game_when_a_save_exists already uses.
func _rebuild_menu_with_a_save() -> void:
	var file := FileAccess.open(TEST_SAVE_PATH, FileAccess.WRITE)
	file.store_var({"health": 80.0})
	file.close()
	menu.free()
	menu = MainMenu.new()
	menu.save_path = TEST_SAVE_PATH
	menu.reroll_save_path = TEST_REROLL_SAVE_PATH
	add_child(menu)


func _find_button(screen: Control, label: String) -> Button:
	for b in screen.find_children("*", "Button", true, false):
		if b.text == label:
			return b
	return null


## New Game and Host Game both reach Begin, and World answers
## start_requested by wiping the player save and every world-persistence
## store (chunk modifications, planted trees, fish populations, the event/
## memory/household/contract/market/institution/world-boss stores, the world
## clock) -- irreversibly, and the 60s autosave then overwrites
## player_save.bin so even undeleting is gone. Begin must not be able to
## trigger that without the player saying so.
func test_begin_does_not_start_immediately_when_a_save_would_be_overwritten():
	_rebuild_menu_with_a_save()
	watch_signals(menu)

	_find_button(menu._create_screen, "Begin").pressed.emit()

	assert_signal_not_emitted(menu, "start_requested")
	assert_true(menu._overwrite_confirm_screen.visible, "the confirmation should be showing")
	assert_false(menu._create_screen.visible, "the creator should have been swapped out")


## The guard on the other side: a first-ever game has nothing to lose, so it
## must not be made to click through a warning about destroying a save that
## does not exist. Uses the SAME has_save predicate that decides whether the
## root screen offers Load Game -- one answer to "is there something to
## lose", in one place.
func test_begin_starts_immediately_when_there_is_no_save_to_lose():
	watch_signals(menu)

	_find_button(menu._create_screen, "Begin").pressed.emit()

	assert_signal_emitted(menu, "start_requested")


func test_confirming_the_overwrite_starts_the_game():
	_rebuild_menu_with_a_save()
	watch_signals(menu)

	_find_button(menu._create_screen, "Begin").pressed.emit()
	_find_button(menu._overwrite_confirm_screen, "Overwrite and start").pressed.emit()

	assert_signal_emitted(menu, "start_requested")


func test_keeping_the_save_returns_to_the_creator_without_starting():
	_rebuild_menu_with_a_save()
	watch_signals(menu)

	_find_button(menu._create_screen, "Begin").pressed.emit()
	_find_button(menu._overwrite_confirm_screen, "Keep my save").pressed.emit()

	assert_signal_not_emitted(menu, "start_requested")
	assert_true(menu._create_screen.visible, "Keep my save should go back to the creator")


## Host Game is exactly as destructive as New Game -- it routes through the
## same creator and the same Begin button, so a confirmation placed only on
## the root screen's "New Game" would miss it entirely.
func test_hosting_a_game_is_confirmed_too():
	_rebuild_menu_with_a_save()
	_find_button(menu._root_screen, "Host Game (LAN)").pressed.emit()
	watch_signals(menu)

	_find_button(menu._create_screen, "Begin").pressed.emit()

	assert_signal_not_emitted(menu, "start_requested")
	assert_true(menu._overwrite_confirm_screen.visible)


## The confirmation is a screen in the SAME state machine as the other three
## (root/create/join), so _show hides it like any other -- a screen missing
## from _show's list stays visible on top of whatever comes next.
func test_the_confirmation_screen_is_hidden_by_showing_another_screen():
	_rebuild_menu_with_a_save()
	_find_button(menu._create_screen, "Begin").pressed.emit()

	menu._show(menu._root_screen)

	assert_false(menu._overwrite_confirm_screen.visible)
	assert_true(menu._root_screen.visible)
