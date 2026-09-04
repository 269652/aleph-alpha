extends GutTest

## Red-first spec for the NPC instruction DSL parser (docs/concept/
## npc_instructions.md): turns player-written instruction scripts into the
## canonical AST -- plain Godot Dictionaries/Arrays -- that
## npc_instruction_cost.gd and npc_instruction_executor.gd will consume once
## they exist. Parsing only -- no evaluation/execution here.
##
## Unlike spell_parser.gd (purely structural, atom legality left to a later
## validator), the instruction grammar's args are positional
## (`inventory_at_least(wood, 20)`), and the concept doc's AST contract wants
## them *named* (`{"item": "wood", "count": 20}`). Turning one into the other
## requires knowing each primitive's own signature, so this parser fails
## closed on an unknown primitive name, a condition/action used in the wrong
## slot, or a wrong arg count/type -- never a crash, never silently accepted.

const NpcInstructionParser = preload("res://src/world/npc_instruction_parser.gd")

var parser: NpcInstructionParser


func before_each():
	parser = NpcInstructionParser.new()


func _ast(source: String) -> Dictionary:
	var result: Dictionary = parser.parse(source)
	assert_true(result["ok"], "expected parse to succeed, errors: %s" % [result["errors"]])
	return result["ast"]


func _assert_rejects(source: String, reason: String = "") -> void:
	var result: Dictionary = parser.parse(source)
	assert_false(result["ok"], "expected parse to fail for: %s (%s)" % [source, reason])
	assert_gt(result["errors"].size(), 0, "a failed parse must report at least one error")


# --- result shape -------------------------------------------------------------

func test_result_always_has_ok_ast_and_errors_keys():
	var result: Dictionary = parser.parse("instruct \"X\" { otherwise: gather(wood) }")
	assert_true(result.has("ok"))
	assert_true(result.has("ast"))
	assert_true(result.has("errors"))


# --- the worked haul_and_forage example (concept doc, verbatim) ---------------

func test_parses_the_worked_haul_and_forage_example_exactly():
	var ast := _ast("""
		instruct "haul_and_forage" {
		    if inventory_at_least(wood, 20): haul(wood, base)
		    if need_above(hunger, 0.7): gather(berries)
		    otherwise: gather(wood)
		}
	""")
	assert_eq(ast["kind"], "instruct")
	assert_eq(ast["name"], "haul_and_forage")
	assert_eq(ast["rules"].size(), 3)
	assert_eq(ast["rules"][0], {
		"condition": {"fn": "inventory_at_least", "args": {"item": "wood", "count": 20}},
		"action": {"fn": "haul", "args": {"item": "wood", "destination_tag": "base"}},
	})
	assert_eq(ast["rules"][1]["condition"], {"fn": "need_above", "args": {"need": "hunger", "threshold": 0.7}})
	assert_eq(ast["rules"][1]["action"], {"fn": "gather", "args": {"resource_tag": "berries"}})
	assert_eq(ast["rules"][2], {
		"condition": null,
		"action": {"fn": "gather", "args": {"resource_tag": "wood"}},
	})


# --- primitive argument shapes -------------------------------------------------

func test_inventory_at_least_names_its_args_item_and_count():
	var ast := _ast("instruct \"X\" { if inventory_at_least(stone, 5): gather(stone) }")
	assert_eq(ast["rules"][0]["condition"], {"fn": "inventory_at_least", "args": {"item": "stone", "count": 5}})


func test_need_above_names_its_args_need_and_threshold():
	var ast := _ast("instruct \"X\" { if need_above(hunger, 0.5): gather(berries) }")
	assert_eq(ast["rules"][0]["condition"], {"fn": "need_above", "args": {"need": "hunger", "threshold": 0.5}})


func test_haul_names_its_args_item_and_destination_tag():
	var ast := _ast("instruct \"X\" { otherwise: haul(wood, base) }")
	assert_eq(ast["rules"][0]["action"], {"fn": "haul", "args": {"item": "wood", "destination_tag": "base"}})


func test_gather_names_its_arg_resource_tag():
	var ast := _ast("instruct \"X\" { otherwise: gather(berries) }")
	assert_eq(ast["rules"][0]["action"], {"fn": "gather", "args": {"resource_tag": "berries"}})


