extends GutTest

## docs/concept/feedback.md: every verb pays, out loud, within a pinned
## interval -- and this test is what keeps that true as the game grows.
##
## Measured on 2026-09-20, before this module existed: `InteractionSfxPlayer`
## had exactly three `play_` methods in the whole game; a grep for a hit
## flash, a damage number, a floating text node or a level-up toast found
## none of the four; `Player.gain_experience` returned the levels gained and
## all three of its callers threw the value away; and of the 36 actions in
## `Keybindings.ACTIONS`, exactly four -- the movement quartet -- made any
## sound at all. Thirty-two bound verbs answered with nothing.
##
## The centrepiece here is the TWO-WAY DRIFT TEST below: the partition of
## the real action list is a named constant, and it is checked in both
## directions, so a new verb that answers with nothing cannot ship and a
## feedback row for a verb that no longer exists cannot linger.

const Answerback = preload("res://src/gameplay/answerback.gd")
const Keybindings = preload("res://src/gameplay/keybindings.gd")
const FootstepGait = preload("res://src/gameplay/footstep_gait.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")
const Player = preload("res://scenes/player.gd")

## How long the HUD gives a one-line banner to be read
## (World.EASTER_EGG_MESSAGE_DURATION, restated rather than preloading the
## whole world scene into a pure-logic test -- held to it by
## test_the_whole_scale_fits_inside_the_huds_own_reading_time below only as
## an upper bound, which is the only direction that matters here).
const HUD_ONE_LINE_BANNER_SECONDS := 6.0


# -- THE PARTITION ------------------------------------------------------
#
# Every action in Keybindings.ACTIONS is in exactly one of these two lists.
# That is the assertion that makes silence structurally impossible: a verb
# added to ACTIONS and to neither list fails test_the_partition_covers_
# every_bound_action_exactly_once, and a verb added to WORLD_CHANGING_ACTIONS
# without a feedback row fails test_every_world_changing_action_is_answered.

## Pressing this changes something OUTSIDE the UI -- the world, the
## character, an animal, an inventory. It must have a feedback row.
##
## The movement quartet is in here deliberately: moving is how this game is
## played, and the feet are already its one honest answer
## (InteractionSfxPlayer.play_footstep). So is hotbar_1..5, which is NOT a
## selection -- Player.activate_hotbar_slot equips a weapon, eats food or
## arms a placeable and returns a bool saying whether it worked.
const WORLD_CHANGING_ACTIONS := [
	"move_up", "move_down", "move_left", "move_right",
	"attack", "block", "sprint", "pickup", "enter", "kick", "stash",
	"fish", "lasso", "mount", "trade", "sell",
	"primary_action", "secondary_action", "talk",
	"build", "destroy", "plant", "cast",
	"hotbar_1", "hotbar_2", "hotbar_3", "hotbar_4", "hotbar_5",
]

## Pressing this only opens a window or changes a mode -- it moves what the
## player is LOOKING at, not the world. It must have NO feedback row: a
## window that thumps when it opens is noise, and letting these in would
## make the forward direction of the drift test meaningless.
const VIEW_ONLY_ACTIONS := [
	"toggle_inventory", "toggle_crafting", "toggle_quest_log",
	"toggle_skills", "toggle_planner", "toggle_settings",
	"toggle_console", "toggle_diagnostics",
]

## World-changing acts that reach the player through something other than a
## key: `craft` is CraftingWindow.craft_requested -> Player.craft, and
## `level_up` is the return value of Player.gain_experience that nobody
## currently reads. These get rows, and must NOT be bound actions -- see
## test_the_unbound_verbs_are_really_unbound.
const UNBOUND_VERBS := ["craft", "level_up"]


func _bound_actions() -> Array:
	return Keybindings.new().action_names()


# -- the two-way drift test ---------------------------------------------

## The one assertion the whole module exists for. Add a verb to ACTIONS and
## it lands in neither list; this goes red before it can ship silent.
func test_the_partition_covers_every_bound_action_exactly_once():
	var bound: Array = _bound_actions()
	var partitioned: Array = []
	partitioned.append_array(WORLD_CHANGING_ACTIONS)
	partitioned.append_array(VIEW_ONLY_ACTIONS)
	for action in bound:
		assert_true(
			partitioned.has(action),
			"%s is bound but in neither partition -- decide whether it answers" % action
		)
	for action in partitioned:
		assert_true(
			bound.has(action),
			"%s is partitioned but no longer bound -- drop it from the partition" % action
		)
	assert_eq(
		partitioned.size(), bound.size(),
		"the two partitions must union to the live action list with no duplicates"
	)


