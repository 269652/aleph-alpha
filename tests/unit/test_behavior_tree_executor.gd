extends GutTest

## The behavior DSL's executor (docs/concept/behavior_dsl.md §3): walks a
## parsed tree against a context, implementing exactly the four
## behaviour-tree semantics the design pillars name (Selector/priority,
## Sequence, Parallel, Decorator/gate) per Colledanchise & Ogren's formal
## account -- no state of its own between calls, so the same node and
## context always give the same answer.

const BehaviorTreeExecutor = preload("res://src/gameplay/behavior_tree_executor.gd")
const BehaviorDslParser = preload("res://src/gameplay/behavior_dsl_parser.gd")
const AntForageBehavior = preload("res://src/gameplay/ant_forage_behavior.gd")


func _stimulus(at: Vector2, channel: String) -> Dictionary:
	return {"position": at, "features": {channel: 1.0}}


func _leaf(atom: String, args: Dictionary = {}) -> Dictionary:
	return {"kind": "leaf", "atom": atom, "args": args}


# --- leaf: dispatches straight to the atom catalog ------------------------------

func test_a_leaf_dispatches_to_the_named_atom():
	assert_eq(BehaviorTreeExecutor.run(_leaf("wander"), {}), {"intent": "wander"})


func test_a_leaf_for_an_unknown_atom_yields_null_not_a_crash():
	assert_null(BehaviorTreeExecutor.run(_leaf("nonesuch"), {}))


# --- priority: first non-null child wins ----------------------------------------

func test_priority_returns_the_first_non_null_child():
	var node := {
		"kind": "priority",
		"children": [_leaf("seek", {"on": "forage"}), _leaf("wander")],
	}
	var context := {"position": Vector2.ZERO, "stimuli": [_stimulus(Vector2(5, 0), "forage")]}
	assert_eq(BehaviorTreeExecutor.run(node, context)["intent"], "seek")


func test_priority_falls_through_to_a_later_child_when_an_earlier_one_is_null():
	var node := {
		"kind": "priority",
		"children": [_leaf("seek", {"on": "forage"}), _leaf("wander")],
	}
	assert_eq(BehaviorTreeExecutor.run(node, {"position": Vector2.ZERO, "stimuli": []}), {"intent": "wander"})


func test_priority_with_every_child_null_yields_null():
	var node := {"kind": "priority", "children": [_leaf("seek", {"on": "forage"})]}
	assert_null(BehaviorTreeExecutor.run(node, {"position": Vector2.ZERO, "stimuli": []}))


func test_priority_with_no_children_yields_null():
	assert_null(BehaviorTreeExecutor.run({"kind": "priority", "children": []}, {}))


# --- sequence: fail-fast, succeeds only if every child does ---------------------

func test_sequence_returns_the_last_result_when_every_child_succeeds():
	var node := {"kind": "sequence", "children": [_leaf("wander"), _leaf("wander")]}
	assert_eq(BehaviorTreeExecutor.run(node, {}), {"intent": "wander"})


func test_sequence_fails_at_the_first_null_child_without_running_the_rest():
	var node := {
		"kind": "sequence",
		"children": [_leaf("seek", {"on": "forage"}), _leaf("wander")],
	}
	assert_null(BehaviorTreeExecutor.run(node, {"position": Vector2.ZERO, "stimuli": []}))


func test_an_empty_sequence_trivially_succeeds_with_null():
	assert_null(BehaviorTreeExecutor.run({"kind": "sequence", "children": []}, {}))


# --- parallel: every child runs, all results collected --------------------------

func test_parallel_collects_every_childs_result_including_nulls():
	var node := {
		"kind": "parallel",
		"children": [_leaf("wander"), _leaf("seek", {"on": "forage"})],
	}
	var results: Array = BehaviorTreeExecutor.run(node, {"position": Vector2.ZERO, "stimuli": []})
	assert_eq(results.size(), 2)
	assert_eq(results[0], {"intent": "wander"})
	assert_null(results[1])


# --- gate: a condition, then the child verbatim ---------------------------------

func test_gate_runs_its_child_when_the_condition_holds():
	var node := {
		"kind": "gate",
		"condition": {"name": "above", "args": {"need": "hunger", "threshold": 0.5}},
		"child": _leaf("wander"),
	}
	assert_eq(BehaviorTreeExecutor.run(node, {"needs": {"hunger": 0.9}}), {"intent": "wander"})


func test_gate_yields_null_without_running_its_child_when_the_condition_fails():
	var node := {
		"kind": "gate",
		"condition": {"name": "above", "args": {"need": "hunger", "threshold": 0.5}},
		"child": _leaf("wander"),
	}
	assert_null(BehaviorTreeExecutor.run(node, {"needs": {"hunger": 0.1}}))


