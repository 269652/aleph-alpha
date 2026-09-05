extends RefCounted

## The behavior DSL's atom catalog (docs/concept/behavior_dsl.md §2): the
## registry of reusable named behaviors a parsed tree references. Exactly
## npc_instruction_primitives.gd's own split -- CONDITION_ATOMS (used only
## inside `gate`, `(args, context) -> bool`) and ACTION_ATOMS (used only as
## a leaf, `(args, context) -> Dictionary or null`) -- so a name used in
## the wrong slot fails closed the same way an unrecognised name does,
## never a silent coercion.
##
## Every action atom here is a thin wrapper, never a reimplementation:
## flee/seek reuse Affinity/BehaviorKernel verbatim with no genome and no
## species record involved anywhere (the "not based on genetics" half of
## the doc made concrete -- the same ranking math ethogram.md built, used
## here as a plain computational tool rather than gated by receptor
## expression); schedule wraps NpcSchedule.current_entry unmodified;
## round_trip reads an AntForageBehavior instance's own phase without
## driving it. Pure, no engine dependency, no RNG.

const Affinity = preload("res://src/gameplay/affinity.gd")
const BehaviorKernel = preload("res://src/gameplay/behavior_kernel.gd")
const NpcSchedule = preload("res://src/world/npc_schedule.gd")
const AntForageBehavior = preload("res://src/gameplay/ant_forage_behavior.gd")

const CONDITION_ATOMS: Array[String] = ["above", "sensed"]
const ACTION_ATOMS: Array[String] = ["wander", "flee", "seek", "schedule", "round_trip"]


## `args.on`/repeated-key values may be a bare scalar or a list (see the
## parser's own accumulation rule) -- every multi-channel atom normalises
## through this rather than checking `is Array` itself in three places.
static func as_list(value: Variant) -> Array:
	if value == null:
		return []
	if value is Array:
		return value
	return [value]


## Dispatches a condition atom by name. An action name, or any name not in
## CONDITION_ATOMS, fails closed to false -- a condition that "doesn't
## hold" is indistinguishable from one that doesn't exist, on purpose: a
## gate guarding against a typo should skip its child, never crash.
static func evaluate_condition(name: String, args: Dictionary, context: Dictionary) -> bool:
	match name:
		"above":
			return _above(args, context)
		"sensed":
			return _sensed(args, context)
		_:
			return false


## Dispatches an action atom by name. A condition name, or any name not in
## ACTION_ATOMS, fails closed to null -- "this leaf did not fire," the same
## answer a tree gives when nothing sensed matches.
static func resolve_action(name: String, args: Dictionary, context: Dictionary) -> Variant:
	match name:
		"wander":
			return _wander(args, context)
		"flee":
			return _flee(args, context)
		"seek":
			return _seek(args, context)
		"schedule":
			return _schedule(args, context)
		"round_trip":
			return _round_trip(args, context)
		_:
			return null


# --- conditions -----------------------------------------------------------------

## True once `context["needs"][args.need]` exceeds `args.threshold` --
## strictly greater, matching need_above's own "has crossed it" contract.
## Fails open to 0.0 for a need not present, or no needs dict at all: an
## unmeasured need is not treated as urgent, the same fail-open convention
## every needs-reading primitive in this project already uses.
static func _above(args: Dictionary, context: Dictionary) -> bool:
	var needs: Dictionary = context.get("needs", {})
	var value := float(needs.get(String(args.get("need", "")), 0.0))
	return value > float(args.get("threshold", 0.0))


## True if any stimulus in context["stimuli"] carries a feature on any of
## the named channels -- pure presence, no sensitivity/valence weighting,
## because this atom answers "is anything out there," not "do I care."
static func _sensed(args: Dictionary, context: Dictionary) -> bool:
	var channels := as_list(args.get("on"))
	for stimulus in context.get("stimuli", []):
		var features: Dictionary = stimulus.get("features", {})
		for channel in channels:
			if features.has(channel):
				return true
	return false


# --- actions --------------------------------------------------------------------

## The universal fallback: fires unconditionally, for any species' tree to
## end on.
static func _wander(_args: Dictionary, _context: Dictionary) -> Variant:
	return {"intent": "wander"}


static func _flee(args: Dictionary, context: Dictionary) -> Variant:
	return _rank(args, context, -1.0, false, "flee")


static func _seek(args: Dictionary, context: Dictionary) -> Variant:
	return _rank(args, context, 1.0, true, "seek")


## Ranks context["stimuli"] on the named channels through BehaviorKernel.
## best_stimulus, with a flat sensitivity/valence built from `args.on`
## alone -- no genome, no species record, no receptor expression: the
## computational core ethogram.md built, reused here as a plain tool.
static func _rank(
	args: Dictionary, context: Dictionary, valence: float, attract_only: bool, intent: String
) -> Variant:
	var channels := as_list(args.get("on"))
	if channels.is_empty():
		return null
	var sensitivity := {}
	var valences := {}
	for channel in channels:
		sensitivity[channel] = 1.0
		valences[channel] = valence
	var receptors := {"sensitivity": sensitivity, "valence": valences}
	var position: Vector2 = context.get("position", Vector2.ZERO)
	var best: Dictionary = BehaviorKernel.best_stimulus(
		receptors, channels, position, context.get("stimuli", []), 1.0, 0.0, attract_only
	)
	if best.is_empty():
		return null
	var stimulus: Dictionary = best["stimulus"]
	var at: Vector2 = stimulus["position"]
	var direction := Affinity.away_from(position, at) if valence < 0.0 else Affinity.toward(position, at)
	return {"intent": intent, "direction": direction, "target": at, "stimulus": stimulus}


## Wraps NpcSchedule.current_entry unmodified. Null with no schedule at all
## (an isolated test context, or a marker not yet given one) rather than
## fabricating a location.
static func _schedule(_args: Dictionary, context: Dictionary) -> Variant:
	var schedule: Array = context.get("schedule", [])
	if schedule.is_empty():
		return null
	var entry := NpcSchedule.current_entry(schedule, int(context.get("hour", 0)))
	return {
		"intent": "schedule",
		"location_tag": entry.get("location_tag", "home"),
		"activity": entry.get("activity", ""),
	}


## Reads (never drives) an AntForageBehavior instance's own phase --
## whatever advances that phase (arrive_at_food, begin_approach) stays the
## caller's job, exactly as ethogram.md's motor programs stay theirs.
static func _round_trip(_args: Dictionary, context: Dictionary) -> Variant:
	var behavior = context.get("round_trip")
	if behavior == null:
		return null
	var approaching: bool = behavior.phase == AntForageBehavior.Phase.APPROACHING
	return {"intent": "approaching" if approaching else "returning"}
