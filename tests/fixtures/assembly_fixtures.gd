extends RefCounted

## The real assemblies the swing model, the item compiler and the absence-reason
## layer are all checked against, in ONE place.
##
## Deliberately outside tests/unit so GUT never collects it as a test script,
## and deliberately shared: the arming sword here is dimension-for-dimension the
## one tests/unit/test_part_graph.gd already asserts masses 1.0-1.5 kg. Three
## test files needed a sword and the alternative was three swords that could
## quietly drift into disagreeing about what a sword is.
##
## Every dimension below is a real measurement of a real object, named in the
## comment above it. Nothing here is a "balanced" number.

const ItemPart: GDScript = preload("res://src/gameplay/item_part.gd")
const PartJoint: GDScript = preload("res://src/gameplay/part_joint.gd")
const PartGraph: GDScript = preload("res://src/gameplay/part_graph.gd")


static func _rigid(joint_id: String, a: String, b: String, material: String) -> RefCounted:
	return PartJoint.new(joint_id, a, b, PartJoint.TYPE_RIGID, PartJoint.FASTENING_FIT, material)


# -- the arming sword ------------------------------------------------------
#
# Dimension-for-dimension test_part_graph.gd's `_sword()`: an 80cm iron blade,
# a 20cm crossguard, an 11cm wooden grip and an iron pommel peined onto the
# tang. Masses 1.377 kg, which is a real single-handed arming sword.

static func sword() -> RefCounted:
	var graph: RefCounted = PartGraph.new()
	graph.add_part("blade", ItemPart.new(
		"iron", ItemPart.GEOMETRY_EDGE, ItemPart.ROLE_WORKING,
		{"length_cm": 80.0, "width_cm": 4.5, "thickness_cm": 0.5, "angle_deg": 20.0}
	))
	graph.add_part("guard", ItemPart.new(
		"iron", ItemPart.GEOMETRY_FACE, ItemPart.ROLE_STRUCTURE,
		{"width_cm": 20.0, "height_cm": 2.0, "thickness_cm": 0.8}
	))
	graph.add_part("grip", ItemPart.new(
		"wood", ItemPart.GEOMETRY_HAFT, ItemPart.ROLE_GRIP,
		{"length_cm": 11.0, "diameter_cm": 3.2}
	))
	graph.add_part("pommel", ItemPart.new(
		"iron", ItemPart.GEOMETRY_BULK, ItemPart.ROLE_COUNTERWEIGHT, {"diameter_cm": 4.5}
	))
	graph.add_joint(_rigid("shoulder", "blade", "guard", "iron"))
	graph.add_joint(_rigid("collar", "guard", "grip", "wood"))
	graph.add_joint(PartJoint.new(
		"peen", "grip", "pommel", PartJoint.TYPE_RIGID, PartJoint.FASTENING_RIVET, "iron"
	))
	return graph


## The same sword with the pommel simply left off -- LIGHTER, and worse. The
## whole point of the pommel, and it is not a rule anybody wrote down.
static func sword_without_pommel() -> RefCounted:
	var graph: RefCounted = PartGraph.new()
	graph.add_part("blade", ItemPart.new(
		"iron", ItemPart.GEOMETRY_EDGE, ItemPart.ROLE_WORKING,
		{"length_cm": 80.0, "width_cm": 4.5, "thickness_cm": 0.5, "angle_deg": 20.0}
	))
	graph.add_part("guard", ItemPart.new(
		"iron", ItemPart.GEOMETRY_FACE, ItemPart.ROLE_STRUCTURE,
		{"width_cm": 20.0, "height_cm": 2.0, "thickness_cm": 0.8}
	))
	graph.add_part("grip", ItemPart.new(
		"wood", ItemPart.GEOMETRY_HAFT, ItemPart.ROLE_GRIP,
		{"length_cm": 11.0, "diameter_cm": 3.2}
	))
	graph.add_joint(_rigid("shoulder", "blade", "guard", "iron"))
	graph.add_joint(_rigid("collar", "guard", "grip", "wood"))
	return graph


