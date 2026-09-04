extends RefCounted

## Primitive registry for the NPC instruction DSL (docs/concept/
## npc_instructions.md): the 2 v1 condition primitives (inventory_at_least,
## need_above) and 2 v1 action primitives (haul, gather), as small
## independently testable pure functions -- one per primitive, plus a
## dispatcher for each kind that reads the exact {"fn": ..., "args": {...}}
## shape npc_instruction_parser.gd already produces for a parsed primitive
## call. Nothing here executes anything against the live world; the
## rule-evaluation loop (npc_instruction_executor.gd) and the impure
## haul/gather dispatch against a real NpcMarker/World
## (npc_instruction_effects.gd) are both later steps.
##
## Conditions take a "frame" Dictionary and return a bool. `frame` matches
## dialogue.md's DialogueContext frame pattern (src/dialogue/
## dialogue_context.gd): a flat Dictionary of already-computed facts, no
## live Object anywhere in it, built the same way CreatureBehavior.decide's
## own `context` is (src/gameplay/creature_behavior.gd). Two keys are read
## here:
##   inventory  Dictionary, item_id -> int count (same item_id -> count
##              shape DialogueContext's own `player_carrying` field uses)
##   needs      Dictionary, need_name -> float 0..1 (the NpcNeeds-shaped
##              signal the concept doc names, e.g. {"hunger": 0.8})
## Both keys are optional and absent reads as empty -- the same
## fail-open/empty-is-not-an-error convention DialogueContext's own doc
## comment states explicitly: an NPC with no measured inventory of an item
## genuinely has none, and an unmeasured need is not treated as urgent.
##
## Actions return an action-descriptor Dictionary, not yet executed.

## Every condition primitive name, in the concept doc's own listed order.
const CONDITION_NAMES: Array[String] = ["inventory_at_least", "need_above"]

## Every action primitive name, in the concept doc's own listed order.
const ACTION_NAMES: Array[String] = ["haul", "gather"]


## inventory_at_least(item, count): true if the NPC's/household's inventory
## count of `item` is >= `count`, per the concept doc verbatim.
static func inventory_at_least(args: Dictionary, frame: Dictionary) -> bool:
	var inventory: Dictionary = frame.get("inventory", {})
	var have := int(inventory.get(String(args["item"]), 0))
	return have >= int(args["count"])


## need_above(need, threshold): true if the named need is strictly above
## `threshold`, per the concept doc verbatim ("is above threshold") -- a
## need sitting exactly on the threshold has not yet crossed it.
static func need_above(args: Dictionary, frame: Dictionary) -> bool:
	var needs: Dictionary = frame.get("needs", {})
	var value := float(needs.get(String(args["need"]), 0.0))
	return value > float(args["threshold"])


## haul(item, destination_tag): go fetch the nearest source of `item` and
## carry it to `destination_tag`. Only describes the intent -- turning this
## into a real inventory/position change is npc_instruction_effects.gd.
static func haul(args: Dictionary) -> Dictionary:
	return {
		"fn": "haul",
		"item": String(args["item"]),
		"destination_tag": String(args["destination_tag"]),
	}


## gather(resource_tag): go to the nearest instance of `resource_tag` and
## perform its default gather action. Same not-yet-executed contract as haul.
static func gather(args: Dictionary) -> Dictionary:
	return {
		"fn": "gather",
		"resource_tag": String(args["resource_tag"]),
	}


## Evaluates a parsed condition call -- the AST's own {"fn": ..., "args":
## {...}} shape -- against `frame`. A null call (an "otherwise" rule's
## condition) is never passed here; the rule-evaluation loop short-circuits
## that case itself, upstream of this dispatcher. An unrecognised `fn` fails
## closed to false rather than crashing, the same never-crash convention
## npc_instruction_parser.gd's own error handling already establishes --
## though in practice every call reaching here already passed that parser's
## own primitive-name/kind validation.
static func evaluate_condition(call: Dictionary, frame: Dictionary) -> bool:
	match call["fn"]:
		"inventory_at_least":
			return inventory_at_least(call["args"], frame)
		"need_above":
			return need_above(call["args"], frame)
	return false


## Resolves a parsed action call into an action descriptor. Same fail-closed
## convention as evaluate_condition: an unrecognised `fn` returns an empty
## Dictionary rather than crashing.
static func resolve_action(call: Dictionary) -> Dictionary:
	match call["fn"]:
		"haul":
			return haul(call["args"])
		"gather":
			return gather(call["args"])
	return {}
