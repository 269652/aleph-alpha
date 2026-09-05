extends GutTest

## Red-first spec for docs/concept/standard_model.md's step 6 ("Fire rules"):
## the solved state becomes a context dictionary keyed by element id, and a
## device's `on EVENT when GUARD: pipeline` rules are evaluated against it
## with the same single-comparison guard the other DSLs use. Pure -- like
## spell_executor.gd and capture_executor.gd it mutates nothing and reports
## which effects apply; dispatching them into the world is the concept doc's
## own ⬜ effects layer.

const DeviceExecutor = preload("res://src/gameplay/device_executor.gd")
const DeviceNetwork = preload("res://src/gameplay/device_network.gd")
const DeviceParser = preload("res://src/gameplay/device_parser.gd")

var executor: DeviceExecutor
var parser: DeviceParser


func before_each():
	executor = DeviceExecutor.new()
	parser = DeviceParser.new()


func _solution() -> Dictionary:
	return DeviceNetwork.solve([
		{"id": "s", "kind": "source", "params": {"effort": 100.0, "resistance": 10.0}},
		{"id": "lever", "kind": "transform", "params": {"ratio": 2.0}},
		{"id": "bulb", "kind": "resist", "params": {"resistance": 40.0}},
		{"id": "cell", "kind": "store", "params": {"capacity": 1000.0, "full_effort": 12.0, "level": 250.0}},
	], 1.0)


func _rules(source: String) -> Dictionary:
	var parsed: Dictionary = parser.parse(source)
	assert_true(parsed["ok"], str(parsed["errors"]))
	return parsed["ast"]


# --- the context: solved state, readable by dotted path -----------------------

func test_the_context_exposes_every_solved_element_by_id():
	var solution := _solution()
	var context: Dictionary = executor.context_for(solution)
	for id in ["s", "lever", "bulb", "cell"]:
		assert_true(context.has(id), id)
		for key in ["effort", "flow", "power", "dissipated", "stored_rate"]:
			assert_true(context[id].has(key), "%s.%s" % [id, key])
	assert_almost_eq(context["bulb"]["power"], solution["elements"]["bulb"]["power"], 1e-12)
	assert_almost_eq(context["lever"]["effort_out"], solution["elements"]["lever"]["effort_out"], 1e-12)


func test_the_context_exposes_a_stores_level_and_capacity():
	var context: Dictionary = executor.context_for(_solution())
	assert_almost_eq(context["cell"]["level"], _solution()["stores"]["cell"]["level"], 1e-12)
	assert_eq(context["cell"]["capacity"], 1000.0)


func test_the_context_carries_device_level_facts_for_at_references():
	var context: Dictionary = executor.context_for(_solution(), {"mass_kg": 3.5})
	assert_eq(context["device"]["mass_kg"], 3.5)
	assert_almost_eq(context["device"]["source_power"], _solution()["source_power"], 1e-12)
	assert_almost_eq(context["device"]["source_flow"], _solution()["source_flow"], 1e-12)


func test_an_unsolved_result_yields_an_empty_context_rather_than_a_crash():
	var context: Dictionary = executor.context_for(DeviceNetwork.solve([], 0.0))
	assert_eq(context.keys(), ["device"])


# --- guards ------------------------------------------------------------------------

func test_a_guard_reads_a_dotted_path_into_the_context():
	var context: Dictionary = executor.context_for(_solution())
	assert_true(executor.evaluate_guard({"op": ">=", "lhs": "bulb.power", "rhs": 1}, context))
	assert_false(executor.evaluate_guard({"op": ">=", "lhs": "bulb.power", "rhs": 1e9}, context))


func test_a_null_guard_always_passes():
	assert_true(executor.evaluate_guard(null, {}))


