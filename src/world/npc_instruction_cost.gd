extends RefCounted

## Complexity-budget cost model for the NPC instruction DSL (docs/concept/
## npc_instructions.md, "Complexity budget"). Computes ONE deterministic
## number from a parsed script's AST alone -- rule count, which primitives
## each rule calls, and how privileged/rare the resource each primitive
## names is. Nothing in the DSL's own grammar can set this number directly;
## it is derived, the same "cost is derived, never authored" contract
## spell_cost.gd already enforces for the magic DSL (docs/concept/magic.md,
## "Constraint layer 1").
##
## Three cost terms, matching the concept doc's own three bullets under
## "Complexity budget" verbatim:
##   - RULE_WEIGHT: a flat per-rule charge, independent of what the rule
##     does -- a longer script costs more purely for having more branches.
##   - CONDITION_WEIGHT / ACTION_WEIGHT: a per-primitive-kind base weight.
##     Actions cost more than conditions -- a script that *does* more kinds
##     of work is a materially smarter hire than one that only checks facts
##     before doing the one thing it always does.
##   - _RESOURCE_RARITY: a multiplier on the resource/item/tag a primitive's
##     own argument names -- hauling gold costs more than hauling wood, the
##     "rarer atoms cost more" lever spell_atom_catalog.gd's tiering already
##     applies to spells. This table stands in for the concept doc's own
##     npc_instruction_catalog.gd, which is not yet a separate module; when
##     it exists this table moves there and this file reads it instead.
##
## No cap/reject enforcement lives here -- this file only derives the
## number. Checking it against a trust-derived ceiling is hiring_gate.gd, a
## later step (concept doc: "What the number gates against is not a
## per-cast resource").
##
## Pure, no state, no engine dependency: takes the exact
## {"kind": "instruct", "name": ..., "rules": [...]} AST
## npc_instruction_parser.gd already produces.

## Flat weight every rule contributes, regardless of what it does.
const RULE_WEIGHT := 1.0

## Base weight for a condition primitive call (checking a fact).
const CONDITION_WEIGHT := 0.5

## Base weight for an action primitive call (doing work) -- deliberately
## higher than CONDITION_WEIGHT, per the concept doc's "action primitives
## weigh more than condition primitives."
const ACTION_WEIGHT := 1.5

## Rarity multiplier applied to a primitive call's resource/item/tag
## argument. An id with no entry here reads as DEFAULT_RESOURCE_RARITY --
## an unlisted resource is common, not free and not an error.
const DEFAULT_RESOURCE_RARITY := 1.0

const _RESOURCE_RARITY := {
	"wood": 1.0,
	"berries": 1.0,
	"stone": 1.2,
	"iron": 1.5,
	"gold": 2.0,
}

## Which arg key names the rarity-relevant resource/item/tag for each
## primitive fn. need_above deliberately has no entry -- a need name
## (hunger, ...) is not a resource and never carries a rarity multiplier.
const _RESOURCE_ARG := {
	"inventory_at_least": "item",
	"haul": "item",
	"gather": "resource_tag",
}


## Rarity multiplier for one resource/item/tag id. An unknown id reads as
## DEFAULT_RESOURCE_RARITY -- common, not an error.
static func resource_rarity(resource_id: String) -> float:
	return _RESOURCE_RARITY.get(resource_id, DEFAULT_RESOURCE_RARITY)


## Rarity multiplier for a parsed primitive call ({"fn": ..., "args": {...}})
## -- reads whichever arg key _RESOURCE_ARG says names this fn's resource,
## or DEFAULT_RESOURCE_RARITY if this fn has no rarity-relevant argument.
static func primitive_rarity_multiplier(call: Dictionary) -> float:
	var fn: String = String(call.get("fn", ""))
	if not _RESOURCE_ARG.has(fn):
		return DEFAULT_RESOURCE_RARITY
	var args: Dictionary = call.get("args", {})
	var arg_key: String = _RESOURCE_ARG[fn]
	return resource_rarity(String(args.get(arg_key, "")))


## Cost of one rule's condition call. A null condition (the "otherwise"
## catch-all) costs nothing -- there is no fact being checked.
static func condition_cost(call: Variant) -> float:
	if call == null:
		return 0.0
	return CONDITION_WEIGHT * primitive_rarity_multiplier(call)


## Cost of one rule's action call. Every rule has exactly one -- the grammar
## has no null-action case.
static func action_cost(call: Dictionary) -> float:
	return ACTION_WEIGHT * primitive_rarity_multiplier(call)


## Cost of one full rule: the flat per-rule charge plus its condition and
## action costs.
static func rule_cost(rule: Dictionary) -> float:
	return RULE_WEIGHT + condition_cost(rule.get("condition")) + action_cost(rule["action"])


## The whole script's complexity: the sum of every rule's cost. Takes the
## parser's own AST shape ({"rules": [...]}) directly.
static func script_cost(ast: Dictionary) -> float:
	var total := 0.0
	for rule in ast.get("rules", []):
		total += rule_cost(rule)
	return total
