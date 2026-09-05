extends RefCounted

## The behavior DSL's executor (docs/concept/behavior_dsl.md §3): walks a
## parsed tree against a context, dispatching leaves to
## behavior_atom_catalog.gd. Implements exactly the four node semantics
## the design pillars name -- Selector, Sequence, Parallel, Decorator, per
## Colledanchise & Ogren's formal account, called `priority`/`sequence`/
## `parallel`/`gate` here for a design-facing vocabulary:
##
##   priority  first non-null child wins; null only if every child is
##   sequence  fails (null) at the first null child; the last child's
##             result if every child succeeds
##   parallel  every child runs regardless of the others; returns the
##             Array of all results, null entries included
##   gate      one condition-atom call, then (only if it holds) its one
##             child's result verbatim
##   leaf      BehaviorAtomCatalog.resolve_action(atom, args, context)
##
## No state of its own between calls -- run() is a pure function of its
## two arguments, the same stateless-kernel discipline
## docs/concept/ethogram.md pillar 4 holds its own kernel to. Whatever
## state a tree's decision actually depends on (a genome, a schedule, a
## live AntForageBehavior instance) lives on `context`, supplied by the
## caller, never here.

const BehaviorAtomCatalog = preload("res://src/gameplay/behavior_atom_catalog.gd")


static func run(node: Dictionary, context: Dictionary) -> Variant:
	match String(node.get("kind", "")):
		"leaf":
			return BehaviorAtomCatalog.resolve_action(node["atom"], node.get("args", {}), context)
		"priority":
			return _run_priority(node["children"], context)
		"sequence":
			return _run_sequence(node["children"], context)
		"parallel":
			return _run_parallel(node["children"], context)
		"gate":
			return _run_gate(node, context)
		_:
			return null


static func _run_priority(children: Array, context: Dictionary) -> Variant:
	for child in children:
		var result: Variant = run(child, context)
		if result != null:
			return result
	return null


static func _run_sequence(children: Array, context: Dictionary) -> Variant:
	var result: Variant = null
	for child in children:
		result = run(child, context)
		if result == null:
			return null
	return result


static func _run_parallel(children: Array, context: Dictionary) -> Array:
	var results: Array = []
	for child in children:
		results.append(run(child, context))
	return results


static func _run_gate(node: Dictionary, context: Dictionary) -> Variant:
	var condition: Dictionary = node["condition"]
	var holds := BehaviorAtomCatalog.evaluate_condition(
		condition["name"], condition.get("args", {}), context
	)
	if not holds:
		return null
	return run(node["child"], context)