func test_every_world_changing_action_is_answered():
	for action in WORLD_CHANGING_ACTIONS:
		assert_true(
			Answerback.has_feedback(action),
			"%s changes the world and answers with nothing" % action
		)


func test_no_view_only_action_is_answered():
	for action in VIEW_ONLY_ACTIONS:
		assert_false(
			Answerback.has_feedback(action),
			"%s only opens a window -- it must not make a noise" % action
		)


## The backward direction: a row for a verb the game no longer has.
func test_every_feedback_row_is_a_verb_that_really_exists():
	var real: Array = []
	real.append_array(WORLD_CHANGING_ACTIONS)
	real.append_array(UNBOUND_VERBS)
	for action in Answerback.answered_actions():
		assert_true(
			real.has(action),
			"%s has feedback but is not a verb in this game" % action
		)


func test_every_unbound_verb_is_answered():
	for verb in UNBOUND_VERBS:
		assert_true(Answerback.has_feedback(verb), "%s answers with nothing" % verb)


## If somebody binds a craft key, the partition has to be redone on purpose.
func test_the_unbound_verbs_are_really_unbound():
	var bound: Array = _bound_actions()
	for verb in UNBOUND_VERBS:
		assert_false(
			bound.has(verb),
			"%s is now a bound action -- move it into the partition above" % verb
		)


# -- the intervals are derived, never picked ----------------------------

## The floor is a real footfall: 0.75 m of stride at this world's scale,
## walked at the player's own speed. Nothing may answer faster than the feet
## already do.
func test_the_reflex_interval_is_one_real_stride_at_walking_pace():
	assert_almost_eq(
		Answerback.REFLEX_INTERVAL_SECONDS,
		FootstepGait.STRIDE_LENGTH_PX / Answerback.WALK_SPEED_PX_PER_SECOND,
		0.0001
	)


func test_the_restated_walk_speed_is_the_players_own():
	assert_almost_eq(Answerback.WALK_SPEED_PX_PER_SECOND, Player.BASE_SPEED, 0.0001)


## A gated verb answers at its own gate, so the answer can never eat a real
## swing the game itself allowed.
func test_the_swing_interval_is_the_swings_own_cooldown():
	assert_almost_eq(Answerback.SWING_INTERVAL_SECONDS, Player.ATTACK_COOLDOWN, 0.0001)


## The ceiling is a read: Brysbaert 2019 puts silent reading of English
## non-fiction at ~238 wpm, and a feedback line is about four words.
func test_the_deliberate_interval_is_the_time_to_read_one_line():
	assert_almost_eq(
		Answerback.DELIBERATE_INTERVAL_SECONDS,
		float(Answerback.WORDS_IN_A_FEEDBACK_LINE)
			/ Answerback.WORDS_PER_MINUTE_SILENT_READING * 60.0,
		0.0001
	)
	assert_almost_eq(Answerback.DELIBERATE_INTERVAL_SECONDS, 1.008, 0.02,
		"four words at 238 wpm is about a second")


func test_the_three_intervals_are_strictly_ordered():
	assert_lt(Answerback.REFLEX_INTERVAL_SECONDS, Answerback.SWING_INTERVAL_SECONDS)
	assert_lt(Answerback.SWING_INTERVAL_SECONDS, Answerback.DELIBERATE_INTERVAL_SECONDS)


func test_the_whole_scale_fits_inside_the_huds_own_reading_time():
	assert_lt(Answerback.DELIBERATE_INTERVAL_SECONDS, HUD_ONE_LINE_BANNER_SECONDS)


## No row may invent a cooldown of its own -- there are three, and they are
## the three above.
func test_no_row_carries_an_ad_hoc_cooldown():
	var allowed := [
		Answerback.REFLEX_INTERVAL_SECONDS,
		Answerback.SWING_INTERVAL_SECONDS,
		Answerback.DELIBERATE_INTERVAL_SECONDS,
	]
	for action in Answerback.answered_actions():
		assert_true(
			allowed.has(Answerback.interval_for(action)),
			"%s carries a cooldown that is not one of the three pinned intervals" % action
		)


