extends GutTest

## Red-first spec for the NPC instruction DSL's primitive registry
## (docs/concept/npc_instructions.md): the 2 v1 condition primitives
## (inventory_at_least, need_above) and 2 v1 action primitives (haul,
## gather), as small independently testable pure functions consistent with
## the {"fn": ..., "args": {...}} shape npc_instruction_parser.gd already
## produces for a parsed primitive call.
##
## Conditions take a "frame" Dictionary -- facts already computed elsewhere,
## matching dialogue.md's DialogueContext frame pattern (see
## src/dialogue/dialogue_context.gd) -- and return a bool. Actions return an
## action-descriptor Dictionary, not yet executed against the live world;
## that dispatch is npc_instruction_effects.gd, a later step. The
## rule-evaluation loop itself (walking rules top to bottom) is also a later
## step (npc_instruction_executor.gd) -- this file only pins the primitives.

const NpcInstructionParser = preload("res://src/world/npc_instruction_parser.gd")
const NpcInstructionPrimitives = preload("res://src/world/npc_instruction_primitives.gd")


func _call_for(source: String) -> Dictionary:
	var parser := NpcInstructionParser.new()
	var result: Dictionary = parser.parse(source)
	assert_true(result["ok"], "expected parse to succeed, errors: %s" % [result["errors"]])
	return result["ast"]["rules"][0]


# --- the registry itself, matching the concept doc's catalog -------------------

func test_condition_names_are_the_two_v1_conditions():
	assert_eq(NpcInstructionPrimitives.CONDITION_NAMES, ["inventory_at_least", "need_above"])


func test_action_names_are_the_two_v1_actions():
	assert_eq(NpcInstructionPrimitives.ACTION_NAMES, ["haul", "gather"])


# --- inventory_at_least(item, count) --------------------------------------------

func test_inventory_at_least_is_true_when_the_frame_meets_the_count():
	var frame := {"inventory": {"wood": 20}}
	assert_true(NpcInstructionPrimitives.inventory_at_least({"item": "wood", "count": 20}, frame))


func test_inventory_at_least_is_true_when_the_frame_exceeds_the_count():
	var frame := {"inventory": {"wood": 25}}
	assert_true(NpcInstructionPrimitives.inventory_at_least({"item": "wood", "count": 20}, frame))


func test_inventory_at_least_is_false_when_the_frame_falls_short():
	var frame := {"inventory": {"wood": 19}}
	assert_false(NpcInstructionPrimitives.inventory_at_least({"item": "wood", "count": 20}, frame))


func test_inventory_at_least_reads_a_missing_item_as_zero_not_an_error():
	var frame := {"inventory": {"stone": 5}}
	assert_false(NpcInstructionPrimitives.inventory_at_least({"item": "wood", "count": 1}, frame))


func test_inventory_at_least_reads_a_missing_inventory_key_as_empty():
	assert_false(NpcInstructionPrimitives.inventory_at_least({"item": "wood", "count": 1}, {}))


# --- need_above(need, threshold) ------------------------------------------------

func test_need_above_is_true_when_the_need_exceeds_the_threshold():
	var frame := {"needs": {"hunger": 0.8}}
	assert_true(NpcInstructionPrimitives.need_above({"need": "hunger", "threshold": 0.7}, frame))


func test_need_above_is_false_when_the_need_is_exactly_at_the_threshold():
	# "above" is strict -- a need sitting exactly on the threshold has not
	# yet crossed it.
	var frame := {"needs": {"hunger": 0.7}}
	assert_false(NpcInstructionPrimitives.need_above({"need": "hunger", "threshold": 0.7}, frame))


func test_need_above_is_false_when_the_need_falls_short():
	var frame := {"needs": {"hunger": 0.3}}
	assert_false(NpcInstructionPrimitives.need_above({"need": "hunger", "threshold": 0.7}, frame))


func test_need_above_reads_a_missing_need_as_zero_not_urgent():
	var frame := {"needs": {"thirst": 0.9}}
	assert_false(NpcInstructionPrimitives.need_above({"need": "hunger", "threshold": 0.1}, frame))


func test_need_above_reads_a_missing_needs_key_as_empty():
	assert_false(NpcInstructionPrimitives.need_above({"need": "hunger", "threshold": 0.0}, {}))


# --- haul(item, destination_tag) ------------------------------------------------

func test_haul_returns_a_descriptor_naming_the_item_and_destination():
	var descriptor: Dictionary = NpcInstructionPrimitives.haul({"item": "wood", "destination_tag": "base"})
	assert_eq(descriptor, {"fn": "haul", "item": "wood", "destination_tag": "base"})


# --- gather(resource_tag) --------------------------------------------------------

func test_gather_returns_a_descriptor_naming_the_resource_tag():
	var descriptor: Dictionary = NpcInstructionPrimitives.gather({"resource_tag": "berries"})
	assert_eq(descriptor, {"fn": "gather", "resource_tag": "berries"})


# --- dispatch, fed real parser output --------------------------------------------
#
# Not hand-built {"fn":..., "args":...} literals -- the actual AST
# npc_instruction_parser.gd produces from source text, so this pins the
# primitives module against the real contract the parser emits rather than
# an assumption about it.

func test_evaluate_condition_dispatches_inventory_at_least_from_real_parser_output():
	var rule := _call_for("instruct \"X\" { if inventory_at_least(wood, 20): gather(wood) }")
	var frame := {"inventory": {"wood": 20}}
	assert_true(NpcInstructionPrimitives.evaluate_condition(rule["condition"], frame))
	assert_false(NpcInstructionPrimitives.evaluate_condition(rule["condition"], {"inventory": {"wood": 0}}))


func test_evaluate_condition_dispatches_need_above_from_real_parser_output():
	var rule := _call_for("instruct \"X\" { if need_above(hunger, 0.7): gather(berries) }")
	assert_true(NpcInstructionPrimitives.evaluate_condition(rule["condition"], {"needs": {"hunger": 0.9}}))
	assert_false(NpcInstructionPrimitives.evaluate_condition(rule["condition"], {"needs": {"hunger": 0.1}}))


func test_resolve_action_dispatches_haul_from_real_parser_output():
	var rule := _call_for("instruct \"X\" { otherwise: haul(wood, base) }")
	assert_eq(
		NpcInstructionPrimitives.resolve_action(rule["action"]),
		{"fn": "haul", "item": "wood", "destination_tag": "base"}
	)


func test_resolve_action_dispatches_gather_from_real_parser_output():
	var rule := _call_for("instruct \"X\" { otherwise: gather(berries) }")
	assert_eq(
		NpcInstructionPrimitives.resolve_action(rule["action"]),
		{"fn": "gather", "resource_tag": "berries"}
	)


# --- fail-closed on an unrecognised call, never a crash --------------------------

func test_evaluate_condition_fails_closed_on_an_unknown_fn():
	assert_false(NpcInstructionPrimitives.evaluate_condition({"fn": "teleport", "args": {}}, {}))


func test_resolve_action_fails_closed_on_an_unknown_fn():
	assert_eq(NpcInstructionPrimitives.resolve_action({"fn": "dance", "args": {}}), {})
