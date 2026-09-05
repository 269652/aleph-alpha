extends GutTest

## Red-first spec for capture_executor.gd (docs/concept/capture_dsl.md): the
## pure GO/NO-GO layer that decides whether a capture action happens and
## which effect atoms actually apply -- it does not mutate any game state
## itself (capture_atom_effects.gd does that), and it does not generate its
## own randomness (the roll is supplied by the caller, same split
## CreatureMarker._step_restraint's own hash roll already keeps).

const CaptureExecutor = preload("res://src/gameplay/capture_executor.gd")
const CaptureParser = preload("res://src/gameplay/capture_parser.gd")

var executor: CaptureExecutor
var parser: CaptureParser


func before_each():
	executor = CaptureExecutor.new()
	parser = CaptureParser.new()


func _ast(source: String) -> Dictionary:
	var result: Dictionary = parser.parse(source)
	assert_true(result["ok"], "expected parse to succeed, errors: %s" % [result["errors"]])
	return result["ast"]


func _net_ast() -> Dictionary:
	return _ast("""
		capture "Butterfly Net" {
		  on catch when target.tier == "flyer":
		    catch_roll(base: 0.65) |> hold_captive()
		  on release:
		    release_captive()
		  on transfer(glass_bottle):
		    move_captive()
		}
	""")


# --- finding rules ------------------------------------------------------------

func test_capture_rule_finds_the_on_catch_rule():
	var rule: Variant = executor.capture_rule(_net_ast())
	assert_not_null(rule)
	assert_eq(rule["event"], "catch")


func test_capture_rule_is_null_when_the_device_has_none():
	var ast := _ast('capture "X" { on release: release_captive() }')
	assert_null(executor.capture_rule(ast))


func test_release_rule_finds_the_on_release_rule():
	var rule: Variant = executor.release_rule(_net_ast())
	assert_not_null(rule)
	assert_eq(rule["event"], "release")


func test_transfer_rule_finds_the_matching_container():
	var rule: Variant = executor.transfer_rule(_net_ast(), "glass_bottle")
	assert_not_null(rule)
	assert_eq(rule["event"], "transfer")
	assert_eq(rule["event_arg"], "glass_bottle")


func test_transfer_rule_is_null_for_an_unhandled_container():
	assert_null(executor.transfer_rule(_net_ast(), "jam_jar"))


# --- guard evaluation ---------------------------------------------------------

func test_a_null_guard_always_passes():
	assert_true(executor.evaluate_guard(null, {}))


func test_a_string_equality_guard_matches_the_context():
	var guard := {"op": "==", "lhs": "target.tier", "rhs": "flyer"}
	assert_true(executor.evaluate_guard(guard, {"target": {"tier": "flyer"}}))
	assert_false(executor.evaluate_guard(guard, {"target": {"tier": "legless"}}))


func test_guard_honors_the_full_comparison_set_on_a_numeric_path():
	var context := {"target": {"boldness": 0.5}}
	var cases := {
		">=": [0.4, true], "<=": [0.6, true], ">": [0.6, false],
		"<": [0.4, false], "==": [0.5, true], "!=": [0.5, false],
	}
	for op in cases:
		var rhs = cases[op][0]
		var expected: bool = cases[op][1]
		var guard := {"op": op, "lhs": "target.boldness", "rhs": rhs}
		assert_eq(executor.evaluate_guard(guard, context), expected, "op '%s' rhs %s" % [op, rhs])


func test_an_unresolved_path_makes_the_guard_false_rather_than_crash():
	var guard := {"op": "==", "lhs": "target.nonexistent", "rhs": "anything"}
	assert_false(executor.evaluate_guard(guard, {"target": {"tier": "flyer"}}))


# --- resolve_catch: the roll gate ---------------------------------------------

func test_resolve_catch_fails_the_guard_before_ever_rolling():
	var rule: Variant = executor.capture_rule(_net_ast())
	var result := executor.resolve_catch(rule, {"target": {"tier": "legless"}}, 0.0)
	assert_false(result["caught"], "wrong tier must not catch regardless of roll")
	assert_eq(result["effects"], [])


func test_resolve_catch_succeeds_when_the_roll_beats_the_chance():
	var rule: Variant = executor.capture_rule(_net_ast())
	# base 0.65, middling boldness (context has none) -> chance == 0.65.
	var result := executor.resolve_catch(rule, {"target": {"tier": "flyer"}}, 0.1)
	assert_true(result["caught"])
	assert_eq(result["effects"], [{"atom": "hold_captive", "params": {}}])


func test_resolve_catch_fails_when_the_roll_loses_to_the_chance():
	var rule: Variant = executor.capture_rule(_net_ast())
	var result := executor.resolve_catch(rule, {"target": {"tier": "flyer"}}, 0.99)
	assert_false(result["caught"])
	assert_eq(result["effects"], [])


func test_resolve_catch_reads_boldness_out_of_the_target_context():
	# Same roll, same base -- a bolder target's higher chance is what flips
	# this specific roll from a miss to a catch (0.65 base + up to +0.15 for
	# boldness 1.0 = 0.80; a roll of 0.75 is a miss at middling but a catch
	# at maximum boldness).
	var rule: Variant = executor.capture_rule(_net_ast())
	var shy := executor.resolve_catch(rule, {"target": {"tier": "flyer", "boldness": 0.5}}, 0.75)
	var bold := executor.resolve_catch(rule, {"target": {"tier": "flyer", "boldness": 1.0}}, 0.75)
	assert_false(shy["caught"], "a middling target should not be caught by this roll")
	assert_true(bold["caught"], "a bolder target's better odds should catch this same roll")


func test_a_null_rule_never_catches():
	var result := executor.resolve_catch(null, {"target": {"tier": "flyer"}}, 0.0)
	assert_false(result["caught"])


# --- resolve_release / resolve_transfer: no roll, guard-gated only -----------

func test_resolve_release_reports_its_effect():
	var rule: Variant = executor.release_rule(_net_ast())
	var result := executor.resolve_release(rule, {})
	assert_true(result["released"])
	assert_eq(result["effects"], [{"atom": "release_captive", "params": {}}])


func test_resolve_transfer_reports_its_effect():
	var rule: Variant = executor.transfer_rule(_net_ast(), "glass_bottle")
	var result := executor.resolve_transfer(rule, {})
	assert_true(result["transferred"])
	assert_eq(result["effects"], [{"atom": "move_captive", "params": {}}])


func test_resolve_transfer_with_a_null_rule_does_not_transfer():
	var result := executor.resolve_transfer(null, {})
	assert_false(result["transferred"])
	assert_eq(result["effects"], [])


# --- end to end: real parser text into the real executor ---------------------

func test_a_device_parsed_from_real_dsl_text_can_actually_be_caught():
	var parsed := CaptureParser.new().parse(
		'capture "Butterfly Net" { on catch when target.tier == "flyer": '
		+ "catch_roll(base: 1.0) |> hold_captive() }"
	)
	assert_true(parsed["ok"], "the example device text must actually parse")
	var rule: Variant = executor.capture_rule(parsed["ast"])
	var result := executor.resolve_catch(rule, {"target": {"tier": "flyer"}}, 0.0)
	assert_true(result["caught"], "base 1.0 must always catch")
