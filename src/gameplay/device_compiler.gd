extends RefCounted

## The compile step of docs/concept/standard_model.md ("5. Resolution order",
## step 1): a parsed `device` AST becomes a REAL PartGraph plus the element
## chain device_network.gd solves. Pure static functions, no engine, no
## scene tree.
##
## ## What it does, and what it refuses
##
## - Parts and joints become the shipped ItemPart / PartJoint / PartGraph,
##   validated by THEIR OWN rules -- an unmodeled material, a missing
##   dimension, a pivot with no axis all come back with the graph's own
##   reason verbatim. Nothing is re-validated here that the graph already
##   validates, so the two cannot drift.
## - Laws become elements. Every parameter is either AUTHORED or DERIVED
##   from a named part or fluid (device_physics.gd), never defaulted -- a
##   missing one is named, and a parameter that is derived may not ALSO be
##   written, because the derivation wins and a second number next to it
##   could only ever be wrong.
## - Every one-port law names a domain and every two-port law names its
##   `in` and `out`; along the loop, consecutive ports must agree, and a
##   mismatch names both. Thermal is catalogued (physics_domains.gd) and
##   refused here: it is a pseudo-bond this slice does not solve.
## - The `loop` becomes the chain, first element a source. One loop per
##   device this slice; a second is refused rather than half-solved.
##
## ## Nothing here branches on what a device IS
##
## There is no "is this a mill" test and there deliberately cannot be one --
## the same rule PartGraph and ItemCompiler already hold to. A mill and a
## lamp compile through the same clauses; the physics decides what each
## does.

const ItemPart: GDScript = preload("res://src/gameplay/item_part.gd")
const PartJoint: GDScript = preload("res://src/gameplay/part_joint.gd")
const PartGraph: GDScript = preload("res://src/gameplay/part_graph.gd")
const DeviceElements: GDScript = preload("res://src/gameplay/device_elements.gd")
const DevicePhysics: GDScript = preload("res://src/gameplay/device_physics.gd")
const PhysicsDomains: GDScript = preload("res://src/gameplay/physics_domains.gd")

## The axis words a pivot or slider may name. A text has no vector literal,
## and a device's joints only ever need a principal axis.
const AXES: Dictionary = {
	"x": Vector3.RIGHT,
	"y": Vector3.UP,
	"z": Vector3.FORWARD,
}

## Store parameters that are optional rather than required, so they are
## carried into the chain when authored and left to their defaults when not.
const _OPTIONAL_STORE_PARAMS: Array[String] = ["level", "resistance"]


