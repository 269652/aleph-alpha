extends RefCounted

## An assembly: parts as nodes, typed joints as edges. Pure logic, no engine,
## no scene tree. Design doc: docs/concept/emergent_crafting.md.
##
## ## Nothing here knows what it is looking at
##
## Every query below is answered from topology and physics alone. There is no
## "is this a sword" branch and there deliberately cannot be one: the design
## rule this model exists to serve is that affordances are INFERRED from the
## graph, never declared on it. So a pair of scissors is not scissors because
## someone said so -- it is an assembly whose two edge parts have no rigid
## route between them and one rotational joint on the route they do have.
## That is a fact this file can compute, and it is the foundation the later
## affordance layer sits on. (That layer is NOT in this slice.)
##
## ## Determinism
##
## Part and joint order is CONSTRUCTION order, kept in explicit arrays rather
## than read back out of a Dictionary's keys, and every traversal expands
## neighbours in that order. This project has been bitten by unstable iteration
## order before, so "same graph, same answers" is a property the tests assert
## rather than a thing we hope the engine does.
##
## ## What is deliberately not modelled yet
##
## Joints are MASSLESS. A lashing's cordage and a rivet have real mass, but no
## dimension on a joint to compute it from, so total_mass_kg is the sum of the
## parts only -- named as a limit rather than fudged with a guess.
##
## Parts have no ORIENTATION. That is why "two OPPOSED edges" can only be
## checked here as far as unoriented topology allows (two edges on either side
## of one articulating joint -- see separates_into); which way each edge faces
## needs a placement layer this slice does not build.

const ItemPart: GDScript = preload("res://src/gameplay/item_part.gd")
const PartJoint: GDScript = preload("res://src/gameplay/part_joint.gd")

var _parts: Dictionary = {}
var _joints: Dictionary = {}
## Construction order, kept explicitly. Never iterate the dictionaries.
var _part_order: Array[String] = []
var _joint_order: Array[String] = []
## part id -> joint ids touching it, in construction order.
var _joints_by_part: Dictionary = {}
var _errors: Array[String] = []


# -- construction ----------------------------------------------------------

## Adds a part under `part_id`. Returns false and records a reason if the id is
## already taken or the part is malformed; a rejected part never enters the
## graph and never overwrites the one already there.
##
## Rejecting here rather than tolerating is the whole point: a part with an
## unmodeled material would otherwise mass itself off MaterialProperties'
## defaults and every aggregate above it would be confidently wrong.
func add_part(part_id: String, part: RefCounted) -> bool:
	if part_id == "":
		_errors.append("a part needs an id")
		return false
	if _parts.has(part_id):
		_errors.append("duplicate part id '%s'" % part_id)
		return false
	if part == null:
		_errors.append("part '%s' is null" % part_id)
		return false
	var reason: String = part.validation_error()
	if reason != "":
		_errors.append("part '%s' is malformed: %s" % [part_id, reason])
		return false
	_parts[part_id] = part
	_part_order.append(part_id)
	_joints_by_part[part_id] = [] as Array[String]
	return true


## Adds a joint. Returns false and records a reason if its id is taken, either
## end names a part that is not in this graph, or the joint is malformed in
## itself.
func add_joint(joint: RefCounted) -> bool:
	if joint == null:
		_errors.append("a null joint cannot be added")
		return false
	var reason: String = joint.validation_error()
	if reason != "":
		_errors.append("joint '%s' is malformed: %s" % [joint.id, reason])
		return false
	if _joints.has(joint.id):
		_errors.append("duplicate joint id '%s'" % joint.id)
		return false
	for end_id in [joint.part_a, joint.part_b]:
		if not _parts.has(end_id):
			_errors.append(
				"joint '%s' references part '%s', which is not in this graph"
				% [joint.id, end_id]
			)
			return false
	_joints[joint.id] = joint
	_joint_order.append(joint.id)
	_joints_by_part[joint.part_a].append(joint.id)
	_joints_by_part[joint.part_b].append(joint.id)
	return true


## Every rejection this graph has recorded, in the order they happened.
func validation_errors() -> Array[String]:
	return _errors.duplicate()


func is_well_formed() -> bool:
	return _errors.is_empty()


# -- access ----------------------------------------------------------------

func has_part(part_id: String) -> bool:
	return _parts.has(part_id)


func has_joint(joint_id: String) -> bool:
	return _joints.has(joint_id)


## The part itself, or null if there is none. Null rather than a stub: a caller
## asking for a part that is not there has made a mistake worth noticing.
func part(part_id: String) -> RefCounted:
	return _parts.get(part_id, null)


func joint(joint_id: String) -> RefCounted:
	return _joints.get(joint_id, null)


func part_ids() -> Array[String]:
	return _part_order.duplicate()


func joint_ids() -> Array[String]:
	return _joint_order.duplicate()


# -- traversal -------------------------------------------------------------

