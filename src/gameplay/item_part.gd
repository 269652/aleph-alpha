extends RefCounted

## One part of an item: a (material, geometry, role) triple. Pure logic, no
## engine, no scene tree.
##
## docs/concept/materials.md's "Shape and assembly" section already commits to
## the sentence "an item is a small graph of parts, each a (material x
## geometry) pair"; this file is that part, made real, and
## docs/concept/emergent_crafting.md is the design doc for the graph it lives
## in.
##
## ## Why role is a THIRD field and not derived from geometry
##
## Geometry and material carry the PHYSICS. Role carries the maker's INTENT --
## which end you hold, which seat receives a gem, which lump is there purely to
## balance the thing. The design rule this model exists to serve is that
## affordances are inferred from topology plus physics and never declared, so
## nothing in this file may let role answer a physical question: a part cuts
## because it is a keen edge of a hard material, never because someone typed
## ROLE_WORKING. Role is read by INTERFACE questions only -- where does a hand
## go, where does a channel terminate -- which genuinely cannot be recovered
## from shape (a scissors bow and a frame rail are the same slender member; one
## is held and one is not, and only the maker knows which).
##
## ## What lives here versus on the graph
##
## A part answers only what it can answer ALONE: its own volume, mass, span,
## load-bearing section, and how keen an edge it can hold. Everything that
## needs a second part is the graph's -- leverage needs a head AND a lever arm
## AND the path between them; "is this the weakest link" needs every other
## joint to compare against; "do these two move relative to each other" is
## purely topological. Splitting it here keeps a part a fact rather than an
## opinion about an assembly it does not know it is in.
##
## ## Volume is derived, never stored
##
## Every geometry below computes its volume from its own real dimensions with
## ordinary solid geometry, so a part cannot claim a mass that its own shape
## contradicts. Storing volume as a field alongside the dimensions would let
## the two disagree, which is the class of bug BuildingPiece.is_load_bearing
## avoids by deriving from support_capacity rather than keeping a second flag.

const MaterialProperties: GDScript = preload("res://src/gameplay/material_properties.gd")

## The geometry primitives docs/concept/materials.md enumerates: edge (length,
## angle -> keenness potential), point (-> pierce), flat/face (-> crush/block),
## haft/lever (length -> torque multiplier), bulk/head (mass concentration).
const GEOMETRY_EDGE := "edge"
const GEOMETRY_POINT := "point"
const GEOMETRY_FACE := "face"
const GEOMETRY_HAFT := "haft"
const GEOMETRY_BULK := "bulk"

const GEOMETRIES: Array[String] = [
	GEOMETRY_EDGE, GEOMETRY_POINT, GEOMETRY_FACE, GEOMETRY_HAFT, GEOMETRY_BULK,
]

## What the maker meant this part FOR. Deliberately small and deliberately not
## weapon-shaped: the same six words have to describe a sword, a pair of
## scissors and a picture frame, or the vocabulary has smuggled in a weapon
## assumption the rest of the design is trying to avoid.
##   WORKING       the business end -- the blade, the spike, the striking head
##   GRIP          where a hand (or another item) takes hold
##   STRUCTURE     a load-carrying member that is neither held nor working
##   COUNTERWEIGHT mass placed to balance, not to strike (a sword's pommel)
##   SETTING       a seat that receives another part (a gem's setting, a
##                 rebate). This is where a magic channel terminates.
##   COVER         a panel that encloses, protects or displays
const ROLE_WORKING := "working"
const ROLE_GRIP := "grip"
const ROLE_STRUCTURE := "structure"
const ROLE_COUNTERWEIGHT := "counterweight"
const ROLE_SETTING := "setting"
const ROLE_COVER := "cover"

const ROLES: Array[String] = [
	ROLE_WORKING, ROLE_GRIP, ROLE_STRUCTURE, ROLE_COUNTERWEIGHT,
	ROLE_SETTING, ROLE_COVER,
]

## The dimensions each geometry genuinely needs to be a solid. Nothing is
## optional: a part with a missing dimension is rejected rather than defaulted,
## because a defaulted dimension produces a confident, wrong mass.
const REQUIRED_DIMENSIONS: Dictionary = {
	GEOMETRY_EDGE: ["length_cm", "width_cm", "thickness_cm", "angle_deg"],
	GEOMETRY_POINT: ["length_cm", "angle_deg"],
	GEOMETRY_FACE: ["width_cm", "height_cm", "thickness_cm"],
	GEOMETRY_HAFT: ["length_cm", "diameter_cm"],
	GEOMETRY_BULK: ["diameter_cm"],
}

