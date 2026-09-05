extends GutTest

## Red-first spec for the `device` DSL parser (docs/concept/standard_model.md,
## "The DSL / Grammar"): a structural sibling of spell_parser.gd /
## npc_instruction_parser.gd (and the successor of the retired
## capture_parser.gd) -- same tokenizer, same `on EVENT(ARG) when GUARD:
## pipeline` rules -- with four declarative clauses in front of them: part,
## joint, law, loop.
##
## PURELY structural, like its siblings: it does not know which materials,
## geometries, element kinds or atoms exist. `part x: unobtainium blob thing`
## parses fine and is rejected by the compiler, not here. Malformed text
## yields {ok:false, errors:["line N: ..."]} rather than crashing.

const DeviceParser = preload("res://src/gameplay/device_parser.gd")

var parser: DeviceParser


func before_each():
	parser = DeviceParser.new()


func _ast(source: String) -> Dictionary:
	var result: Dictionary = parser.parse(source)
	assert_true(result["ok"], "expected parse to succeed, errors: %s" % [result["errors"]])
	return result["ast"]


const MILL_RACE_LIGHT := """
	device "Mill Race Light" {
	  part wheel: wood face working (width_cm: 200, height_cm: 200, thickness_cm: 4)
	  part axle: iron haft structure (length_cm: 60, diameter_cm: 4)
	  part wire: copper haft structure (length_cm: 1000, diameter_cm: 0.3)
	  joint hub: wheel to axle rigid fit iron
	  law river: source(domain: translation, fluid: water, area_m2: 0.5, velocity: 1.5)
	  law wheel: transform(in: translation, out: rotation, part: wheel)
	  law wire: resist(domain: electrical, part: wire)
	  loop river |> wheel |> wire
	  on step when wire.power >= 1: shine(target: wire)
	}
"""


# --- result shape -------------------------------------------------------------

func test_result_always_has_ok_ast_and_errors_keys():
	var result: Dictionary = parser.parse('device "X" { }')
	assert_true(result.has("ok"))
	assert_true(result.has("ast"))
	assert_true(result.has("errors"))


func test_an_empty_device_parses_to_empty_lists():
	var ast := _ast('device "X" { }')
	assert_eq(ast["kind"], "device")
	assert_eq(ast["name"], "X")
	assert_eq(ast["parts"], [])
	assert_eq(ast["joints"], [])
	assert_eq(ast["laws"], [])
	assert_eq(ast["loops"], [])
	assert_eq(ast["rules"], [])


# --- the canonical example ------------------------------------------------------

func test_parses_the_mill_race_light():
	var ast := _ast(MILL_RACE_LIGHT)
	assert_eq(ast["name"], "Mill Race Light")
	assert_eq(ast["parts"].size(), 3)
	assert_eq(ast["joints"].size(), 1)
	assert_eq(ast["laws"].size(), 3)
	assert_eq(ast["loops"], [["river", "wheel", "wire"]])
	assert_eq(ast["rules"].size(), 1)


func test_a_part_is_material_geometry_role_and_its_dimensions():
	var ast := _ast(MILL_RACE_LIGHT)
	assert_eq(ast["parts"][0], {
		"id": "wheel", "material": "wood", "geometry": "face", "role": "working",
		"dimensions": {"width_cm": 200, "height_cm": 200, "thickness_cm": 4},
	})
	assert_almost_eq(ast["parts"][2]["dimensions"]["diameter_cm"], 0.3, 1e-9)


func test_a_joint_is_two_members_then_type_fastening_material():
	var ast := _ast(MILL_RACE_LIGHT)
	assert_eq(ast["joints"][0], {
		"id": "hub", "part_a": "wheel", "part_b": "axle",
		"type": "rigid", "fastening": "fit", "material": "iron", "params": {},
	})


func test_a_pivot_names_its_axis_in_its_params():
	var ast := _ast('device "X" { joint pin: a to b pivot pin iron (axis: z) }')
	assert_eq(ast["joints"][0]["type"], "pivot")
	assert_eq(ast["joints"][0]["params"], {"axis": "z"})


func test_a_law_is_an_element_kind_and_its_params():
	var ast := _ast(MILL_RACE_LIGHT)
	assert_eq(ast["laws"][0], {
		"id": "river", "element": "source",
		"params": {"domain": "translation", "fluid": "water", "area_m2": 0.5, "velocity": 1.5},
	})
	assert_eq(ast["laws"][1]["params"]["part"], "wheel")


func test_a_law_with_no_parentheses_has_empty_params():
	var ast := _ast('device "X" { law shaft: transform }')
	assert_eq(ast["laws"][0], {"id": "shaft", "element": "transform", "params": {}})


func test_a_part_with_no_parentheses_has_no_dimensions_and_the_parser_does_not_mind():
	# Structural only: the compiler is what says a haft needs a length.
	var ast := _ast('device "X" { part stub: iron haft grip }')
	assert_eq(ast["parts"][0]["dimensions"], {})


