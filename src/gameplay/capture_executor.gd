extends RefCounted

## The capture DSL executor (docs/concept/capture_dsl.md): decides whether a
## capture action happens and which effect atoms actually apply. Pure --
## like spell_executor.gd, it does not mutate any game state itself
## (capture_atom_effects.gd does that once the caller applies the reported
## effects) and it does not generate its own randomness. The roll is
## supplied by the caller, the same split CreatureMarker._step_restraint's
## own hash roll already keeps between "pure decision given a roll" and
## "where the roll comes from".
##
## ## Revised 2026-09-05: a pipeline has a physics gate and a static check
##
## The net is device text now (standard_model.md's grammar), and its catch
## pipeline is `mesh_holds(mesh: bag) |> catch_roll(base: 0.65) |>
## confine(in: bag)`:
##
## - `mesh_holds` is a CHECK atom: it reads the named bag's real geometry
##   off the context (the compiler's part facts -- `bag.aperture_mm`,
##   `bag.width_cm`) and the subject's measured extents, asks
##   CapturePhysics.mesh_verdict, and fails WITH A REASON ("the bee slips
##   through the 10 mm mesh") when the subject slips through, is too big for
##   the mouth, or has no measured size. A player told the reason can act on
##   it -- weave a finer bag, build a bigger one -- which is the same
##   legibility rule affordance_notes.gd holds crafting to.
## - `catch_roll` is a ROLL atom: it fails silently. A miss is a miss.
## - `confine(in: bag)` is an EFFECT, and validate() below refuses any text
##   in which it does not follow a `mesh_holds` on the same part in the same
##   pipeline: an author cannot write a net that ignores its own mesh. That
##   check is static -- the same way ItemCompiler resolves an affordance's
##   conjunctions at compile time -- and CaptureBook runs it at load.
##
## The executor never knew which parser produced its AST and still does not:
## rules are the same four-key shape every DSL in this project emits.

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


# --- resolution: guard, then the pipeline's gates, then the effects list ------

## `roll` in [0, 1): success means it beats the derived chance, the same
## "roll < chance" convention Taming._step_restraint already uses. `reason`
## is non-empty only when a check atom refused -- a lost roll is silent.
func resolve_catch(rule: Variant, context: Dictionary, roll: float) -> Dictionary:
	var result := _resolve_pipeline(rule, context, roll)
	return {"caught": result["ok"], "effects": result["effects"], "reason": result["reason"]}


func resolve_release(rule: Variant, context: Dictionary) -> Dictionary:
	var result := _resolve_pipeline(rule, context, 0.0)
	return {"released": result["ok"], "effects": result["effects"], "reason": result["reason"]}


func resolve_transfer(rule: Variant, context: Dictionary) -> Dictionary:
	var result := _resolve_pipeline(rule, context, 0.0)
	return {"transferred": result["ok"], "effects": result["effects"], "reason": result["reason"]}


## Shared walk: a null rule or a failed guard means nothing happens. A
## "check" atom asks the physics and, on refusal, short-circuits with its
## reason; a "roll" atom resolves its own pass/fail against the supplied
## roll and, on failure, short-circuits silently; every other atom is
## collected as an effect to apply. This is capture's own constraint layer
## (capture_dsl.md: "a pipeline can fail partway, on purpose"), the one
## significant divergence from magic's unconditional-sequence pipeline.
func _resolve_pipeline(rule: Variant, context: Dictionary, roll: float) -> Dictionary:
	if rule == null or not evaluate_guard(rule.get("guard"), context):
		return {"ok": false, "effects": [], "reason": ""}
	var effects: Array = []
	for step in rule.get("pipeline", []):
		var atom_id: String = step["atom"]
		var category: String = _catalog.category(atom_id) if _catalog.has(atom_id) else "effect"
		match category:
			"check":
				var verdict := _check(step, context)
				if not bool(verdict["holds"]):
					return {"ok": false, "effects": [], "reason": verdict["reason"]}
			"roll":
				if not _passes_roll(step, context, roll):
					return {"ok": false, "effects": [], "reason": ""}
			_:
				effects.append(step)
	return {"ok": true, "effects": effects, "reason": ""}


## mesh_holds: the named part's facts (aperture and mouth) against the
## subject's extents. A bag with no `aperture_mm` is solid cloth and holds
## everything; one with no `width_cm` has no mouth and takes nothing.
func _check(step: Dictionary, context: Dictionary) -> Dictionary:
	var target: Dictionary = context.get("target", {})
	var species := String(target.get("species", "subject"))
	var mesh_id := String(step.get("params", {}).get("mesh", ""))
	var facts: Variant = context.get(mesh_id, null)
	if not (facts is Dictionary):
		return {"holds": false, "reason": "the net has no part '%s' to hold with" % mesh_id}
	var verdict: Dictionary = _physics.mesh_verdict(
		Array(target.get("extents_mm", [])),
		float(facts.get("aperture_mm", 0.0)),
		float(facts.get("width_cm", 0.0)) * 10.0
	)
	if bool(verdict["holds"]):
		return verdict
	if String(verdict.get("code", "")) == CapturePhysics.CODE_UNMEASURED:
		return {"holds": false, "reason": "the net has no measure of a %s's size" % species}
	return {"holds": false, "reason": "the %s %s" % [species, verdict["reason"]]}


func _passes_roll(step: Dictionary, context: Dictionary, roll: float) -> bool:
	var base: float = float(step["params"].get("base", 0.0))
	var target: Dictionary = context.get("target", {})
	var boldness: float = float(target.get("boldness", FlyerPersonality.MIDDLING_BOLDNESS))
	var chance := _physics.catch_chance(base, boldness)
	return roll < chance


# --- validate: the static constraint layer ----------------------------------------

## Every problem in a device's rules, in source order -- [] for a text that
## may ship. An unknown atom; an atom missing a parameter it cannot run
## without; a part-naming atom naming a part the device does not declare;
## and the load-bearing one: a `confine(in: X)` not preceded, in its own
## pipeline, by a `mesh_holds(mesh: X)` -- nothing else has said X can hold
## what it confines. Reports every problem rather than the first, so an
## author fixes a text in one pass.
func validate(ast: Dictionary) -> Array:
	var errors: Array = []
	var declared := {}
	for part in ast.get("parts", []):
		declared[String(part["id"])] = true
	for rule in ast.get("rules", []):
		var label := "on %s" % rule.get("event", "?")
		if rule.get("event_arg") != null:
			label += "(%s)" % rule["event_arg"]
		var held := {}
		for step in rule.get("pipeline", []):
			var atom_id := String(step.get("atom", ""))
			var params: Dictionary = step.get("params", {})
			if not _catalog.has(atom_id):
				errors.append("%s: unknown atom '%s'" % [label, atom_id])
				continue
			var missing := false
			for name in _catalog.required_params(atom_id):
				if not params.has(name):
					errors.append("%s: %s needs '%s'" % [label, atom_id, name])
					missing = true
			if missing:
				continue
			var part_param := _catalog.part_param(atom_id)
			if part_param == "":
				continue
			var part_id := String(params[part_param])
			if not declared.has(part_id):
				errors.append(
					"%s: %s names part '%s', which this device does not declare"
					% [label, atom_id, part_id]
				)
			match atom_id:
				"mesh_holds":
					held[part_id] = true
				"confine":
					if not held.has(part_id):
						errors.append(
							"%s: confine(in: %s) needs mesh_holds(mesh: %s) before it in the"
							% [label, part_id, part_id]
							+ " same pipeline -- nothing else says '%s' can hold what it confines"
							% part_id
						)
	return errors
