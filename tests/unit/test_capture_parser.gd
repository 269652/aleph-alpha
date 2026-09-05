extends GutTest

## Red-first spec for the capture DSL parser (docs/concept/capture_dsl.md):
## turns device text into the canonical AST -- plain Godot Dictionaries/
## Arrays -- that the atom catalog, physics, and executor all consume.
## Structurally a sibling of spell_parser.gd (same tokenizer, same
## `on EVENT(ARG) when GUARD: pipeline` rule shape), not a subclass or a
## shared parser -- capture is its own domain, the same way
## npc_instruction_parser.gd is already a structural sibling of the magic
## parser rather than a shared one.
##
## PURELY structural, same as spell_parser.gd: it does not know which atoms
## exist -- that is the atom catalog/executor's job -- so `bogus_atom()`
## parses fine. Player-authored text is fallible, so bad input returns
## {ok:false, errors:[...]} rather than crashing.

const CaptureParser = preload("res://src/gameplay/capture_parser.gd")

var parser: CaptureParser


func before_each():
	parser = CaptureParser.new()


func _ast(source: String) -> Dictionary:
	var result: Dictionary = parser.parse(source)
	assert_true(result["ok"], "expected parse to succeed, errors: %s" % [result["errors"]])
	return result["ast"]


# --- result shape -----------------------------------------------------------

func test_result_always_has_ok_ast_and_errors_keys():
	var result: Dictionary = parser.parse("capture \"X\" { on release: release_captive() }")
	assert_true(result.has("ok"))
	assert_true(result.has("ast"))
	assert_true(result.has("errors"))


# --- the worked butterfly net example ---------------------------------------

func test_parses_the_butterfly_net_device():
	var ast := _ast("""
		capture "Butterfly Net" {
		  on catch when target.tier == "flyer":
		    catch_roll(base: 0.65) |> hold_captive()
		  on release:
		    release_captive()
		  on transfer(glass_bottle):
		    move_captive()
		}
	""")
	assert_eq(ast["kind"], "capture")
	assert_eq(ast["name"], "Butterfly Net")
	assert_eq(ast["rules"].size(), 3)

	var catch_rule: Dictionary = ast["rules"][0]
	assert_eq(catch_rule["event"], "catch")
	assert_eq(catch_rule["event_arg"], null)
	assert_eq(catch_rule["guard"], {"op": "==", "lhs": "target.tier", "rhs": "flyer"})
	assert_eq(catch_rule["pipeline"], [
		{"atom": "catch_roll", "params": {"base": 0.65}},
		{"atom": "hold_captive", "params": {}},
	])

	var release_rule: Dictionary = ast["rules"][1]
	assert_eq(release_rule["event"], "release")
	assert_eq(release_rule["event_arg"], null)
	assert_eq(release_rule["guard"], null)
	assert_eq(release_rule["pipeline"], [{"atom": "release_captive", "params": {}}])

	var transfer_rule: Dictionary = ast["rules"][2]
	assert_eq(transfer_rule["event"], "transfer")
	assert_eq(transfer_rule["event_arg"], "glass_bottle")
	assert_eq(transfer_rule["guard"], null)
	assert_eq(transfer_rule["pipeline"], [{"atom": "move_captive", "params": {}}])


# --- guard / operand details -------------------------------------------------

func test_a_string_guard_operand_compares_against_a_bare_word():
	var ast := _ast("capture \"X\" { on catch when target.tier == \"flyer\": hold_captive() }")
	assert_eq(ast["rules"][0]["guard"], {"op": "==", "lhs": "target.tier", "rhs": "flyer"})


func test_guard_supports_the_full_comparison_set():
	for op in [">=", "<=", ">", "<", "==", "!="]:
		var ast := _ast('capture "X" { on catch when target.boldness %s 0.5: hold_captive() }' % op)
		assert_eq(ast["rules"][0]["guard"]["op"], op)


# --- pipeline / atom / param details -----------------------------------------

func test_an_atom_with_no_parentheses_has_empty_params():
	var ast := _ast("capture \"X\" { on release: release_captive }")
	assert_eq(ast["rules"][0]["pipeline"][0], {"atom": "release_captive", "params": {}})


func test_an_atom_with_empty_parentheses_has_empty_params():
	var ast := _ast("capture \"X\" { on release: release_captive() }")
	assert_eq(ast["rules"][0]["pipeline"][0]["params"], {})


func test_params_carry_int_float_and_bool_values():
	var ast := _ast("capture \"X\" { on catch: catch_roll(base: 0.65, lucky: true, tries: 3) }")
	var params: Dictionary = ast["rules"][0]["pipeline"][0]["params"]
	assert_almost_eq(params["base"], 0.65, 0.0001)
	assert_eq(params["lucky"], true)
	assert_eq(params["tries"], 3)


func test_parser_accepts_atoms_it_does_not_know_about():
	# Structural only -- `bogus_atom` is not in the atom catalog, but the
	# parser still produces a well-formed step. The catalog/executor reject
	# unknown atoms, not the parser.
	var ast := _ast("capture \"X\" { on catch: bogus_atom(radius: 4) }")
	assert_eq(ast["rules"][0]["pipeline"][0]["atom"], "bogus_atom")


# --- event argument reuse ----------------------------------------------------

func test_event_arg_accepts_a_bare_ident_naming_a_container():
	var ast := _ast("capture \"X\" { on transfer(glass_bottle): move_captive() }")
	assert_eq(ast["rules"][0]["event_arg"], "glass_bottle")


func test_event_arg_is_null_when_omitted():
	var ast := _ast("capture \"X\" { on release: release_captive() }")
	assert_eq(ast["rules"][0]["event_arg"], null)


# --- whitespace / comments --------------------------------------------------

func test_whitespace_is_insignificant():
	var ast := _ast("capture\t\"X\"{on catch:catch_roll(base:0.5)}")
	assert_eq(ast["rules"][0]["pipeline"][0], {"atom": "catch_roll", "params": {"base": 0.5}})


func test_hash_starts_a_line_comment():
	var ast := _ast("""
		# a leading comment
		capture "X" {   # trailing comment
		  on release: release_captive   # let it go
		}
	""")
	assert_eq(ast["rules"][0]["pipeline"][0]["atom"], "release_captive")


# --- error handling ---------------------------------------------------------

func _assert_rejects(source: String) -> void:
	var result: Dictionary = parser.parse(source)
	assert_false(result["ok"], "expected parse to fail for: %s" % source)
	assert_gt(result["errors"].size(), 0, "a failed parse must report at least one error")


func test_empty_input_is_rejected():
	_assert_rejects("")


func test_unknown_block_kind_is_rejected():
	# "spell" is a real block kind in the magic DSL, but capture is its own
	# domain (see this file's own header) -- this parser only knows "capture".
	_assert_rejects("spell \"X\" { on cast: reveal }")


func test_missing_name_is_rejected():
	_assert_rejects("capture { on release: release_captive }")


func test_missing_colon_before_pipeline_is_rejected():
	_assert_rejects("capture \"X\" { on release release_captive }")


func test_unclosed_block_is_rejected():
	_assert_rejects("capture \"X\" { on release: release_captive")


func test_unterminated_string_is_rejected():
	_assert_rejects("capture \"X { on release: release_captive }")
