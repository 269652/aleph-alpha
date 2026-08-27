extends GutTest

## Parts as nodes, typed joints as edges -- docs/concept/emergent_crafting.md.
##
## The three assemblies at the bottom of this file ARE the spec. A sword is the
## easy case the existing rigid model already handled; a pair of scissors is
## the case it could not express at all and is the proof the joint primitive
## earns its place; a photo frame is the proof the grammar is not weapon-only.

var PartGraph: GDScript = preload("res://src/gameplay/part_graph.gd")
var ItemPart: GDScript = preload("res://src/gameplay/item_part.gd")
var PartJoint: GDScript = preload("res://src/gameplay/part_joint.gd")


func _haft(material: String = "wood", length: float = 11.0) -> RefCounted:
	return ItemPart.new(
		material, ItemPart.GEOMETRY_HAFT, ItemPart.ROLE_GRIP,
		{"length_cm": length, "diameter_cm": 3.2}
	)


func _blade(material: String = "iron", length: float = 80.0) -> RefCounted:
	return ItemPart.new(
		material, ItemPart.GEOMETRY_EDGE, ItemPart.ROLE_WORKING,
		{"length_cm": length, "width_cm": 4.5, "thickness_cm": 0.5, "angle_deg": 20.0}
	)


func _rigid(joint_id: String, a: String, b: String, material: String = "iron") -> RefCounted:
	return PartJoint.new(
		joint_id, a, b, PartJoint.TYPE_RIGID, PartJoint.FASTENING_FIT, material
	)


## A three-part rigid chain: haft -- blade -- haft, used by the traversal tests.
func _chain() -> RefCounted:
	var graph: RefCounted = PartGraph.new()
	graph.add_part("a", _haft())
	graph.add_part("b", _blade())
	graph.add_part("c", _haft())
	graph.add_joint(_rigid("ab", "a", "b"))
	graph.add_joint(_rigid("bc", "b", "c"))
	return graph


# -- construction and ordering --------------------------------------------
#
# Ordering is CONSTRUCTION order, explicitly kept, never a dictionary's key
# order -- this project has been bitten by unstable iteration before.

func test_a_graph_lists_its_parts_in_the_order_they_were_added() -> void:
	var graph: RefCounted = PartGraph.new()
	graph.add_part("grip", _haft())
	graph.add_part("pommel", _haft())
	assert_eq(graph.part_ids(), ["grip", "pommel"])


func test_a_graph_lists_its_joints_in_the_order_they_were_added() -> void:
	assert_eq(_chain().joint_ids(), ["ab", "bc"])


func test_a_graph_hands_back_the_very_part_it_was_given() -> void:
	var graph: RefCounted = PartGraph.new()
	var grip: RefCounted = _haft()
	graph.add_part("grip", grip)
	assert_true(graph.has_part("grip"))
	assert_same(graph.part("grip"), grip)
	assert_null(graph.part("nothing"), "an absent part is null, not a stub")


func test_a_graph_hands_back_the_very_joint_it_was_given() -> void:
	var graph: RefCounted = _chain()
	assert_true(graph.has_joint("ab"))
	assert_eq(graph.joint("ab").id, "ab")
	assert_null(graph.joint("nothing"))


# -- malformed graphs are rejected at the point of the mistake -------------
#
# Every rejection returns false AND records a message naming what was wrong, so
# a bad assembly fails where it was built rather than later, somewhere else,
# confusingly.

func test_a_well_formed_graph_reports_no_errors() -> void:
	var graph: RefCounted = _chain()
	assert_true(graph.is_well_formed())
	assert_eq(graph.validation_errors(), [])


func test_a_duplicate_part_id_is_rejected_and_named() -> void:
	var graph: RefCounted = PartGraph.new()
	assert_true(graph.add_part("grip", _haft()))
	assert_false(graph.add_part("grip", _blade()))
	assert_false(graph.is_well_formed())
	assert_string_contains(graph.validation_errors()[0], "grip")


func test_the_first_part_under_a_duplicated_id_is_the_one_that_stays() -> void:
	var graph: RefCounted = PartGraph.new()
	var first: RefCounted = _haft()
	graph.add_part("grip", first)
	graph.add_part("grip", _blade())
	assert_same(graph.part("grip"), first, "a rejected add must not overwrite")


