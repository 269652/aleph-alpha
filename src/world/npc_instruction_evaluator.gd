extends RefCounted

## Rule evaluator for the NPC instruction DSL (docs/concept/
## npc_instructions.md, "Script shape" / "Execution / wiring"): steps a
## parsed script's rules top to bottom, evaluating each rule's condition via
## npc_instruction_primitives.gd's registry against a frame, and returns the
## first matching rule's action descriptor (also resolved via
## npc_instruction_primitives.gd) -- "the first rule whose condition holds
## wins," per the concept doc verbatim. A rule with a null condition (the
## "otherwise" catch-all) always matches. Returns null when no rule matches
## at all -- the no-`otherwise`-authored case the concept doc's own Open
## questions section names, left for a caller to fall back on the ordinary
## planner-produced schedule entry.
##
## Pure, no state, no engine dependency: takes the exact
## {"kind": "instruct", "name": ..., "rules": [...]} AST
## npc_instruction_parser.gd already produces, same convention
## npc_instruction_cost.gd's script_cost(ast) already established -- a caller
## can go straight from NpcInstructionParser.parse(source)["ast"] to a
## resolved action.
##
## This is deliberately NOT the {location_tag, activity}-shaped
## NpcInstructionExecutor the concept doc's "Execution / wiring" section
## specifies for NpcMarker._process -- turning a resolved action descriptor
## into a walk target/activity flag is npc_instruction_effects.gd's job, a
## later step. This module only picks which rule fires.

const NpcInstructionPrimitives = preload("res://src/world/npc_instruction_primitives.gd")


## Steps `parsed_script["rules"]` top to bottom; for the first rule whose
## condition is null (an "otherwise") or evaluates true against `frame`,
## returns that rule's action resolved to a descriptor. Returns null if no
## rule matches -- an unauthored "otherwise" is not an error, just "nothing
## fired this tick."
static func evaluate(parsed_script: Dictionary, frame: Dictionary) -> Variant:
	for rule in parsed_script.get("rules", []):
		var condition: Variant = rule.get("condition")
		if condition == null or NpcInstructionPrimitives.evaluate_condition(condition, frame):
			return NpcInstructionPrimitives.resolve_action(rule["action"])
	return null