func test_an_unresolved_path_fails_the_guard_rather_than_crashing():
	var context: Dictionary = executor.context_for(_solution())
	assert_false(executor.evaluate_guard({"op": ">=", "lhs": "ghost.power", "rhs": 0}, context))
	assert_false(executor.evaluate_guard({"op": ">=", "lhs": "bulb.vibes", "rhs": 0}, context))


func test_an_at_reference_resolves_against_the_device_facts():
	var context: Dictionary = executor.context_for(_solution(), {"mass_kg": 3.5})
	assert_true(executor.evaluate_guard({"op": "==", "lhs": "@mass_kg", "rhs": 3.5}, context))
	assert_false(executor.evaluate_guard({"op": "==", "lhs": "@ghost", "rhs": 3.5}, context))


func test_guards_support_the_full_comparison_set():
	var context := {"x": {"v": 2.0}}
	assert_true(executor.evaluate_guard({"op": ">=", "lhs": "x.v", "rhs": 2.0}, context))
	assert_true(executor.evaluate_guard({"op": "<=", "lhs": "x.v", "rhs": 2.0}, context))
	assert_true(executor.evaluate_guard({"op": ">", "lhs": "x.v", "rhs": 1.0}, context))
	assert_true(executor.evaluate_guard({"op": "<", "lhs": "x.v", "rhs": 3.0}, context))
	assert_true(executor.evaluate_guard({"op": "==", "lhs": "x.v", "rhs": 2.0}, context))
	assert_true(executor.evaluate_guard({"op": "!=", "lhs": "x.v", "rhs": 3.0}, context))


# --- resolution: which rules fire, and what they ask for -------------------------

func test_a_rule_fires_when_its_event_matches_and_its_guard_holds():
	var ast := _rules("""
		device "X" {
		  on step when bulb.power >= 1: shine(target: bulb)
		  on step when cell.level >= 999999: overflow_warning()
		  on strike: clang()
		}
	""")
	var result: Dictionary = executor.resolve(ast, "step", executor.context_for(_solution()))
	assert_eq(result["effects"], [{"atom": "shine", "params": {"target": "bulb"}}])
	assert_eq(result["fired"].size(), 1)


func test_a_guardless_rule_always_fires_for_its_event():
	var ast := _rules('device "X" { on strike: clang() }')
	var result: Dictionary = executor.resolve(ast, "strike", {})
	assert_eq(result["effects"], [{"atom": "clang", "params": {}}])


func test_nothing_fires_for_an_event_no_rule_names():
	var ast := _rules('device "X" { on strike: clang() }')
	var result: Dictionary = executor.resolve(ast, "step", {})
	assert_eq(result["effects"], [])
	assert_eq(result["fired"], [])


func test_an_event_argument_selects_among_rules_the_capture_dsl_way():
	var ast := _rules("""
		device "X" {
		  on strike(anvil): ring()
		  on strike(mud): squelch()
		}
	""")
	assert_eq(executor.resolve(ast, "strike", {}, "mud")["effects"], [{"atom": "squelch", "params": {}}])
	assert_eq(executor.resolve(ast, "strike", {}, "anvil")["effects"], [{"atom": "ring", "params": {}}])
	# No argument asked for: every rule of that event is considered.
	assert_eq(executor.resolve(ast, "strike", {})["effects"].size(), 2)


func test_every_step_of_a_fired_pipeline_is_reported_in_order():
	var ast := _rules('device "X" { on step: warm(amount: 2) |> glow() }')
	var result: Dictionary = executor.resolve(ast, "step", {})
	assert_eq(result["effects"], [
		{"atom": "warm", "params": {"amount": 2}}, {"atom": "glow", "params": {}},
	])


func test_resolve_never_mutates_the_ast_or_the_context():
	var ast := _rules('device "X" { on step when bulb.power >= 1: shine() }')
	var before := str(ast)
	var context: Dictionary = executor.context_for(_solution())
	var context_before := str(context)
	executor.resolve(ast, "step", context)
	assert_eq(str(ast), before)
	assert_eq(str(context), context_before)
