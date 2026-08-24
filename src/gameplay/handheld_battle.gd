extends RefCounted

## Pure rules core for docs/concept/easter_eggs.md's "hidden retro handheld"
## entry: a tiny, original, turn-based 1v1 battle between a player-controlled
## unit and an AI-controlled wild unit, built from HandheldRoster stat
## blocks. Exactly Duel.advance/JoustMatch.advance's own pure state-in/
## state-out shape -- the caller (HandheldBattleView) owns and persists the
## state Dictionary across rounds; this module keeps no instance state of
## its own, so it's trivially testable one round at a time.
##
## No randf() anywhere: "deterministic damage/outcome resolution -- no RNG,
## consistent with this project's whole combat/crafting philosophy of
## derived-not-rolled outcomes" per this stage's own task, the same
## discipline JoustMatch.ai_should_flap already established for this doc's
## family of Easter eggs. ai_choose_move below is a skill-based rule (guard
## when low on health, otherwise press the attack), never a dice roll.
##
## Catching is deliberately NOT this module's concern at all -- see
## HandheldCatch, a fully separate pure module. HandheldBattleView lets the
## player spend a turn on a catch attempt by passing MOVE_PASS in here (a
## true no-op) rather than teaching this battle core anything about
## catching; the same "caller supplies the real primitive, module only
## decides its own narrow slice" shape SeaCaveGuardian/JoustMatch already
## split between location-gating and match rules.
##
## Every constant below is a first-pass placeholder -- no real playtesting
## data exists yet for this project's Easter eggs (the same situation
## JoustMatch's own doc comment documents) -- but each is pinned by a direct
## exact-value assertion in test_handheld_battle.gd rather than left as an
## eyeballed comment, matching spell_cost.gd's MAG_EXP/SPAM_PENALTY
## discipline.

const MOVE_CHARGE := "charge"
const MOVE_REND := "rend"
const MOVE_GUARD := "guard"
const MOVE_FOCUS := "focus"
## A true no-op -- HandheldBattleView's own escape hatch for "the player is
## doing something this round that isn't a battle move" (a catch attempt).
## Never selected by ai_choose_move; only ever supplied by a caller.
const MOVE_PASS := "pass"

## Every move a real battle menu offers the player (not MOVE_PASS, which is
## an internal escape hatch, not a menu option).
const PLAYER_MOVES: Array[String] = [MOVE_CHARGE, MOVE_REND, MOVE_GUARD, MOVE_FOCUS]

const CHARGE_POWER := 10.0
## Rend hits harder than Charge but persistently weakens its own user's
## defense (see REND_DEFENSE_PENALTY) -- a real risk/reward choice, not a
## strictly-better option, the same "no strictly dominant move" shape a
## turn-based battle needs to stay interesting.
const REND_POWER := 18.0
const REND_DEFENSE_PENALTY := 2.0
## No stat may be pushed below this floor by a persistent penalty (Rend) --
## a defense of zero or negative would make every future hit received scale
## with raw attack alone, an unbounded spiral this mini-game doesn't want.
const MIN_STAT := 1.0

## Fraction of incoming damage removed by guarding this exact round.
const GUARD_DAMAGE_REDUCTION := 0.5
## Persistent (rest-of-battle) attack bonus from using Focus once.
const FOCUS_ATTACK_BONUS := 4.0
## A hit always deals at least this much -- a defense stat can reduce a hit,
## but never fully no-sell it.
const MIN_DAMAGE := 1.0

## ai_choose_move guards once its own remaining-health fraction is at or
## below this threshold, otherwise presses the attack -- a real, reactive
## opponent without ever rolling dice, the same shape JoustMatch.
## ai_should_flap already established for this doc's family of Easter eggs.
const AI_GUARD_HEALTH_FRACTION := 0.3


## A fresh 1v1 battle: both units start at full hp, copying `player_stats`/
## `enemy_stats` (see HandheldRoster.stats_for) rather than referencing them,
## so nothing outside this state can mutate a battle already in progress.
func initial_state(player_stats: Dictionary, enemy_stats: Dictionary) -> Dictionary:
	return {
		"player": _unit_state(player_stats),
		"enemy": _unit_state(enemy_stats),
		"over": false,
		"winner": "",
		"last_player_move": "",
		"last_enemy_move": "",
		"last_player_damage": 0.0,
		"last_enemy_damage": 0.0,
	}


func _unit_state(stats: Dictionary) -> Dictionary:
	return {
		"hp": float(stats["hp"]),
		"max_hp": float(stats["hp"]),
		"attack": float(stats["attack"]),
		"defense": float(stats["defense"]),
		"speed": float(stats["speed"]),
	}