func test_an_invalid_part_is_rejected_and_its_own_reason_is_carried_up() -> void:
	var graph: RefCounted = PartGraph.new()
	var bad: RefCounted = ItemPart.new("unobtainium", ItemPart.GEOMETRY_BULK,
		ItemPart.ROLE_COUNTERWEIGHT, {"diameter_cm": 4.0})
	assert_false(graph.add_part("lump", bad))
	assert_string_contains(graph.validation_errors()[0], "unobtainium")


func test_a_joint_referencing_a_part_that_does_not_exist_is_rejected_and_named() -> void:
	var graph: RefCounted = PartGraph.new()
	graph.add_part("a", _haft())
	assert_false(graph.add_joint(_rigid("ab", "a", "ghost")))
	assert_false(graph.is_well_formed())
	assert_string_contains(graph.validation_errors()[0], "ghost")


func test_a_duplicate_joint_id_is_rejected() -> void:
	var graph: RefCounted = _chain()
	assert_false(graph.add_joint(_rigid("ab", "a", "c")))
	assert_string_contains(graph.validation_errors()[0], "ab")


func test_an_invalid_joint_is_rejected_and_its_own_reason_is_carried_up() -> void:
	var graph: RefCounted = PartGraph.new()
	graph.add_part("a", _haft())
	graph.add_part("b", _blade())
	var welded_pivot: RefCounted = PartJoint.new(
		"ab", "a", "b", PartJoint.TYPE_PIVOT, PartJoint.FASTENING_WELD, "iron", Vector3.UP
	)
	assert_false(graph.add_joint(welded_pivot))
	assert_string_contains(graph.validation_errors()[0], "weld")


func test_a_rejected_part_or_joint_never_enters_the_graph() -> void:
	var graph: RefCounted = PartGraph.new()
	graph.add_part("a", _haft())
	graph.add_joint(_rigid("ab", "a", "ghost"))
	assert_eq(graph.joint_ids(), [], "a rejected joint must leave no trace")


# -- traversal -------------------------------------------------------------

func test_the_joints_and_neighbours_at_a_part_come_back_in_construction_order() -> void:
	var graph: RefCounted = _chain()
	assert_eq(graph.joints_at("b"), ["ab", "bc"])
	assert_eq(graph.neighbors("b"), ["a", "c"])
	assert_eq(graph.neighbors("a"), ["b"])
	assert_eq(graph.neighbors("nothing"), [])


func test_a_path_runs_from_one_part_to_another_through_the_parts_between() -> void:
	assert_eq(_chain().path_between("a", "c"), ["a", "b", "c"])


func test_a_path_from_a_part_to_itself_is_just_that_part() -> void:
	assert_eq(_chain().path_between("b", "b"), ["b"])


func test_there_is_no_path_to_a_part_nothing_joins() -> void:
	var graph: RefCounted = _chain()
	graph.add_part("loose", _haft())
	assert_eq(graph.path_between("a", "loose"), [])


func test_there_is_no_path_to_a_part_that_does_not_exist() -> void:
	assert_eq(_chain().path_between("a", "ghost"), [])


## Load-bearing for channel routing, which cares about how FAR the route is.
## The shortest route must be the one returned, not merely the first one found.
func test_a_path_takes_the_shortest_route_when_a_cycle_offers_two() -> void:
	var graph: RefCounted = PartGraph.new()
	for part_id in ["a", "b", "c", "d"]:
		graph.add_part(part_id, _haft())
	graph.add_joint(_rigid("ab", "a", "b"))
	graph.add_joint(_rigid("bc", "b", "c"))
	graph.add_joint(_rigid("cd", "c", "d"))
	graph.add_joint(_rigid("ad", "a", "d"))
	assert_eq(graph.path_between("a", "d"), ["a", "d"],
		"one hop round the ring, not three")


## The joints a route crosses, derived from the part path rather than kept as a
## second answer that could disagree with it. Disassembly walks exactly this.
func test_the_joints_along_a_path_are_derived_from_the_path_itself() -> void:
	var graph: RefCounted = _chain()
	assert_eq(graph.joints_along_path(graph.path_between("a", "c")), ["ab", "bc"])
	assert_eq(graph.joints_along_path(graph.path_between("b", "b")), [])
	assert_eq(graph.joints_along_path([]), [])


