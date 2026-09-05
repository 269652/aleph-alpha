extends GutTest

## Parser for the behavior DSL (docs/concept/behavior_dsl.md): turns an
## authored behavior script into the canonical AST -- plain Godot
## Dictionaries/Arrays -- that behavior_atom_catalog.gd and
## behavior_tree_executor.gd consume. Parsing only, no evaluation.
##
## Purely structural, like spell_parser.gd: an unknown atom name parses
## fine and is only rejected by the executor/catalog later. Named args only
## (`on: predator`), never positional, so unlike npc_instruction_parser.gd
## this needs no per-atom signature table to convert one shape into the
## other -- the surface syntax already matches the AST it produces.

const BehaviorDslParser = preload("res://src/gameplay/behavior_dsl_parser.gd")

var parser: BehaviorDslParser


func before_each():
	parser = BehaviorDslParser.new()


func _parse(source: String) -> Dictionary:
	return parser.parse(source)


func _behaviors(source: String) -> Dictionary:
	var result := _parse(source)
	assert_true(result["ok"], "expected parse to succeed, errors: %s" % [result["errors"]])
	return result["behaviors"]


func _assert_rejects(source: String, reason: String = "") -> void:
	var result := _parse(source)
	assert_false(result["ok"], "expected parse to fail for: %s (%s)" % [source, reason])
	assert_gt(result["errors"].size(), 0, "a failed parse must report at least one error")


# --- result shape -------------------------------------------------------------

func test_result_always_has_ok_behaviors_and_errors_keys():
	var result := _parse("behavior \"x\" { wander() }")
	assert_true(result.has("ok"))
	assert_true(result.has("behaviors"))
	assert_true(result.has("errors"))


func test_an_empty_script_parses_to_no_behaviors_and_is_not_an_error():
	var result := _parse("")
	assert_true(result["ok"])
	assert_eq(result["behaviors"], {})


# --- the simplest tree: one leaf ----------------------------------------------

func test_a_single_leaf_behavior_parses_to_a_leaf_node():
	var behaviors := _behaviors("behavior \"idle\" { wander() }")
	assert_eq(behaviors.keys(), ["idle"])
	assert_eq(behaviors["idle"], {"kind": "leaf", "atom": "wander", "args": {}})


func test_a_leaf_with_one_named_arg():
	var behaviors := _behaviors("behavior \"x\" { seek(on: forage) }")
	assert_eq(behaviors["x"], {"kind": "leaf", "atom": "seek", "args": {"on": "forage"}})


func test_a_leaf_with_several_named_args_of_different_kinds():
	var behaviors := _behaviors(
		"behavior \"x\" { thing(name: berries, count: 3, ripe: true, label: \"hi\") }"
	)
	assert_eq(behaviors["x"]["args"], {"name": "berries", "count": 3, "ripe": true, "label": "hi"})


func test_a_number_arg_may_be_a_float():
	var behaviors := _behaviors("behavior \"x\" { above(need: hunger, threshold: 0.5) }")
	assert_eq(behaviors["x"]["args"]["threshold"], 0.5)


func test_false_parses_as_a_real_boolean():
	var behaviors := _behaviors("behavior \"x\" { thing(ripe: false) }")
	assert_eq(behaviors["x"]["args"]["ripe"], false)


## Repeated keys accumulate into a list, in the order written; a single
## occurrence of a key stays a plain scalar (docs/concept/behavior_dsl.md
## §1) -- this is what lets flee/seek take one or several channels with no
## separate list-literal syntax.
func test_a_repeated_key_accumulates_into_a_list():
	var behaviors := _behaviors("behavior \"x\" { flee(on: predator, on: player) }")
	assert_eq(behaviors["x"]["args"], {"on": ["predator", "player"]})


func test_three_repeats_of_the_same_key_give_a_three_element_list():
	var behaviors := _behaviors("behavior \"x\" { flee(on: a, on: b, on: c) }")
	assert_eq(behaviors["x"]["args"]["on"], ["a", "b", "c"])


func test_a_single_occurrence_of_a_key_stays_a_scalar_not_a_one_item_list():
	var behaviors := _behaviors("behavior \"x\" { seek(on: water) }")
	assert_eq(behaviors["x"]["args"]["on"], "water")


# --- composition: priority, sequence, parallel --------------------------------

func test_priority_holds_its_children_in_the_written_order():
	var behaviors := _behaviors(
		"behavior \"x\" { priority { flee(on: predator) seek(on: water) wander() } }"
	)
	var root: Dictionary = behaviors["x"]
	assert_eq(root["kind"], "priority")
	assert_eq(root["children"].size(), 3)
	assert_eq(root["children"][0], {"kind": "leaf", "atom": "flee", "args": {"on": "predator"}})
	assert_eq(root["children"][1], {"kind": "leaf", "atom": "seek", "args": {"on": "water"}})
	assert_eq(root["children"][2], {"kind": "leaf", "atom": "wander", "args": {}})


func test_sequence_parses_the_same_shape_as_priority_with_its_own_kind():
	var behaviors := _behaviors("behavior \"x\" { sequence { wander() wander() } }")
	assert_eq(behaviors["x"]["kind"], "sequence")
	assert_eq(behaviors["x"]["children"].size(), 2)


func test_parallel_parses_the_same_shape_with_its_own_kind():
	var behaviors := _behaviors("behavior \"x\" { parallel { wander() wander() } }")
	assert_eq(behaviors["x"]["kind"], "parallel")


