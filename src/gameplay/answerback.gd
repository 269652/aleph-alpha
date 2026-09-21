extends RefCounted

## The single statement of what every world-changing action in this game
## answers with (docs/concept/feedback.md). A sound, a flash, a number that
## floats, a line of text, and the minimum interval between two answers.
##
## Measured on 2026-09-20, before this module existed:
## `src/audio/interaction_sfx_player.gd` had exactly THREE `play_` methods
## in the whole game (footstep, mushroom crush, creature call); a grep for a
## hit flash, a damage number, a floating text node or a level-up toast
## anywhere under scenes/ or src/ found none of the four; and
## `Player.gain_experience` returned the levels gained while all three of
## its callers (scenes/player.gd:2929, :3744, :4943) threw the value away.
## Of the 36 actions in `Keybindings.ACTIONS`, exactly four -- the movement
## quartet -- made any sound at all. Thirty-two bound verbs answered with
## nothing, which is most of why a first-time player reports that nothing
## is happening.
##
## The table below is not the fix on its own; `test_answerback.gd`'s
## two-way drift test is. It partitions the REAL action list into the verbs
## that change the world and the ones that only open a window, and checks
## both directions -- so a new verb with no feedback cannot ship, and a row
## for a verb that no longer exists cannot linger. Silence stops being an
## oversight and becomes a red test.
##
## Pure: a RefCounted of static functions. No node, no world, no clock, no
## singleton -- `should_play` takes both timestamps as arguments precisely
## so the rate limit is a tested property rather than something you have to
## play the game to check. The wiring (the flash, the floating label, the
## toast, the clips) is the caller's; this module only ever says WHAT.

const FootstepGait = preload("res://src/gameplay/footstep_gait.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")


# -- the intervals ------------------------------------------------------
#
# Three, and every one of them is read off something real. There is no
# global magic cooldown here, because a single number would either
# machine-gun the deliberate verbs or silence the fast ones.

## The player's own walking speed in pixels per second, restated rather
## than preloading `scenes/player.gd` -- a pure rule module must not drag a
## Node2D scene script into every test that touches a number, the same
## reasoning `SprintCost.sprint_speed_px_per_second` already gives. Held to
## `Player.BASE_SPEED` by test.
const WALK_SPEED_PX_PER_SECOND := 40.0

## The fastest anything may answer: one real footfall.
## `FootstepGait.STRIDE_LENGTH_METERS` is 0.75 m, the measured heel-to-heel
## stride of an average adult at a walk, and at this world's scale that is
## 8.415 px -- so at walking speed the player plants a foot every ~0.210 s.
## That is the rate this game ALREADY answers a verb at (the one verb it
## answers at all), so it is the floor: below a fifth of a second a
## repeated sound stops being a rhythm and becomes a buzz.
const REFLEX_INTERVAL_SECONDS := FootstepGait.STRIDE_LENGTH_PX / WALK_SPEED_PX_PER_SECOND

## `Player.ATTACK_COOLDOWN`, restated for the same reason
## WALK_SPEED_PX_PER_SECOND is and held to it by test.
const ATTACK_COOLDOWN_SECONDS := 0.5

## A gated verb answers at its own gate. An interval equal to the rate
## limit the verb already has is exactly transparent: it can never suppress
## an action the game itself allowed, which is the failure mode of every
## invented cooldown.
const SWING_INTERVAL_SECONDS := ATTACK_COOLDOWN_SECONDS

## Brysbaert's 2019 meta-analysis (190 studies) puts silent reading of
## English non-fiction at about 238 words per minute.
const WORDS_PER_MINUTE_SILENT_READING := 238.0

## What a feedback line actually is: "Crafted Stone Axe", "+3 Stick",
## "Nothing in reach". Four words, counting the number as one.
const WORDS_IN_A_FEEDBACK_LINE := 4

## A deliberate act answers with a SENTENCE, and a sentence has to be read.
## ~1.01 s at the rate above. Two lines inside one read is not two answers,
## it is one answer lost -- so this is the one place the interval
## deliberately eats a real action's answer, because an unread line is
## worse than a line not shown. Comfortably under the 6.0 s the HUD already
## gives a one-line banner (World.EASTER_EGG_MESSAGE_DURATION).
const DELIBERATE_INTERVAL_SECONDS := (
	float(WORDS_IN_A_FEEDBACK_LINE) / WORDS_PER_MINUTE_SILENT_READING * 60.0
)