## Channel loss is decided by how far the route physically is, so the path has
## to have a real length in cm, not a hop count.
func test_a_path_has_a_real_length_in_centimetres() -> void:
	var graph: RefCounted = _chain()
	# haft 11 + blade 80 + haft 11
	assert_almost_eq(graph.path_length_cm(graph.path_between("a", "c")), 102.0, 0.0001)


func test_a_longer_member_on_the_route_makes_the_route_longer() -> void:
	var graph: RefCounted = PartGraph.new()
	graph.add_part("a", _haft("wood", 11.0))
	graph.add_part("b", _haft("wood", 50.0))
	graph.add_joint(_rigid("ab", "a", "b"))
	assert_almost_eq(graph.path_length_cm(graph.path_between("a", "b")), 61.0, 0.0001)


func test_a_graph_knows_whether_it_is_one_connected_assembly() -> void:
	assert_true(_chain().is_one_assembly())
	var split: RefCounted = _chain()
	split.add_part("loose", _haft())
	assert_false(split.is_one_assembly(), "a part nothing joins is not part of the assembly")


func test_an_empty_graph_is_trivially_connected() -> void:
	assert_true(PartGraph.new().is_one_assembly())


# -- aggregates ------------------------------------------------------------

## Joints are massless in this slice -- a lashing's cordage and a rivet have
## real mass, but no dimension to compute it from yet. Named as a limit rather
## than fudged.
func test_total_mass_is_the_sum_of_the_parts_masses() -> void:
	var graph: RefCounted = _chain()
	var expected: float = graph.part("a").mass_kg() + graph.part("b").mass_kg() \
		+ graph.part("c").mass_kg()
	assert_almost_eq(graph.total_mass_kg(), expected, 0.0000001)


func test_an_empty_graph_masses_nothing() -> void:
	assert_almost_eq(PartGraph.new().total_mass_kg(), 0.0, 0.0001)


func test_parts_can_be_found_by_role_and_by_geometry_in_construction_order() -> void:
	var graph: RefCounted = _chain()
	assert_eq(graph.parts_with_role(ItemPart.ROLE_GRIP), ["a", "c"])
	assert_eq(graph.parts_with_role(ItemPart.ROLE_WORKING), ["b"])
	assert_eq(graph.parts_with_geometry(ItemPart.GEOMETRY_EDGE), ["b"])
	assert_eq(graph.parts_with_role(ItemPart.ROLE_SETTING), [])


# -- the weakest link ------------------------------------------------------
#
# A joint has to be ABLE to be the weakest link, so "is it" must be computed
# rather than assumed: every joint's capacity is compared against every part's
# own section capacity, and the smallest wins. A part carries its own section
# at full efficiency, which is what joint efficiency is a fraction OF.

func test_a_parts_capacity_is_its_material_strength_through_its_own_section() -> void:
	var graph: RefCounted = _chain()
	var blade: RefCounted = graph.part("b")
	assert_almost_eq(
		graph.part_load_capacity("b"),
		blade.property_value("toughness") * blade.cross_section_cm2(), 0.0001
	)


## A joint can be no larger in section than the smaller member it joins -- the
## same net-section logic that governs a real riveted connection.
func test_a_joints_capacity_is_capped_by_the_thinner_of_the_two_members() -> void:
	var graph: RefCounted = _chain()
	var thinner: float = minf(
		graph.part("a").cross_section_cm2(), graph.part("b").cross_section_cm2()
	)
	assert_almost_eq(
		graph.joint_load_capacity("ab"), graph.joint("ab").load_capacity(thinner), 0.0001
	)


## An obsidian blade socketed into an iron haft fails at the BLADE, not at the
## joint: obsidian's toughness of 1 is so far below iron's 7 that even a
## half-efficiency friction fit out-carries the glass it holds. Exactly the
## "keen but shatters" trade materials.md's Physical-honesty section describes.
func test_a_part_can_be_the_weakest_link_when_its_material_is_brittle_enough() -> void:
	var graph: RefCounted = PartGraph.new()
	graph.add_part("haft", _haft("wood"))
	graph.add_part("flake", _blade("obsidian", 10.0))
	graph.add_joint(_rigid("socket", "haft", "flake", "iron"))
	var weakest: Dictionary = graph.weakest_link()
	assert_eq(weakest["kind"], "part")
	assert_eq(weakest["id"], "flake")


