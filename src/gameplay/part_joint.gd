extends RefCounted

## A typed joint between two parts -- the primitive
## docs/concept/materials.md's assembly model is missing. Pure logic, no
## engine, no scene tree. Design doc: docs/concept/emergent_crafting.md.
##
## ## Why this file exists
##
## materials.md's "an item is a small graph of parts" is implicitly RIGID: its
## assembly rules compose a haft with a head and nothing ever moves relative to
## anything else. That expresses a sword beautifully and CANNOT express a pair
## of scissors at all -- scissors are two opposed edges sharing a PIVOT, and
## they cut by closing. Once a joint can be typed, the whole articulated
## category opens up with no new machinery: shears, bows (a limb held under
## tension), flails, doors.
##
## ## Two vocabularies, not one, and why
##
## A joint answers two INDEPENDENT questions and this file keeps them apart:
##
##   TYPE      what motion does it permit? (kinematics)
##   FASTENING what holds it, and what does undoing it cost? (joinery)
##
## The design brief listed LASHED as a joint TYPE, alongside RIGID. It is a
## fastening here instead, because "lashed" is not a statement about motion: a
## lashing holds two parts still relative to each other in exactly the way a
## rivet does. Keeping it as a type would permit a joint that is both LASHED
## and RIVET-fastened -- two fields disagreeing about one fact. The split also
## pays for itself immediately in both directions: a lashed flail head really
## does swing on its lashing (PIVOT + LASHING), and a scissors pivot really is
## sometimes a screw and sometimes a peined rivet -- same kinematics, wildly
## different serviceability. That difference is exactly what a later
## disassembly layer needs and a single enum would have flattened away.
##
## Adhesive is DELIBERATELY absent from the fastening vocabulary. Its
## serviceability genuinely depends on which adhesive -- hide glue is prized
## for being reversible with heat and water, epoxy is not -- so it is a
## material question this joint vocabulary cannot honestly answer yet.

const MaterialProperties: GDScript = preload("res://src/gameplay/material_properties.gd")

## Kinematics: what moves, and how.
##   RIGID     nothing moves; force passes straight through (a sword's tang)
##   PIVOT     one rotational freedom about one axis (a scissors pivot, a hinge)
##   SLIDING   one translational freedom along one direction (a drawer, a bolt)
##   SPRUNG    one elastic freedom that stores energy and returns (a bow limb)
##   SOCKET    three rotational freedoms, no constrained axis (a ball in a
##             socket). NOTE this is the mechanical ball-and-socket, not a
##             jeweller's gem socket -- a seat that RECEIVES a part is a part
##             role (ItemPart.ROLE_SETTING), because the seat is a piece of
##             material and the thing holding the gem in it is an ordinary
##             rigid friction fit.
const TYPE_RIGID := "rigid"
const TYPE_PIVOT := "pivot"
const TYPE_SLIDING := "sliding"
const TYPE_SPRUNG := "sprung"
const TYPE_SOCKET := "socket"

const TYPES: Array[String] = [
	TYPE_RIGID, TYPE_PIVOT, TYPE_SLIDING, TYPE_SPRUNG, TYPE_SOCKET,
]

const MOTION_NONE := "none"
const MOTION_ROTATION := "rotation"
const MOTION_TRANSLATION := "translation"
const MOTION_FLEX := "flex"

## Joinery: what holds it together.
const FASTENING_LASHING := "lashing"
const FASTENING_PIN := "pin"
const FASTENING_FIT := "fit"
const FASTENING_RIVET := "rivet"
const FASTENING_WELD := "weld"

## Ordered most-serviceable-first. Every iteration over the fastenings uses
## this array rather than the dictionary's keys, so results never depend on
## dictionary order.
const FASTENINGS: Array[String] = [
	FASTENING_LASHING, FASTENING_PIN, FASTENING_FIT, FASTENING_RIVET, FASTENING_WELD,
]

## ## The two real scales serviceability is derived from
##
## Serviceability is the scalar a later disassembly-risk layer consumes, so it
## is worth getting its grounding right rather than picking five numbers that
## feel ordered. It is DERIVED from two facts a workshop can actually observe
## about undoing a fastening, each on a four-step scale:
##
## What it DESTROYS -- nothing / the fastener itself / a joined part / the
## whole assembly:
const DESTROYS_NOTHING := 0
const DESTROYS_THE_FASTENER := 1
const DESTROYS_A_JOINED_PART := 2
const DESTROYS_THE_ASSEMBLY := 3

## What it TAKES -- your hands / an ordinary hand tool / a workshop process
## (drilling, heating) / nothing will:
const EFFORT_HANDS := 0
const EFFORT_HAND_TOOL := 1
const EFFORT_WORKSHOP := 2
const EFFORT_IMPOSSIBLE := 3