## Structure in, graph and chain out. Always returns every key, whether or
## not it compiled, so a caller reads the result rather than branching on
## `ok` to find out which fields exist.
static func compile(ast: Dictionary) -> Dictionary:
	var result := _empty_result()
	if ast == null or ast.is_empty() or String(ast.get("kind", "")) != "device":
		result["errors"] = _errors(["there is no device to compile"])
		return result

	# -- parts and joints: the shipped part graph, validated by its own rules --
	var graph: RefCounted = PartGraph.new()
	var errors: Array = []
	for part in ast.get("parts", []):
		graph.add_part(String(part["id"]), ItemPart.new(
			String(part["material"]), String(part["geometry"]), String(part["role"]),
			part.get("dimensions", {})
		))
	for joint in ast.get("joints", []):
		var params: Dictionary = joint.get("params", {})
		var axis := Vector3.ZERO
		if params.has("axis"):
			var word := String(params["axis"])
			if not AXES.has(word):
				errors.append("joint '%s': unknown axis '%s' (use x, y or z)" % [joint["id"], word])
				continue
			axis = AXES[word]
		graph.add_joint(PartJoint.new(
			String(joint["id"]), String(joint["part_a"]), String(joint["part_b"]),
			String(joint["type"]), String(joint["fastening"]), String(joint["material"]), axis
		))
	errors.append_array(graph.validation_errors())
	result["graph"] = graph
	result["mass_kg"] = graph.total_mass_kg()
	if not errors.is_empty():
		result["errors"] = _errors(errors)
		return result

	# -- laws: elements with every parameter authored or derived ---------------
	var elements := {}
	for law in ast.get("laws", []):
		var id := String(law["id"])
		if elements.has(id):
			errors.append("law '%s' is declared twice" % id)
			continue
		var resolved := _resolve_law(law, graph)
		errors.append_array(resolved["errors"])
		if resolved["errors"].is_empty():
			elements[id] = resolved["element"]
	result["elements"] = elements
	if not errors.is_empty():
		result["errors"] = _errors(errors)
		return result

	# -- the loop: the chain the solver walks -----------------------------------
	var loops: Array = ast.get("loops", [])
	if loops.size() > 1:
		result["errors"] = _errors(["this slice compiles one loop per device; this one has %d" % loops.size()])
		return result
	if loops.size() == 1:
		var loop: Array = loops[0]
		for id in loop:
			if not elements.has(String(id)):
				errors.append("loop names '%s', which has no law" % id)
		if not errors.is_empty():
			result["errors"] = _errors(errors)
			return result
		var first: Dictionary = elements[String(loop[0])]
		if first["kind"] != DeviceElements.KIND_SOURCE:
			errors.append("a loop needs a source first, got %s '%s'" % [first["kind"], loop[0]])
		for i in range(1, loop.size()):
			var upstream: Dictionary = elements[String(loop[i - 1])]
			var downstream: Dictionary = elements[String(loop[i])]
			if upstream["domain_out"] != downstream["domain_in"]:
				errors.append(
					"'%s' puts out %s but '%s' takes in %s"
					% [loop[i - 1], upstream["domain_out"], loop[i], downstream["domain_in"]]
				)
		if not errors.is_empty():
			result["errors"] = _errors(errors)
			return result
		var chain: Array = []
		var loop_ids: Array[String] = []
		for id in loop:
			var element: Dictionary = elements[String(id)]
			chain.append({"id": String(id), "kind": element["kind"], "params": element["params"].duplicate()})
			loop_ids.append(String(id))
		result["chain"] = chain
		result["loop"] = loop_ids

	result["ok"] = true
	return result


# -- laws ----------------------------------------------------------------------------