func test_the_weakest_link_reports_the_capacity_it_found() -> void:
	var graph: RefCounted = _chain()
	var weakest: Dictionary = graph.weakest_link()
	var reported: float = weakest["capacity"]
	if weakest["kind"] == "joint":
		assert_almost_eq(reported, graph.joint_load_capacity(weakest["id"]), 0.0001)
	else:
		assert_almost_eq(reported, graph.part_load_capacity(weakest["id"]), 0.0001)


func test_an_empty_graph_has_no_weakest_link() -> void:
	assert_eq(PartGraph.new().weakest_link()["kind"], "")


# -- articulation: topology, not declaration -------------------------------
#
# Nothing here reads a part's role or an item's name. Whether two parts can
# move relative to each other is answered purely from the joints between them,
# which is what makes it the foundation affordance inference can later sit on.

func test_a_wholly_rigid_assembly_is_a_rigid_body() -> void:
	assert_true(_chain().is_rigid_body())
	assert_eq(_chain().articulating_joints(), [])


func test_one_pivot_anywhere_stops_the_assembly_being_a_rigid_body() -> void:
	var graph: RefCounted = _chain()
	graph.add_part("d", _haft())
	graph.add_joint(PartJoint.new(
		"cd", "c", "d", PartJoint.TYPE_PIVOT, PartJoint.FASTENING_PIN, "iron", Vector3.UP
	))
	assert_false(graph.is_rigid_body())
	assert_eq(graph.articulating_joints(), ["cd"])


func test_two_parts_with_only_rigid_joints_between_them_cannot_move_apart() -> void:
	assert_false(_chain().permits_relative_motion("a", "c"))


## A rigid route WINS over an articulated one. If any all-rigid path exists the
## two parts are held still relative to each other, whatever else also joins
## them -- which is why a hinge with a welded strap across it is not a hinge.
func test_a_rigid_route_anywhere_overrules_an_articulated_one() -> void:
	var graph: RefCounted = PartGraph.new()
	graph.add_part("a", _haft())
	graph.add_part("b", _haft())
	graph.add_joint(PartJoint.new(
		"pivot", "a", "b", PartJoint.TYPE_PIVOT, PartJoint.FASTENING_PIN, "iron", Vector3.UP
	))
	assert_true(graph.permits_relative_motion("a", "b"))
	graph.add_joint(_rigid("strap", "a", "b"))
	assert_false(graph.permits_relative_motion("a", "b"),
		"welding a strap across a hinge stops it being a hinge")


func test_parts_that_are_not_joined_at_all_report_no_relative_motion() -> void:
	var graph: RefCounted = _chain()
	graph.add_part("loose", _haft())
	assert_false(graph.permits_relative_motion("a", "loose"),
		"two parts of different objects are not an articulation")


# -- splitting an assembly at a joint --------------------------------------
#
# One query, two named consumers: it is how "two opposed parts share a pivot"
# is checked structurally, and it is what disassembly asks -- what falls off if
# I undo this?

func test_undoing_a_joint_in_a_chain_splits_it_in_two() -> void:
	var pieces: Array = _chain().separates_into("ab")
	assert_eq(pieces.size(), 2)
	assert_eq(pieces[0], ["a"])
	assert_eq(pieces[1], ["b", "c"])


## Undoing one corner of a closed loop drops nothing -- the ring still holds.
func test_undoing_one_joint_of_a_cycle_separates_nothing() -> void:
	var graph: RefCounted = PartGraph.new()
	for part_id in ["a", "b", "c"]:
		graph.add_part(part_id, _haft())
	graph.add_joint(_rigid("ab", "a", "b"))
	graph.add_joint(_rigid("bc", "b", "c"))
	graph.add_joint(_rigid("ca", "c", "a"))
	var pieces: Array = graph.separates_into("ab")
	assert_eq(pieces.size(), 1, "a closed ring stays whole when one link lets go")


func test_undoing_a_joint_that_is_not_there_separates_nothing() -> void:
	assert_eq(_chain().separates_into("ghost"), [])


# -- determinism -----------------------------------------------------------

func test_the_same_graph_built_twice_answers_identically() -> void:
	var first: RefCounted = _chain()
	var second: RefCounted = _chain()
	assert_eq(first.part_ids(), second.part_ids())
	assert_eq(first.path_between("a", "c"), second.path_between("a", "c"))
	assert_almost_eq(first.total_mass_kg(), second.total_mass_kg(), 0.0)
	assert_eq(first.weakest_link(), second.weakest_link())