## ## Joint efficiency: the real engineering quantity
##
## `efficiency_band` is the fraction of the SOLID parent section's strength the
## connection retains -- exactly the quantity boiler and ship design has
## computed for riveted joints for over a century (efficiency = strength of the
## riveted joint / strength of the solid plate). Each fastening carries a real
## published band and its efficiency is the MIDPOINT of that band, so the
## number is derived from the band rather than eyeballed. Pinned by
## test_every_efficiency_is_the_midpoint_of_its_real_world_band.
##
##   LASHING (0.25-0.35) cordage transmits load only through friction between
##       the wraps and the members. It is the weakest of the classical
##       connections, and the reason a lashed stone head works loose in use.
##   PIN     (0.50-0.70) a pin or unpreloaded bolt loses the net section its
##       hole removes and then carries the load in bearing and shear on the
##       pin, with no clamping friction to share it.
##   FIT     (0.40-0.60) a taper or interference fit has no fastener in tension
##       at all; it holds by normal force alone. Which is precisely why a
##       socketed axe head tightens under every swing but pulls straight off in
##       tension.
##   RIVET   (0.60-0.80) the classic double-riveted lap/butt joint band from
##       boiler and ship practice. A hot-driven rivet shrinks as it cools and
##       clamps the members, so it beats a slip pin.
##   WELD    (1.00-1.00) a sound full-penetration forge or fusion weld is
##       DEFINED by being as strong as the parent metal; pressure-vessel codes
##       allow a joint efficiency of 1.00 for a fully radiographed butt weld.
##       A point, not a band -- anything less is a defective weld, not a
##       different kind of one.
##
## Read the serviceability and efficiency columns together and the trade-off
## the whole vocabulary exists for falls out: the fastening you can always undo
## carries the least, the one that carries the parent metal's full load is the
## one you are never undoing, and nothing is best at both. A smith picks a
## point on that line at build time.
const _FASTENING_PROPERTIES: Dictionary = {
	FASTENING_LASHING: {
		"destroys": DESTROYS_NOTHING, "effort": EFFORT_HANDS,
		"efficiency_band": [0.25, 0.35],
	},
	FASTENING_PIN: {
		"destroys": DESTROYS_NOTHING, "effort": EFFORT_HAND_TOOL,
		"efficiency_band": [0.50, 0.70],
	},
	FASTENING_FIT: {
		"destroys": DESTROYS_THE_FASTENER, "effort": EFFORT_HAND_TOOL,
		"efficiency_band": [0.40, 0.60],
	},
	# Drilling a rivet out destroys the rivet AND reams the hole in a member
	# oversize -- which is the sense in which, as the design puts it, riveted
	# "costs you a part".
	FASTENING_RIVET: {
		"destroys": DESTROYS_A_JOINED_PART, "effort": EFFORT_WORKSHOP,
		"efficiency_band": [0.60, 0.80],
	},
	FASTENING_WELD: {
		"destroys": DESTROYS_THE_ASSEMBLY, "effort": EFFORT_IMPOSSIBLE,
		"efficiency_band": [1.00, 1.00],
	},
}

## Kinematics per type. `dof` is the count of independent freedoms the
## mechanism really has: a hinge one, a ball in a socket three.
const _TYPE_KINEMATICS: Dictionary = {
	TYPE_RIGID: {"dof": 0, "motion": MOTION_NONE, "needs_axis": false, "springs": false},
	TYPE_PIVOT: {"dof": 1, "motion": MOTION_ROTATION, "needs_axis": true, "springs": false},
	TYPE_SLIDING: {"dof": 1, "motion": MOTION_TRANSLATION, "needs_axis": true, "springs": false},
	TYPE_SPRUNG: {"dof": 1, "motion": MOTION_FLEX, "needs_axis": false, "springs": true},
	# Three rotational freedoms and no constrained axis -- that is what makes a
	# socket a socket rather than a hinge.
	TYPE_SOCKET: {"dof": 3, "motion": MOTION_ROTATION, "needs_axis": false, "springs": false},
}

var id: String
var part_a: String
var part_b: String
var type: String
var fastening: String
## What the JOINT itself is made of -- the cord, the pin, the rivet, the weld
## metal. Not the members': a fibre lashing between two iron parts is still a
## fibre-strength connection, because the cord is what fails.
var material: String
## The rotation axis of a PIVOT or the direction of a SLIDING joint. Ignored
## (and expected to be ZERO) by the other types.
var axis: Vector3

var _materials: RefCounted = MaterialProperties.new()


func _init(
	a_id: String,
	a_part_a: String,
	a_part_b: String,
	a_type: String,
	a_fastening: String,
	a_material: String,
	a_axis: Vector3 = Vector3.ZERO
) -> void:
	id = a_id
	part_a = a_part_a
	part_b = a_part_b
	type = a_type
	fastening = a_fastening
	material = a_material
	axis = a_axis


# -- fastening facts, answerable without an instance ----------------------
#
# Static because a crafting UI wants to compare fastenings BEFORE any joint
# exists -- "what would this cost me to take apart later" is a build-time
# question.

## What undoing this fastening destroys. See the DESTROYS_* scale.
static func destroys_of(a_fastening: String) -> int:
	return _FASTENING_PROPERTIES.get(a_fastening, {}).get("destroys", DESTROYS_THE_ASSEMBLY)


