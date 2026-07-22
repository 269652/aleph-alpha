extends GutTest

## Red-first spec for the magic DSL parser: turns player-written spell text
## (pipeline + blocks surface syntax) into the canonical AST -- plain Godot
## Dictionaries/Arrays -- that the cost model, validator, and runtime consume.
## Same spirit as console_command_parser.gd (text -> data, no side effects),
## but recursive. The parser is PURELY structural: it does not know which atoms
## exist or whether params are legal -- that is the validator's job -- so it
## happily parses unknown atoms like `taunt`. Player input is fallible, so bad
## input returns {ok:false, errors:[...]} rather than crashing.
##
## Atom names are snake_case (fire_damage), matching the atom catalog and the
## rest of the codebase, not the docs' PascalCase shorthand.

const SpellParser = preload("res://src/gameplay/spell_parser.gd")

var parser: SpellParser


func before_each():
	parser = SpellParser.new()


func _ast(source: String) -> Dictionary:
	var result: Dictionary = parser.parse(source)
	assert_true(result["ok"], "expected parse to succeed, errors: %s" % [result["errors"]])
	return result["ast"]


# --- result shape -----------------------------------------------------------

func test_result_always_has_ok_ast_and_errors_keys():
	var result: Dictionary = parser.parse("spell \"X\" { on cast: reveal }")
	assert_true(result.has("ok"))
	assert_true(result.has("ast"))
	assert_true(result.has("errors"))


# --- the worked sword example ----------------------------------------------

func test_parses_the_flame_brand_enchant():
	var ast := _ast("""
		enchant "Flame Brand" {
		  on hit when wielder.mana >= @cost:
		    fire_damage(magnitude: 8) |> ignite(duration: 3, spread: true)
		}
	""")
	assert_eq(ast["kind"], "enchant")
	assert_eq(ast["name"], "Flame Brand")
	assert_eq(ast["rules"].size(), 1)

	var rule: Dictionary = ast["rules"][0]
	assert_eq(rule["event"], "hit")
	assert_eq(rule["event_arg"], null)
	assert_eq(rule["guard"], {"op": ">=", "lhs": "wielder.mana", "rhs": "@cost"})
	assert_eq(rule["pipeline"], [
		{"atom": "fire_damage", "params": {"magnitude": 8}},
		{"atom": "ignite", "params": {"duration": 3, "spread": true}},
	])


# --- kinds ------------------------------------------------------------------

func test_parses_a_spell_block_with_no_guard():
	var ast := _ast("spell \"Frost Lance\" { on cast: frost_damage(magnitude: 10) |> slow(duration: 2) }")
	assert_eq(ast["kind"], "spell")
	var rule: Dictionary = ast["rules"][0]
	assert_eq(rule["event"], "cast")
	assert_eq(rule["guard"], null)
	assert_eq(rule["pipeline"].size(), 2)


func test_parses_an_instruct_block_with_multiple_rules():
	var ast := _ast("""
		instruct "Wary Sentry" {
		  on see(enemy) when self.stamina > 10:
		    taunt(radius: 4)
		  on low_health(0.3):
		    minor_heal(magnitude: 6)
		}
	""")
	assert_eq(ast["kind"], "instruct")
	assert_eq(ast["rules"].size(), 2)

	var see_rule: Dictionary = ast["rules"][0]
	assert_eq(see_rule["event"], "see")
	assert_eq(see_rule["event_arg"], "enemy")
	assert_eq(see_rule["guard"], {"op": ">", "lhs": "self.stamina", "rhs": 10})

	var low_rule: Dictionary = ast["rules"][1]
	assert_eq(low_rule["event"], "low_health")
	assert_almost_eq(low_rule["event_arg"], 0.3, 0.0001)
	assert_eq(low_rule["guard"], null)


# --- pipeline / atom / param details ---------------------------------------

func test_an_atom_with_no_parentheses_has_empty_params():
	var ast := _ast("spell \"X\" { on cast: reveal }")
	assert_eq(ast["rules"][0]["pipeline"][0], {"atom": "reveal", "params": {}})


func test_an_atom_with_empty_parentheses_has_empty_params():
	var ast := _ast("spell \"X\" { on cast: reveal() }")
	assert_eq(ast["rules"][0]["pipeline"][0]["params"], {})


func test_params_carry_int_float_bool_and_bareword_values():
	var ast := _ast("spell \"X\" { on cast: shield(magnitude: 10, duration: 4.5, spread: false, to: nearest_ally) }")
	var params: Dictionary = ast["rules"][0]["pipeline"][0]["params"]
	assert_eq(params["magnitude"], 10)
	assert_almost_eq(params["duration"], 4.5, 0.0001)
	assert_eq(params["spread"], false)
	assert_eq(params["to"], "nearest_ally")


func test_parser_accepts_atoms_it_does_not_know_about():
	# Structural only -- `taunt` is not in the atom catalog, but the parser
	# still produces a well-formed step. The validator rejects unknown atoms.
	var ast := _ast("spell \"X\" { on cast: taunt(radius: 4) }")
	assert_eq(ast["rules"][0]["pipeline"][0]["atom"], "taunt")


# --- whitespace / comments --------------------------------------------------

func test_whitespace_is_insignificant():
	var ast := _ast("spell\t\"X\"{on cast:fire_damage(magnitude:5)}")
	assert_eq(ast["rules"][0]["pipeline"][0], {"atom": "fire_damage", "params": {"magnitude": 5}})


func test_hash_starts_a_line_comment():
	var ast := _ast("""
		# a leading comment
		spell "X" {   # trailing comment
		  on cast: reveal   # cast reveals the area
		}
	""")
	assert_eq(ast["rules"][0]["pipeline"][0]["atom"], "reveal")


# --- error handling ---------------------------------------------------------

func _assert_rejects(source: String) -> void:
	var result: Dictionary = parser.parse(source)
	assert_false(result["ok"], "expected parse to fail for: %s" % source)
	assert_gt(result["errors"].size(), 0, "a failed parse must report at least one error")


func test_empty_input_is_rejected():
	_assert_rejects("")


func test_unknown_block_kind_is_rejected():
	_assert_rejects("potion \"X\" { on cast: reveal }")


func test_missing_name_is_rejected():
	_assert_rejects("spell { on cast: reveal }")


func test_missing_colon_before_pipeline_is_rejected():
	_assert_rejects("spell \"X\" { on cast reveal }")


func test_unclosed_block_is_rejected():
	_assert_rejects("spell \"X\" { on cast: reveal")


func test_unterminated_string_is_rejected():
	_assert_rejects("spell \"X { on cast: reveal }")