func test_repeated_queries_on_one_graph_never_drift() -> void:
	var graph: RefCounted = _chain()
	for _i in range(5):
		assert_eq(graph.path_between("a", "c"), ["a", "b", "c"])
		assert_eq(graph.neighbors("b"), ["a", "c"])


# ==========================================================================
# THE ACCEPTANCE ASSEMBLIES -- these tests are the spec
# ==========================================================================

# -- a sword: the easy case ------------------------------------------------
#
# An arming sword built to real dimensions: an 80cm blade, a 20cm crossguard, a
# wooden grip and an iron pommel peined onto the tang. Everything is rigid, so
# this is exactly what materials.md's existing implicitly-rigid assembly model
# could already express -- it is here as the control.

func _sword() -> RefCounted:
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
	# The blade shoulders against the guard and the grip slides over the tang:
	# both friction fits. The pommel is PEINED over the tang end -- the one
	# genuinely permanent joint on the whole sword, and the one that holds the
	# other three together.
	graph.add_joint(_rigid("shoulder", "blade", "guard", "iron"))
	graph.add_joint(_rigid("collar", "guard", "grip", "wood"))
	graph.add_joint(PartJoint.new(
		"peen", "grip", "pommel", PartJoint.TYPE_RIGID, PartJoint.FASTENING_RIVET, "iron"
	))
	return graph


func test_the_sword_is_well_formed_and_whole() -> void:
	var sword: RefCounted = _sword()
	assert_true(sword.is_well_formed(), str(sword.validation_errors()))
	assert_true(sword.is_one_assembly())


func test_the_sword_is_a_rigid_body_end_to_end() -> void:
	var sword: RefCounted = _sword()
	assert_true(sword.is_rigid_body())
	assert_eq(sword.articulating_joints(), [])
	assert_false(sword.permits_relative_motion("blade", "pommel"),
		"a sword that wobbled at the pommel would be a flail")


func test_the_sword_routes_from_its_grip_to_its_edge_through_the_guard() -> void:
	assert_eq(_sword().path_between("grip", "blade"), ["grip", "guard", "blade"])


## The mass every volume formula in item_part.gd is checked against at once: a
## real single-handed arming sword is 1.0-1.5 kg. An order-of-magnitude error
## in any one of the four geometries would show up here.
func test_the_sword_masses_what_a_real_arming_sword_masses() -> void:
	assert_between(_sword().total_mass_kg(), 1.0, 1.5)


## And it fails where real swords fail: at the shoulder, where the wide blade
## necks down to meet the guard. Nobody wrote that down -- it falls out of the
## blade's thin wedge section being the smallest in the assembly.
func test_the_sword_is_weakest_where_the_blade_meets_the_guard() -> void:
	var weakest: Dictionary = _sword().weakest_link()
	assert_eq(weakest["kind"], "joint")
	assert_eq(weakest["id"], "shoulder")


func test_the_sword_has_one_grip_one_edge_and_one_counterweight() -> void:
	var sword: RefCounted = _sword()
	assert_eq(sword.parts_with_role(ItemPart.ROLE_GRIP), ["grip"])
	assert_eq(sword.parts_with_geometry(ItemPart.GEOMETRY_EDGE), ["blade"])
	assert_eq(sword.parts_with_role(ItemPart.ROLE_COUNTERWEIGHT), ["pommel"])


# -- a pair of scissors: THE case -----------------------------------------
#
# Two opposed edges sharing ONE pivot, cutting by closing. This is the thing
# the implicitly-rigid assembly model cannot express AT ALL, and every
# assertion below is a structural fact about the scissors that the sword does
# not have. Built to real household dimensions: 8cm blades, 8cm bows, ~54g.

func _scissors() -> RefCounted:
	var graph: RefCounted = PartGraph.new()
	for half in ["a", "b"]:
		graph.add_part("blade_" + half, ItemPart.new(
			"iron", ItemPart.GEOMETRY_EDGE, ItemPart.ROLE_WORKING,
			{"length_cm": 8.0, "width_cm": 1.2, "thickness_cm": 0.25, "angle_deg": 30.0}
		))
		graph.add_part("bow_" + half, ItemPart.new(
			"iron", ItemPart.GEOMETRY_HAFT, ItemPart.ROLE_GRIP,
			{"length_cm": 8.0, "diameter_cm": 0.6}
		))
		# Bow forge-welded to blade: each half is one continuous piece of
		# steel, which is how larger shears really were made.
		graph.add_joint(PartJoint.new(
			"weld_" + half, "bow_" + half, "blade_" + half,
			PartJoint.TYPE_RIGID, PartJoint.FASTENING_WELD, "iron"
		))
	# The whole point. One pivot, turning about the axis through the screw --
	# perpendicular to the plane the blades lie in.
	graph.add_joint(PartJoint.new(
		"pivot", "blade_a", "blade_b", PartJoint.TYPE_PIVOT,
		PartJoint.FASTENING_PIN, "iron", Vector3.FORWARD
	))
	return graph