## Advances `state` by one full round: both sides declare a move
## simultaneously (no ordering trick lets one side see the other's choice
## first), guard/focus/rend's own persistent effects are applied before any
## damage is computed (so a guard taken this round protects against an
## attack landing this SAME round, and a rend/focus taken this round already
## reflects in this round's own attack roll), then attacks resolve in speed
## order -- the faster unit's attack lands first and, if it defeats its
## target, the slower unit's own attack this round never happens. A finished
## battle (state["over"]) is inert -- resolve_round keeps returning the same
## state unchanged, so a caller can keep calling this every input without
## checking is_over first (mirrors JoustMatch.advance's identical contract).
## Never mutates the caller's own state Dictionary -- always returns a fresh
## one (mirrors JoustMatch.advance's identical contract).
func resolve_round(state: Dictionary, player_move: String, enemy_move: String) -> Dictionary:
	if bool(state["over"]):
		return state
	var next: Dictionary = state.duplicate(true)

	var player_guarding := player_move == MOVE_GUARD
	var enemy_guarding := enemy_move == MOVE_GUARD

	if player_move == MOVE_FOCUS:
		next["player"]["attack"] = float(next["player"]["attack"]) + FOCUS_ATTACK_BONUS
	if enemy_move == MOVE_FOCUS:
		next["enemy"]["attack"] = float(next["enemy"]["attack"]) + FOCUS_ATTACK_BONUS
	if player_move == MOVE_REND:
		next["player"]["defense"] = maxf(MIN_STAT, float(next["player"]["defense"]) - REND_DEFENSE_PENALTY)
	if enemy_move == MOVE_REND:
		next["enemy"]["defense"] = maxf(MIN_STAT, float(next["enemy"]["defense"]) - REND_DEFENSE_PENALTY)

	next["last_player_move"] = player_move
	next["last_enemy_move"] = enemy_move
	next["last_player_damage"] = 0.0
	next["last_enemy_damage"] = 0.0

	# Ties favor the player -- a deliberate, deterministic tie-break (never
	# an arbitrary dictionary-iteration-order accident), the friendlier
	# default for a mini-game a player is meant to enjoy winning close calls
	# in, not a claim about real animal speed.
	var player_first: bool = float(state["player"]["speed"]) >= float(state["enemy"]["speed"])
	var order := ["player", "enemy"] if player_first else ["enemy", "player"]
	var moves := {"player": player_move, "enemy": enemy_move}
	var guarding := {"player": player_guarding, "enemy": enemy_guarding}

	for actor_id in order:
		if float(next[actor_id]["hp"]) <= 0.0:
			continue  # a unit defeated earlier this round never gets to act
		var move: String = moves[actor_id]
		if move != MOVE_CHARGE and move != MOVE_REND:
			continue
		var target_id: String = "enemy" if actor_id == "player" else "player"
		if float(next[target_id]["hp"]) <= 0.0:
			continue  # target already down this round -- nothing left to hit
		var power: float = CHARGE_POWER if move == MOVE_CHARGE else REND_POWER
		var damage := _damage(
			power, float(next[actor_id]["attack"]), float(next[target_id]["defense"]), guarding[target_id]
		)
		next[target_id]["hp"] = maxf(0.0, float(next[target_id]["hp"]) - damage)
		next["last_%s_damage" % actor_id] = damage

	var player_down: bool = float(next["player"]["hp"]) <= 0.0
	var enemy_down: bool = float(next["enemy"]["hp"]) <= 0.0
	if player_down and enemy_down:
		next["over"] = true
		# Whoever acted first this round dealt the round's decisive blow.
		next["winner"] = "player" if player_first else "enemy"
	elif enemy_down:
		next["over"] = true
		next["winner"] = "player"
	elif player_down:
		next["over"] = true
		next["winner"] = "enemy"

	return next


func _damage(power: float, attack: float, defense: float, target_guarding: bool) -> float:
	var raw := power + attack - defense
	if target_guarding:
		raw *= 1.0 - GUARD_DAMAGE_REDUCTION
	return maxf(MIN_DAMAGE, roundf(raw))


## Deterministic AI opponent -- guards while badly hurt, otherwise presses
## the attack. `own_hp_fraction` is a plain caller-supplied float (the
## caller already has the state Dictionary this comes from), the same
## "caller supplies the real primitive" shape JoustMatch.ai_should_flap uses.
func ai_choose_move(own_hp_fraction: float) -> String:
	if own_hp_fraction <= AI_GUARD_HEALTH_FRACTION:
		return MOVE_GUARD
	return MOVE_CHARGE