## The sword with an obsidian blade -- a real material with a real consequence.
## Obsidian takes the keenest edge there is (sharpness_capacity 10, above iron's
## 8) and its toughness of 1.0 is below the threshold the impact model already
## shatters things at.
static func obsidian_sword() -> RefCounted:
	var graph: RefCounted = sword()
	var swapped: RefCounted = PartGraph.new()
	for part_id in graph.part_ids():
		var part: RefCounted = graph.part(part_id)
		var material: String = "obsidian" if part_id == "blade" else part.material
		swapped.add_part(part_id, ItemPart.new(
			material, part.geometry, part.role, part.dimensions
		))
	for joint_id in graph.joint_ids():
		swapped.add_joint(graph.joint(joint_id))
	return swapped


# -- the felling axe -------------------------------------------------------
#
# A 70cm hickory haft and a 1.54 kg iron head, bit ground at 28 degrees
# included -- inside the real 25-30 degree felling range, where the bevel still
# severs fibres rather than merely splitting them. Its edge is a TRANSVERSE bit:
# no teeth, no pitch, nothing running along the cut.

static func felling_axe() -> RefCounted:
	var graph: RefCounted = PartGraph.new()
	graph.add_part("haft", ItemPart.new(
		"wood", ItemPart.GEOMETRY_HAFT, ItemPart.ROLE_GRIP,
		{"length_cm": 70.0, "diameter_cm": 3.5}
	))
	graph.add_part("bit", ItemPart.new(
		"iron", ItemPart.GEOMETRY_EDGE, ItemPart.ROLE_WORKING,
		{"length_cm": 11.0, "width_cm": 12.0, "thickness_cm": 3.0, "angle_deg": 28.0}
	))
	# A socketed axe head is a taper fit: it tightens under every swing and
	# pulls straight off in tension, which is exactly what FASTENING_FIT means.
	graph.add_joint(_rigid("eye", "haft", "bit", "wood"))
	return graph


# -- the rip saw -----------------------------------------------------------
#
# A 60cm x 12cm plate of 0.9mm spring steel, 5 teeth per inch (a 5.08mm pitch,
# the classic rip filing), each tooth set 0.3mm to its own side, hung on a 12cm
# wooden handle. Teeth are filed at 60 degrees included -- steep, because a rip
# tooth is a row of little chisels, not a knife.
#
# The set is the detail that matters: it cuts a kerf 1.5mm wide through a 0.9mm
# plate, and a saw whose kerf is not wider than its own plate BINDS. That, and
# not sharpness, is why an axe cannot rip a plank.

static func rip_saw() -> RefCounted:
	return _saw_with_set_mm(0.3)


## The same saw filed with no set at all. It has every tooth it needs and it
## still cannot rip, because it jams in its own kerf.
static func unset_saw() -> RefCounted:
	return _saw_with_set_mm(0.0)


static func _saw_with_set_mm(tooth_set_mm: float) -> RefCounted:
	var graph: RefCounted = PartGraph.new()
	graph.add_part("handle", ItemPart.new(
		"wood", ItemPart.GEOMETRY_HAFT, ItemPart.ROLE_GRIP,
		{"length_cm": 12.0, "diameter_cm": 3.5}
	))
	graph.add_part("plate", ItemPart.new(
		"iron", ItemPart.GEOMETRY_EDGE, ItemPart.ROLE_WORKING,
		{
			"length_cm": 60.0, "width_cm": 12.0, "thickness_cm": 0.09, "angle_deg": 60.0,
			"tooth_pitch_mm": 25.4 / 5.0, "tooth_set_mm": tooth_set_mm,
		}
	))
	graph.add_joint(_rigid("tote", "handle", "plate", "wood"))
	return graph


# -- the malformed one -----------------------------------------------------

## A blade and nothing to hold it by. Not a knife -- a knife has a handle. This
## is the offcut that comes off the grinder, and there is no pivot to swing it
## about, so the swing model has nothing to say about it.
static func headless_edge() -> RefCounted:
	var graph: RefCounted = PartGraph.new()
	graph.add_part("blade", ItemPart.new(
		"iron", ItemPart.GEOMETRY_EDGE, ItemPart.ROLE_WORKING,
		{"length_cm": 20.0, "width_cm": 3.0, "thickness_cm": 0.3, "angle_deg": 18.0}
	))
	return graph