## Joint ids touching `part_id`, in construction order.
func joints_at(part_id: String) -> Array[String]:
	var found: Array[String] = []
	for joint_id in _joints_by_part.get(part_id, []):
		found.append(joint_id)
	return found


## Part ids joined to `part_id`, in the construction order of the joints that
## reach them.
func neighbors(part_id: String) -> Array[String]:
	var found: Array[String] = []
	for joint_id in joints_at(part_id):
		found.append(_joints[joint_id].other_end(part_id))
	return found


## The shortest route from one part to another, as part ids including both
## ends. [] when either part is missing or nothing joins them; [id] when they
## are the same part.
##
## SHORTEST, not merely first-found, because two named later systems depend on
## the route being the real one: magic channelling routes from a grip along a
## material path to a setting and its loss follows the path's length, and
## disassembly walks the joints between two parts. Breadth-first, expanding
## neighbours in construction order, so the tie between two equally short
## routes always breaks the same way.
func path_between(from_part: String, to_part: String) -> Array[String]:
	var route: Array[String] = []
	if not _parts.has(from_part) or not _parts.has(to_part):
		return route
	if from_part == to_part:
		route.append(from_part)
		return route
	var came_from := {from_part: ""}
	var queue: Array[String] = [from_part]
	var head := 0
	while head < queue.size():
		var current := queue[head]
		head += 1
		for next_part in neighbors(current):
			if came_from.has(next_part):
				continue
			came_from[next_part] = current
			if next_part == to_part:
				return _rebuild_route(came_from, from_part, to_part)
			queue.append(next_part)
	return route


## The joints a route crosses, derived from the part path rather than kept as a
## second answer that could drift out of step with it.
func joints_along_path(part_path: Array) -> Array[String]:
	var crossed: Array[String] = []
	for i in range(part_path.size() - 1):
		var joint_id := _joint_between(str(part_path[i]), str(part_path[i + 1]))
		if joint_id != "":
			crossed.append(joint_id)
	return crossed


## How far a route physically is, in cm: the sum of the spans of the parts it
## passes through. A hop count would not do -- channel loss is decided by real
## distance through real material, so a route through one long haft is longer
## than a route through three short ones.
func path_length_cm(part_path: Array) -> float:
	var total := 0.0
	for part_id in part_path:
		var found: RefCounted = _parts.get(str(part_id), null)
		if found != null:
			total += found.span_cm()
	return total


## Is this one assembly, or several things in a bag? An empty graph is
## trivially one.
##
## Named is_one_assembly rather than is_connected because Object already has an
## is_connected(signal, callable) and the two would collide.
func is_one_assembly() -> bool:
	if _part_order.is_empty():
		return true
	return _reachable_from(_part_order[0], "").size() == _part_order.size()


# -- aggregates ------------------------------------------------------------

## The sum of the parts' masses. Joints are massless in this slice -- see this
## file's own doc comment on what that leaves out and why.
func total_mass_kg() -> float:
	var total := 0.0
	for part_id in _part_order:
		total += _parts[part_id].mass_kg()
	return total


func parts_with_role(role: String) -> Array[String]:
	var found: Array[String] = []
	for part_id in _part_order:
		if _parts[part_id].role == role:
			found.append(part_id)
	return found


func parts_with_geometry(geometry: String) -> Array[String]:
	var found: Array[String] = []
	for part_id in _part_order:
		if _parts[part_id].geometry == geometry:
			found.append(part_id)
	return found


## What a part carries through its own section before it fails: its material's
## strength across its cross-section. This is the load a joint's efficiency is
## a FRACTION OF -- a part is its own connection to itself, at 100%.
func part_load_capacity(part_id: String) -> float:
	var found: RefCounted = _parts.get(part_id, null)
	if found == null:
		return 0.0
	return found.property_value("toughness") * found.cross_section_cm2()


## What a joint carries, acting through the SMALLER of the two sections it
## joins -- a connection can be no bigger than the thinner member, the same
## net-section logic that governs a real riveted joint.
func joint_load_capacity(joint_id: String) -> float:
	var found: RefCounted = _joints.get(joint_id, null)
	if found == null:
		return 0.0
	var section := minf(
		_parts[found.part_a].cross_section_cm2(), _parts[found.part_b].cross_section_cm2()
	)
	return found.load_capacity(section)


## Where this assembly gives way first: {"kind": "part"/"joint", "id",
## "capacity"}. An empty graph answers kind "".
##
## COMPUTED, not assumed. A joint has to be able to be the weakest link -- that
## is the design claim -- so every joint's capacity is compared against every
## part's own, and either can win. Parts are checked before joints and ties go
## to whichever was constructed first, so the answer is stable.
func weakest_link() -> Dictionary:
	var weakest := {"kind": "", "id": "", "capacity": 0.0}
	for part_id in _part_order:
		var capacity := part_load_capacity(part_id)
		if weakest["kind"] == "" or capacity < float(weakest["capacity"]):
			weakest = {"kind": "part", "id": part_id, "capacity": capacity}
	for joint_id in _joint_order:
		var capacity := joint_load_capacity(joint_id)
		if weakest["kind"] == "" or capacity < float(weakest["capacity"]):
			weakest = {"kind": "joint", "id": joint_id, "capacity": capacity}
	return weakest


