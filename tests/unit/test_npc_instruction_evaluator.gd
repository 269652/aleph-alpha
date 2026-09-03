extends GutTest

## Red-first spec for the NPC instruction DSL's rule evaluator (docs/concept/
## npc_instructions.md, "Execution / wiring"): steps a parsed script's rules
## top-to-bottom, evaluating each rule's condition via
## npc_instruction_primitives.gd's registry against a frame, and returns the
## first matching rule's action descriptor (also resolved via
## npc_instruction_primitives.gd), or null once nothing matches -- the "first
## rule whose condition holds wins" contract the concept doc's own "Script
## shape" section states verbatim. Pure -- no engine dependency, Dictionary/
## Array in, Dictionary or null out.
##
## This is deliberately NOT the {location_tag, activity}-shaped
## NpcInstructionExecutor the concept doc's "Execution / wiring" section
## specifies for NpcMarker._process -- turning an action descriptor into a
## walk target is a later step (npc_instruction_effects.gd's spatial
## queries). This module only picks which rule fires.
##
## Reproduces npc.md's own worked example end-to-end (concept doc, Design
## pillar 2: "if inventory has >20 wood, haul to base; otherwise chop nearest
## tree"), mapped onto the v1 primitives, for both branches.

const NpcInstructionParser = preload("res://src/world/npc_instruction_parser.gd")
const NpcInstructionEvaluator = preload("res://src/world/npc_instruction_evaluator.gd")

const HAUL_AND_FORAGE := (
	"instruct \"haul_and_forage\" {\n"
	+ "    if inventory_at_least(wood, 20): haul(wood, base)\n"
	+ "    otherwise: gather(tree)\n"
	+ "}"
)


## Parses real DSL source text and returns the AST -- the same convention
## test_npc_instruction_primitives.gd and test_npc_instruction_cost.gd both
## already use -- so this pins the evaluator against the parser's actual
## emitted contract, not a hand-built AST literal.
func _ast_for(source: String) -> Dictionary:
	var parser := NpcInstructionParser.new()
	var result: Dictionary = parser.parse(source)
	assert_true(result["ok"], "expected parse to succeed, errors: %s" % [result["errors"]])
	return result["ast"]


# --- npc.md's own worked example, both branches, end-to-end -------------------

func test_the_condition_branch_hauls_when_inventory_meets_the_threshold():
	var ast := _ast_for(HAUL_AND_FORAGE)
	var action: Variant = NpcInstructionEvaluator.evaluate(ast, {"inventory": {"wood": 20}})
	assert_eq(action, {"fn": "haul", "item": "wood", "destination_tag": "base"})


func test_the_otherwise_branch_gathers_when_inventory_falls_short():
	var ast := _ast_for(HAUL_AND_FORAGE)
	var action: Variant = NpcInstructionEvaluator.evaluate(ast, {"inventory": {"wood": 5}})
	assert_eq(action, {"fn": "gather", "resource_tag": "tree"})


func test_an_empty_frame_falls_through_to_the_otherwise_rule():
	# No "inventory" key at all -- reads as zero, same fail-open convention
	# npc_instruction_primitives.gd's own tests already pin.
	var ast := _ast_for(HAUL_AND_FORAGE)
	var action: Variant = NpcInstructionEvaluator.evaluate(ast, {})
	assert_eq(action, {"fn": "gather", "resource_tag": "tree"})


# --- selection mechanics -------------------------------------------------------

func test_the_first_matching_rule_wins_over_a_later_matching_one():
	var ast := _ast_for(
		"instruct \"X\" {\n"
		+ "    if inventory_at_least(wood, 1): gather(wood)\n"
		+ "    if inventory_at_least(wood, 1): gather(stone)\n"
		+ "    otherwise: gather(iron)\n"
		+ "}"
	)
	var action: Variant = NpcInstructionEvaluator.evaluate(ast, {"inventory": {"wood": 5}})
	assert_eq(action, {"fn": "gather", "resource_tag": "wood"})


func test_a_later_rule_fires_when_an_earlier_one_does_not_match():
	var ast := _ast_for(
		"instruct \"X\" {\n"
		+ "    if inventory_at_least(wood, 20): haul(wood, base)\n"
		+ "    if need_above(hunger, 0.7): gather(berries)\n"
		+ "    otherwise: gather(wood)\n"
		+ "}"
	)
	var action: Variant = NpcInstructionEvaluator.evaluate(
		ast, {"inventory": {"wood": 0}, "needs": {"hunger": 0.9}}
	)
	assert_eq(action, {"fn": "gather", "resource_tag": "berries"})


func test_returns_null_when_no_rule_matches_and_there_is_no_otherwise():
	var ast := _ast_for("instruct \"X\" { if inventory_at_least(wood, 20): haul(wood, base) }")
	var action: Variant = NpcInstructionEvaluator.evaluate(ast, {"inventory": {"wood": 0}})
	assert_null(action)