func test_an_empty_composition_block_parses_to_zero_children():
	var behaviors := _behaviors("behavior \"x\" { priority { } }")
	assert_eq(behaviors["x"]["children"], [])


# --- gate: a condition-call, then exactly one child ---------------------------

func test_gate_holds_a_condition_call_and_one_child():
	var behaviors := _behaviors(
		"behavior \"x\" { gate(above(need: hunger, threshold: 0.5)) { seek(on: forage) } }"
	)
	var root: Dictionary = behaviors["x"]
	assert_eq(root["kind"], "gate")
	assert_eq(root["condition"], {"name": "above", "args": {"need": "hunger", "threshold": 0.5}})
	assert_eq(root["child"], {"kind": "leaf", "atom": "seek", "args": {"on": "forage"}})


func test_gates_child_may_itself_be_a_composition_block():
	var behaviors := _behaviors(
		"behavior \"x\" { gate(sensed(on: predator)) { priority { flee(on: predator) wander() } } }"
	)
	assert_eq(behaviors["x"]["child"]["kind"], "priority")
	assert_eq(behaviors["x"]["child"]["children"].size(), 2)


func test_a_gate_with_no_condition_call_is_rejected():
	_assert_rejects("behavior \"x\" { gate() { wander() } }", "no condition")


func test_a_gate_whose_condition_has_no_parens_is_rejected():
	_assert_rejects("behavior \"x\" { gate(above) { wander() } }", "condition must be a call")


# --- nesting and multiple behaviors --------------------------------------------

func test_a_priority_may_nest_a_gate_which_nests_a_priority():
	var behaviors := _behaviors(
		"""
		behavior "mammal" {
		    priority {
		        flee(on: predator, on: player)
		        gate(above(need: thirst, threshold: 0.5)) {
		            seek(on: water)
		        }
		        gate(above(need: hunger, threshold: 0.5)) {
		            priority {
		                seek(on: flesh)
		                seek(on: forage)
		            }
		        }
		        wander()
		    }
		}
		"""
	)
	var root: Dictionary = behaviors["mammal"]
	assert_eq(root["kind"], "priority")
	assert_eq(root["children"].size(), 4)
	assert_eq(root["children"][0]["args"], {"on": ["predator", "player"]})
	assert_eq(root["children"][1]["kind"], "gate")
	assert_eq(root["children"][1]["condition"], {"name": "above", "args": {"need": "thirst", "threshold": 0.5}})
	assert_eq(root["children"][2]["child"]["kind"], "priority")
	assert_eq(root["children"][2]["child"]["children"][0]["atom"], "seek")
	assert_eq(root["children"][3], {"kind": "leaf", "atom": "wander", "args": {}})


func test_several_behavior_blocks_parse_into_one_dictionary_keyed_by_name():
	var behaviors := _behaviors(
		"""
		behavior "mammal" { wander() }
		behavior "villager" { schedule() }
		behavior "ant_forager" { round_trip() }
		"""
	)
	assert_eq(behaviors.keys().size(), 3)
	assert_eq(behaviors["mammal"], {"kind": "leaf", "atom": "wander", "args": {}})
	assert_eq(behaviors["villager"], {"kind": "leaf", "atom": "schedule", "args": {}})
	assert_eq(behaviors["ant_forager"], {"kind": "leaf", "atom": "round_trip", "args": {}})


# --- comments -------------------------------------------------------------------

func test_hash_comments_are_ignored():
	var behaviors := _behaviors(
		"""
		# a comment above the block
		behavior "x" {
		    wander() # trailing comment
		}
		"""
	)
	assert_eq(behaviors["x"], {"kind": "leaf", "atom": "wander", "args": {}})


# --- fail-closed: never a crash, always a "line N: ..." error ------------------

func test_an_unknown_top_level_keyword_is_rejected():
	_assert_rejects("spell \"x\" { wander() }", "not a behavior block")


func test_a_missing_behavior_name_string_is_rejected():
	_assert_rejects("behavior { wander() }", "name must be a string")


func test_an_unclosed_brace_is_rejected():
	_assert_rejects("behavior \"x\" { wander()", "missing closing brace")


func test_an_unclosed_string_is_rejected():
	_assert_rejects("behavior \"x { wander() }", "unterminated string")


func test_an_unrecognised_composition_keyword_falls_through_to_a_leaf_and_needs_parens():
	# "loop" is not a reserved word, so it is read as a leaf atom name --
	# structurally valid (the parser doesn't know atom names, see the class
	# doc comment), but it still needs the call syntax leaves require.
	_assert_rejects("behavior \"x\" { loop { wander() } }", "not a recognised block form")


func test_a_bare_identifier_with_no_parens_at_all_is_rejected():
	_assert_rejects("behavior \"x\" { wander }", "a leaf must be a call")


func test_a_trailing_comma_in_an_arg_list_is_rejected():
	_assert_rejects("behavior \"x\" { seek(on: water,) }", "trailing comma")


func test_a_failed_parse_reports_no_partial_behaviors():
	var result := _parse("behavior \"x\" { wander() } behavior \"y\" { nope")
	assert_false(result["ok"])
	assert_eq(result["behaviors"], {})


# --- determinism: same source, same AST ----------------------------------------

func test_parsing_the_same_source_twice_gives_the_same_ast():
	var source := "behavior \"x\" { priority { flee(on: predator) wander() } }"
	assert_eq(_behaviors(source), BehaviorDslParser.new().parse(source)["behaviors"])
