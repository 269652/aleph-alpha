extends GutTest

## Turns a parsed spell AST + live caster state into a GO/NO-GO decision
## (docs/concept/spell_runtime.md). Applying a pipeline's atoms to real
## targets is a separate concern tested elsewhere (Player/CreatureMarker's
## own per-atom methods) -- this covers only "can this cast happen, and what
## does it cost."

const SpellExecutor = preload("res://src/gameplay/spell_executor.gd")
const SpellParser = preload("res://src/gameplay/spell_parser.gd")

var executor := SpellExecutor.new()


func _fire_bolt_ast(event_arg = null, guard = null) -> Dictionary:
	return {
		"kind": "spell",
		"name": "Fire Bolt",
		"rules": [{
			"event": "cast",
			"event_arg": event_arg,
			"guard": guard,
			"pipeline": [{"atom": "fire_damage", "params": {"magnitude": 8}}],
		}],
	}


func test_cast_rule_finds_the_on_cast_rule():
	var rule = executor.cast_rule(_fire_bolt_ast())
	assert_not_null(rule)
	assert_eq(rule["event"], "cast")


func test_cast_rule_is_null_for_a_non_spell_block():
	var enchant_ast := {"kind": "enchant", "name": "Flame Brand", "rules": [{"event": "hit", "pipeline": []}]}
	assert_null(executor.cast_rule(enchant_ast))


func test_cast_rule_is_null_when_no_rule_is_an_on_cast_rule():
	var ast := {"kind": "spell", "name": "Weird", "rules": [{"event": "something_else", "pipeline": []}]}
	assert_null(executor.cast_rule(ast))


func test_delivery_defaults_to_touch_when_no_event_arg_is_given():
	var rule = executor.cast_rule(_fire_bolt_ast())
	assert_eq(executor.delivery_for(rule), "touch")


func test_delivery_reads_the_event_arg_when_given():
	var rule = executor.cast_rule(_fire_bolt_ast("projectile"))
	assert_eq(executor.delivery_for(rule), "projectile")


func test_cost_for_matches_spell_cost_directly():
	var SpellCost = preload("res://src/gameplay/spell_cost.gd")
	var cost_model := SpellCost.new()
	var rule = executor.cast_rule(_fire_bolt_ast())
	var pipeline := [{"atom": "fire_damage", "params": {"magnitude": 8}}]
	assert_almost_eq(
		executor.cost_for(rule), cost_model.paid_mana(pipeline, "touch", 0.0), 0.001
	)


func test_can_cast_is_false_when_mana_is_insufficient():
	var rule = executor.cast_rule(_fire_bolt_ast())
	var cost := executor.cost_for(rule)
	assert_false(executor.can_cast(rule, cost - 0.01, {}))


func test_can_cast_is_true_when_mana_is_sufficient_and_there_is_no_guard():
	var rule = executor.cast_rule(_fire_bolt_ast())
	var cost := executor.cost_for(rule)
	assert_true(executor.can_cast(rule, cost, {}))


func test_can_cast_honors_an_explicit_guard_on_top_of_affordability():
	var guard := {"op": ">=", "lhs": "wielder.mana", "rhs": "@cost"}
	var rule = executor.cast_rule(_fire_bolt_ast(null, guard))
	var cost := executor.cost_for(rule)

	assert_true(executor.can_cast(rule, cost, {"wielder": {"mana": cost}}))
	assert_false(
		executor.can_cast(rule, cost + 100.0, {"wielder": {"mana": 0.0}}),
		"plenty of raw mana doesn't help if the GUARD checks a context value that says otherwise"
	)


func test_can_cast_is_false_when_guard_references_an_unresolvable_path():
	var guard := {"op": ">=", "lhs": "wielder.nonexistent_stat", "rhs": 5.0}
	var rule = executor.cast_rule(_fire_bolt_ast(null, guard))
	var cost := executor.cost_for(rule)
	assert_false(executor.can_cast(rule, cost, {"wielder": {}}))


func test_guard_evaluates_every_comparison_operator():
	var context := {"wielder": {"mana": 10.0}}
	for case in [
		[">=", 10.0, true], [">=", 11.0, false],
		["<=", 10.0, true], ["<=", 9.0, false],
		[">", 9.0, true], [">", 10.0, false],
		["<", 11.0, true], ["<", 10.0, false],
		["==", 10.0, true], ["==", 5.0, false],
		["!=", 5.0, true], ["!=", 10.0, false],
	]:
		var guard := {"op": case[0], "lhs": "wielder.mana", "rhs": case[1]}
		assert_eq(
			executor.evaluate_guard(guard, context, 0.0), case[2],
			"wielder.mana(10.0) %s %s should be %s" % [case[0], case[1], case[2]]
		)


func test_guard_with_no_guard_at_all_always_passes():
	assert_true(executor.evaluate_guard(null, {}, 0.0))


# -- integration: the real parser feeds the executor directly --------------

func test_a_spell_parsed_from_real_dsl_text_can_be_cast():
	var parsed := SpellParser.new().parse(
		'spell "Fire Bolt" { on cast(touch) when wielder.mana >= @cost: fire_damage(magnitude: 8) }'
	)
	assert_true(parsed["ok"], "the example spell text must actually parse")
	var rule = executor.cast_rule(parsed["ast"])
	assert_not_null(rule)
	var cost := executor.cost_for(rule)
	assert_true(executor.can_cast(rule, cost, {"wielder": {"mana": cost}}))
	assert_false(executor.can_cast(rule, cost, {"wielder": {"mana": cost - 0.01}}))
