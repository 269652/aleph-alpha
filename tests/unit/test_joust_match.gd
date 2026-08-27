extends GutTest

## JoustMatch (docs/concept/easter_eggs.md's "hidden sea cave... dueling-
## birds cabinet" entry): the pure rules core for the aerial joust mini-game
## -- two mounted riders close a gap on a scrolling arena, height decides
## who wins each pass, first to JoustMatch.ROUNDS_TO_WIN passes wins the
## match. Same pure state-in/state-out shape as Duel.advance -- the caller
## (JoustMatchView) owns and persists the state Dictionary between frames,
## this module never keeps its own instance state.
##
## Pins every tuned constant (GRAVITY/FLAP_BOOST/APPROACH_SPEED/PASS_GAP/
## TIE_MARGIN/AI_HEIGHT_MARGIN) via direct exact-value assertions rather
## than an eyeballed comment, matching spell_cost.gd's MAG_EXP/SPAM_PENALTY
## discipline -- first-pass placeholders (no real playtesting data yet, same
## situation as every other Easter-egg rarity constant in this project), but
## pinned, not guessed.
##
## Also pins the deterministic AI: ai_should_flap never touches randf() --
## this project has no random rolls anywhere except the deliberate d20 egg
## (SecretD20), and the AI opponent here is the one place a "second RNG"
## would have been the obvious wrong shortcut.

const JoustMatch = preload("res://src/gameplay/joust_match.gd")

var match_rules: JoustMatch


func before_each():
	match_rules = JoustMatch.new()


## --- rider_step: single-rider height physics ---


func test_rider_step_without_flap_loses_exactly_gravity_times_delta():
	var result := match_rules.rider_step(50.0, false, 1.0)
	assert_almost_eq(result, 50.0 - JoustMatch.GRAVITY, 0.001)


func test_rider_step_with_flap_gains_flap_boost_minus_gravity():
	var result := match_rules.rider_step(50.0, true, 1.0)
	assert_almost_eq(result, 50.0 - JoustMatch.GRAVITY + JoustMatch.FLAP_BOOST, 0.001)


func test_rider_step_clamps_to_max_height():
	# A tiny delta keeps gravity's own pull negligible so the flat FLAP_BOOST
	# alone pushes the raw (pre-clamp) result past MAX_HEIGHT.
	var result := match_rules.rider_step(JoustMatch.MAX_HEIGHT - 1.0, true, 0.01)
	assert_eq(result, JoustMatch.MAX_HEIGHT)


func test_rider_step_clamps_to_min_height():
	var result := match_rules.rider_step(1.0, false, 1.0)
	assert_eq(result, JoustMatch.MIN_HEIGHT)


func test_rider_step_scales_with_delta():
	var half_second := match_rules.rider_step(50.0, false, 0.5)
	assert_almost_eq(half_second, 50.0 - JoustMatch.GRAVITY * 0.5, 0.001)


## --- pass_result: who wins a single collision ---


func test_pass_result_higher_rider_is_player():
	assert_eq(match_rules.pass_result(80.0, 20.0), "player")


func test_pass_result_higher_rider_is_ai():
	assert_eq(match_rules.pass_result(20.0, 80.0), "ai")


func test_pass_result_within_tie_margin_is_a_tie():
	assert_eq(match_rules.pass_result(50.0, 50.0 + JoustMatch.TIE_MARGIN), "tie")


func test_pass_result_just_outside_tie_margin_has_a_winner():
	var result := match_rules.pass_result(50.0, 50.0 + JoustMatch.TIE_MARGIN + 0.5)
	assert_eq(result, "ai")


## --- ai_should_flap: deterministic (no randf()) skill-based opponent ---


func test_ai_flaps_when_at_or_below_player_height_plus_margin():
	assert_true(match_rules.ai_should_flap(40.0, 40.0))
	assert_true(match_rules.ai_should_flap(40.0, 40.0 - JoustMatch.AI_HEIGHT_MARGIN))


func test_ai_does_not_flap_once_clearly_above_player_plus_margin():
	assert_false(match_rules.ai_should_flap(40.0, 40.0 - JoustMatch.AI_HEIGHT_MARGIN - 1.0))


## --- initial_state ---


func test_initial_state_starts_scoreless_and_not_over():
	var state := match_rules.initial_state()
	assert_eq(state["player_wins"], 0)
	assert_eq(state["ai_wins"], 0)
	assert_eq(state["over"], false)
	assert_eq(state["winner"], "")
	assert_eq(state["gap"], JoustMatch.PASS_GAP)


func test_initial_state_starts_both_riders_at_the_same_height():
	var state := match_rules.initial_state()
	assert_eq(state["player_height"], state["ai_height"])


## --- advance: full state-in/state-out integration ---


func test_advance_closes_the_gap_before_a_pass_resolves():
	var state := match_rules.initial_state()
	var next := match_rules.advance(state, 0.1, false)
	assert_almost_eq(next["gap"], JoustMatch.PASS_GAP - JoustMatch.APPROACH_SPEED * 0.1, 0.001)
	assert_eq(next["last_result"], "")