func test_the_scissors_are_well_formed_and_whole() -> void:
	var scissors: RefCounted = _scissors()
	assert_true(scissors.is_well_formed(), str(scissors.validation_errors()))
	assert_true(scissors.is_one_assembly())


## The structural difference from the sword, stated as plainly as it can be.
func test_the_scissors_are_not_a_rigid_body_and_the_sword_is() -> void:
	assert_false(_scissors().is_rigid_body())
	assert_true(_sword().is_rigid_body())


func test_the_scissors_articulate_at_exactly_one_joint() -> void:
	assert_eq(_scissors().articulating_joints(), ["pivot"])


func test_the_two_blades_move_relative_to_each_other_and_that_is_the_cut() -> void:
	var scissors: RefCounted = _scissors()
	assert_true(scissors.permits_relative_motion("blade_a", "blade_b"))
	assert_eq(scissors.motion_between("blade_a", "blade_b"), [PartJoint.MOTION_ROTATION],
		"they close about the pivot -- rotation, not sliding")


func test_the_bows_move_relative_to_each_other_because_the_route_crosses_the_pivot() -> void:
	var scissors: RefCounted = _scissors()
	assert_true(scissors.permits_relative_motion("bow_a", "bow_b"))
	assert_eq(scissors.path_between("bow_a", "bow_b"),
		["bow_a", "blade_a", "blade_b", "bow_b"])


func test_each_half_of_the_scissors_is_internally_rigid() -> void:
	var scissors: RefCounted = _scissors()
	assert_false(scissors.permits_relative_motion("bow_a", "blade_a"),
		"a bow forge-welded to its own blade is one piece of steel")


## Opposition, as far as unoriented topology can state it: undo the pivot and
## the scissors fall into two separate halves, each carrying exactly one edge.
## Two edges, on opposite sides of one articulating joint. (Which SIDE each
## edge faces needs part orientation, which this slice deliberately does not
## model -- see the concept doc's Status list.)
func test_the_pivot_separates_the_scissors_into_two_halves_of_one_edge_each() -> void:
	var scissors: RefCounted = _scissors()
	var halves: Array = scissors.separates_into("pivot")
	assert_eq(halves.size(), 2, "one pivot, two opposed halves")
	for half in halves:
		var edges := 0
		for part_id in half:
			if scissors.part(part_id).geometry == ItemPart.GEOMETRY_EDGE:
				edges += 1
		assert_eq(edges, 1, "each half carries exactly one of the two opposed edges")


func test_the_scissors_pivot_turns_about_one_real_axis() -> void:
	var pivot: RefCounted = _scissors().joint("pivot")
	assert_eq(pivot.degrees_of_freedom(), 1)
	assert_almost_eq(pivot.motion_axis().length(), 1.0, 0.0001)


func test_both_scissor_blades_are_keen_edges_of_the_same_grind() -> void:
	var scissors: RefCounted = _scissors()
	assert_eq(scissors.parts_with_geometry(ItemPart.GEOMETRY_EDGE), ["blade_a", "blade_b"])
	assert_almost_eq(
		scissors.part("blade_a").keenness(), scissors.part("blade_b").keenness(), 0.0001
	)
	assert_gt(scissors.part("blade_a").keenness(), 0.0)


func test_the_scissors_mass_what_household_scissors_mass() -> void:
	# 50-90g for a pair of household scissors.
	assert_between(_scissors().total_mass_kg(), 0.04, 0.09)


## And they fail where scissors really fail: at the pivot. The pin is a
## 60%-efficiency fastening acting through the blades' thin section, so it
## carries less than either blade does.
func test_the_scissors_are_weakest_at_the_pivot() -> void:
	var weakest: Dictionary = _scissors().weakest_link()
	assert_eq(weakest["kind"], "joint")
	assert_eq(weakest["id"], "pivot")