## The two ends of the real sharpening range, and the reason `angle_deg` is a
## required dimension of an edge at all (materials.md: "edge (length, angle ->
## keenness potential)").
##
## MEASURED against actual cutlery/woodworking practice rather than picked:
## razors, scalpels and straight-edge knives are ground at roughly 15 degrees
## INCLUDED, and below that the steel -- not the angle -- is what limits how
## keen the edge gets, which is precisely why nobody grinds thinner. Felling
## axes and splitting bits are ground at roughly 40 degrees included, and at
## that angle the tool is a wedge that parts fibres rather than a cutter that
## severs them. Between the two, keenness falls off linearly, scaling the
## material's own sharpness_capacity from the shared 8-scalar vector.
##
## Pinned by test_the_two_sharpening_angles_are_the_real_razor_and_axe_bit_numbers,
## test_a_razor_ground_edge_realizes_the_materials_full_sharpness_capacity and
## test_an_axe_ground_edge_is_a_splitting_wedge_with_no_keenness_left.
const KEEN_ANGLE_DEG := 15.0
const WEDGE_ANGLE_DEG := 40.0

var material: String
var geometry: String
var role: String
var dimensions: Dictionary

var _materials: RefCounted = MaterialProperties.new()


func _init(
	a_material: String, a_geometry: String, a_role: String, a_dimensions: Dictionary
) -> void:
	material = a_material
	geometry = a_geometry
	role = a_role
	# A COPY: a caller that keeps mutating the dictionary it passed in must not
	# be able to change an already-built part's mass out from under the graph
	# that already measured it (see BuildingPiece.cost_of's same .duplicate()).
	dimensions = a_dimensions.duplicate()


## "" when the part is well formed, otherwise a message naming the offending
## value. Explicit rejection is the point: an unknown material would otherwise
## fall through MaterialProperties' DEFAULT_PROPERTIES to density 1.0 and hand
## back a confident, wrong mass -- a wrong answer being much worse here than no
## answer.
func validation_error() -> String:
	if not GEOMETRIES.has(geometry):
		return "unknown geometry '%s'" % geometry
	if not ROLES.has(role):
		return "unknown role '%s'" % role
	if not MaterialProperties.MATERIALS.has(material):
		return "unmodeled material '%s' -- it has no property vector" % material
	for dimension_name in REQUIRED_DIMENSIONS[geometry]:
		if not dimensions.has(dimension_name):
			return "geometry '%s' needs dimension '%s'" % [geometry, dimension_name]
		var value: float = float(dimensions[dimension_name])
		if value <= 0.0:
			return "dimension '%s' must be positive, got %s" % [dimension_name, value]
		# An included angle of 180 degrees or more is a flat sheet, not a
		# wedge or a cone -- there is no solid to measure.
		if dimension_name == "angle_deg" and value >= 180.0:
			return "dimension 'angle_deg' must be under 180, got %s" % value
	return ""


func is_valid() -> bool:
	return validation_error() == ""


## Real volume from real dimensions. 0.0 for a malformed part -- this project's
## existing "not modeled" value (see Item.mass_kg's doc comment) rather than a
## crash, so a bad graph is caught by validation rather than by a stack trace.
func volume_cm3() -> float:
	if not is_valid():
		return 0.0
	match geometry:
		GEOMETRY_EDGE:
			# A blade is a wedge -- a triangular prism, half its bounding box.
			# NOTE the back thickness is its own dimension and is NOT derived
			# from the edge angle: on a real blade the cutting bevel is ground
			# into the last few millimetres and says nothing about how thick
			# the spine is. Deriving one from the other would make every keenly
			# ground sword implausibly thin (or every thick one implausibly
			# blunt), and materials.md is explicit that angle feeds KEENNESS.
			return 0.5 * _dim("length_cm") * _dim("width_cm") * _dim("thickness_cm")
		GEOMETRY_POINT:
			# A cone whose base radius follows from the included apex angle.
			var radius := _dim("length_cm") * tan(deg_to_rad(_dim("angle_deg") * 0.5))
			return PI * radius * radius * _dim("length_cm") / 3.0
		GEOMETRY_FACE:
			return _dim("width_cm") * _dim("height_cm") * _dim("thickness_cm")
		GEOMETRY_HAFT:
			var haft_radius := _dim("diameter_cm") * 0.5
			return PI * haft_radius * haft_radius * _dim("length_cm")
		GEOMETRY_BULK:
			# Bulk has no working shape of its own -- it is mass concentration
			# and nothing else -- so it is the equivalent sphere of its
			# diameter, the same convention StoneSize.mass_kg_for already uses
			# to give a loose stone a real mass.
			return PI * pow(_dim("diameter_cm"), 3.0) / 6.0
		_:
			return 0.0


