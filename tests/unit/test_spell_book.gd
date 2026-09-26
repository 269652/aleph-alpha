extends GutTest

## A small, fixed table of pre-authored example spells (docs/concept/
## spell_runtime.md's "fixed example spellbook, not a spell-authoring UI") --
## the same role ItemCatalog._ITEMS played before any crafting UI existed.

const SpellBook = preload("res://src/gameplay/spell_book.gd")
const SpellExecutor = preload("res://src/gameplay/spell_executor.gd")

var book := SpellBook.new()


func test_has_returns_true_for_a_known_spell():
	assert_true(book.has("fire_bolt"))


func test_has_returns_false_for_an_unknown_spell():
	assert_false(book.has("not_a_real_spell"))


func test_ast_for_returns_null_for_an_unknown_spell():
	assert_null(book.ast_for("not_a_real_spell"))


## Every entry must actually parse -- a real regression guard: if someone
## edits _SOURCES and typos the DSL text, this fails loudly instead of the
## spell silently becoming uncastable in play.
func test_every_known_spell_parses_into_a_real_castable_cast_rule():
	var executor := SpellExecutor.new()
	for spell_id in book.known_ids():
		var ast = book.ast_for(spell_id)
		assert_not_null(ast, "%s must parse" % spell_id)
		assert_eq(ast.get("kind", ""), "spell", "%s must be a spell block" % spell_id)
		var rule = executor.cast_rule(ast)
		assert_not_null(rule, "%s must have a real 'on cast' rule" % spell_id)
		assert_gt(executor.cost_for(rule), 0.0, "%s must cost real mana -- no atom is ever free" % spell_id)


func test_ast_for_is_cached_across_calls():
	assert_same(book.ast_for("fire_bolt"), book.ast_for("fire_bolt"))


func test_known_ids_lists_every_source_spell():
	assert_true(book.known_ids().size() >= 3)
	assert_true(book.known_ids().has("fire_bolt"))


## The name a player reads, from the spell's own source rather than from a
## second table beside it.
##
## Every entry already declares one -- `spell "Frost Lance" { ... }` -- and
## the parser already carries it on the AST, but nothing could ask for it:
## the spell bar would have had to print `frost_lance` or keep its own list
## of prettier strings, and a second list is how two names drift apart.
func test_a_spell_knows_what_it_is_called():
	assert_eq(SpellBook.new().name_for("frost_lance"), "Frost Lance")


func test_every_authored_spell_has_a_real_name():
	var book := SpellBook.new()
	for spell_id in book.known_ids():
		var spell_name: String = book.name_for(String(spell_id))
		assert_ne(spell_name, "", "%s has no name" % spell_id)
		assert_ne(spell_name, spell_id, "%s reads as its own id" % spell_id)


## An id nobody authored reads as itself rather than as an empty box: a
## caller that got here has a bug, and a blank slot hides it.
func test_an_unknown_id_reads_as_itself():
	assert_eq(SpellBook.new().name_for("not_a_spell"), "not_a_spell")


# -- Fire Bolt's damage, measured against a real wolf (2026-09-26) ----------
#
# Reported live as too weak: at the original magnitude (8), a wolf took
# ~14 casts to fell. Measured, not assumed, against CreatureInfo's own
# health formula across every level a wolf can roll -- a wolf-tuning
# change elsewhere would otherwise silently drift this claim false with
# nothing to catch it, the same reasoning CombatPacing.EXCHANGE_HEALTH_
# SCALE's own test-pinning already uses for melee's "two landed bites"
# rule.

const CreatureInfo = preload("res://src/world/creature_info.gd")
const ClassArchetype = preload("res://src/gameplay/class_archetype.gd")


func _fire_bolt_magnitude() -> float:
	var executor := SpellExecutor.new()
	var rule = executor.cast_rule(book.ast_for("fire_bolt"))
	for step in rule.get("pipeline", []):
		if step.get("atom", "") == "fire_damage":
			return float(step.get("params", {}).get("magnitude", 0.0))
	return 0.0


func test_fire_bolt_kills_any_level_wolf_within_three_casts():
	var magnitude := _fire_bolt_magnitude()
	assert_gt(magnitude, 0.0, "fire_bolt must actually cast fire_damage")
	for level_seed in range(CreatureInfo.LEVEL_RANGE):
		var wolf := CreatureInfo.new("wolf", level_seed)
		var casts_to_kill := int(ceil(wolf.max_health / magnitude))
		assert_true(
			casts_to_kill <= 3,
			(
				"a level %d wolf (%.1f hp) should die within 3 Fire Bolts, needs %d"
				% [wolf.level, wolf.max_health, casts_to_kill]
			)
		)


## The other half of the same claim: a real fireball must still be
## something a starting mage can actually cast more than once, not a
## single-shot nuke that empties their whole pool (spell_cost.gd's
## magnitude exponent is deliberately superlinear, so a naive damage bump
## alone would have made this uncastable -- see fire_damage's own mag_ref
## in spell_atom_catalog.gd).
func test_fire_bolt_leaves_a_starting_mage_room_to_recast():
	var executor := SpellExecutor.new()
	var cost := executor.cost_for(executor.cast_rule(book.ast_for("fire_bolt")))
	var mage_max_mana: float = ClassArchetype.new().stats_for("mage")["max_mana"]
	assert_lt(cost, mage_max_mana / 2.0, "Fire Bolt must leave a starting mage room for at least one more cast")
