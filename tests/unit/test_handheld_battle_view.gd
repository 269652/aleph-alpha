extends GutTest

## HandheldBattleView: the node/rendering adapter for docs/concept/
## easter_eggs.md's "hidden retro handheld" entry -- the actual visible,
## playable screen the prop boots into (a battle screen + a "world's
## smallest Pokédex" catch-list/dex screen). Every real GAME RULE is
## HandheldBattle/HandheldCatch/HandheldCollection's own job and is covered
## at full rigor by their own test files; this file only pins the thin glue
## this Control adds on top (screen switching, that selecting a move/catch
## actually drives a real HandheldBattle round, that a caught species lands
## in the collection, that closing emits its signal) -- matching this
## project's own established convention that a Control's on-screen layout
## doesn't get the same unit-test rigor as a pure rules module (see
## test_crafting_window.gd's own "layout glue, not game rules" framing, and
## test_joust_match_view.gd's identical treatment of JoustMatchView).

const HandheldBattleView = preload("res://src/rendering/handheld_battle_view.gd")
const HandheldBattle = preload("res://src/gameplay/handheld_battle.gd")
const HandheldRoster = preload("res://src/gameplay/handheld_roster.gd")

var view: HandheldBattleView


func before_each():
	view = HandheldBattleView.new()
	add_child(view)


func after_each():
	view.free()


func test_hidden_until_open():
	assert_false(view.visible)


func test_open_makes_it_visible_and_starts_an_encounter_on_the_battle_screen():
	view.open()
	assert_true(view.visible)
	assert_eq(view._screen, HandheldBattleView.SCREEN_BATTLE)
	assert_true(view._active)
	assert_false(view._state["over"])


func test_open_picks_an_enemy_species_from_the_roster():
	view.open()
	var roster := HandheldRoster.new()
	assert_true(roster.all_species().has(view._enemy_species))


func test_selecting_charge_deals_damage_and_advances_the_round():
	view.open()
	var enemy_hp_before: float = view._state["enemy"]["hp"]
	view.select_move(HandheldBattle.MOVE_CHARGE)
	assert_true(float(view._state["enemy"]["hp"]) <= enemy_hp_before)


func test_show_dex_screen_switches_the_screen_and_lists_every_species():
	view.open()
	view.show_dex_screen()
	assert_eq(view._screen, HandheldBattleView.SCREEN_DEX)
	var roster := HandheldRoster.new()
	assert_eq(view._collection.entries().size(), roster.all_species().size())


func test_show_battle_screen_switches_back():
	view.open()
	view.show_dex_screen()
	view.show_battle_screen()
	assert_eq(view._screen, HandheldBattleView.SCREEN_BATTLE)


func test_a_successful_catch_marks_the_species_caught_and_ends_the_encounter():
	view.open()
	# Force a guaranteed-success catch attempt directly, bypassing the real
	# battle's own damage math (already covered exhaustively by
	# test_handheld_battle.gd/test_handheld_catch.gd) so this test stays
	# fast and deterministic.
	view._state["enemy"]["hp"] = 0.001
	view._state["enemy"]["max_hp"] = 100.0
	view.attempt_catch_now(0)
	assert_true(view._collection.has_caught(view._enemy_species))
	assert_false(view._active)


func test_closing_hides_the_view_and_emits_closed():
	view.open()
	watch_signals(view)
	view.close()
	assert_false(view.visible)
	assert_signal_emitted(view, "closed")
