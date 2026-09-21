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
