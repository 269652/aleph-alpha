extends RefCounted

## Pure rules core for docs/concept/easter_eggs.md's "hidden sea cave...
## dueling-birds cabinet" entry: an aerial joust mini-game built from
## scratch for this engine, homaging a real 1982 two-player arcade game's
## "elegant two-line premise" (the doc's own words) without reproducing its
## code, assets, or name. Two mounted riders close a gap on a scrolling
## arena; whichever is higher when the gap closes unseats the other and
## wins that pass; first to ROUNDS_TO_WIN passes wins the match
## (best-of-three). SeaCaveGuardian gates WHERE/WHEN a match can start;
## this module only knows the match's own rules, and never touches Input,
## GeoCoordinates, or anything Godot-node-shaped -- the same
## pure-module-plus-node-adapter split every other system in this project
## uses (see JoustMatchView for the node/rendering half).
##
## Shape: pure state-in/state-out, exactly like Duel.advance -- the caller
## (JoustMatchView) owns and persists the state Dictionary across frames;
## this module keeps no instance state of its own, so it's trivially
## testable one tick at a time.
##
## Deterministic AI opponent, on purpose: this project has no random rolls
## anywhere except the one deliberately isolated d20 Easter egg
## (SecretD20) -- ai_should_flap below is a skill-based rule (stay at or
## above the player's own height), never randf(), consistent with every
## other combat/crafting system in this project (materials.md, magic.md).
## It reacts to the player's height as of the START of the tick (state's
## own player_height, before this tick's move is applied) rather than
## where the player's simultaneous flap moves them to -- a deliberate
## one-tick lag, the same "the AI can't literally read simultaneous input"
## fairness every real two-player game needs, and what keeps a well-timed
## player's own flap meaningful instead of the AI trivially mirroring it.
##
## Every constant below is a first-pass placeholder -- no real playtesting
## data exists yet for this project's Easter eggs (the same situation
## EasterEggSightings.SIGHTINGS/BridgekeeperEncounter.CHANCE_PER_CHECK's
## own comments already note) -- but each is pinned by a direct, exact-value
## assertion in test_joust_match.gd rather than left as an eyeballed
## comment, matching spell_cost.gd's MAG_EXP/SPAM_PENALTY discipline.

## Height lost per second while airborne and not flapping.
const GRAVITY := 18.0
## Height gained the instant a flap is pressed this tick (a flat kick, not
## a rate -- flapping harder doesn't matter, only WHEN you flap does).
const FLAP_BOOST := 6.0
const MIN_HEIGHT := 0.0
const MAX_HEIGHT := 100.0

## Gap distance closed per second -- the arena's own "scroll speed".
const APPROACH_SPEED := 70.0
## Starting distance between riders, and the distance restored after each
## pass resolves so the next pass has the same real closing time.
const PASS_GAP := 260.0

## Height difference at or under which a resolving pass is a tie (bounce,
## nobody unseated, the pass simply continues) rather than a win for
## whichever rider is even fractionally higher.
const TIE_MARGIN := 3.0
## The AI flaps whenever its own height is at or below the player's own
## height (as of the start of this tick) plus this margin -- a real,
## actively-contesting opponent, not a pushover, without ever rolling dice.
const AI_HEIGHT_MARGIN := 5.0

## Best-of-three: first to this many round wins takes the match.
const ROUNDS_TO_WIN := 2


## One rider's next height: gravity always applies; a flap adds a flat
## boost on top instead of overriding it, so a flap during a fall softens
## rather than fully reverses a steep drop. Clamped to the arena's own
## floor/ceiling.
func rider_step(height: float, flap: bool, delta: float) -> float:
	var next := height - GRAVITY * delta
	if flap:
		next += FLAP_BOOST
	return clampf(next, MIN_HEIGHT, MAX_HEIGHT)


## Who wins a pass at these two heights: "tie" within TIE_MARGIN (nobody's
## knocked off), otherwise whichever rider is higher.
func pass_result(player_height: float, ai_height: float) -> String:
	if absf(player_height - ai_height) <= TIE_MARGIN:
		return "tie"
	return "player" if player_height > ai_height else "ai"


## Deterministic AI flap decision -- see this module's own doc comment for
## why this is a skill rule, never a random roll.
func ai_should_flap(ai_height: float, player_height: float) -> bool:
	return ai_height <= player_height + AI_HEIGHT_MARGIN


## A fresh match: round 0-0, both riders centered, a full pass gap ahead.
func initial_state() -> Dictionary:
	var mid_height := (MIN_HEIGHT + MAX_HEIGHT) / 2.0
	return {
		"player_height": mid_height,
		"ai_height": mid_height,
		"gap": PASS_GAP,
		"player_wins": 0,
		"ai_wins": 0,
		"last_result": "",
		"over": false,
		"winner": "",
	}


## Advances `state` by one physics tick. `player_flap` is the caller's own
## just-pressed edge for this frame (a real input event in play, a plain
## bool in tests) -- this module never reads Input itself, the same
## "caller supplies the real primitive" shape every sibling module in this
## Easter-egg family uses (see SignedSecretRoom's own doc comment). A
## finished match (state["over"]) is inert -- advance keeps returning the
## same state unchanged, so a caller can keep calling this every frame
## without checking is_over first. Never mutates the caller's own state
## Dictionary -- always returns a fresh one.
func advance(state: Dictionary, delta: float, player_flap: bool) -> Dictionary:
	if bool(state["over"]):
		return state
	var next := state.duplicate()
	var pre_step_player_height: float = state["player_height"]
	next["player_height"] = rider_step(state["player_height"], player_flap, delta)
	var ai_flap := ai_should_flap(state["ai_height"], pre_step_player_height)
	next["ai_height"] = rider_step(state["ai_height"], ai_flap, delta)
	next["gap"] = float(state["gap"]) - APPROACH_SPEED * delta
	next["last_result"] = ""
	if float(next["gap"]) <= 0.0:
		var result := pass_result(next["player_height"], next["ai_height"])
		next["last_result"] = result
		if result == "player":
			next["player_wins"] = int(state["player_wins"]) + 1
		elif result == "ai":
			next["ai_wins"] = int(state["ai_wins"]) + 1
		next["gap"] = PASS_GAP
	if int(next["player_wins"]) >= ROUNDS_TO_WIN:
		next["over"] = true
		next["winner"] = "player"
	elif int(next["ai_wins"]) >= ROUNDS_TO_WIN:
		next["over"] = true
		next["winner"] = "ai"
	return next
