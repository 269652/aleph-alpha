extends GutTest

## Order is the craft -- and it changed nothing at all.
##
## `docs/concept/spell_weaving.md`'s fifth design pillar is *"Order is the
## craft. Adjacent motes react, and the reactions scale magnitude at
## resolution"*, and its own table prices five of them: a conflagration at
## 1.50, a conduction at 1.40, a flash freeze at 1.35, steam at 1.25, a
## quench at 0.70.
##
## Measured: `SpellDraft.reaction_multiplier` had exactly **one** caller --
## `scenes/spell_weave_window.gd`, which PRINTS the reactions. `cast_woven`
## parsed the draft, ran the pipeline and never asked. So the Weave window
## told a player that arranging fire before ignite made a conflagration,
## and arranging it made no difference whatever to what the spell did.
##
## Which also means the quench was free: putting frost after fire is
## supposed to cost you thirty percent of your spell, and it cost nothing.

const SpellDraft = preload("res://src/gameplay/spell_draft.gd")
const PlayerScene = preload("res://scenes/player.tscn")


# -- the rule, pure -------------------------------------------------------

## What "scales the effect" means for an atom that has a magnitude, and for
## one that has only a duration: a conflagration burns harder, a flash
## freeze holds longer. One rule, and never both for one atom -- an atom
## carrying a magnitude AND a duration would otherwise be scaled twice for
## a single reaction.
func test_a_magnitude_is_what_scales_when_there_is_one():
	var scaled: Dictionary = SpellDraft.scaled_params({"magnitude": 6.0}, 1.5)
	assert_almost_eq(float(scaled["magnitude"]), 9.0, 0.0001)


func test_a_duration_scales_when_there_is_no_magnitude():
	var scaled: Dictionary = SpellDraft.scaled_params({"duration": 4.0}, 1.5)
	assert_almost_eq(float(scaled["duration"]), 6.0, 0.0001)


func test_an_atom_with_both_is_scaled_once_and_on_its_magnitude():
	var scaled: Dictionary = SpellDraft.scaled_params({"magnitude": 6.0, "duration": 4.0}, 1.5)
	assert_almost_eq(float(scaled["magnitude"]), 9.0, 0.0001)
	assert_almost_eq(float(scaled["duration"]), 4.0, 0.0001, "scaled once, not twice")


func test_a_row_that_reacted_with_nothing_changes_nothing():
	var params := {"magnitude": 6.0, "duration": 4.0}
	assert_eq(SpellDraft.scaled_params(params, 1.0), params)


func test_an_atom_with_neither_survives_untouched():
	assert_eq(SpellDraft.scaled_params({"target": "self"}, 1.5), {"target": "self"})


## The caller is never handed the dictionary it passed in: a scaled step
## must not rewrite the draft it came from.
func test_the_original_is_left_alone():
	var params := {"magnitude": 6.0}
	SpellDraft.scaled_params(params, 2.0)
	assert_almost_eq(float(params["magnitude"]), 6.0, 0.0001)


# -- and the cast really uses it ------------------------------------------

## The five reactions the table prices, and the one that is a penalty.
func test_the_table_really_prices_an_order():
	var hot := {"atoms": ["fire_damage", "ignite"], "delivery": "touch"}
	var quenched := {"atoms": ["fire_damage", "frost_damage"], "delivery": "touch"}
	assert_gt(SpellDraft.reaction_multiplier(hot), 1.0, "a conflagration is a bonus")
	assert_lt(SpellDraft.reaction_multiplier(quenched), 1.0, "a quench is a penalty")


## Through the real cast path, not the pure rule: the resolution layer has
## to ask, and it never did.
func test_the_cast_scales_its_steps_by_the_reaction_it_earned():
	var body := _function_body("cast_woven")
	assert_false(body.is_empty(), "precondition: cast_woven was found")
	assert_true(
		body.contains("SpellDraft.reaction_multiplier(_woven_draft)"),
		"the order a player arranged must reach the spell they cast"
	)
	assert_true(
		body.contains("SpellDraft.scaled_params("),
		"and it must scale the steps, not merely be computed"
	)


## An authored spell from the book is NOT reordered by anybody, so it has
## no reaction to earn and must not be quietly scaled by one.
func test_an_authored_spell_is_not_scaled():
	var body := _function_body("cast_spell")
	assert_false(
		body.contains("reaction_multiplier"),
		"a spell nobody arranged has no order to be paid for"
	)


func _function_body(name: String) -> String:
	var source := FileAccess.get_file_as_string("res://scenes/player.gd")
	var start := source.find("func %s(" % name)
	if start < 0:
		return ""
	var rest := source.substr(start)
	var next := rest.find("\nfunc ")
	return rest if next < 0 else rest.substr(0, next)