## Real mass in kilograms. Consumes MaterialProperties.mass_kg_for rather than
## re-deriving density x volume, so a part, a thrown stone and a swung weapon
## all get their mass from one place (see that function's own doc comment).
func mass_kg() -> float:
	if not is_valid():
		return 0.0
	return _materials.mass_kg_for(material, volume_cm3())


## The part's extent along its principal axis, in cm.
##
## Two named later layers read exactly this: magic channelling needs a real
## path LENGTH in cm to decide loss along a route, and the leverage rule
## (`delivered_force ~ head_mass x lever_length x swing_speed`) needs a real
## lever arm. A slab's principal axis is its longer in-plane dimension
## regardless of which one the caller happened to call "width" -- a 20x2
## crossguard spans 20cm either way round.
func span_cm() -> float:
	if not is_valid():
		return 0.0
	match geometry:
		GEOMETRY_EDGE, GEOMETRY_POINT, GEOMETRY_HAFT:
			return _dim("length_cm")
		GEOMETRY_FACE:
			return maxf(_dim("width_cm"), _dim("height_cm"))
		GEOMETRY_BULK:
			return _dim("diameter_cm")
		_:
			return 0.0


## The area of a cut made ACROSS the span -- the section that actually carries
## load, and therefore the cap on how strong a joint made into this part can
## be (see PartJoint.load_capacity). A joint can be no stronger than the
## thinnest material it has to act through, which is the same net-section logic
## that governs a real riveted or bolted connection.
func cross_section_cm2() -> float:
	if not is_valid():
		return 0.0
	match geometry:
		GEOMETRY_EDGE:
			# The wedge section: a triangle of width x back thickness.
			return 0.5 * _dim("width_cm") * _dim("thickness_cm")
		GEOMETRY_POINT:
			# A cone's section varies from nothing at the tip to the base
			# circle. The BASE is the honest one to report: that is where the
			# point meets whatever it is mounted in, which is where a joint is.
			var base_radius := _dim("length_cm") * tan(deg_to_rad(_dim("angle_deg") * 0.5))
			return PI * base_radius * base_radius
		GEOMETRY_FACE:
			return minf(_dim("width_cm"), _dim("height_cm")) * _dim("thickness_cm")
		GEOMETRY_HAFT:
			var haft_radius := _dim("diameter_cm") * 0.5
			return PI * haft_radius * haft_radius
		GEOMETRY_BULK:
			var bulk_radius := _dim("diameter_cm") * 0.5
			return PI * bulk_radius * bulk_radius
		_:
			return 0.0


## How keen an edge this part actually holds: the material's sharpness_capacity
## scaled by how the edge is ground, between the two real sharpening angles
## (see KEEN_ANGLE_DEG / WEDGE_ANGLE_DEG). Only an edge has one -- a haft, a
## slab and a lump answer 0.0 because there is no edge on them to be keen.
##
## This is per-part physics, NOT affordance inference: it says how keen this
## piece of material at this grind is, and says nothing about what the assembly
## it belongs to can do. "Two opposed edges on a pivot afford shear" is a
## topological question and lives on the graph.
func keenness() -> float:
	if not is_valid() or geometry != GEOMETRY_EDGE:
		return 0.0
	var angle := _dim("angle_deg")
	var grind_factor := clampf(
		(WEDGE_ANGLE_DEG - angle) / (WEDGE_ANGLE_DEG - KEEN_ANGLE_DEG), 0.0, 1.0
	)
	return _materials.property_value(material, "sharpness_capacity") * grind_factor


## One named scalar from this part's material vector -- how the shared 8-scalar
## vector reaches a graph query without every caller having to know which
## material this part is made of.
func property_value(property_name: String) -> float:
	return _materials.property_value(material, property_name)


func _dim(dimension_name: String) -> float:
	return float(dimensions.get(dimension_name, 0.0))
