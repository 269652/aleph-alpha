extends GutTest

## "Why can't this chop?" -- the legibility surface over the item compiler.
##
## An emergent system whose failures are silent is an unlearnable black box. A
## player who is told "your saw cannot chop" and nothing else has to guess; a
## player told it is the plate's mass has learned something true about the model
## and can act on it. That is why this is a feature with tests rather than a
## debug aid.

var AffordanceNotes: GDScript = preload("res://src/gameplay/affordance_notes.gd")
var ItemCompiler: GDScript = preload("res://src/gameplay/item_compiler.gd")
var Assemblies: GDScript = preload("res://tests/fixtures/assembly_fixtures.gd")


## THE test this file exists for. A saw has excellent teeth. They are not the
## reason it cannot chop, and a note that blamed them would teach the player
## something false.
func test_absence_reason_for_chop_on_a_saw_names_head_mass_not_teeth() -> void:
	var reason: String = AffordanceNotes.absence_reason(Assemblies.rip_saw(), "chop")
	assert_string_contains(reason, "mass")
	assert_false(reason.contains("tooth"), reason)
	assert_false(reason.contains("teeth"), reason)


func test_an_afforded_verb_has_no_absence_reason() -> void:
	assert_eq(AffordanceNotes.absence_reason(Assemblies.rip_saw(), "rip"), "")
	assert_eq(AffordanceNotes.absence_reason(Assemblies.felling_axe(), "chop"), "")


## An assembly that is not an item at all answers with THAT, rather than with a
## verb-shaped reason that would imply it was nearly a tool.
func test_something_that_is_not_an_item_says_so_instead_of_blaming_the_verb() -> void:
	var reason: String = AffordanceNotes.absence_reason(Assemblies.headless_edge(), "cut")
	assert_string_contains(reason, "grip")


func test_a_verb_the_compiler_does_not_know_says_so() -> void:
	var reason: String = AffordanceNotes.absence_reason(Assemblies.sword(), "photosynthesize")
	assert_string_contains(reason, "photosynthesize")


## The positive counterpart, and the exact call a player.gd bridge would make in
## place of Item.is_saw(). It must never disagree with the compiler it reads.
func test_affords_agrees_with_the_compiler() -> void:
	for graph in [
		Assemblies.sword(), Assemblies.felling_axe(), Assemblies.rip_saw(),
		Assemblies.obsidian_sword(), Assemblies.headless_edge(),
	]:
		var afforded: Array = ItemCompiler.compile(graph, 1.0)["affordances"]
		for verb in ItemCompiler.VERBS:
			assert_eq(AffordanceNotes.affords(graph, verb), afforded.has(verb),
				"'%s' must mean the same thing to both" % verb)
			assert_ne(AffordanceNotes.affords(graph, verb),
				AffordanceNotes.absence_reason(graph, verb) != "",
				"a verb is afforded or explained, never both")
