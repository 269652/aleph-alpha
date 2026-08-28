extends RefCounted

## Turns a parsed spell AST (spell_parser.gd) + live caster state into a
## GO/NO-GO decision (docs/concept/spell_runtime.md). Pure -- applying the
## resolved pipeline's atoms to real targets is a separate concern (see
## Player/CreatureMarker's own per-atom methods); this only answers "can
## this cast happen, and what does it cost."

const SpellCost = preload("res://src/gameplay/spell_cost.gd")

## `on EVENT(ARG):` -- delivery rides the parser's existing event_arg slot
## (see spell_runtime.md's own section on this) rather than a new grammar
## feature. Most single-target spells are point-blank contact by default.
const DEFAULT_DELIVERY := "touch"

var _cost := SpellCost.new()


## The AST's "on cast" rule (kind == "spell" blocks only -- enchant/instruct
## are the DSL's other two surface forms and stay out of scope here, see
## spell_runtime.md), or null if there isn't one.
func cast_rule(ast: Dictionary):
	if ast.get("kind", "") != "spell":
		return null
	for rule in ast.get("rules", []):
		if rule.get("event", "") == "cast":
			return rule
	return null


## The delivery method a cast rule resolves to: its event_arg if given, else
## the default. event_arg is untyped in the parser (an ident or a number);
## only a String value is meaningful here.
func delivery_for(rule: Dictionary) -> String:
	var event_arg = rule.get("event_arg")
	if event_arg == null:
		return DEFAULT_DELIVERY
	return String(event_arg)


func cost_for(rule: Dictionary, governing_stat: float = 0.0) -> float:
	return _cost.paid_mana(rule.get("pipeline", []), delivery_for(rule), governing_stat)


func cast_time_for(rule: Dictionary, haste_stat: float = 0.0) -> float:
	return _cost.cast_time(rule.get("pipeline", []), delivery_for(rule), haste_stat)


## Resolves one guard operand (see spell_parser.gd's _parse_operand, whose
## three shapes this mirrors exactly): a raw number, an "@ref" (only "@cost"
## means anything today -- resolves to the already-computed cost), or a
## dotted path walked against `context` (e.g. "wielder.mana" reads
## context["wielder"]["mana"]). An unresolvable path or unknown @ref
## resolves to 0.0 rather than erroring -- a malformed/unmet reference fails
## whatever comparison it's in instead of crashing the cast.
func _resolve_operand(operand, context: Dictionary, computed_cost: float) -> float:
	if operand is float or operand is int:
		return float(operand)
	var text := String(operand)
	if text == "@cost":
		return computed_cost
	if text.begins_with("@"):
		return 0.0
	var current: Variant = context
	for segment in text.split("."):
		if not (current is Dictionary) or not current.has(segment):
			return 0.0
		current = current[segment]
	return float(current) if (current is float or current is int) else 0.0


## true if `guard` is absent/empty (nothing to check), else the real
## comparison. Every operator spell_parser.gd's grammar accepts.
func evaluate_guard(guard, context: Dictionary, computed_cost: float) -> bool:
	if guard == null or not (guard is Dictionary) or guard.is_empty():
		return true
	var lhs := _resolve_operand(guard["lhs"], context, computed_cost)
	var rhs := _resolve_operand(guard["rhs"], context, computed_cost)
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
			return is_equal_approx(lhs, rhs)
		"!=":
			return not is_equal_approx(lhs, rhs)
	return true


## Full decision: can `rule` be cast right now. Cost is ALWAYS enforced
## (Constraint layer 1, magic.md) regardless of whether the spell text also
## writes an explicit `when` guard -- an explicit guard is an ADDITIONAL
## condition an author can add on top, never a way to skip the baseline
## affordability check by simply not writing one.
func can_cast(rule: Dictionary, caster_mana: float, context: Dictionary, governing_stat: float = 0.0) -> bool:
	var cost := cost_for(rule, governing_stat)
	if caster_mana < cost:
		return false
	return evaluate_guard(rule.get("guard"), context, cost)