## The point of having more than one: a footstep-rate verb and a deliberate
## one must not share a number.
func test_a_fast_verb_and_a_slow_verb_really_differ():
	assert_almost_eq(Answerback.interval_for("move_up"), Answerback.REFLEX_INTERVAL_SECONDS, 0.0001)
	assert_almost_eq(Answerback.interval_for("craft"), Answerback.DELIBERATE_INTERVAL_SECONDS, 0.0001)
	assert_lt(Answerback.interval_for("move_up"), Answerback.interval_for("craft"))


# -- every row is well formed -------------------------------------------

func test_every_row_has_a_real_sound_and_a_known_flash_kind():
	var kinds := [
		Answerback.FLASH_NONE, Answerback.FLASH_HIT, Answerback.FLASH_GAIN,
		Answerback.FLASH_REFUSED, Answerback.FLASH_LEVEL,
	]
	var sources := [
		Answerback.FLOAT_NONE, Answerback.FLOAT_DAMAGE, Answerback.FLOAT_ITEM,
		Answerback.FLOAT_XP, Answerback.FLOAT_COIN, Answerback.FLOAT_LEVEL,
	]
	for action in Answerback.answered_actions():
		var row: Dictionary = Answerback.FEEDBACK[action]
		assert_false(String(row["sound"]).is_empty(), "%s has no sound id" % action)
		assert_true(kinds.has(row["flash"]), "%s has an unknown flash kind" % action)
		assert_true(sources.has(row["floats"]), "%s floats an unknown source" % action)


## The flash colours are the game's own good/bad pair, not a second palette.
func test_the_flash_colours_come_from_the_shared_theme():
	assert_eq(Answerback.flash_color_for(Answerback.FLASH_HIT), UiTheme.NEGATIVE)
	assert_eq(Answerback.flash_color_for(Answerback.FLASH_GAIN), UiTheme.ACCENT)
	assert_eq(Answerback.flash_color_for(Answerback.FLASH_LEVEL), UiTheme.ACCENT)
	assert_eq(Answerback.flash_color_for(Answerback.FLASH_REFUSED), UiTheme.TEXT_MUTED)


## A template may only ask for something a caller can actually supply.
func test_no_message_template_asks_for_an_unknown_field():
	var known := ["{item}", "{count}", "{damage}", "{xp}", "{level}", "{target}"]
	for action in Answerback.answered_actions():
		var template := String(Answerback.FEEDBACK[action]["message"])
		var rest := template
		for field in known:
			rest = rest.replace(field, "")
		assert_false(
			rest.contains("{"),
			"%s's message template asks for a field no caller supplies: %s" % [action, template]
		)


# -- for_action ---------------------------------------------------------

func test_a_successful_swing_answers_with_a_sound_a_flash_and_the_damage():
	var fb: Dictionary = Answerback.for_action("attack", {"damage": 12})
	assert_false(fb.is_empty())
	assert_eq(fb["flash"], Answerback.FLASH_HIT)
	assert_eq(fb["flash_color"], UiTheme.NEGATIVE)
	assert_eq(fb["float_text"], "-12")
	assert_false(fb["failed"])
	assert_almost_eq(float(fb["interval"]), Answerback.SWING_INTERVAL_SECONDS, 0.0001)


## A refusal is feedback too -- and a DIFFERENT one.
func test_a_refused_swing_answers_differently_from_a_landed_one():
	var hit: Dictionary = Answerback.for_action("attack", {"damage": 12})
	var missed: Dictionary = Answerback.for_action(
		"attack", {"failed": true, "reason": "Nothing in reach"}
	)
	assert_false(missed.is_empty())
	assert_ne(missed["sound"], hit["sound"], "a refusal must not sound like a success")
	assert_eq(missed["sound"], Answerback.SOUND_REFUSED)
	assert_eq(missed["flash"], Answerback.FLASH_REFUSED)
	assert_eq(missed["message"], "Nothing in reach")
	assert_true(missed["failed"])


func test_a_refusal_with_no_reason_still_says_something():
	var fb: Dictionary = Answerback.for_action("build", {"failed": true})
	assert_false(String(fb["message"]).is_empty(), "a silent refusal is the bug this module exists for")


