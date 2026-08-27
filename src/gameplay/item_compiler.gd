extends RefCounted

## An item is a small program, and crafting is the compiler. Pure logic, no
## engine, no scene tree. Design doc: docs/concept/emergent_crafting.md.
##
## ## The thesis
##
## An assembly (a PartGraph) compiles to a list of `event -> guard -> pipeline`
## RULES in the SAME AST shape spell_parser.gd already produces for player-
## written magic. Affordances -- "it cuts", "it rips" -- are a UI PROJECTION
## over those rules, never the output itself.
##
## That single choice is the whole point. Derived physics and a hand-authored
## enchantment are then the same kind of thing, so a Flame Brand enchantment and
## a blade's own cut rule merge into one list on one item with no adapter
## between them. Had this emitted `{"cuts": true, "damage": 7}` instead, the two
## would have been different kinds of thing forever.
## test_a_compiled_rule_has_the_same_shape_as_a_parsed_spell_rule is what holds
## the two shapes together.
##
## ## Guards are single comparisons, and that is a FEATURE
##
## spell_parser's `_parse_guard` is one comparison -- there is no `and`. So every
## conjunction in an affordance predicate is evaluated STATICALLY, here, at
## compile time: either the rule is emitted, or it is not and a note says WHICH
## clause failed. What is left in the guard is the one genuinely dynamic term,
## the momentum of the actual blow.
##
## The consequence is the thing this file is really for: "why can't this chop?"
## has an answer. An emergent system whose failures are silent is an unlearnable
## black box, so the absence reasons are a feature and are tested like one (see
## affordance_notes.gd, which projects them at the player).
##
## ## Nothing here branches on what an assembly IS
##
## There is no "is this a saw" test and there deliberately cannot be one, for
## the same reason PartGraph has none. A saw rips because its edge carries a
## tooth pitch and a set that cuts a kerf wider than its own plate; an axe does
## not because its bit is a transverse wedge. Both facts are read off geometry.
##
## ## Status: does anything CALL this?
##
## As of this commit, NO -- and that matters, because a tested module nothing
## calls is this codebase's dominant defect. The bridge is named honestly in
## docs/concept/emergent_crafting.md: scenes/player.gd's `equipped_item` is an
## `Item`, not an assembly, and `Item.is_saw()/is_axe()/is_pickaxe()` are still
## `id.contains(...)` string hacks. Retiring them needs an `Item.affords()` that
## resolves an assembly through CraftedItemRegistry, which is deliberately NOT
## in this slice.

const ItemPart: GDScript = preload("res://src/gameplay/item_part.gd")
const PartMechanics: GDScript = preload("res://src/gameplay/part_mechanics.gd")
const ImpactResolver: GDScript = preload("res://src/gameplay/impact_resolver.gd")
const MaterialProperties: GDScript = preload("res://src/gameplay/material_properties.gd")

## The verbs this compiler can emit, in a fixed order so two compiles of one
## assembly never disagree about the order of their own affordances.
const VERB_CUT := "cut"
const VERB_CHOP := "chop"
const VERB_RIP := "rip"
const VERB_PIERCE := "pierce"
const VERB_CRUSH := "crush"
const VERB_PARRY := "parry"

const VERBS: Array[String] = [
	VERB_CUT, VERB_CHOP, VERB_RIP, VERB_PIERCE, VERB_CRUSH, VERB_PARRY,
]

## The actor an affordance is decided against.
##
## An affordance has to be settled at BUILD time, before the compiler knows
## whose hand it ends up in, so the static momentum clause asks about the
## reference adult PartMechanics' torque constant was calibrated for -- the one
## who swings the framing hammer at its measured speed. A stronger wielder still
## hits harder at runtime; what they do not get is a different set of verbs,
## because "this saw becomes an axe if you are strong enough" is not a thing.
const NOMINAL_ACTOR_STRENGTH: float = 1.0

## The included angle where a bevel stops severing fibres and starts merely
## splitting them.
##
## Real woodworking practice draws this line at about 30 degrees: knives and
## carving tools live below it, splitting wedges and froes above it, and axes
## straddle it at 25-30 depending on whether they are meant to fell or to split.
## ItemPart already pins the two ENDS of the range (15 degrees razor, 40 degrees
## axe bit); this is the transition inside it.
##
## Pinned by test_the_cut_line_sits_between_the_shipped_razor_and_wedge_angles.
const CUTTING_GRIND_ANGLE_DEG: float = 30.0