# -- articulation ----------------------------------------------------------

## Every joint that permits relative motion, in construction order.
func articulating_joints() -> Array[String]:
	var found: Array[String] = []
	for joint_id in _joint_order:
		if _joints[joint_id].permits_motion():
			found.append(joint_id)
	return found


## Does nothing in this assembly move relative to anything else? True for a
## sword and a picture frame, false for a pair of scissors.
func is_rigid_body() -> bool:
	return articulating_joints().is_empty()


## Can these two parts move relative to each other?
##
## The test is whether an ALL-RIGID route exists between them, not whether the
## shortest route happens to cross a hinge. If any rigid path holds them they
## are held, whatever else also joins them -- which is why welding a strap
## across a hinge stops it being a hinge. Two parts nothing joins answer false:
## they are not one body, so there is no articulation to speak of.
func permits_relative_motion(from_part: String, to_part: String) -> bool:
	if from_part == to_part:
		return false
	if not _parts.has(from_part) or not _parts.has(to_part):
		return false
	if not _reachable_from(from_part, "").has(to_part):
		return false
	return not _rigidly_reachable_from(from_part).has(to_part)


## The kinds of motion the route between two parts permits (PartJoint.MOTION_*),
## distinct, in the order they are met along the shortest route. Empty when a
## rigid route holds them still -- coherent with permits_relative_motion rather
## than a second opinion that could contradict it.
func motion_between(from_part: String, to_part: String) -> Array[String]:
	var kinds: Array[String] = []
	if not permits_relative_motion(from_part, to_part):
		return kinds
	for joint_id in joints_along_path(path_between(from_part, to_part)):
		var moving: RefCounted = _joints[joint_id]
		if moving.permits_motion() and not kinds.has(moving.motion_kind()):
			kinds.append(moving.motion_kind())
	return kinds


## What this assembly falls into if that one joint lets go: an Array of
## Array[String], each a connected group in construction order, the groups
## themselves ordered by their first member. [] for a joint that is not there.
##
## One query, two consumers. It is how "two opposed parts share a pivot" is
## checked structurally -- undo the pivot and count what is on each side -- and
## it is exactly what a later disassembly layer asks: what comes off? A joint
## in a closed loop yields ONE group, because a ring stays whole when one link
## lets go, which is why a mitred frame does not drop a rail.
func separates_into(joint_id: String) -> Array:
	var groups: Array = []
	if not _joints.has(joint_id):
		return groups
	var seen := {}
	for part_id in _part_order:
		if seen.has(part_id):
			continue
		var group := _reachable_from(part_id, joint_id)
		for member in group:
			seen[member] = true
		groups.append(group)
	return groups


# -- internals -------------------------------------------------------------

## Every part reachable from `start`, in construction order, optionally with
## one joint treated as absent.
func _reachable_from(start: String, without_joint: String) -> Array[String]:
	var seen := {start: true}
	var queue: Array[String] = [start]
	var head := 0
	while head < queue.size():
		var current := queue[head]
		head += 1
		for step in joints_at(current):
			if step == without_joint:
				continue
			var next_part: String = _joints[step].other_end(current)
			if seen.has(next_part):
				continue
			seen[next_part] = true
			queue.append(next_part)
	var ordered: Array[String] = []
	for part_id in _part_order:
		if seen.has(part_id):
			ordered.append(part_id)
	return ordered


## Every part held STILL relative to `start` -- reachable using only joints
## that transmit rigidly.
func _rigidly_reachable_from(start: String) -> Array[String]:
	var seen := {start: true}
	var queue: Array[String] = [start]
	var head := 0
	while head < queue.size():
		var current := queue[head]
		head += 1
		for step in joints_at(current):
			if not _joints[step].transmits_rigidly():
				continue
			var next_part: String = _joints[step].other_end(current)
			if seen.has(next_part):
				continue
			seen[next_part] = true
			queue.append(next_part)
	var ordered: Array[String] = []
	for part_id in _part_order:
		if seen.has(part_id):
			ordered.append(part_id)
	return ordered


## The first joint, in construction order, directly joining these two parts.
func _joint_between(from_part: String, to_part: String) -> String:
	for joint_id in joints_at(from_part):
		if _joints[joint_id].other_end(from_part) == to_part:
			return joint_id
	return ""


func _rebuild_route(came_from: Dictionary, from_part: String, to_part: String) -> Array[String]:
	var backwards: Array[String] = []
	var current := to_part
	while current != "":
		backwards.append(current)
		if current == from_part:
			break
		current = str(came_from[current])
	backwards.reverse()
	return backwards
