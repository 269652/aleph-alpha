extends GutTest

## HandheldBattle (docs/concept/easter_eggs.md's "hidden retro handheld"
## entry): the pure, deterministic turn-based battle rules core for the
## mini-game the handheld prop boots into. State-in/state-out, exactly like
## Duel.advance/JoustMatch.advance -- the caller (HandheldBattleView) owns
## and persists the state Dictionary across rounds, this module keeps no
## instance state of its own.
##
## No randf() anywhere, on purpose: "deterministic damage/outcome
## resolution -- no RNG, consistent with this project's whole combat/
## crafting philosophy of derived-not-rolled outcomes" per this stage's own
## task. Every tuned constant (CHARGE_POWER/REND_POWER/REND_DEFENSE_PENALTY/
## GUARD_DAMAGE_REDUCTION/FOCUS_ATTACK_BONUS/MIN_DAMAGE) is a first-pass
## placeholder (no real playtesting data yet, the same situation JoustMatch's
## own doc comment documents) but pinned by direct exact-value assertions
## below, matching spell_cost.gd's MAG_EXP/SPAM_PENALTY discipline rather
## than an eyeballed comment.
##
## Four original moves -- charge (a plain attack), rend (a harder-hitting
## attack that persistently weakens the user's own defense), guard (halves
## damage taken this round), focus (persistently raises the user's own
## attack) -- plus "pass", a pure no-op HandheldBattleView uses to spend a
## turn on something outside battle rules entirely (a catch attempt, see
## HandheldCatch) without this module ever needing to know catching exists.

const HandheldBattle = preload("res://src/gameplay/handheld_battle.gd")

var battle: HandheldBattle
var player_stats: Dictionary
var enemy_stats: Dictionary


func before_each():
	battle = HandheldBattle.new()
	player_stats = {"hp": 30.0, "attack": 10.0, "defense": 6.0, "speed": 10.0}
	enemy_stats = {"hp": 30.0, "attack": 10.0, "defense": 6.0, "speed": 10.0}


## --- initial_state ---


func test_initial_state_starts_both_units_at_full_hp():
	var state := battle.initial_state(player_stats, enemy_stats)
	assert_eq(state["player"]["hp"], 30.0)
	assert_eq(state["player"]["max_hp"], 30.0)
	assert_eq(state["enemy"]["hp"], 30.0)
	assert_eq(state["enemy"]["max_hp"], 30.0)


func test_initial_state_copies_the_given_stat_blocks():
	var state := battle.initial_state(player_stats, enemy_stats)
	assert_eq(state["player"]["attack"], 10.0)
	assert_eq(state["player"]["defense"], 6.0)
	assert_eq(state["player"]["speed"], 10.0)


func test_initial_state_starts_not_over_with_no_winner():
	var state := battle.initial_state(player_stats, enemy_stats)
	assert_false(state["over"])
	assert_eq(state["winner"], "")


## --- _damage (private helper, exercised indirectly via resolve_round) ---


func test_charge_damage_is_power_plus_attack_minus_defense():
	var state := battle.initial_state(player_stats, enemy_stats)
	var next := battle.resolve_round(state, HandheldBattle.MOVE_CHARGE, HandheldBattle.MOVE_PASS)
	var expected := HandheldBattle.CHARGE_POWER + 10.0 - 6.0
	assert_almost_eq(next["last_player_damage"], expected, 0.001)
	assert_almost_eq(float(next["enemy"]["hp"]), 30.0 - expected, 0.001)


func test_rend_deals_more_damage_than_charge_the_first_time_its_used():
	var charge_state := battle.resolve_round(
		battle.initial_state(player_stats, enemy_stats), HandheldBattle.MOVE_CHARGE, HandheldBattle.MOVE_PASS
	)
	var rend_state := battle.resolve_round(
		battle.initial_state(player_stats, enemy_stats), HandheldBattle.MOVE_REND, HandheldBattle.MOVE_PASS
	)
	assert_true(float(rend_state["last_player_damage"]) > float(charge_state["last_player_damage"]))


