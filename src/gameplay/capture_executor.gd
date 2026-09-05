extends RefCounted

## The capture DSL executor (docs/concept/capture_dsl.md): decides whether a
## capture action happens and which effect atoms actually apply. Pure --
## like spell_executor.gd, it does not mutate any game state itself
## (capture_atom_effects.gd does that once the caller applies the reported
## effects) and it does not generate its own randomness. The roll is
## supplied by the caller, the same split CreatureMarker._step_restraint's
## own hash roll already keeps between "pure decision given a roll" and
## "where the roll comes from".

const CaptureAtomCatalog = preload("res://src/gameplay/capture_atom_catalog.gd")
const CapturePhysics = preload("res://src/gameplay/capture_physics.gd")
const FlyerPersonality = preload("res://src/gameplay/flyer_personality.gd")

var _catalog := CaptureAtomCatalog.new()
var _physics := CapturePhysics.new()


# --- finding rules ------------------------------------------------------------

func capture_rule(ast: Dictionary) -> Variant:
	return _find_rule(ast, "catch", null)


func release_rule(ast: Dictionary) -> Variant:
	return _find_rule(ast, "release", null)


## `container_id` matches the rule's event_arg -- `on transfer(glass_bottle)`
## reuses that slot to name which container a rule handles, the same reuse
## trick `on cast(touch)` already makes of it for delivery method.
func transfer_rule(ast: Dictionary, container_id: String) -> Variant:
	return _find_rule(ast, "transfer", container_id)


func _find_rule(ast: Dictionary, event: String, event_arg: Variant) -> Variant:
	for rule in ast.get("rules", []):
		if rule.get("event", "") != event:
			continue
		if event_arg != null and rule.get("event_arg") != event_arg:
			continue
		return rule
	return null


# --- guard evaluation ---------------------------------------------------------

## A null guard always passes -- a rule with no `when` clause always applies
## once its event/event_arg matched.
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


## A dotted path (contains ".") is walked against `context`; anything else
## (a number, or a bare string like "flyer") is a literal, returned as-is.
## An unresolved path returns null rather than crashing on a missing key.
func _resolve_operand(operand: Variant, context: Dictionary) -> Variant:
	if operand is String and operand.contains("."):
		var value: Variant = context
		for part in operand.split("."):
			if value is Dictionary and value.has(part):
				value = value[part]
			else:
				return null
		return value
	return operand


# --- resolution: guard, then (for catch) a roll, then the effects list ------

## `roll` in [0, 1): success means it beats the derived chance, the same
## "roll < chance" convention Taming._step_restraint already uses.
func resolve_catch(rule: Variant, context: Dictionary, roll: float) -> Dictionary:
	var result := _resolve_pipeline(rule, context, roll)
	return {"caught": result["ok"], "effects": result["effects"]}


func resolve_release(rule: Variant, context: Dictionary) -> Dictionary:
	var result := _resolve_pipeline(rule, context, 0.0)
	return {"released": result["ok"], "effects": result["effects"]}


func resolve_transfer(rule: Variant, context: Dictionary) -> Dictionary:
	var result := _resolve_pipeline(rule, context, 0.0)
	return {"transferred": result["ok"], "effects": result["effects"]}


## Shared walk: a null rule or a failed guard means nothing happens. Every
## non-"roll" atom in the pipeline is collected as an effect to apply; a
## "roll" atom (today, only catch_roll) resolves its own pass/fail from
## capture_physics and, on failure, short-circuits -- nothing after it
## applies. This is capture's own constraint layer (capture_dsl.md: "a
## pipeline can fail partway, on purpose"), the one significant divergence
## from magic's unconditional-sequence pipeline.
func _resolve_pipeline(rule: Variant, context: Dictionary, roll: float) -> Dictionary:
	if rule == null or not evaluate_guard(rule.get("guard"), context):
		return {"ok": false, "effects": []}
	var effects: Array = []
	for step in rule.get("pipeline", []):
		var atom_id: String = step["atom"]
		if _catalog.has(atom_id) and _catalog.category(atom_id) == "roll":
			if not _passes_roll(step, context, roll):
				return {"ok": false, "effects": []}
		else:
			effects.append(step)
	return {"ok": true, "effects": effects}


func _passes_roll(step: Dictionary, context: Dictionary, roll: float) -> bool:
	var base: float = float(step["params"].get("base", 0.0))
	var target: Dictionary = context.get("target", {})
	var boldness: float = float(target.get("boldness", FlyerPersonality.MIDDLING_BOLDNESS))
	var chance := _physics.catch_chance(base, boldness)
	return roll < chance