func test_an_otherwise_rule_has_a_null_condition():
	var ast := _ast("instruct \"X\" { otherwise: gather(wood) }")
	assert_eq(ast["rules"][0]["condition"], null)


func test_a_script_may_have_a_single_conditional_rule_with_no_otherwise():
	var ast := _ast("instruct \"X\" { if need_above(hunger, 0.5): gather(berries) }")
	assert_eq(ast["rules"].size(), 1)
	assert_true(ast["rules"][0]["condition"] != null)


# --- whitespace / comments -----------------------------------------------------

func test_whitespace_is_insignificant():
	var ast := _ast("instruct\t\"X\"{otherwise:gather(wood)}")
	assert_eq(ast["rules"][0]["action"], {"fn": "gather", "args": {"resource_tag": "wood"}})


func test_hash_starts_a_line_comment():
	var ast := _ast("""
		# a leading comment
		instruct "X" {   # trailing comment
		    otherwise: gather(wood)   # always fall back to wood
		}
	""")
	assert_eq(ast["rules"][0]["action"]["fn"], "gather")


# --- error handling: structure --------------------------------------------------

func test_empty_input_is_rejected():
	_assert_rejects("", "empty script")


func test_missing_instruct_keyword_is_rejected():
	_assert_rejects("\"X\" { otherwise: gather(wood) }", "no 'instruct' keyword")


func test_missing_name_is_rejected():
	_assert_rejects("instruct { otherwise: gather(wood) }", "no quoted name")


func test_unclosed_block_is_rejected():
	_assert_rejects("instruct \"X\" { otherwise: gather(wood)", "missing closing brace")


func test_unterminated_string_name_is_rejected():
	_assert_rejects("instruct \"X { otherwise: gather(wood) }", "unterminated name string")


func test_a_script_with_zero_rules_is_rejected():
	_assert_rejects("instruct \"X\" {  }", "no rules at all")


func test_a_rule_missing_the_colon_is_rejected():
	_assert_rejects("instruct \"X\" { otherwise gather(wood) }", "missing ':' before the action")


func test_a_rule_not_starting_with_if_or_otherwise_is_rejected():
	_assert_rejects("instruct \"X\" { always: gather(wood) }", "neither 'if' nor 'otherwise'")


func test_otherwise_must_be_the_last_rule():
	_assert_rejects("""
		instruct "X" {
		    otherwise: gather(wood)
		    if need_above(hunger, 0.5): gather(berries)
		}
	""", "'otherwise' before another rule")


func test_only_one_otherwise_rule_is_allowed():
	_assert_rejects("""
		instruct "X" {
		    otherwise: gather(wood)
		    otherwise: gather(stone)
		}
	""", "two 'otherwise' rules")


# --- error handling: unknown / misplaced primitives ------------------------------

func test_unknown_condition_primitive_is_rejected():
	_assert_rejects("instruct \"X\" { if teleport(x): gather(wood) }", "unknown condition primitive")


func test_unknown_action_primitive_is_rejected():
	_assert_rejects("instruct \"X\" { otherwise: dance() }", "unknown action primitive")


func test_an_action_primitive_used_as_a_condition_is_rejected():
	_assert_rejects("instruct \"X\" { if haul(wood, base): gather(wood) }", "action used where a condition is required")


func test_a_condition_primitive_used_as_an_action_is_rejected():
	_assert_rejects("instruct \"X\" { otherwise: inventory_at_least(wood, 5) }", "condition used where an action is required")


# --- error handling: arg count / type ---------------------------------------------

func test_too_few_args_is_rejected():
	_assert_rejects("instruct \"X\" { if inventory_at_least(wood): gather(wood) }", "missing the count arg")


func test_too_many_args_is_rejected():
	_assert_rejects("instruct \"X\" { otherwise: gather(wood, base) }", "gather takes only one arg")


func test_wrong_arg_type_for_a_number_slot_is_rejected():
	_assert_rejects("instruct \"X\" { if inventory_at_least(wood, plenty): gather(wood) }", "count must be a number, not a bareword")


func test_wrong_arg_type_for_a_name_slot_is_rejected():
	_assert_rejects("instruct \"X\" { otherwise: gather(20) }", "resource_tag must be a name, not a number")
