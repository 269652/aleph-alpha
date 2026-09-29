extends GutTest

## Nothing may take your health without telling you (docs/concept/feedback.md,
## "Being hurt is a verb too").
##
## Reported from play: *"I constantly die out of nowhere."*
##
## There are exactly two doors into the player's health. `take_damage` is the
## blow, and it answers -- a flash, a number, a screen tint.
## `take_tick_damage` is continuous harm, and it answers **nothing**, on
## purpose: a receipt every frame is a buzz rather than an answer, which is
## the exact failure `REFLEX_INTERVAL_SECONDS` exists to name.
##
## feedback.md resolves that deliberately and in so many words: *"A poison is
## a CONDITION, and this HUD already shows conditions as chips. So `hurt`
## fires on the discrete blow and nothing else, and the chip carries the
## rest."*
##
## So the contract is: **every continuous harm carries a chip.** Measured, one
## did not. `Player.active_effects()` gathers venom, spell debuffs, food buffs
## and the shield -- and never `active_mushroom_toxin_debuffs`, although that
## state is tracked, ticked, and already in the identical DebuffStack shape.
## Eat a Death Cap and your health drains with no receipt and no chip: nothing
## on screen names it, and you die of something you were never told about.
##
## This suite pins the contract itself rather than that one omission, so the
## next continuous harm cannot be added without its chip.

const PlayerScene = preload("res://scenes/player.tscn")
const MushroomToxin = preload("res://src/gameplay/mushroom_toxin.gd")
const SpellStatusEffects = preload("res://src/gameplay/spell_status_effects.gd")
const VenomModel = preload("res://src/gameplay/venom_model.gd")
const HudReadouts = preload("res://src/ui/hud_readouts.gd")

var player


func before_each():
	player = PlayerScene.instantiate()
	add_child(player)


func after_each():
	player.queue_free()


func _named_effects() -> Array:
	var ids: Array = []
	for effect in player.active_effects():
		ids.append(String(effect.get("debuff_id", "")))
	return ids


# -- the contract ----------------------------------------------------------

## The heart of it, and the one that was broken.
func test_a_poisoned_character_is_told_they_are_poisoned():
	player.apply_mushroom_toxin("death_cap")
	assert_true(
		_named_effects().has(MushroomToxin.DEBUFF_ID),
		"a toxin draining your health must name itself on the HUD"
	)


## The chip has to carry a clock too, or it says "something is wrong" without
## saying how long -- the thing every other chip in the row does.
func test_the_poison_chip_says_how_long_is_left():
	player.apply_mushroom_toxin("death_cap")
	for effect in player.active_effects():
		if String(effect.get("debuff_id", "")) == MushroomToxin.DEBUFF_ID:
			assert_gt(
				float(effect.get("time_remaining", 0.0)), 0.0,
				"a poison with a clock must show its clock"
			)
			return
	fail_test("the toxin never reached the row at all")


## And it counts, the way venom does: a second bad mushroom is worse, not
## merely longer.
func test_a_twice_poisoned_character_is_told_it_is_worse():
	player.apply_mushroom_toxin("death_cap")
	player.apply_mushroom_toxin("death_cap")
	for effect in player.active_effects():
		if String(effect.get("debuff_id", "")) == MushroomToxin.DEBUFF_ID:
			assert_gt(int(effect.get("stacks", 0)), 1, "two doses must read as two")
			return
	fail_test("the toxin never reached the row at all")


# -- and the contract in general -------------------------------------------

## The drift guard. Every continuous harm the character can suffer must name
## itself, so the next one cannot be added silently. Each is applied through
## the real verb that inflicts it in the running game.
func test_every_continuous_harm_names_itself_on_the_hud():
	var applied := {
		VenomModel.DEBUFF_ID: func(): player.apply_venom(),
		MushroomToxin.DEBUFF_ID: func(): player.apply_mushroom_toxin("death_cap"),
		SpellStatusEffects.IGNITE: func(): player.apply_spell_debuff(SpellStatusEffects.IGNITE, 8.0),
		SpellStatusEffects.BLIGHT: func(): player.apply_spell_debuff(SpellStatusEffects.BLIGHT, 8.0),
	}
	for debuff_id in applied:
		applied[debuff_id].call()
	var named := _named_effects()
	for debuff_id in applied:
		assert_true(
			named.has(debuff_id),
			"%s takes health every frame, so it must appear on the HUD" % debuff_id
		)


## A character with nothing on them says nothing -- the row is information,
## not decoration.
func test_an_unharmed_character_wears_nothing():
	assert_eq(player.active_effects().size(), 0)


# -- and the chip reads as a word ------------------------------------------

## `effect_chip` falls back to the raw debuff id for anything unnamed, which
## is the safe direction -- an unnamed effect reads as itself rather than
## vanishing -- but "mushroom_toxin 42s" is a variable name on a player's
## HUD, not a sentence. Every other harm in the table has a word.
func test_the_poison_chip_reads_as_a_word_not_an_identifier():
	assert_true(
		HudReadouts.EFFECT_LABELS.has(MushroomToxin.DEBUFF_ID),
		"a toxin that can kill you deserves a name on the row"
	)
	var chip: Dictionary = HudReadouts.effect_chip({
		"debuff_id": MushroomToxin.DEBUFF_ID, "stacks": 1, "time_remaining": 42.0
	})
	assert_false(
		String(chip.get("text", "")).contains("_"),
		"a debuff id leaking onto the HUD reads as a bug to a player"
	)


## And it reads as harm rather than as good news -- the colour is the first
## thing a player takes off the row.
func test_the_poison_chip_reads_as_harm():
	assert_false(
		HudReadouts.HELPFUL_EFFECTS.has(MushroomToxin.DEBUFF_ID),
		"being poisoned is not good news"
	)