## Refusals answer at the deliberate rate whatever verb they came from: a
## player holding a key against a wall should hear ONE "no", not forty. The
## refusal is also a sentence, so it is the same sentence-shaped interval.
const REFUSAL_INTERVAL_SECONDS := DELIBERATE_INTERVAL_SECONDS

## Slack on the due comparison, so an interval added to itself in floating
## point is still due on the frame it should be (the same guard
## `StepCadence.DUE_EPSILON_SECONDS` uses for the same reason).
const DUE_EPSILON_SECONDS := 0.000001


# -- the vocabulary -----------------------------------------------------

## Flash kinds. Five, because a sixth would be a colour nobody can name.
const FLASH_NONE := "none"
const FLASH_HIT := "hit"
const FLASH_GAIN := "gain"
const FLASH_REFUSED := "refused"
const FLASH_LEVEL := "level"

## Which of the caller's own numbers is the one worth floating. This module
## never invents a number; it only says which one is the receipt.
const FLOAT_NONE := ""
const FLOAT_DAMAGE := "damage"
const FLOAT_ITEM := "item"
const FLOAT_XP := "xp"
const FLOAT_COIN := "coins"
const FLOAT_LEVEL := "level"

## Most physical fact first. A row declares its own preferred source and
## falls through this order when the context does not carry it -- which is
## how one `attack` row answers both a creature (damage) and a tree (wood)
## without the table having to know the difference.
const FLOAT_PRECEDENCE := [FLOAT_DAMAGE, FLOAT_ITEM, FLOAT_COIN, FLOAT_XP, FLOAT_LEVEL]

## Every refusal shares one sound, because "no" is one answer however you
## arrived at it, and a per-verb refusal clip is a library nobody will
## record.
const SOUND_REFUSED := "refused"

## What a refusal says when the caller has no reason to give. Deliberately
## not empty: a silent refusal is the exact bug this module exists for.
const GENERIC_REFUSAL := "Not now"


# -- the table ----------------------------------------------------------
#
# Keyed by action id. The keys are checked against the live
# `Keybindings.ACTIONS` in both directions by test_answerback.gd; `craft`
# and `level_up` are the two verbs that reach the player through something
# other than a key (CraftingWindow.craft_requested -> Player.craft, and
# Player.gain_experience's discarded return value) and the test pins that
# they are NOT bound, so binding one forces the partition to be redone on
# purpose.
#
# The sound ids are a COMMISSIONING LIST, not a claim the clips exist. Only
# "footstep" has one today (FootstepSound); the rest name the sound the
# audio layer owes each verb, so the gap is written down in one place
# instead of being invisible.

## The one verb in this table nobody presses: a blow landing on the player.
##
## Measured on 2026-09-21, with the fight only just made loseable: a bear
## could close, bite, and take a fifth of the character's health with no
## sound, no flash, no number and no line. The health bar moved, and that
## was all. Named here rather than written as a literal at both ends so the
## raiser and the table cannot drift.
##
## Its interval is REFLEX_INTERVAL_SECONDS and that choice is provable
## rather than taste: pillar 5 sets an answer's gate to the rate limit the
## verb already has, and the gate on being hurt is how fast something can
## bite you. The fastest real bite among every species a biome pool can
## promote is the arctic fox at 0.533 s (SpeciesBite.bite_cooldown_seconds_
## for, derived from body mass); the reflex floor is 0.210 s, less than
## half of it, so the limiter can never swallow a blow the world really
## landed. test_nothing_in_this_world_bites_faster_than_the_answer_to_
## being_bitten sweeps the live pools and holds it.
##
## Deliberately NOT raised by continuous harm. Venom, a mushroom toxin and
## a spell debuff tick every frame through Player.take_tick_damage, and a
## receipt per frame is a buzz rather than an answer -- the exact failure
## the reflex floor exists to name. A poison is a CONDITION, and this HUD
## already shows conditions as chips (HudReadouts.condition_chips).
const HURT := "hurt"

