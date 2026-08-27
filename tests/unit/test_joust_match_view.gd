extends GutTest

## JoustMatchView: the node/rendering adapter for JoustMatch (docs/concept/
## easter_eggs.md's "hidden sea cave... dueling-birds cabinet" entry) -- the
## actual visible, playable arcade-cabinet screen the stone bench becomes.
## Every real GAME RULE is JoustMatch's own job and is covered at full
## rigor by test_joust_match.gd; this file only pins the thin glue this
## Control adds on top (visibility, the timed transform beat before real
## play starts, and that finishing a match both hides the overlay and
## fires match_finished) -- matching this project's own established
## convention that a Control's on-screen layout doesn't get the same
## unit-test rigor as a pure rules module (see test_crafting_window.gd's
## own "layout glue, not game rules" framing).

const JoustMatchView = preload("res://src/rendering/joust_match_view.gd")
const JoustMatch = preload("res://src/gameplay/joust_match.gd")

var view: JoustMatchView


func before_each():
	# World._apply_keybindings normally registers every Keybindings action
	# onto the InputMap at runtime (there is no static [input] section in
	# project.godot) -- this test instantiates JoustMatchView directly,
	# without a World, so it registers the one action it needs itself (see
	# test_player_kick.gd's own before_each for the same pattern).
	if not InputMap.has_action("attack"):
		InputMap.add_action("attack")

	view = JoustMatchView.new()
	add_child(view)


func after_each():
	view.free()


func test_hidden_until_start_match():
	assert_false(view.visible)


func test_start_match_makes_it_visible_and_resets_the_score():
	view.start_match()
	assert_true(view.visible)
	assert_eq(view._state["player_wins"], 0)
	assert_eq(view._state["ai_wins"], 0)


func test_stays_inactive_during_the_transform_beat():
	view.start_match()
	view._process(JoustMatchView.TRANSFORM_DURATION - 0.1)
	assert_false(view._active)


func test_becomes_active_once_the_transform_beat_finishes():
	view.start_match()
	view._process(JoustMatchView.TRANSFORM_DURATION + 0.1)
	assert_true(view._active)


func test_match_finished_signal_fires_and_hides_the_view_when_the_match_ends():
	view.start_match()
	view._process(JoustMatchView.TRANSFORM_DURATION + 0.1)
	assert_true(view._active)
	watch_signals(view)
	# Force a near-finished state directly (bypassing real Input, which
	# test_joust_match.gd already covers exhaustively) so this test stays
	# fast and deterministic rather than racing a full best-of-three match.
	view._state["player_wins"] = JoustMatch.ROUNDS_TO_WIN - 1
	view._state["player_height"] = 90.0
	view._state["ai_height"] = 10.0
	view._state["gap"] = 1.0
	view._process(0.1)
	assert_signal_emitted(view, "match_finished")
	assert_false(view.visible)