## The material the "keen" threshold is defined on. Not a preference: it is the
## material MaterialProperties.KEEN_SHARPNESS was itself set from -- that
## constant's own doc comment says it is "iron's own sharpness_capacity (8.0),
## the material the game treats as the benchmark blade". Pinned equal by
## test_the_cut_threshold_is_the_benchmark_blade_material_at_the_cutting_line.
const BENCHMARK_BLADE_MATERIAL := "iron"


## The least keenness an edge must actually realize to sever rather than split.
##
## DERIVED, never written down: it is the benchmark blade material ground at the
## cutting line, measured with ItemPart's own keenness() rather than by
## restating its formula here. Restating it is exactly the drift this codebase
## keeps getting bitten by -- change the sharpening range in item_part.gd and
## this moves with it, because it is literally an ItemPart being asked.
static func cut_keenness_min() -> float:
	return ItemPart.new(
		BENCHMARK_BLADE_MATERIAL, ItemPart.GEOMETRY_EDGE, ItemPart.ROLE_WORKING,
		{
			"length_cm": 1.0, "width_cm": 1.0, "thickness_cm": 1.0,
			"angle_deg": CUTTING_GRIND_ANGLE_DEG,
		}
	).keenness()


## How keen an edge a crafter of this skill actually achieves on `part`.
##
## A novice cannot put a razor edge on steel; what they produce is a wedge. So
## skill interpolates the REALIZED grind angle from ItemPart.WEDGE_ANGLE_DEG
## (skill 0 -- the blunt end of real sharpening practice) to the angle the part
## was designed with (skill 1). Both ends are shipped symbols, so this needed no
## constant of its own -- the alternative, a "skill factor" multiplier with a
## floor picked to feel right, would have been a tuned number with nothing
## behind it.
##
## The keenness itself comes back from a real ItemPart at the realized angle, so
## the grind formula lives in exactly one place.
static func realized_keenness(part: RefCounted, crafter_skill: float) -> float:
	if part == null or part.geometry != ItemPart.GEOMETRY_EDGE:
		return 0.0
	var designed: float = float(part.dimensions.get("angle_deg", ItemPart.WEDGE_ANGLE_DEG))
	var realized: Dictionary = part.dimensions.duplicate()
	realized["angle_deg"] = lerpf(
		ItemPart.WEDGE_ANGLE_DEG, designed, clampf(crafter_skill, 0.0, 1.0)
	)
	return ItemPart.new(part.material, part.geometry, part.role, realized).keenness()


## Structure in, rule program out.
##
## Always returns every key, whether or not it compiled, so a caller reads the
## result rather than branching on `ok` to find out which fields exist. Mass is
## reported even for a failure -- an offcut with no handle still has a mass, and
## refusing to say so would be a worse answer than the true one.
static func compile(graph: RefCounted, crafter_skill: float) -> Dictionary:
	var result := {
		"ok": false,
		"errors": [] as Array[String],
		"mass_kg": 0.0,
		"swing_time_s": INF,
		"reach_cm": 0.0,
		"delivered_momentum": 0.0,
		"balance_point_cm": 0.0,
		"rules": [],
		"affordances": [] as Array[String],
		"notes": [] as Array[String],
		"absences": {},
	}
	if graph == null:
		result["errors"] = _errors(["there is no assembly to compile"])
		return result
	result["mass_kg"] = graph.total_mass_kg()

	var refusal := _why_it_will_not_compile(graph)
	if not refusal.is_empty():
		result["errors"] = _errors(refusal)
		return result

	var pivot: String = PartMechanics.grip_part_id(graph)
	result["ok"] = true
	result["reach_cm"] = PartMechanics.reach_cm(graph, pivot)
	result["balance_point_cm"] = PartMechanics.balance_point_cm(graph, pivot)
	result["swing_time_s"] = PartMechanics.swing_time_s(graph, NOMINAL_ACTOR_STRENGTH)
	result["delivered_momentum"] = PartMechanics.delivered_momentum(
		graph, NOMINAL_ACTOR_STRENGTH
	)

	var rules: Array = []
	var affordances: Array[String] = []
	var notes: Array[String] = []
	var absences := {}
	for verb in VERBS:
		var verdict := _evaluate(verb, graph, crafter_skill, float(result["delivered_momentum"]))
		if bool(verdict["ok"]):
			affordances.append(verb)
			rules.append(verdict["rule"])
		else:
			absences[verb] = verdict["reason"]
			notes.append("cannot %s: %s" % [verb, verdict["reason"]])
	result["rules"] = rules
	result["affordances"] = affordances
	result["notes"] = notes
	result["absences"] = absences
	return result