const FEEDBACK := {
	# The feet. The one verb this game already answers, and the reason the
	# floor interval is what it is.
	"move_up": {"sound": "footstep", "flash": FLASH_NONE, "floats": FLOAT_NONE, "message": "", "interval": REFLEX_INTERVAL_SECONDS},
	"move_down": {"sound": "footstep", "flash": FLASH_NONE, "floats": FLOAT_NONE, "message": "", "interval": REFLEX_INTERVAL_SECONDS},
	"move_left": {"sound": "footstep", "flash": FLASH_NONE, "floats": FLOAT_NONE, "message": "", "interval": REFLEX_INTERVAL_SECONDS},
	"move_right": {"sound": "footstep", "flash": FLASH_NONE, "floats": FLOAT_NONE, "message": "", "interval": REFLEX_INTERVAL_SECONDS},

	# Every harvest-shaped verb in this game piggybacks on attack (chop,
	# smash, pull, butcher, collect -- see Player._harvest_farm_plot_step's
	# own note), so this ONE row has to answer a creature and a tree alike.
	# It declares damage and falls through to the yield, which is exactly
	# what that fall-through exists for.
	"attack": {"sound": "swing_hit", "flash": FLASH_HIT, "floats": FLOAT_DAMAGE, "message": "", "interval": SWING_INTERVAL_SECONDS},
	# A stance, not a strike: it answers at swing rate so raising the guard
	# reads as part of the same exchange.
	"block": {"sound": "guard_up", "flash": FLASH_NONE, "floats": FLOAT_NONE, "message": "", "interval": SWING_INTERVAL_SECONDS},
	# Held, and polled every frame -- so it needs the SLOW interval, not the
	# fast one: one breath a second while running, not one per frame.
	# Sprint costs stamina now (SprintCost), which is the change that made
	# it worth answering at all.
	"sprint": {"sound": "breath", "flash": FLASH_NONE, "floats": FLOAT_NONE, "message": "", "interval": DELIBERATE_INTERVAL_SECONDS},

	"pickup": {"sound": "pickup", "flash": FLASH_GAIN, "floats": FLOAT_ITEM, "message": "", "interval": SWING_INTERVAL_SECONDS},
	"stash": {"sound": "stash", "flash": FLASH_GAIN, "floats": FLOAT_ITEM, "message": "", "interval": SWING_INTERVAL_SECONDS},
	"kick": {"sound": "kick_stone", "flash": FLASH_HIT, "floats": FLOAT_NONE, "message": "", "interval": SWING_INTERVAL_SECONDS},

	# Crossing a threshold, throwing a rope, getting on a horse: one
	# deliberate act each, none of them repeatable at swing rate.
	"enter": {"sound": "door", "flash": FLASH_NONE, "floats": FLOAT_NONE, "message": "", "interval": DELIBERATE_INTERVAL_SECONDS},
	"lasso": {"sound": "rope_throw", "flash": FLASH_NONE, "floats": FLOAT_NONE, "message": "", "interval": DELIBERATE_INTERVAL_SECONDS},
	"mount": {"sound": "mount", "flash": FLASH_NONE, "floats": FLOAT_NONE, "message": "", "interval": DELIBERATE_INTERVAL_SECONDS},
	# Lying down for a night (docs/concept/sleep.md): the most deliberate
	# act in the game -- it hands the next several hours to the world --
	# and the one whose whole result is a SENTENCE, since what a sleeper
	# wants to know on waking is how much of the night they got.
	"rest": {"sound": "rest", "flash": FLASH_NONE, "floats": FLOAT_NONE, "message": "", "interval": DELIBERATE_INTERVAL_SECONDS},
	# Cast and reel is a held level, polled every frame: slow interval for
	# the same reason sprint's is.
	"fish": {"sound": "cast_line", "flash": FLASH_NONE, "floats": FLOAT_ITEM, "message": "", "interval": DELIBERATE_INTERVAL_SECONDS},

	# Money moves in one direction per key, so each floats the side the
	# player gained: goods when buying, coins when selling.
	"trade": {"sound": "coins", "flash": FLASH_GAIN, "floats": FLOAT_ITEM, "message": "", "interval": DELIBERATE_INTERVAL_SECONDS},
	"sell": {"sound": "coins", "flash": FLASH_GAIN, "floats": FLOAT_COIN, "message": "", "interval": DELIBERATE_INTERVAL_SECONDS},
	"talk": {"sound": "greeting", "flash": FLASH_NONE, "floats": FLOAT_NONE, "message": "", "interval": DELIBERATE_INTERVAL_SECONDS},

	# The two context slots: what they do is decided by whatever is under
	# the cursor (see Keybindings' own note), so they answer with the
	# generic interact and float whatever the caller came back with.
	"primary_action": {"sound": "interact", "flash": FLASH_GAIN, "floats": FLOAT_ITEM, "message": "", "interval": SWING_INTERVAL_SECONDS},
	"secondary_action": {"sound": "interact", "flash": FLASH_GAIN, "floats": FLOAT_ITEM, "message": "", "interval": SWING_INTERVAL_SECONDS},

	# Terraforming repeats as fast as the swing does, so it answers at swing
	# rate. Destroy flashes HIT rather than GAIN: the tile is what is being
	# hurt, even when a material falls out of it.
	"build": {"sound": "place_block", "flash": FLASH_GAIN, "floats": FLOAT_NONE, "message": "", "interval": SWING_INTERVAL_SECONDS},
	"destroy": {"sound": "break_block", "flash": FLASH_HIT, "floats": FLOAT_ITEM, "message": "", "interval": SWING_INTERVAL_SECONDS},
	"plant": {"sound": "till", "flash": FLASH_GAIN, "floats": FLOAT_NONE, "message": "", "interval": SWING_INTERVAL_SECONDS},
	"cast": {"sound": "spell_cast", "flash": FLASH_GAIN, "floats": FLOAT_DAMAGE, "message": "", "interval": SWING_INTERVAL_SECONDS},

	# NOT a selection: Player.activate_hotbar_slot equips a weapon, eats
	# food or arms a placeable, and returns a bool saying whether it worked
	# -- a bool every caller currently drops. The answer to "what did slot 3
	# do" is the name of the thing, so this is the one row whose whole
	# payload is its message.
	"hotbar_1": {"sound": "equip", "flash": FLASH_GAIN, "floats": FLOAT_NONE, "message": "{item}", "interval": SWING_INTERVAL_SECONDS},
	"hotbar_2": {"sound": "equip", "flash": FLASH_GAIN, "floats": FLOAT_NONE, "message": "{item}", "interval": SWING_INTERVAL_SECONDS},
	"hotbar_3": {"sound": "equip", "flash": FLASH_GAIN, "floats": FLOAT_NONE, "message": "{item}", "interval": SWING_INTERVAL_SECONDS},
	"hotbar_4": {"sound": "equip", "flash": FLASH_GAIN, "floats": FLOAT_NONE, "message": "{item}", "interval": SWING_INTERVAL_SECONDS},
	"hotbar_5": {"sound": "equip", "flash": FLASH_GAIN, "floats": FLOAT_NONE, "message": "{item}", "interval": SWING_INTERVAL_SECONDS},

	# Unbound: reached through the crafting window's own button.
	"craft": {"sound": "craft_done", "flash": FLASH_GAIN, "floats": FLOAT_ITEM, "message": "Crafted {item}", "interval": DELIBERATE_INTERVAL_SECONDS},
	# Unbound: Player.gain_experience already returns this and nobody reads
	# it. The single most valuable discarded fact in the codebase.
	"level_up": {"sound": "level_up", "flash": FLASH_LEVEL, "floats": FLOAT_LEVEL, "message": "Level {level}", "interval": DELIBERATE_INTERVAL_SECONDS},
	# Unbound, and the only row in this table for something that happens TO
	# the player rather than because they pressed something. See HURT.
	HURT: {"sound": "hurt", "flash": FLASH_HIT, "floats": FLOAT_DAMAGE, "message": "", "interval": REFLEX_INTERVAL_SECONDS},
}