func test_a_gate_may_wrap_a_composition_block_as_its_child():
	var node := {
		"kind": "gate",
		"condition": {"name": "sensed", "args": {"on": "predator"}},
		"child": {"kind": "priority", "children": [_leaf("flee", {"on": "predator"}), _leaf("wander")]},
	}
	var context := {"position": Vector2.ZERO, "stimuli": [_stimulus(Vector2(10, 0), "predator")]}
	assert_eq(BehaviorTreeExecutor.run(node, context)["intent"], "flee")


# --- determinism ------------------------------------------------------------------

func test_running_the_same_tree_twice_gives_the_same_answer():
	var node := {"kind": "priority", "children": [_leaf("seek", {"on": "forage"}), _leaf("wander")]}
	var context := {"position": Vector2.ZERO, "stimuli": [_stimulus(Vector2(5, 0), "forage")]}
	assert_eq(BehaviorTreeExecutor.run(node, context), BehaviorTreeExecutor.run(node, context))


# --- the payoff: real text, two unrelated species, one shared atom -------------
#
# docs/concept/behavior_dsl.md's own worked examples, parsed by the real
# parser and run by the real executor -- the reuse claim exercised end to
# end, not merely argued. A land mammal and a villager share no code, no
# genome, and no body plan, and yet gate(above(...)) is the identical three
# tokens doing identical work for both.

const MAMMAL_SCRIPT := """
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

const VILLAGER_SCRIPT := """
behavior "villager" {
    priority {
        gate(above(need: hunger, threshold: 0.5)) {
            seek(on: forage)
        }
        schedule()
    }
}
"""

const ANT_SCRIPT := """
behavior "ant_forager" {
    round_trip()
}
"""


func _tree(source: String, name: String) -> Dictionary:
	var parser := BehaviorDslParser.new()
	var result := parser.parse(source)
	assert_true(result["ok"], "expected parse to succeed: %s" % [result["errors"]])
	return result["behaviors"][name]


func test_a_hungry_thirsty_mammal_flees_over_everything_else():
	var tree := _tree(MAMMAL_SCRIPT, "mammal")
	var context := {
		"position": Vector2.ZERO,
		"needs": {"hunger": 0.9, "thirst": 0.9},
		"stimuli": [
			_stimulus(Vector2(10, 0), "predator"),
			_stimulus(Vector2(0, 5), "water"),
			_stimulus(Vector2(0, -5), "forage"),
		],
	}
	assert_eq(BehaviorTreeExecutor.run(tree, context)["intent"], "flee")


func test_an_unthreatened_thirsty_mammal_seeks_water_before_food():
	var tree := _tree(MAMMAL_SCRIPT, "mammal")
	var context := {
		"position": Vector2.ZERO,
		"needs": {"hunger": 0.9, "thirst": 0.9},
		"stimuli": [_stimulus(Vector2(0, 5), "water"), _stimulus(Vector2(0, -5), "forage")],
	}
	var decision: Variant = BehaviorTreeExecutor.run(tree, context)
	assert_eq(decision["intent"], "seek")
	assert_eq(decision["target"], Vector2(0, 5))


func test_a_sated_mammal_with_nothing_pressing_wanders():
	var tree := _tree(MAMMAL_SCRIPT, "mammal")
	var context := {
		"position": Vector2.ZERO, "needs": {"hunger": 0.1, "thirst": 0.1},
		"stimuli": [_stimulus(Vector2(0, -5), "forage")],
	}
	assert_eq(BehaviorTreeExecutor.run(tree, context), {"intent": "wander"})


## The reuse claim, concretely: the SAME above() gate, unmodified, fires
## for a villager exactly as it did for the mammal above.
func test_a_hungry_villager_seeks_forage_through_the_same_gate_the_mammal_used():
	var tree := _tree(VILLAGER_SCRIPT, "villager")
	var context := {
		"position": Vector2.ZERO,
		"needs": {"hunger": 0.9},
		"stimuli": [_stimulus(Vector2(0, -5), "forage")],
		"schedule": [], "hour": 10,
	}
	var decision: Variant = BehaviorTreeExecutor.run(tree, context)
	assert_eq(decision["intent"], "seek")
	assert_eq(decision["target"], Vector2(0, -5))


func test_a_fed_villager_falls_back_to_its_schedule():
	var tree := _tree(VILLAGER_SCRIPT, "villager")
	var context := {
		"position": Vector2.ZERO, "needs": {"hunger": 0.1}, "stimuli": [],
		"schedule": [{"time_block": "morning", "location_tag": "field", "activity": "work"}],
		"hour": 8,
	}
	var decision: Variant = BehaviorTreeExecutor.run(tree, context)
	assert_eq(decision["intent"], "schedule")
	assert_eq(decision["location_tag"], "field")


func test_an_ant_forager_tree_reports_its_own_round_trip_phase():
	var tree := _tree(ANT_SCRIPT, "ant_forager")
	var behavior := AntForageBehavior.new()
	assert_eq(BehaviorTreeExecutor.run(tree, {"round_trip": behavior}), {"intent": "approaching"})
	behavior.arrive_at_food(true)
	assert_eq(BehaviorTreeExecutor.run(tree, {"round_trip": behavior}), {"intent": "returning"})