func test_the_rule_is_exactly_the_capture_dsl_rule_shape():
	var ast := _ast(MILL_RACE_LIGHT)
	assert_eq(ast["rules"][0], {
		"event": "step", "event_arg": null,
		"guard": {"op": ">=", "lhs": "wire.power", "rhs": 1},
		"pipeline": [{"atom": "shine", "params": {"target": "wire"}}],
	})


func test_rule_event_arg_and_guardless_rules_still_work():
	var ast := _ast('device "X" { on strike(anvil): crush() }')
	assert_eq(ast["rules"][0]["event_arg"], "anvil")
	assert_eq(ast["rules"][0]["guard"], null)


# --- loops ------------------------------------------------------------------------

func test_a_loop_of_one_element_is_a_one_element_chain():
	var ast := _ast('device "X" { loop river }')
	assert_eq(ast["loops"], [["river"]])


func test_two_loop_clauses_are_kept_separately_in_order():
	var ast := _ast('device "X" { loop a |> b loop c }')
	assert_eq(ast["loops"], [["a", "b"], ["c"]])


# --- structural only ------------------------------------------------------------

func test_unknown_materials_geometries_elements_and_atoms_all_parse():
	var ast := _ast("""
		device "X" {
		  part blob: unobtainium blob thing (mass: 3)
		  law blob: levitate(altitude: 4)
		  on wobble: jiggle(amount: 2)
		}
	""")
	assert_eq(ast["parts"][0]["material"], "unobtainium")
	assert_eq(ast["laws"][0]["element"], "levitate")
	assert_eq(ast["rules"][0]["pipeline"][0]["atom"], "jiggle")


func test_clauses_may_come_in_any_order_and_keep_their_own_order():
	var ast := _ast("""
		device "X" {
		  law b: resist
		  part p: iron haft grip (length_cm: 1, diameter_cm: 1)
		  law a: resist
		  on step: tick()
		  part q: iron haft grip (length_cm: 1, diameter_cm: 1)
		}
	""")
	assert_eq(ast["laws"][0]["id"], "b")
	assert_eq(ast["laws"][1]["id"], "a")
	assert_eq(ast["parts"][0]["id"], "p")
	assert_eq(ast["parts"][1]["id"], "q")


# --- whitespace / comments ------------------------------------------------------

func test_whitespace_is_insignificant():
	var ast := _ast('device\t"X"{law\tr:resist(resistance:2)loop r}')
	assert_eq(ast["laws"][0]["params"], {"resistance": 2})
	assert_eq(ast["loops"], [["r"]])


func test_hash_starts_a_line_comment():
	var ast := _ast("""
		# the whole machine
		device "X" {   # opening
		  law r: resist(resistance: 2)   # the load
		}
	""")
	assert_eq(ast["laws"][0]["id"], "r")


# --- error handling ---------------------------------------------------------------

func _assert_rejects(source: String, mentioning: String = "") -> void:
	var result: Dictionary = parser.parse(source)
	assert_false(result["ok"], "expected parse to fail for: %s" % source)
	assert_gt(result["errors"].size(), 0, "a failed parse must report at least one error")
	if mentioning != "":
		assert_true(
			String(result["errors"][0]).contains(mentioning),
			"expected an error mentioning '%s', got: %s" % [mentioning, result["errors"]]
		)
	assert_true(String(result["errors"][0]).begins_with("line "), str(result["errors"]))


func test_empty_input_is_rejected():
	_assert_rejects("", "device")


func test_another_dsl_block_kind_is_rejected():
	# A capture block is a real thing in its own DSL; this parser only knows devices.
	_assert_rejects('capture "Net" { on catch: hold_captive() }', "device")


func test_missing_name_is_rejected():
	_assert_rejects("device { }")


func test_an_unknown_clause_keyword_is_rejected_naming_the_clauses():
	_assert_rejects('device "X" { bogus x: y }', "part")


func test_a_part_missing_its_colon_is_rejected():
	_assert_rejects('device "X" { part wheel wood face working }')


func test_a_part_missing_a_word_is_rejected():
	_assert_rejects('device "X" { part wheel: wood face }')


func test_a_joint_without_to_is_rejected():
	_assert_rejects('device "X" { joint hub: wheel axle rigid fit iron }', "to")


func test_a_loop_with_a_dangling_pipe_is_rejected():
	_assert_rejects('device "X" { loop a |> }')


func test_a_loop_step_cannot_carry_parameters():
	_assert_rejects('device "X" { loop a(ratio: 2) }')


func test_an_unclosed_block_is_rejected():
	_assert_rejects('device "X" { law r: resist')


func test_an_unterminated_string_is_rejected():
	_assert_rejects('device "X { }')