func test_damage_never_drops_below_min_damage_against_overwhelming_defense():
	var tanky_enemy := enemy_stats.duplicate()
	tanky_enemy["defense"] = 999.0
	var state := battle.initial_state(player_stats, tanky_enemy)
	var next := battle.resolve_round(state, HandheldBattle.MOVE_CHARGE, HandheldBattle.MOVE_PASS)
	assert_eq(next["last_player_damage"], HandheldBattle.MIN_DAMAGE)


func test_guard_halves_damage_received_the_same_round():
	var unguarded := battle.resolve_round(
		battle.initial_state(player_stats, enemy_stats), HandheldBattle.MOVE_CHARGE, HandheldBattle.MOVE_PASS
	)
	var guarded := battle.resolve_round(
		battle.initial_state(player_stats, enemy_stats), HandheldBattle.MOVE_CHARGE, HandheldBattle.MOVE_GUARD
	)
	assert_almost_eq(
		float(guarded["last_player_damage"]),
		float(unguarded["last_player_damage"]) * (1.0 - HandheldBattle.GUARD_DAMAGE_REDUCTION),
		0.001
	)


func test_focus_persistently_raises_the_users_own_attack():
	var state := battle.initial_state(player_stats, enemy_stats)
	var next := battle.resolve_round(state, HandheldBattle.MOVE_FOCUS, HandheldBattle.MOVE_PASS)
	assert_almost_eq(float(next["player"]["attack"]), 10.0 + HandheldBattle.FOCUS_ATTACK_BONUS, 0.001)
	# A later charge should now hit harder than it would have pre-focus.
	var after_charge := battle.resolve_round(next, HandheldBattle.MOVE_CHARGE, HandheldBattle.MOVE_PASS)
	var expected := HandheldBattle.CHARGE_POWER + (10.0 + HandheldBattle.FOCUS_ATTACK_BONUS) - 6.0
	assert_almost_eq(float(after_charge["last_player_damage"]), expected, 0.001)


func test_rend_persistently_lowers_the_users_own_defense():
	var state := battle.initial_state(player_stats, enemy_stats)
	var next := battle.resolve_round(state, HandheldBattle.MOVE_REND, HandheldBattle.MOVE_PASS)
	assert_almost_eq(
		float(next["player"]["defense"]), 6.0 - HandheldBattle.REND_DEFENSE_PENALTY, 0.001
	)


func test_rend_defense_penalty_never_drops_defense_below_the_floor():
	var frail := player_stats.duplicate()
	frail["defense"] = HandheldBattle.MIN_STAT + 0.5
	var state := battle.initial_state(frail, enemy_stats)
	var next := battle.resolve_round(state, HandheldBattle.MOVE_REND, HandheldBattle.MOVE_PASS)
	assert_true(float(next["player"]["defense"]) >= HandheldBattle.MIN_STAT)


func test_pass_deals_no_damage_and_changes_no_stats():
	var state := battle.initial_state(player_stats, enemy_stats)
	var next := battle.resolve_round(state, HandheldBattle.MOVE_PASS, HandheldBattle.MOVE_PASS)
	assert_eq(next["last_player_damage"], 0.0)
	assert_eq(next["last_enemy_damage"], 0.0)
	assert_eq(next["player"]["hp"], 30.0)
	assert_eq(next["enemy"]["hp"], 30.0)


## --- turn order ---


func test_the_faster_unit_acts_first_and_can_defeat_the_slower_before_it_acts():
	var fast_player := player_stats.duplicate()
	fast_player["speed"] = 20.0
	fast_player["attack"] = 999.0
	var frail_enemy := enemy_stats.duplicate()
	frail_enemy["speed"] = 1.0
	frail_enemy["hp"] = 5.0
	var state := battle.initial_state(fast_player, frail_enemy)
	var next := battle.resolve_round(state, HandheldBattle.MOVE_CHARGE, HandheldBattle.MOVE_CHARGE)
	# The enemy was defeated by the player's first-acting hit before its own
	# attack could land -- the player takes no damage this round.
	assert_eq(next["enemy"]["hp"], 0.0)
	assert_eq(next["last_enemy_damage"], 0.0)