func test_advance_awards_player_a_round_when_gap_closes_with_player_higher():
	var state := match_rules.initial_state()
	state["player_height"] = 90.0
	state["ai_height"] = 10.0
	state["gap"] = 1.0
	var next := match_rules.advance(state, 0.1, false)
	assert_eq(next["last_result"], "player")
	assert_eq(next["player_wins"], 1)
	assert_eq(next["ai_wins"], 0)


func test_advance_awards_ai_a_round_when_gap_closes_with_ai_higher():
	var state := match_rules.initial_state()
	state["player_height"] = 10.0
	state["ai_height"] = 90.0
	state["gap"] = 1.0
	var next := match_rules.advance(state, 0.1, false)
	assert_eq(next["last_result"], "ai")
	assert_eq(next["ai_wins"], 1)
	assert_eq(next["player_wins"], 0)


func test_advance_resets_the_gap_for_the_next_pass_after_resolving():
	var state := match_rules.initial_state()
	state["player_height"] = 90.0
	state["ai_height"] = 10.0
	state["gap"] = 1.0
	var next := match_rules.advance(state, 0.1, false)
	assert_eq(next["gap"], JoustMatch.PASS_GAP)


func test_advance_tie_awards_nobody_a_round_and_still_resets_the_gap():
	# Starting both riders at the same height AND flapping the player means
	# the AI's own reactive rule (ai_should_flap) also fires -- both apply
	# the exact same rider_step from the exact same starting height, landing
	# them exactly together.
	var state := match_rules.initial_state()
	state["player_height"] = 50.0
	state["ai_height"] = 50.0
	state["gap"] = 1.0
	var next := match_rules.advance(state, 0.1, true)
	assert_eq(next["last_result"], "tie")
	assert_eq(next["player_wins"], 0)
	assert_eq(next["ai_wins"], 0)
	assert_eq(next["gap"], JoustMatch.PASS_GAP)


func test_advance_ends_the_match_once_player_reaches_rounds_to_win():
	var state := match_rules.initial_state()
	state["player_wins"] = JoustMatch.ROUNDS_TO_WIN - 1
	state["player_height"] = 90.0
	state["ai_height"] = 10.0
	state["gap"] = 1.0
	var next := match_rules.advance(state, 0.1, false)
	assert_eq(next["player_wins"], JoustMatch.ROUNDS_TO_WIN)
	assert_true(next["over"])
	assert_eq(next["winner"], "player")


func test_advance_ends_the_match_once_ai_reaches_rounds_to_win():
	var state := match_rules.initial_state()
	state["ai_wins"] = JoustMatch.ROUNDS_TO_WIN - 1
	state["player_height"] = 10.0
	state["ai_height"] = 90.0
	state["gap"] = 1.0
	var next := match_rules.advance(state, 0.1, false)
	assert_eq(next["ai_wins"], JoustMatch.ROUNDS_TO_WIN)
	assert_true(next["over"])
	assert_eq(next["winner"], "ai")


func test_advance_a_two_one_match_needs_a_third_pass_not_two():
	var state := match_rules.initial_state()
	state["player_wins"] = 1
	state["ai_wins"] = 1
	state["player_height"] = 90.0
	state["ai_height"] = 10.0
	state["gap"] = 1.0
	var next := match_rules.advance(state, 0.1, false)
	assert_true(next["over"])
	assert_eq(next["player_wins"], 2)
	assert_eq(next["ai_wins"], 1)


func test_advance_on_an_already_finished_match_is_inert():
	var state := match_rules.initial_state()
	state["over"] = true
	state["winner"] = "player"
	state["gap"] = 1.0
	var next := match_rules.advance(state, 1.0, true)
	assert_eq(next, state)


func test_advance_does_not_mutate_the_callers_original_state():
	var state := match_rules.initial_state()
	var original_gap: float = state["gap"]
	match_rules.advance(state, 0.1, false)
	assert_eq(state["gap"], original_gap)


func test_ai_flap_decision_uses_the_players_height_from_before_this_ticks_move():
	# The AI reacts to the player's height as of the START of this tick, not
	# the height the player's own simultaneous flap moves them to -- a
	# deliberate one-tick lag (see JoustMatch.advance's own doc comment) so
	# the AI can't literally read the player's simultaneous input. Proven
	# directly here: the player's height going INTO this tick is far enough
	# below ai_height - AI_HEIGHT_MARGIN that the AI correctly free-falls
	# (does not flap) even though the player's own flap this same tick
	# closes some of that gap.
	var state := match_rules.initial_state()
	state["player_height"] = 40.0
	state["ai_height"] = 40.0 + JoustMatch.AI_HEIGHT_MARGIN + 1.0
	state["gap"] = 100.0
	var next := match_rules.advance(state, 0.1, true)
	var expected_ai_height := match_rules.rider_step(state["ai_height"], false, 0.1)
	assert_almost_eq(next["ai_height"], expected_ai_height, 0.001)