## A refusal held against a wall says "no" once a second, not forty times.
func test_a_refusal_is_rate_limited_to_the_deliberate_interval():
	var fb: Dictionary = Answerback.for_action("move_up", {"failed": true})
	assert_almost_eq(float(fb["interval"]), Answerback.REFUSAL_INTERVAL_SECONDS, 0.0001)
	assert_gt(Answerback.REFUSAL_INTERVAL_SECONDS, Answerback.REFLEX_INTERVAL_SECONDS)


func test_an_action_with_no_row_answers_with_nothing_rather_than_erroring():
	assert_true(Answerback.for_action("toggle_inventory", {}).is_empty())
	assert_true(Answerback.for_action("no_such_verb", {}).is_empty())
	assert_eq(Answerback.floating_text_for("toggle_inventory", {"xp": 9}), "")


func test_a_message_template_is_filled_from_the_callers_own_context():
	var fb: Dictionary = Answerback.for_action("craft", {"item": "Stone Axe", "count": 1})
	assert_eq(fb["message"], "Crafted Stone Axe")
	var lvl: Dictionary = Answerback.for_action("level_up", {"level": 4})
	assert_eq(lvl["message"], "Level 4")


# -- floating_text_for --------------------------------------------------

func test_what_floats_carries_its_sign():
	assert_eq(Answerback.floating_text_for("attack", {"damage": 12}), "-12")
	assert_eq(Answerback.floating_text_for("pickup", {"item": "Stick", "count": 3}), "+3 Stick")
	assert_eq(Answerback.floating_text_for("level_up", {"level": 2}), "Level 2")


func test_a_single_item_still_names_its_count():
	assert_eq(Answerback.floating_text_for("pickup", {"item": "Stick"}), "+1 Stick")


func test_coins_are_counted_in_words_a_player_reads():
	assert_eq(Answerback.floating_text_for("sell", {"coins": 12}), "+12 coins")
	assert_eq(Answerback.floating_text_for("sell", {"coins": 1}), "+1 coin")


## One float per press: the most physical fact wins.
func test_only_one_thing_floats_and_damage_beats_the_rest():
	assert_eq(
		Answerback.floating_text_for("attack", {"damage": 7, "item": "Pelt", "xp": 6}),
		"-7"
	)


## Chopping a tree deals no damage but yields wood -- the row declares
## damage, and with no damage to show it falls through to what really
## changed.
func test_a_row_falls_through_to_whatever_the_context_really_carries():
	assert_eq(Answerback.floating_text_for("attack", {"item": "Wood", "count": 2}), "+2 Wood")
	assert_eq(Answerback.floating_text_for("attack", {"xp": 6}), "+6 XP")


## A row that declares nothing floats nothing, however full the context is.
func test_a_row_that_floats_nothing_stays_quiet_with_a_full_context():
	assert_eq(
		Answerback.floating_text_for("build", {"damage": 9, "item": "Earth", "xp": 3}),
		""
	)


func test_a_refusal_is_said_not_scored():
	assert_eq(
		Answerback.floating_text_for("attack", {"damage": 12, "failed": true}),
		"",
		"a refusal names itself in words; it does not float a number"
	)
	assert_eq(Answerback.for_action("attack", {"damage": 12, "failed": true})["float_text"], "")


func test_an_empty_context_floats_nothing():
	assert_eq(Answerback.floating_text_for("attack", {}), "")
	assert_eq(Answerback.floating_text_for("attack", {"damage": 0}), "")


# -- should_play --------------------------------------------------------

## Pure: the clock is an argument, so the cooldown is a property, not
## something you have to play the game to see.
func test_a_verb_that_has_never_answered_answers_now():
	assert_true(Answerback.should_play("attack", -1.0, 0.0))


func test_exactly_one_interval_later_is_due():
	assert_true(
		Answerback.should_play("attack", 10.0, 10.0 + Answerback.SWING_INTERVAL_SECONDS)
	)


func test_just_short_of_the_interval_stays_quiet():
	assert_false(
		Answerback.should_play("attack", 10.0, 10.0 + Answerback.SWING_INTERVAL_SECONDS - 0.05)
	)


## The same gap answers a footstep-rate verb and not a deliberate one --
## which is the entire reason there is more than one interval.
func test_the_same_gap_answers_the_fast_verb_and_not_the_slow_one():
	var gap := 0.3
	assert_true(Answerback.should_play("move_up", 0.0, gap))
	assert_false(Answerback.should_play("craft", 0.0, gap))