## Whether this verb answers at all. False for a window toggle and for an
## action this table has never heard of -- both are real answers, not
## errors.
static func has_feedback(action_id: String) -> bool:
	return FEEDBACK.has(action_id)


## Every verb with a row, sorted, so the drift test can walk them.
static func answered_actions() -> Array:
	var ids: Array = FEEDBACK.keys()
	ids.sort()
	return ids


## The minimum seconds between two answers from this verb. 0.0 for a verb
## with no row, which `should_play` never reaches anyway.
static func interval_for(action_id: String) -> float:
	if not has_feedback(action_id):
		return 0.0
	return float(FEEDBACK[action_id]["interval"])


## The game's own good/bad pair (UiTheme.ACCENT / UiTheme.NEGATIVE, the
## same one docs/concept/hud.md pins for karma), never a second palette
## invented here. A gain in the world and a gain in a window are one
## decision.
static func flash_color_for(flash_kind: String) -> Color:
	match flash_kind:
		FLASH_HIT:
			return UiTheme.NEGATIVE
		FLASH_GAIN, FLASH_LEVEL:
			return UiTheme.ACCENT
		FLASH_REFUSED:
			return UiTheme.TEXT_MUTED
		_:
			return Color(1, 1, 1, 0)


## The resolved answer for one press. `context` carries only what the
## caller already knows: damage, item/count, coins, xp, level, target,
## failed, reason.
##
## `severity` is how BIG the act was: the fraction of whatever bar it moved,
## 0..1, which only the caller can know. A flash that is the same red for a
## scratch and for a near-killing blow is a warning light rather than a
## reading, so the kind of answer and its size are two different facts. Zero
## for every caller that does not say, and for a refusal whatever it was
## going to cost.
##
## A FAILED action answers differently from a successful one, and that is
## the whole point of the branch: today `Player.activate_item_id` returns
## false and the bool is dropped on the floor, so a press that could not do
## what it meant produces literally nothing and the player is left
## wondering whether the key is broken.
##
## Empty for a verb with no row -- "this answers with nothing", which is
## the correct answer for a window toggle.
static func for_action(action_id: String, context: Dictionary) -> Dictionary:
	if not has_feedback(action_id):
		return {}
	if bool(context.get("failed", false)):
		var reason := String(context.get("reason", "")).strip_edges()
		return {
			"action": action_id,
			"sound": SOUND_REFUSED,
			"flash": FLASH_REFUSED,
			"flash_color": flash_color_for(FLASH_REFUSED),
			"message": reason if not reason.is_empty() else GENERIC_REFUSAL,
			"float_text": "",
			"interval": REFUSAL_INTERVAL_SECONDS,
			"severity": 0.0,
			"failed": true,
		}
	var row: Dictionary = FEEDBACK[action_id]
	var flash := String(row["flash"])
	return {
		"action": action_id,
		"sound": String(row["sound"]),
		"flash": flash,
		"flash_color": flash_color_for(flash),
		"message": _fill(String(row["message"]), context),
		"float_text": floating_text_for(action_id, context),
		"interval": float(row["interval"]),
		"severity": clampf(float(context.get("severity", 0.0)), 0.0, 1.0),
		"failed": false,
	}