func test_ties_in_speed_favor_the_player_acting_first():
	var glass_cannon_enemy := enemy_stats.duplicate()
	glass_cannon_enemy["hp"] = 1.0
	var strong_player := player_stats.duplicate()
	strong_player["attack"] = 999.0
	var state := battle.initial_state(strong_player, glass_cannon_enemy)
	var next := battle.resolve_round(state, HandheldBattle.MOVE_CHARGE, HandheldBattle.MOVE_CHARGE)
	assert_eq(next["enemy"]["hp"], 0.0)
	assert_eq(next["last_enemy_damage"], 0.0)


## --- win conditions ---


func test_enemy_reaching_zero_hp_ends_the_battle_with_player_as_winner():
	var strong_player := player_stats.duplicate()
	strong_player["attack"] = 999.0
	var state := battle.initial_state(strong_player, enemy_stats)
	var next := battle.resolve_round(state, HandheldBattle.MOVE_CHARGE, HandheldBattle.MOVE_PASS)
	assert_true(next["over"])
	assert_eq(next["winner"], "player")


func test_player_reaching_zero_hp_ends_the_battle_with_enemy_as_winner():
	var strong_enemy := enemy_stats.duplicate()
	strong_enemy["attack"] = 999.0
	var state := battle.initial_state(player_stats, strong_enemy)
	var next := battle.resolve_round(state, HandheldBattle.MOVE_PASS, HandheldBattle.MOVE_CHARGE)
	assert_true(next["over"])
	assert_eq(next["winner"], "enemy")


func test_hp_never_drops_below_zero():
	var strong_player := player_stats.duplicate()
	strong_player["attack"] = 9999.0
	var state := battle.initial_state(strong_player, enemy_stats)
	var next := battle.resolve_round(state, HandheldBattle.MOVE_CHARGE, HandheldBattle.MOVE_PASS)
	assert_eq(next["enemy"]["hp"], 0.0)


func test_resolve_round_on_an_already_finished_battle_is_inert():
	var state := battle.initial_state(player_stats, enemy_stats)
	state["over"] = true
	state["winner"] = "player"
	var next := battle.resolve_round(state, HandheldBattle.MOVE_CHARGE, HandheldBattle.MOVE_CHARGE)
	assert_eq(next, state)


func test_resolve_round_does_not_mutate_the_callers_original_state():
	var state := battle.initial_state(player_stats, enemy_stats)
	var original_hp: float = state["enemy"]["hp"]
	battle.resolve_round(state, HandheldBattle.MOVE_CHARGE, HandheldBattle.MOVE_PASS)
	assert_eq(state["enemy"]["hp"], original_hp)


## --- PLAYER_MOVES: the real battle-menu contract HandheldBattleView reads ---


func test_player_moves_is_exactly_the_four_named_moves():
	var expected: Array[String] = [
		HandheldBattle.MOVE_CHARGE, HandheldBattle.MOVE_REND, HandheldBattle.MOVE_GUARD, HandheldBattle.MOVE_FOCUS
	]
	assert_eq(HandheldBattle.PLAYER_MOVES, expected)


func test_player_moves_excludes_the_internal_pass_escape_hatch():
	assert_false(HandheldBattle.PLAYER_MOVES.has(HandheldBattle.MOVE_PASS))


## --- ai_choose_move: deterministic (no randf()) skill-based opponent ---


func test_ai_guards_at_or_below_the_low_health_threshold():
	assert_eq(
		battle.ai_choose_move(HandheldBattle.AI_GUARD_HEALTH_FRACTION),
		HandheldBattle.MOVE_GUARD
	)
	assert_eq(battle.ai_choose_move(0.01), HandheldBattle.MOVE_GUARD)


func test_ai_charges_above_the_low_health_threshold():
	assert_eq(
		battle.ai_choose_move(HandheldBattle.AI_GUARD_HEALTH_FRACTION + 0.01),
		HandheldBattle.MOVE_CHARGE
	)
	assert_eq(battle.ai_choose_move(1.0), HandheldBattle.MOVE_CHARGE)