## What undoing this fastening takes. See the EFFORT_* scale.
static func effort_of(a_fastening: String) -> int:
	return _FASTENING_PROPERTIES.get(a_fastening, {}).get("effort", EFFORT_IMPOSSIBLE)


## How readily this fastening comes apart, 0 (never) to 1 (freely). The share
## of the two cost scales NOT spent -- not a hand-picked table. An unknown
## fastening answers 0.0, the conservative end: never promise a disassembly
## layer that something the model has not thought about will come apart.
static func serviceability_of(a_fastening: String) -> float:
	var worst := float(DESTROYS_THE_ASSEMBLY + EFFORT_IMPOSSIBLE)
	return 1.0 - float(destroys_of(a_fastening) + effort_of(a_fastening)) / worst


## Does undoing this cost a whole part, rather than just the fastener? The
## question a later disassembly-risk layer actually asks.
static func costs_a_part(a_fastening: String) -> bool:
	return destroys_of(a_fastening) >= DESTROYS_A_JOINED_PART


## The real published band this fastening's efficiency is the midpoint of.
static func efficiency_band_of(a_fastening: String) -> Array:
	return _FASTENING_PROPERTIES.get(a_fastening, {}).get("efficiency_band", [0.0, 0.0])


## Fraction of the solid parent section's strength this connection retains.
static func efficiency_of(a_fastening: String) -> float:
	var band := efficiency_band_of(a_fastening)
	return (float(band[0]) + float(band[1])) * 0.5


# -- this joint ------------------------------------------------------------

func serviceability() -> float:
	return serviceability_of(fastening)


func efficiency() -> float:
	return efficiency_of(fastening)


## Does force pass straight through, or can these two parts move relative to
## each other? THE question that distinguishes a sword from a pair of scissors.
func transmits_rigidly() -> bool:
	return degrees_of_freedom() == 0


func permits_motion() -> bool:
	return not transmits_rigidly()


func degrees_of_freedom() -> int:
	return _TYPE_KINEMATICS.get(type, {}).get("dof", 0)


func motion_kind() -> String:
	return _TYPE_KINEMATICS.get(type, {}).get("motion", MOTION_NONE)


## The unit axis a PIVOT turns about or a SLIDING joint runs along. ZERO for
## everything else -- a rigid joint has no motion to have an axis for, and a
## socket turns about every axis, so naming one would be a lie.
func motion_axis() -> Vector3:
	if not _TYPE_KINEMATICS.get(type, {}).get("needs_axis", false):
		return Vector3.ZERO
	if axis.is_zero_approx():
		return Vector3.ZERO
	return axis.normalized()


## Does this joint store the energy put into it and return it? The bow limb.
func stores_energy() -> bool:
	return _TYPE_KINEMATICS.get(type, {}).get("springs", false)


## The load this joint carries before it fails, given the section it acts
## through: efficiency x the joint material's strength x that area.
##
## Toughness stands in for tensile strength here. That is not a fudge invented
## for this file -- MaterialProperties.ROPE_MIN_TOUGHNESS's own doc comment
## already establishes it, because the shared 8-scalar vector has no separate
## tensile scalar and toughness (resistance to fracture under stress) is the
## closest of the eight to "will not let go under load".
##
## `section_area_cm2` is supplied by the caller because a joint does not know
## its members -- the graph does, and it passes the SMALLER of the two parts'
## cross-sections, the same net-section logic that governs a real riveted
## connection. An invalid joint carries nothing.
func load_capacity(section_area_cm2: float) -> float:
	if not is_valid():
		return 0.0
	return efficiency() * _materials.property_value(material, "toughness") * section_area_cm2


func connects(part_id: String) -> bool:
	return part_id == part_a or part_id == part_b


## The part at this joint's far end from `part_id`, or "" if it does not touch
## `part_id` at all. This is what the graph's traversal walks.
func other_end(part_id: String) -> String:
	if part_id == part_a:
		return part_b
	if part_id == part_b:
		return part_a
	return ""


## "" when the joint is well formed, otherwise a message naming what is wrong.
func validation_error() -> String:
	if id == "":
		return "a joint needs an id"
	if part_a == "" or part_b == "":
		return "a joint needs two named ends, got '%s' and '%s'" % [part_a, part_b]
	if part_a == part_b:
		return "a joint from '%s' to itself joins nothing" % part_a
	if not TYPES.has(type):
		return "unknown joint type '%s'" % type
	if not FASTENINGS.has(fastening):
		return "unknown fastening '%s'" % fastening
	if not MaterialProperties.MATERIALS.has(material):
		return "unmodeled material '%s' -- it has no property vector" % material
	# The one cross-rule between the two vocabularies, and it is physically
	# undeniable: a forge weld has made the two parts one piece of metal, so
	# there is nothing left to pivot, slide, flex or swivel about.
	if fastening == FASTENING_WELD and permits_motion():
		return "a weld admits no relative motion, so it cannot hold a '%s' joint" % type
	if _TYPE_KINEMATICS[type]["needs_axis"] and axis.is_zero_approx():
		return "a '%s' joint needs a non-zero axis to move about" % type
	return ""


func is_valid() -> bool:
	return validation_error() == ""