## The number or word that floats, or "". One per press: a stack of three
## receipts is not three answers, it is a mess.
##
## Sign convention, pinned by test: "+" is something gained ("+3 Stick",
## "+6 XP"), "-" is something lost ("-12" over the creature that took the
## hit). A level is neither, so it floats as the word.
##
## A row that declares FLOAT_NONE floats nothing however full the context
## is -- the TABLE decides what is worth showing, not whatever the caller
## happened to pack. Everything else tries its declared source first and
## then falls through FLOAT_PRECEDENCE, which is how the single `attack`
## row answers a creature with damage and a tree with wood.
##
## A refusal floats nothing: it is said, not scored.
static func floating_text_for(action_id: String, context: Dictionary) -> String:
	if not has_feedback(action_id):
		return ""
	if bool(context.get("failed", false)):
		return ""
	var declared := String(FEEDBACK[action_id]["floats"])
	if declared == FLOAT_NONE:
		return ""
	var order: Array = [declared]
	for source in FLOAT_PRECEDENCE:
		if source != declared:
			order.append(source)
	for source in order:
		var text := _text_for_source(String(source), context)
		if not text.is_empty():
			return text
	return ""


## Whether this verb may answer again yet. Pure -- both timestamps are
## arguments, so the rate limit is a property a test can walk rather than
## something you have to play the game to see.
##
## Two cases both answer rather than mute, deliberately: a verb that has
## never answered (`last_played_seconds` negative), and a clock that has
## gone backwards (a reload, a fresh session, a rewound world time). The
## failure this module exists to prevent is silence, so when in doubt it
## makes noise.
static func should_play(
	action_id: String, last_played_seconds: float, now_seconds: float
) -> bool:
	if not has_feedback(action_id):
		return false
	if last_played_seconds < 0.0:
		return true
	if now_seconds < last_played_seconds:
		return true
	return now_seconds - last_played_seconds >= interval_for(action_id) - DUE_EPSILON_SECONDS