# -- refusals --------------------------------------------------------------

## Why this structure is not an item at all, as opposed to an item that cannot
## do something. Reported as errors rather than as absences, because "your saw
## cannot chop" and "that is a loose blade with nothing to hold it by" are
## different kinds of answer and a caller must be able to tell them apart.
static func _why_it_will_not_compile(graph: RefCounted) -> Array:
	if not graph.is_well_formed():
		return graph.validation_errors()
	if graph.part_ids().is_empty():
		return ["an assembly with no parts is not an item"]
	if not graph.is_one_assembly():
		return ["these parts are not joined into one thing"]
	if PartMechanics.grip_part_id(graph) == "":
		return [
			"nothing on it is a grip, so there is no pivot to swing it about"
			+ " -- an edge with no handle is an offcut, not a tool",
		]
	return []


# -- the verbs -------------------------------------------------------------

## One verb's static predicate, clause by clause, stopping at the first failure
## so the reason names the clause that actually bit.
static func _evaluate(
	verb: String, graph: RefCounted, crafter_skill: float, momentum: float
) -> Dictionary:
	match verb:
		VERB_CUT:
			return _evaluate_cut(graph, crafter_skill)
		VERB_CHOP:
			return _evaluate_chop(graph, momentum)
		VERB_RIP:
			return _evaluate_rip(graph)
		VERB_PIERCE:
			return _evaluate_pierce(graph)
		VERB_CRUSH:
			return _evaluate_crush(graph)
		VERB_PARRY:
			return _evaluate_parry(graph)
		_:
			return _denied("'%s' is not a verb this compiler knows" % verb)


## Cutting is severing with a bevel, so it is a question about the GRIND. How
## hard you can swing the thing does not enter into it -- that is chop's
## question, and keeping them apart is what makes a scalpel and a maul different
## objects.
static func _evaluate_cut(graph: RefCounted, crafter_skill: float) -> Dictionary:
	var edges: Array = graph.parts_with_geometry(ItemPart.GEOMETRY_EDGE)
	if edges.is_empty():
		return _denied("nothing on it is an edge, so there is no bevel to sever with")
	var best_id := ""
	var best_keenness := -1.0
	for part_id in edges:
		var keenness: float = realized_keenness(graph.part(part_id), crafter_skill)
		if keenness > best_keenness:
			best_keenness = keenness
			best_id = String(part_id)
	var required := cut_keenness_min()
	if best_keenness < required:
		return _denied(
			"its keenest edge (%s) realizes only %.1f keenness against the %.1f a"
			% [best_id, best_keenness, required]
			+ " severing cut needs -- that grind is a splitting wedge, not a cutter"
		)
	return _granted(_rule(
		"hit", ImpactResolver.T_CUT, "cut_damage",
		{"contact": "edge", "keenness": best_keenness, "edge": best_id}
	))


## Chopping is severing by MOMENTUM: you are not drawing the edge through
## anything, you are arriving with enough of a blow to part the fibres in one
## go. So the clause that bites is whether this assembly, swung, actually gets
## there -- which is a question about mass and where it sits, and has nothing to
## do with teeth.
static func _evaluate_chop(graph: RefCounted, momentum: float) -> Dictionary:
	if graph.parts_with_geometry(ItemPart.GEOMETRY_EDGE).is_empty():
		return _denied("nothing on it is an edge, so there is no bevel to sever with")
	if momentum < ImpactResolver.T_CUT:
		return _denied(
			"swung by hand it carries only %.2f of momentum to its edge, under the"
			% momentum
			+ " %.1f a chop needs to sever in one blow -- its working mass is too low"
			% ImpactResolver.T_CUT
		)
	return _granted(_rule(
		"hit", ImpactResolver.T_CUT, "chop_damage",
		{"contact": "edge", "delivered_momentum": momentum}
	))