## One law -> {errors, element: {kind, params, domain_in, domain_out}}. The
## element's params are the CANONICAL ones DeviceElements validates and the
## solver consumes; steering parameters (domain, part, fluid, ...) are
## consumed here and not passed on.
static func _resolve_law(law: Dictionary, graph: RefCounted) -> Dictionary:
	var id := String(law["id"])
	var kind := String(law["element"])
	var params: Dictionary = law.get("params", {})
	var errors: Array = []
	var element := {"kind": kind, "params": {}, "domain_in": "", "domain_out": ""}
	if not DeviceElements.is_known(kind):
		return {"errors": ["law '%s': unknown element kind '%s'" % [id, kind]], "element": element}

	# -- domains --
	var domains: RefCounted = PhysicsDomains.new()
	if DeviceElements.is_two_port(kind):
		for key in ["in", "out"]:
			if not params.has(key):
				errors.append("law '%s': a %s needs an '%s' domain" % [id, kind, key])
			else:
				errors.append_array(_domain_errors(id, String(params[key]), domains))
		if errors.is_empty():
			element["domain_in"] = String(params["in"])
			element["domain_out"] = String(params["out"])
	else:
		if not params.has("domain"):
			errors.append("law '%s': a %s needs a 'domain'" % [id, kind])
		else:
			errors.append_array(_domain_errors(id, String(params["domain"]), domains))
		if errors.is_empty():
			element["domain_in"] = String(params["domain"])
			element["domain_out"] = String(params["domain"])
	if not errors.is_empty():
		return {"errors": errors, "element": element}

	# -- authored canonical parameters --
	var canonical := {}
	var allowed: Array = DeviceElements.required_params(kind)
	if kind == DeviceElements.KIND_STORE:
		allowed.append_array(_OPTIONAL_STORE_PARAMS)
	for key in allowed:
		if params.has(key):
			canonical[key] = params[key]

	# -- derivations: derived wins, and only where a derivation exists --
	match kind:
		DeviceElements.KIND_SOURCE:
			if params.has("fluid"):
				_refuse_authored(id, params, ["effort", "resistance"], "the fluid", errors)
				for key in ["area_m2", "velocity"]:
					if not params.has(key):
						errors.append("law '%s': a source from a fluid needs '%s'" % [id, key])
				var density: float = DevicePhysics.fluid_density(String(params["fluid"]))
				if density <= 0.0:
					errors.append("law '%s': unknown fluid '%s'" % [id, params["fluid"]])
				if errors.is_empty():
					var source: Dictionary = DevicePhysics.paddle_source(
						density, float(params["area_m2"]), float(params["velocity"])
					)
					canonical["effort"] = source["effort"]
					canonical["resistance"] = source["resistance"]
		DeviceElements.KIND_RESIST:
			if params.has("part"):
				_refuse_authored(id, params, ["resistance"], "the part", errors)
				var part: RefCounted = _part_named(id, params, graph, errors)
				if element["domain_in"] != PhysicsDomains.DOMAIN_ELECTRICAL:
					errors.append(
						"law '%s': a resistance is derived from a part only in the electrical"
						% id + " domain (a wire); in %s it must be written" % element["domain_in"]
					)
				if part != null and not DevicePhysics.can_derive_resistance(part):
					errors.append(
						"law '%s': a resistance can only be derived from a haft (a wire is a"
						% id + " cylinder), and '%s' is a %s" % [params["part"], part.geometry]
					)
				if errors.is_empty():
					canonical["resistance"] = DevicePhysics.wire_resistance_of_part(part)
		DeviceElements.KIND_TRANSFORM:
			if params.has("part"):
				_refuse_authored(id, params, ["ratio"], "the part", errors)
				var part: RefCounted = _part_named(id, params, graph, errors)
				if element["domain_in"] != PhysicsDomains.DOMAIN_TRANSLATION \
						or element["domain_out"] != PhysicsDomains.DOMAIN_ROTATION:
					errors.append(
						"law '%s': a ratio is derived from a part only between translation"
						% id + " and rotation (a wheel's radius)"
					)
				if errors.is_empty():
					canonical["ratio"] = DevicePhysics.wheel_radius_m(part)
		DeviceElements.KIND_GYRATE:
			var faraday := ["magnet_tesla", "turns", "area_m2"]
			var any_faraday := false
			for key in faraday:
				if params.has(key):
					any_faraday = true
			if any_faraday:
				_refuse_authored(id, params, ["ratio"], "Faraday's figures", errors)
				for key in faraday:
					if not params.has(key):
						errors.append("law '%s': a gyrator from Faraday needs '%s'" % [id, key])
				if errors.is_empty():
					canonical["ratio"] = DevicePhysics.faraday_ratio(
						float(params["magnet_tesla"]), float(params["turns"]), float(params["area_m2"])
					)
	if not errors.is_empty():
		return {"errors": errors, "element": element}

	var reason: String = DeviceElements.validation_error(kind, canonical)
	if reason != "":
		errors.append("law '%s': %s" % [id, reason])
	element["params"] = canonical
	return {"errors": errors, "element": element}


static func _domain_errors(id: String, domain: String, domains: RefCounted) -> Array:
	if not domains.has(domain):
		return ["law '%s': unknown domain '%s'" % [id, domain]]
	if not domains.is_power_domain(domain):
		return [
			"law '%s': %s is a pseudo-bond (its effort x flow is not a power)"
			% [id, domain] + " and this slice does not solve it",
		]
	return []


## A derived parameter may not also be written: the derivation wins, and a
## second number next to it could only ever disagree with it.
static func _refuse_authored(
	id: String, params: Dictionary, derived: Array, from_what: String, errors: Array
) -> void:
	for key in derived:
		if params.has(key):
			errors.append(
				"law '%s': '%s' is derived from %s; do not also write it" % [id, key, from_what]
			)


static func _part_named(id: String, params: Dictionary, graph: RefCounted, errors: Array) -> RefCounted:
	var part_id := String(params["part"])
	var part: RefCounted = graph.part(part_id)
	if part == null:
		errors.append("law '%s' names part '%s', which is not in this device" % [id, part_id])
	return part


# -- result -----------------------------------------------------------------------------

static func _empty_result() -> Dictionary:
	return {
		"ok": false,
		"errors": [] as Array[String],
		"graph": null,
		"mass_kg": 0.0,
		"chain": [],
		"elements": {},
		"loop": [] as Array[String],
	}


static func _errors(messages: Array) -> Array[String]:
	var typed: Array[String] = []
	for message in messages:
		typed.append(str(message))
	return typed
