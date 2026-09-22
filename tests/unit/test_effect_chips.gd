extends GutTest

## Every timed thing riding on the character, on screen (docs/concept/hud.md).
##
## Measured: `HudReadouts.condition_chips(meters, movement_mode)` took the
## survival meters and nothing else, so the row said *Hungry*, *Parched*,
## *Freezing*, *Exhausted*, *Malnourished* and where you were standing --
## and said nothing at all about anything with a **clock** on it. A
## character could be venomed, burning, blighted, frozen, rooted, slowed,
## shielded and fed a damage-boosting meal at the same moment and the HUD
## would show exactly none of it.
##
## Every one of those is already tracked, already ticked and already
## carries its own `time_remaining`. Only the reading was missing -- which
## is why this reuses the chip row the HUD already has rather than building
## a second piece of furniture for it.

const HudReadouts = preload("res://src/ui/hud_readouts.gd")
const SurvivalMeters = preload("res://src/gameplay/survival_meters.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")
const SpellStatusEffects = preload("res://src/gameplay/spell_status_effects.gd")
const VenomModel = preload("res://src/gameplay/venom_model.gd")


func _well_fed() -> SurvivalMeters:
	# Nothing wrong, so the row is empty but for what this suite adds.
	var meters := SurvivalMeters.new()
	meters.hunger = 0.0
	meters.thirst = 0.0
	meters.stamina = 1.0
	meters.warmth = 1.0
	return meters


func _effect(id: String, seconds: float, stacks: int = 1) -> Dictionary:
	return {"debuff_id": id, "stacks": stacks, "time_remaining": seconds}


func _texts(chips: Array) -> Array:
	var out: Array = []
	for chip in chips:
		out.append(String(chip["text"]))
	return out


# -- the things with a clock on them --------------------------------------

func test_a_venomed_character_says_so():
	var chips := HudReadouts.condition_chips(
		_well_fed(), "walking", [_effect(VenomModel.DEBUFF_ID, 8.0)]
	)
	assert_true(_texts(chips).any(func(t): return t.begins_with("Venomed")))


func test_every_spell_status_a_character_can_wear_has_a_name():
	for id in [
		SpellStatusEffects.IGNITE,
		SpellStatusEffects.BLIGHT,
		SpellStatusEffects.FREEZE,
		SpellStatusEffects.ROOT,
		SpellStatusEffects.SLOW,
		SpellStatusEffects.FEAR,
		SpellStatusEffects.CALM,
	]:
		var chips := HudReadouts.condition_chips(_well_fed(), "walking", [_effect(id, 5.0)])
		assert_eq(chips.size(), 1, "%s is on the character and not on the screen" % id)
		assert_false(
			String(chips[0]["text"]).begins_with(id),
			"%s reads as its own id rather than as a word" % id
		)


## What a player needs from a timed effect is how long it has left. A chip
## that only says *Burning* answers nothing they can act on.
func test_a_chip_says_how_long_is_left():
	var chips := HudReadouts.condition_chips(
		_well_fed(), "walking", [_effect(SpellStatusEffects.IGNITE, 7.0)]
	)
	assert_string_contains(String(chips[0]["text"]), "7")


func test_a_chip_rounds_up_rather_than_to_nothing():
	var chips := HudReadouts.condition_chips(
		_well_fed(), "walking", [_effect(SpellStatusEffects.IGNITE, 0.4)]
	)
	assert_string_contains(
		String(chips[0]["text"]), "1", "half a second left is still a second to act in"
	)


## Stacks are the difference between an irritation and a death sentence
## (VenomModel caps at three), so a stacked effect says how many.
func test_a_stacked_effect_says_how_many():
	var chips := HudReadouts.condition_chips(
		_well_fed(), "walking", [_effect(VenomModel.DEBUFF_ID, 8.0, 3)]
	)
	assert_string_contains(String(chips[0]["text"]), "3")


