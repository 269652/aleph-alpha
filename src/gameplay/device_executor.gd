extends RefCounted

## The rule half of docs/concept/standard_model.md ("5. Resolution order",
## step 6): the solved state of a device becomes a context Dictionary keyed
## by element id, and the device's `on EVENT when GUARD: pipeline` rules are
## evaluated against it. Pure -- like spell_executor.gd and
## capture_executor.gd it mutates nothing and generates nothing; it reports
## which effects apply, and dispatching them into the world is the concept
## doc's own designed-but-unbuilt effects layer.
##
## A structural sibling of capture_executor.gd (same guard evaluation, same
## "a null guard always passes", same dotted-path walk), deliberately not a
## subclass: devices are their own domain, with one addition -- an
## @reference (`@mass_kg`) resolves against the device-level facts the
## compiler knows, the way `@cost` resolves against the spell runtime's own
## computed cost.


# --- the context ----------------------------------------------------------------

## Every solved element by id, each carrying its port effort/flow, its power
## in/out, what it dissipated and what it stored, plus -- for a store -- its
## level and capacity after the tick. `device_facts` (the compiler's mass and
## anything else a caller wants @-addressable) lands under "device" together
## with the source's flow and power. An unsolved result yields only the
## device facts: nothing to read, nothing invented.
func context_for(solution: Dictionary, device_facts: Dictionary = {}) -> Dictionary:
	var context := {}
	if solution.get("ok", false):
		for id in solution.get("order", []):
			var record: Dictionary = solution["elements"][String(id)].duplicate()
			var stores: Dictionary = solution.get("stores", {})
			if stores.has(String(id)):
				var store: Dictionary = stores[String(id)]
				record["level"] = store["level"]
				record["capacity"] = store["capacity"]
				record["overflow_j"] = store["overflow_j"]
				record["depleted"] = store["depleted"]
			context[String(id)] = record
	var device := device_facts.duplicate()
	device["source_flow"] = solution.get("source_flow", 0.0)
	device["source_effort"] = solution.get("source_effort", 0.0)
	device["source_power"] = solution.get("source_power", 0.0)
	device["dissipated_power"] = solution.get("dissipated_power", 0.0)
	device["stored_power"] = solution.get("stored_power", 0.0)
	context["device"] = device
	return context


# --- guard evaluation ---------------------------------------------------------------

## A null guard always passes -- a rule with no `when` clause always applies
## once its event matched. An operand that cannot be resolved fails the
## guard rather than crashing: a rule about an element that is not in the
## solved loop simply does not fire.
func evaluate_guard(guard: Variant, context: Dictionary) -> bool:
	if guard == null:
		return true
	var lhs: Variant = _resolve_operand(guard["lhs"], context)
	var rhs: Variant = _resolve_operand(guard["rhs"], context)
	if lhs == null or rhs == null:
		return false
	match guard["op"]:
		">=":
			return lhs >= rhs
		"<=":
			return lhs <= rhs
		">":
			return lhs > rhs
		"<":
			return lhs < rhs
		"==":
			return lhs == rhs
		"!=":
			return lhs != rhs
		_:
			return false


## A dotted path (contains ".") is walked against `context`; an @reference
## is looked up under the device facts; anything else (a number, or a bare
## string) is a literal, returned as-is. An unresolved path returns null.
func _resolve_operand(operand: Variant, context: Dictionary) -> Variant:
	if operand is String and operand.begins_with("@"):
		var device: Dictionary = context.get("device", {})
		return device.get(operand.substr(1), null)
	if operand is String and operand.contains("."):
		var value: Variant = context
		for part in operand.split("."):
			if value is Dictionary and value.has(part):
				value = value[part]
			else:
				return null
		return value
	return operand


# --- resolution --------------------------------------------------------------------

## Every rule of `event` (and of `event_arg`, when one is asked for -- the
## same slot reuse `on transfer(glass_bottle)` makes in the capture DSL)
## whose guard holds against `context`, in source order, with every step of
## every fired pipeline flattened into `effects` for a dispatcher to apply.
## Duplicated on the way out, so nothing downstream can reach back into the
## AST.
func resolve(ast: Dictionary, event: String, context: Dictionary, event_arg: Variant = null) -> Dictionary:
	var fired: Array = []
	var effects: Array = []
	for rule in ast.get("rules", []):
		if rule.get("event", "") != event:
			continue
		if event_arg != null and rule.get("event_arg") != event_arg:
			continue
		if not evaluate_guard(rule.get("guard"), context):
			continue
		fired.append(rule.duplicate(true))
		for step in rule.get("pipeline", []):
			effects.append(step.duplicate(true))
	return {"fired": fired, "effects": effects}