## Ripping is not a blow at all -- it is a stroke that carries chips out of a
## kerf, repeated. So the clauses are pure edge geometry, and the guard is only
## the floor below which nothing at all happens.
##
## The second clause is the real one and it is the reason an axe cannot rip a
## plank: a saw's teeth are bent alternately to each side (the SET) so the cut
## they make is wider than the plate following them through it. A saw with no
## set jams in its own kerf no matter how sharp it is.
static func _evaluate_rip(graph: RefCounted) -> Dictionary:
	for part_id in graph.parts_with_geometry(ItemPart.GEOMETRY_EDGE):
		var part: RefCounted = graph.part(part_id)
		var pitch_mm: float = float(part.dimensions.get("tooth_pitch_mm", 0.0))
		if pitch_mm <= 0.0:
			continue
		var plate_mm: float = float(part.dimensions.get("thickness_cm", 0.0)) * 10.0
		var kerf_mm: float = plate_mm + 2.0 * float(part.dimensions.get("tooth_set_mm", 0.0))
		if kerf_mm <= plate_mm:
			return _denied(
				"its teeth have no set, so the kerf is no wider than the %.2f mm"
				% plate_mm
				+ " plate behind them and it would bind in its own cut"
			)
		return _granted(_rule(
			"stroke", ImpactResolver.BOUNCE_MOMENTUM_THRESHOLD, "rip_damage",
			{"tooth_pitch_mm": pitch_mm, "kerf_mm": kerf_mm, "edge": String(part_id)}
		))
	return _denied(
		"its edge is a transverse bit with no tooth pitch, so there is nothing"
		+ " to carry chips along a cut"
	)


static func _evaluate_pierce(graph: RefCounted) -> Dictionary:
	var points: Array = graph.parts_with_geometry(ItemPart.GEOMETRY_POINT)
	if points.is_empty():
		return _denied("nothing on it is a point, so there is no tip to concentrate a blow")
	return _granted(_rule(
		"hit", ImpactResolver.T_PIERCE, "pierce_damage",
		{"contact": "point", "point": String(points[0])}
	))


## Crushing needs a blunt WORKING part -- a head or a face the maker meant to
## land with. A sword's crossguard is a face and its pommel is a lump, and
## neither makes a sword a mace, which is exactly why role is consulted here and
## nowhere that answers a physical question.
static func _evaluate_crush(graph: RefCounted) -> Dictionary:
	for part_id in graph.parts_with_role(ItemPart.ROLE_WORKING):
		var geometry: String = graph.part(part_id).geometry
		if geometry == ItemPart.GEOMETRY_BULK or geometry == ItemPart.GEOMETRY_FACE:
			return _granted(_rule(
				"hit", ImpactResolver.T_CRUSH, "crush_damage",
				{"contact": "blunt", "head": String(part_id)}
			))
	return _denied("nothing on it is a working head or face to land flat with")


## Parrying is taking a blow on the item instead of on yourself, so the only
## question is whether the item survives doing it. A material under the
## toughness the impact model already SHATTERS at cannot: the guard would be
## statically false, so no rule is emitted and "cannot parry" is a consequence
## of obsidian being obsidian rather than an authored exception for it.
static func _evaluate_parry(graph: RefCounted) -> Dictionary:
	for part_id in graph.parts_with_role(ItemPart.ROLE_WORKING):
		var part: RefCounted = graph.part(part_id)
		var toughness: float = part.property_value("toughness")
		if toughness < ImpactResolver.T_BRITTLE_TOUGHNESS:
			return _denied(
				"its working %s is %s, whose toughness of %.1f is under the %.1f the"
				% [part_id, part.material, toughness, ImpactResolver.T_BRITTLE_TOUGHNESS]
				+ " impact model shatters at -- it would break rather than block"
			)
	return _granted(_rule(
		"parry", ImpactResolver.BOUNCE_MOMENTUM_THRESHOLD, "parry", {}
	))


# -- the AST ---------------------------------------------------------------

## One rule, in spell_parser.gd's own shape -- the same four keys `_parse_rule`
## returns, `event_arg` included, so a compiled rule and a hand-written
## enchantment's rule are indistinguishable to everything downstream.
##
## `rhs` is ALWAYS the shipped ImpactResolver symbol passed in by the caller,
## never a literal: physics, tooltip and item text must not be able to drift.
static func _rule(
	event: String, threshold: float, atom: String, params: Dictionary
) -> Dictionary:
	return {
		"event": event,
		"event_arg": null,
		"guard": {"op": ">=", "lhs": "impact.momentum", "rhs": threshold},
		"pipeline": [{"atom": atom, "params": params}],
	}


static func _granted(rule: Dictionary) -> Dictionary:
	return {"ok": true, "rule": rule, "reason": ""}


static func _denied(reason: String) -> Dictionary:
	return {"ok": false, "rule": {}, "reason": reason}


static func _errors(messages: Array) -> Array[String]:
	var typed: Array[String] = []
	for message in messages:
		typed.append(str(message))
	return typed