## One float source against one context, or "" when the context does not
## carry it. Zero and below is "not carried": a hit for no damage and a sale
## for no coins are both non-events, and floating "0" over them would be a
## receipt for nothing.
static func _text_for_source(source: String, context: Dictionary) -> String:
	match source:
		FLOAT_DAMAGE:
			var damage := int(context.get("damage", 0))
			return "-%d" % damage if damage > 0 else ""
		FLOAT_ITEM:
			var item := String(context.get("item", ""))
			if item.is_empty():
				return ""
			return "+%d %s" % [maxi(1, int(context.get("count", 1))), item]
		FLOAT_COIN:
			var coins := int(context.get("coins", 0))
			if coins <= 0:
				return ""
			return "+%d %s" % [coins, "coin" if coins == 1 else "coins"]
		FLOAT_XP:
			var xp := int(context.get("xp", 0))
			return "+%d XP" % xp if xp > 0 else ""
		FLOAT_LEVEL:
			var level := int(context.get("level", 0))
			return "Level %d" % level if level > 0 else ""
		_:
			return ""


## Fills a message template from the caller's context. Only the six fields
## a caller can really supply are substituted, and a template that asks for
## anything else fails test_no_message_template_asks_for_an_unknown_field
## rather than reaching a player as a literal brace.
static func _fill(template: String, context: Dictionary) -> String:
	if template.is_empty():
		return ""
	var out := template
	out = out.replace("{item}", String(context.get("item", "")))
	out = out.replace("{count}", str(int(context.get("count", 1))))
	out = out.replace("{damage}", str(int(context.get("damage", 0))))
	out = out.replace("{xp}", str(int(context.get("xp", 0))))
	out = out.replace("{level}", str(int(context.get("level", 0))))
	out = out.replace("{target}", String(context.get("target", "")))
	return out.strip_edges()


# -- how long a passage needs to be on screen ---------------------------
#
# The intervals above answer "how often"; these answer "how long". Same
# source, because they are the same fact about a reader: a line has to be
# read before the next thing can happen.

## The longest any prose card may need. Not a clamp -- `seconds_to_read`
## never truncates, because a card cut off mid-warning is worse than a card
## shown a moment too long. It is the ceiling tests hold real card text to,
## so a passage that grows into an essay fails loudly instead of quietly
## becoming a HUD element. The figure is
## `World.ANCIENT_TERMINAL_MESSAGE_DURATION`, the longest passage this HUD
## already shows anywhere, restated (a pure rule must not preload a scene
## script) and held to it by test.
const MAX_CARD_SECONDS := 12.0


## Words in a passage, counted across the line breaks a card is built from.
static func word_count(text: String) -> int:
	var flattened := text.replace("\n", " ").replace("\t", " ").strip_edges()
	if flattened == "":
		return 0
	return flattened.split(" ", false).size()


## How long a card must stay on screen: its OWN word count at the reading
## rate above (Brysbaert's 2019 meta-analysis, 238 wpm).
##
## Derived rather than picked, because a duration nobody derived is a
## duration somebody eyeballed -- and a card is not one length: a journey
## ring's crossing card runs from seventeen words to thirty-four, and
## showing both for the same six seconds means one of them is wrong.
##
## The floor is `DELIBERATE_INTERVAL_SECONDS`, this module's own "a sentence
## has to be read" interval, so a very short card is still a sentence rather
## than a flash. Nothing at all to read is no time at all -- the caller has
## no business showing an empty card.
static func seconds_to_read(text: String) -> float:
	var words := word_count(text)
	if words <= 0:
		return 0.0
	return maxf(
		DELIBERATE_INTERVAL_SECONDS,
		float(words) / WORDS_PER_MINUTE_SILENT_READING * 60.0
	)