# -- a photo frame: proof the grammar is not weapon-only -------------------
#
# Four mitred rails pinned into a closed rectangle, holding a photograph in the
# rebate. No edge, no point, no head, nothing to swing. Real dimensions for an
# 18x25cm frame: ~236g.

func _photo_frame() -> RefCounted:
	var graph: RefCounted = PartGraph.new()
	for rail in [["rail_top", 25.0], ["rail_bottom", 25.0],
			["rail_left", 18.0], ["rail_right", 18.0]]:
		graph.add_part(rail[0], ItemPart.new(
			"wood", ItemPart.GEOMETRY_FACE, ItemPart.ROLE_STRUCTURE,
			{"width_cm": rail[1], "height_cm": 3.0, "thickness_cm": 1.5}
		))
	# Paper is fibre. A 18x25cm print, 0.3mm thick.
	graph.add_part("photo", ItemPart.new(
		"fiber", ItemPart.GEOMETRY_FACE, ItemPart.ROLE_COVER,
		{"width_cm": 18.0, "height_cm": 25.0, "thickness_cm": 0.03}
	))
	# Mitred corners, pinned the way a frame really is V-nailed.
	for corner in [["tl", "rail_top", "rail_left"], ["tr", "rail_top", "rail_right"],
			["bl", "rail_bottom", "rail_left"], ["br", "rail_bottom", "rail_right"]]:
		graph.add_joint(PartJoint.new(
			corner[0], corner[1], corner[2],
			PartJoint.TYPE_RIGID, PartJoint.FASTENING_PIN, "wood"
		))
	# The photo sits in the rebate, held by nothing but the fit.
	graph.add_joint(_rigid("rebate_top", "rail_top", "photo", "wood"))
	graph.add_joint(_rigid("rebate_bottom", "rail_bottom", "photo", "wood"))
	return graph


func test_the_photo_frame_is_well_formed_and_whole() -> void:
	var frame: RefCounted = _photo_frame()
	assert_true(frame.is_well_formed(), str(frame.validation_errors()))
	assert_true(frame.is_one_assembly())


## The same vocabulary that built a sword builds a thing with no working end at
## all -- four structural members and something they display.
func test_the_photo_frame_is_four_structural_rails_holding_one_cover() -> void:
	var frame: RefCounted = _photo_frame()
	assert_eq(frame.parts_with_role(ItemPart.ROLE_STRUCTURE),
		["rail_top", "rail_bottom", "rail_left", "rail_right"])
	assert_eq(frame.parts_with_role(ItemPart.ROLE_COVER), ["photo"])
	assert_eq(frame.parts_with_role(ItemPart.ROLE_WORKING), [],
		"a picture frame has no business end")
	assert_eq(frame.parts_with_geometry(ItemPart.GEOMETRY_EDGE), [])


func test_the_photo_frame_is_a_rigid_body_like_the_sword_and_unlike_the_scissors() -> void:
	assert_true(_photo_frame().is_rigid_body())
	assert_eq(_photo_frame().articulating_joints(), [])


## A frame is a CLOSED loop -- more joints than a tree of these parts needs --
## and the shortest route between two opposite rails goes round one way, not
## the long way round the other.
func test_the_frame_is_a_closed_loop_and_paths_take_the_short_way_round() -> void:
	var frame: RefCounted = _photo_frame()
	assert_gt(frame.joint_ids().size(), frame.part_ids().size() - 1,
		"a closed frame has more joints than a tree would")
	assert_eq(frame.path_between("rail_left", "rail_right").size(), 3,
		"left rail -> a horizontal rail -> right rail")


## And because it is closed, letting one corner go does not drop a rail. That
## is what a frame IS, and no rule about frames had to be written for it.
func test_letting_one_mitred_corner_go_does_not_drop_a_rail() -> void:
	assert_eq(_photo_frame().separates_into("tl").size(), 1)


func test_the_photo_frame_masses_what_a_small_wooden_frame_masses() -> void:
	assert_between(_photo_frame().total_mass_kg(), 0.20, 0.35)


func test_the_photograph_is_the_least_of_the_frames_mass() -> void:
	var frame: RefCounted = _photo_frame()
	assert_lt(frame.part("photo").mass_kg(), frame.part("rail_left").mass_kg() * 0.1)