## When in doubt this module makes noise: the failure it exists to prevent
## is silence, so a clock that has gone backwards (a reload, a new session)
## answers rather than muting.
func test_a_clock_that_went_backwards_answers_rather_than_muting():
	assert_true(Answerback.should_play("craft", 500.0, 3.0))


func test_a_verb_with_no_feedback_never_plays():
	assert_false(Answerback.should_play("toggle_inventory", -1.0, 999.0))
	assert_false(Answerback.should_play("no_such_verb", -1.0, 999.0))


func test_the_interval_of_a_verb_with_no_row_is_zero_rather_than_an_error():
	assert_almost_eq(Answerback.interval_for("toggle_map"), 0.0, 0.0001)


# -- sweeps: the table is checked as a whole, not by sampling ------------
#
# The tests above name individual verbs, which means a row added later
# could quietly be malformed and never be looked at. These walk every row.

## A row could satisfy `has_feedback` and still answer with nothing --
## which is precisely the bug this module exists to make impossible. Every
## row must produce at least one perceptible thing.
func test_no_row_answers_with_nothing():
	var full := {"damage": 5, "item": "Stick", "count": 2, "coins": 3, "xp": 4, "level": 2, "target": "Wolf"}
	for action in Answerback.answered_actions():
		var fb: Dictionary = Answerback.for_action(action, full)
		var says_something: bool = (
			not String(fb["sound"]).is_empty()
			or fb["flash"] != Answerback.FLASH_NONE
			or not String(fb["float_text"]).is_empty()
			or not String(fb["message"]).is_empty()
		)
		assert_true(says_something, "%s has a row but answers with nothing" % action)


## Every row resolves to the full answer shape, so a typo'd key in the
## table is a failure here rather than a crash at the call site.
func test_every_row_resolves_to_a_complete_answer():
	var keys := ["action", "sound", "flash", "flash_color", "message", "float_text", "interval", "failed"]
	for action in Answerback.answered_actions():
		var fb: Dictionary = Answerback.for_action(action, {"item": "Stick", "damage": 3})
		for key in keys:
			assert_true(fb.has(key), "%s's answer is missing %s" % [action, key])
		assert_eq(fb["action"], action)
		assert_gt(float(fb["interval"]), 0.0, "%s answers with no interval at all" % action)


## Every verb can be refused, and a refusal never looks like a success.
func test_every_verb_can_refuse_and_a_refusal_never_looks_like_a_success():
	for action in Answerback.answered_actions():
		var ok: Dictionary = Answerback.for_action(action, {"item": "Stick", "damage": 3})
		var no: Dictionary = Answerback.for_action(
			action, {"item": "Stick", "damage": 3, "failed": true}
		)
		assert_true(no["failed"], "%s cannot be refused" % action)
		assert_ne(no["sound"], ok["sound"], "%s's refusal sounds like its success" % action)
		assert_ne(no["flash_color"], ok["flash_color"], "%s's refusal looks like its success" % action)
		assert_eq(no["float_text"], "", "%s floats a number on a refusal" % action)
		assert_false(String(no["message"]).is_empty(), "%s refuses silently" % action)


## The rate limit really holds for every verb, not just the two sampled
## above: answering twice in the same instant is never allowed.
func test_no_verb_answers_twice_in_the_same_instant():
	for action in Answerback.answered_actions():
		assert_true(Answerback.should_play(action, -1.0, 100.0), "%s never answers" % action)
		assert_false(
			Answerback.should_play(action, 100.0, 100.0),
			"%s answers twice in the same instant" % action
		)
		assert_true(
			Answerback.should_play(action, 100.0, 100.0 + Answerback.interval_for(action)),
			"%s does not answer again after its own interval" % action
		)


## The partition lists must not double-count: a repeated entry would keep
## both containment directions happy on its own.
func test_neither_partition_repeats_an_action():
	var seen: Dictionary = {}
	var both: Array = []
	both.append_array(WORLD_CHANGING_ACTIONS)
	both.append_array(VIEW_ONLY_ACTIONS)
	for action in both:
		assert_false(seen.has(action), "%s is listed twice in the partition" % action)
		seen[action] = true