func test_a_single_stack_does_not_say_one():
	var chips := HudReadouts.condition_chips(
		_well_fed(), "walking", [_effect(VenomModel.DEBUFF_ID, 8.0, 1)]
	)
	assert_false(String(chips[0]["text"]).contains("x1"))


# -- harm and help read differently ---------------------------------------

func test_harm_reads_as_harm_and_help_reads_as_help():
	var harmful := HudReadouts.condition_chips(
		_well_fed(), "walking", [_effect(SpellStatusEffects.IGNITE, 5.0)]
	)
	var helpful := HudReadouts.condition_chips(
		_well_fed(), "walking", [_effect("stamina_regen", 5.0)]
	)
	assert_eq(Color(harmful[0]["color"]), UiTheme.NEGATIVE)
	assert_eq(Color(helpful[0]["color"]), UiTheme.ACCENT)


# -- and the row still behaves ---------------------------------------------

## Nothing riding on you, nothing wrong: the HUD is quiet, which is the
## rule this row already kept.
func test_a_character_with_nothing_on_them_still_gets_a_quiet_row():
	assert_eq(HudReadouts.condition_chips(_well_fed(), "walking", []).size(), 0)


## Every caller that predates the parameter behaves exactly as before.
func test_omitting_the_effects_keeps_the_old_row():
	var meters := _well_fed()
	meters.hunger = 1.0
	assert_eq(
		HudReadouts.chips_signature(HudReadouts.condition_chips(meters, "walking")),
		HudReadouts.chips_signature(HudReadouts.condition_chips(meters, "walking", []))
	)


## A meter problem still outranks a spell: starving is worse news than
## being briefly slowed, and the row must not reorder as effects come and
## go -- the same fixed-order rule the chips already follow.
func test_a_meter_problem_still_comes_first():
	var meters := _well_fed()
	meters.hunger = 1.0
	var chips := HudReadouts.condition_chips(
		meters, "walking", [_effect(SpellStatusEffects.SLOW, 3.0)]
	)
	assert_string_contains(String(chips[0]["text"]), "Starv")


## An id nobody named reads as itself rather than vanishing: a silent chip
## is how an effect goes unnoticed, which is the bug this closes.
func test_an_unnamed_effect_still_shows_up():
	var chips := HudReadouts.condition_chips(_well_fed(), "walking", [_effect("mystery", 4.0)])
	assert_eq(chips.size(), 1)
	assert_string_contains(String(chips[0]["text"]), "mystery")


# -- and the live character really hands them over ------------------------

const PlayerScene = preload("res://scenes/player.tscn")


## One place that gathers every timed thing on this character, so World
## does not have to know which arrays exist -- and so a new kind of buff
## added later reaches the HUD by being listed once rather than by
## somebody remembering to add a fifth argument.
func test_the_character_reports_every_clock_running_on_them():
	var player = PlayerScene.instantiate()
	add_child(player)
	player.apply_venom()
	player.apply_spell_debuff(SpellStatusEffects.IGNITE, 5.0)
	var ids: Array = []
	for effect in player.active_effects():
		ids.append(String(effect["debuff_id"]))
	assert_true(ids.has(VenomModel.DEBUFF_ID), "venom is a clock on the character")
	assert_true(ids.has(SpellStatusEffects.IGNITE), "and so is a burn")
	player.queue_free()


func test_a_character_with_nothing_on_them_reports_nothing():
	var player = PlayerScene.instantiate()
	add_child(player)
	assert_eq(player.active_effects().size(), 0)
	player.queue_free()


## And World really draws them, rather than a builder nobody calls.
func test_the_hud_really_asks_for_them():
	var source := FileAccess.get_file_as_string("res://scenes/world.gd")
	var start := source.find("func _update_condition_chips(")
	assert_gt(start, 0, "precondition: the updater was found")
	var rest := source.substr(start)
	var body := rest.substr(0, rest.find("\nfunc "))
	assert_true(
		body.contains("active_effects()"),
		"the row must ask the character what is riding on them"
	)
