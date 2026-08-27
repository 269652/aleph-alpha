extends GutTest

## The typed joint -- the primitive materials.md's implicitly-RIGID assembly
## model is missing, and the reason it can express a sword beautifully but
## cannot express a pair of scissors at all. See
## docs/concept/emergent_crafting.md.

var PartJoint: GDScript = preload("res://src/gameplay/part_joint.gd")
var MaterialProperties: GDScript = preload("res://src/gameplay/material_properties.gd")


func _joint(
	type: String = PartJoint.TYPE_RIGID,
	fastening: String = PartJoint.FASTENING_RIVET,
	material: String = "iron",
	axis: Vector3 = Vector3.ZERO
) -> RefCounted:
	return PartJoint.new("j", "a", "b", type, fastening, material, axis)


# -- serviceability: real joinery, derived rather than typed in ------------
#
# Two independently observable facts about undoing a fastening -- what it
# DESTROYS and what it TAKES -- each on a four-step real-world scale, combined
# into one 0..1 scalar. The three cases the design names by hand land exactly
# where they should: a lashing at 1.0, a drilled-out rivet in the middle, a
# forge weld at 0.0.

func test_a_lashing_is_fully_serviceable_because_untying_is_what_it_is_for() -> void:
	assert_almost_eq(PartJoint.serviceability_of(PartJoint.FASTENING_LASHING), 1.0, 0.0001)


func test_a_forge_weld_is_not_serviceable_at_all_because_it_is_one_metal_now() -> void:
	assert_almost_eq(PartJoint.serviceability_of(PartJoint.FASTENING_WELD), 0.0, 0.0001)


## Drilling a rivet out destroys the rivet AND reams the hole in a member
## oversize, and it needs a workshop process rather than a hand tool: (2, 2)
## of a possible (3, 3).
func test_a_rivet_sits_in_the_middle_because_drilling_it_out_costs_a_part() -> void:
	assert_almost_eq(PartJoint.serviceability_of(PartJoint.FASTENING_RIVET), 1.0 / 3.0, 0.0001)


func test_a_pin_gives_up_only_the_screwdriver_it_takes_to_pull_it() -> void:
	assert_almost_eq(PartJoint.serviceability_of(PartJoint.FASTENING_PIN), 5.0 / 6.0, 0.0001)


## A taper/friction fit is driven apart with a mallet and drift -- a hand tool
## -- but the wedge or the interference set that held it is gone: (1, 1).
func test_a_friction_fit_gives_up_the_set_that_held_it() -> void:
	assert_almost_eq(PartJoint.serviceability_of(PartJoint.FASTENING_FIT), 2.0 / 3.0, 0.0001)


## The scalar is a formula over the two scales, not five hand-picked numbers.
func test_serviceability_is_one_minus_the_share_of_the_two_cost_scales_spent() -> void:
	for fastening in PartJoint.FASTENINGS:
		var destroys: int = PartJoint.destroys_of(fastening)
		var effort: int = PartJoint.effort_of(fastening)
		var worst: float = float(PartJoint.DESTROYS_THE_ASSEMBLY + PartJoint.EFFORT_IMPOSSIBLE)
		assert_almost_eq(
			PartJoint.serviceability_of(fastening),
			1.0 - float(destroys + effort) / worst, 0.0001,
			"serviceability of '%s' must follow the formula, not a table" % fastening
		)


func test_serviceability_ranks_the_fastenings_the_way_a_workshop_would() -> void:
	var ordered: Array[String] = [
		PartJoint.FASTENING_LASHING, PartJoint.FASTENING_PIN, PartJoint.FASTENING_FIT,
		PartJoint.FASTENING_RIVET, PartJoint.FASTENING_WELD,
	]
	for i in range(ordered.size() - 1):
		assert_gt(
			PartJoint.serviceability_of(ordered[i]),
			PartJoint.serviceability_of(ordered[i + 1]),
			"'%s' must come apart more readily than '%s'" % [ordered[i], ordered[i + 1]]
		)


## What a later disassembly-risk layer actually asks: do I lose a part doing
## this? A lashing and a pin cost nothing; a fit costs only the wedge; a rivet
## and a weld cost a member.
func test_only_a_rivet_and_a_weld_cost_you_a_joined_part() -> void:
	assert_false(PartJoint.costs_a_part(PartJoint.FASTENING_LASHING))
	assert_false(PartJoint.costs_a_part(PartJoint.FASTENING_PIN))
	assert_false(PartJoint.costs_a_part(PartJoint.FASTENING_FIT))
	assert_true(PartJoint.costs_a_part(PartJoint.FASTENING_RIVET))
	assert_true(PartJoint.costs_a_part(PartJoint.FASTENING_WELD))


func test_a_joint_reports_the_serviceability_of_its_own_fastening() -> void:
	assert_almost_eq(
		_joint(PartJoint.TYPE_RIGID, PartJoint.FASTENING_LASHING, "fiber").serviceability(),
		1.0, 0.0001
	)


# -- strength: joint efficiency, the real engineering quantity -------------
#
# Joint efficiency is the fraction of the SOLID parent section's strength a
# connection retains -- the same quantity boiler and ship design has computed
# for riveted joints for a century. Each fastening's number is the midpoint of
# a real published band (see part_joint.gd for the band and its grounding), so
# the value is derived from the band rather than picked.

func test_a_sound_weld_retains_the_full_strength_of_the_parent_metal() -> void:
	assert_almost_eq(PartJoint.efficiency_of(PartJoint.FASTENING_WELD), 1.0, 0.0001)


func test_every_efficiency_is_the_midpoint_of_its_real_world_band() -> void:
	for fastening in PartJoint.FASTENINGS:
		var band: Array = PartJoint.efficiency_band_of(fastening)
		assert_almost_eq(
			PartJoint.efficiency_of(fastening),
			(float(band[0]) + float(band[1])) * 0.5, 0.0001,
			"'%s' efficiency must be the midpoint of its band" % fastening
		)
		assert_true(float(band[0]) <= float(band[1]), "band for '%s' must be ordered" % fastening)


func test_a_riveted_joint_lands_in_the_classic_boiler_practice_band() -> void:
	# 60-80% of the solid plate is the textbook range for a double-riveted
	# lap/butt joint; the midpoint is 0.70.
	assert_almost_eq(PartJoint.efficiency_of(PartJoint.FASTENING_RIVET), 0.70, 0.0001)


func test_a_lashing_is_the_weakest_connection_in_the_vocabulary() -> void:
	for fastening in PartJoint.FASTENINGS:
		if fastening == PartJoint.FASTENING_LASHING:
			continue
		assert_gt(
			PartJoint.efficiency_of(fastening),
			PartJoint.efficiency_of(PartJoint.FASTENING_LASHING),
			"a cord lashing carries load only in friction -- '%s' beats it" % fastening
		)


## The trade-off the whole vocabulary exists to express: the fastening you can
## always undo is the one that carries least, and the one that carries the
## parent metal's full load is the one you are never undoing. A smith picks a
## point on this line at build time.
func test_the_most_serviceable_fastening_is_the_weakest_and_the_least_is_the_strongest() -> void:
	var most_serviceable: String = PartJoint.FASTENINGS[0]
	var least_serviceable: String = PartJoint.FASTENINGS[0]
	var weakest: String = PartJoint.FASTENINGS[0]
	var strongest: String = PartJoint.FASTENINGS[0]
	for fastening in PartJoint.FASTENINGS:
		if PartJoint.serviceability_of(fastening) > PartJoint.serviceability_of(most_serviceable):
			most_serviceable = fastening
		if PartJoint.serviceability_of(fastening) < PartJoint.serviceability_of(least_serviceable):
			least_serviceable = fastening
		if PartJoint.efficiency_of(fastening) < PartJoint.efficiency_of(weakest):
			weakest = fastening
		if PartJoint.efficiency_of(fastening) > PartJoint.efficiency_of(strongest):
			strongest = fastening
	assert_eq(most_serviceable, weakest, "the fastening you can always undo carries least")
	assert_eq(least_serviceable, strongest, "the permanent one carries the parent load")


## No fastening wins on both axes -- otherwise the choice would not be a choice.
func test_no_fastening_is_best_at_both_coming_apart_and_holding_together() -> void:
	for fastening in PartJoint.FASTENINGS:
		var best_service := true
		var best_strength := true
		for other in PartJoint.FASTENINGS:
			if PartJoint.serviceability_of(other) > PartJoint.serviceability_of(fastening):
				best_service = false
			if PartJoint.efficiency_of(other) > PartJoint.efficiency_of(fastening):
				best_strength = false
		assert_false(
			best_service and best_strength,
			"'%s' would be a strictly dominant choice" % fastening
		)


## A joint's load capacity is efficiency x the material's strength x the
## section it acts through. Toughness stands in for tensile strength -- the
## precedent MaterialProperties.ROPE_MIN_TOUGHNESS's own doc comment already
## sets, since the 8-scalar vector has no separate tensile scalar.
func test_load_capacity_is_efficiency_times_material_strength_times_section() -> void:
	var mp: RefCounted = MaterialProperties.new()
	var rivet: RefCounted = _joint(PartJoint.TYPE_RIGID, PartJoint.FASTENING_RIVET, "iron")
	assert_almost_eq(
		rivet.load_capacity(3.0),
		0.70 * mp.property_value("iron", "toughness") * 3.0, 0.0001
	)


func test_a_bigger_section_carries_more_load() -> void:
	var rivet: RefCounted = _joint()
	assert_gt(rivet.load_capacity(6.0), rivet.load_capacity(3.0))


## The joint's OWN material governs, not the members' -- the pin in a pinned
## joint and the cord in a lashing are what fail, which is why a wooden
## treenail through two iron plates is still a wood-strength connection.
func test_the_joints_own_material_governs_its_capacity() -> void:
	var iron_pin: RefCounted = _joint(PartJoint.TYPE_RIGID, PartJoint.FASTENING_PIN, "iron")
	var treenail: RefCounted = _joint(PartJoint.TYPE_RIGID, PartJoint.FASTENING_PIN, "wood")
	assert_gt(iron_pin.load_capacity(2.0), treenail.load_capacity(2.0),
		"iron's toughness 7 beats wood's 6 at the same fastening and section")


func test_an_invalid_joint_carries_no_load_rather_than_crashing() -> void:
	var bad: RefCounted = _joint("wobble")
	assert_false(bad.is_valid())
	assert_almost_eq(bad.load_capacity(5.0), 0.0, 0.0001)


# -- kinematics: what actually distinguishes a sword from scissors ---------

func test_only_a_rigid_joint_transmits_force_without_relative_motion() -> void:
	assert_true(_joint(PartJoint.TYPE_RIGID).transmits_rigidly())
	assert_false(_joint(PartJoint.TYPE_PIVOT, PartJoint.FASTENING_PIN, "iron", Vector3.UP)
		.transmits_rigidly())
	assert_false(_joint(PartJoint.TYPE_SLIDING, PartJoint.FASTENING_FIT, "iron", Vector3.RIGHT)
		.transmits_rigidly())
	assert_false(_joint(PartJoint.TYPE_SPRUNG, PartJoint.FASTENING_LASHING, "fiber")
		.transmits_rigidly())
	assert_false(_joint(PartJoint.TYPE_SOCKET, PartJoint.FASTENING_FIT).transmits_rigidly())


func test_permits_motion_is_exactly_the_opposite_of_transmitting_rigidly() -> void:
	for type in PartJoint.TYPES:
		var axis := Vector3.UP if type in [PartJoint.TYPE_PIVOT, PartJoint.TYPE_SLIDING] \
			else Vector3.ZERO
		var joint: RefCounted = _joint(type, PartJoint.FASTENING_PIN, "iron", axis)
		assert_ne(joint.transmits_rigidly(), joint.permits_motion(),
			"'%s' cannot both hold rigidly and permit motion" % type)


func test_each_type_permits_the_degrees_of_freedom_its_mechanism_really_has() -> void:
	assert_eq(_joint(PartJoint.TYPE_RIGID).degrees_of_freedom(), 0)
	assert_eq(_joint(PartJoint.TYPE_PIVOT, PartJoint.FASTENING_PIN, "iron", Vector3.UP)
		.degrees_of_freedom(), 1)
	assert_eq(_joint(PartJoint.TYPE_SLIDING, PartJoint.FASTENING_FIT, "iron", Vector3.RIGHT)
		.degrees_of_freedom(), 1)
	assert_eq(_joint(PartJoint.TYPE_SPRUNG, PartJoint.FASTENING_LASHING, "fiber")
		.degrees_of_freedom(), 1)
	# A ball in a socket turns about all three axes -- that is what makes it a
	# socket rather than a hinge.
	assert_eq(_joint(PartJoint.TYPE_SOCKET, PartJoint.FASTENING_FIT).degrees_of_freedom(), 3)


func test_each_type_names_the_kind_of_motion_it_permits() -> void:
	assert_eq(_joint(PartJoint.TYPE_RIGID).motion_kind(), PartJoint.MOTION_NONE)
	assert_eq(_joint(PartJoint.TYPE_PIVOT, PartJoint.FASTENING_PIN, "iron", Vector3.UP)
		.motion_kind(), PartJoint.MOTION_ROTATION)
	assert_eq(_joint(PartJoint.TYPE_SLIDING, PartJoint.FASTENING_FIT, "iron", Vector3.RIGHT)
		.motion_kind(), PartJoint.MOTION_TRANSLATION)
	assert_eq(_joint(PartJoint.TYPE_SPRUNG, PartJoint.FASTENING_LASHING, "fiber")
		.motion_kind(), PartJoint.MOTION_FLEX)
	assert_eq(_joint(PartJoint.TYPE_SOCKET, PartJoint.FASTENING_FIT).motion_kind(),
		PartJoint.MOTION_ROTATION)


## A pivot turns about ONE axis and a slider runs along ONE direction, so both
## report a real unit vector. A socket has no constrained axis at all, and a
## rigid joint has no motion to have an axis for.
func test_a_pivot_reports_its_rotation_axis_as_a_unit_vector() -> void:
	var pivot: RefCounted = PartJoint.new(
		"j", "a", "b", PartJoint.TYPE_PIVOT, PartJoint.FASTENING_PIN, "iron",
		Vector3(0.0, 7.0, 0.0)
	)
	assert_almost_eq(pivot.motion_axis().length(), 1.0, 0.0001)
	assert_almost_eq(pivot.motion_axis().dot(Vector3.UP), 1.0, 0.0001)


func test_a_rigid_joint_and_a_socket_have_no_single_motion_axis() -> void:
	assert_eq(_joint(PartJoint.TYPE_RIGID).motion_axis(), Vector3.ZERO)
	assert_eq(_joint(PartJoint.TYPE_SOCKET, PartJoint.FASTENING_FIT).motion_axis(),
		Vector3.ZERO, "a ball in a socket turns about every axis, so it has no one axis")


## The bow limb: a joint that moves AND returns, storing the energy you put in.
func test_only_a_sprung_joint_stores_and_returns_energy() -> void:
	assert_true(_joint(PartJoint.TYPE_SPRUNG, PartJoint.FASTENING_LASHING, "fiber")
		.stores_energy())
	assert_false(_joint(PartJoint.TYPE_PIVOT, PartJoint.FASTENING_PIN, "iron", Vector3.UP)
		.stores_energy())
	assert_false(_joint(PartJoint.TYPE_RIGID).stores_energy())


# -- the vocabulary decision: "lashed" is a FASTENING, not a kinematic type -
#
# The design brief listed LASHED alongside RIGID as a joint type. It is split
# out here because "lashed" answers a serviceability question and not a
# kinematics one: a lashing holds two parts still relative to each other
# exactly as a rivet does. Keeping it as a type would allow a joint that is
# both LASHED and RIVET-fastened, two fields saying different things about one
# fact. See part_joint.gd's own doc comment.

func test_a_lashed_joint_is_rigid_kinematics_plus_a_lashing_fastening() -> void:
	var lashed: RefCounted = _joint(PartJoint.TYPE_RIGID, PartJoint.FASTENING_LASHING, "fiber")
	assert_true(lashed.is_valid())
	assert_true(lashed.transmits_rigidly(), "a lashing holds two parts still, like a rivet")
	assert_almost_eq(lashed.serviceability(), 1.0, 0.0001, "...but comes apart, unlike a rivet")


## And the payoff of the split: a lashing can equally hold a joint that MOVES.
## A lashed flail head really does swing on its lashing.
func test_a_lashing_can_also_hold_a_joint_that_moves() -> void:
	var flail: RefCounted = PartJoint.new(
		"j", "haft", "head", PartJoint.TYPE_PIVOT, PartJoint.FASTENING_LASHING,
		"fiber", Vector3.UP
	)
	assert_true(flail.is_valid())
	assert_true(flail.permits_motion())


# -- malformed joints are rejected explicitly -----------------------------

func test_a_well_formed_joint_is_valid_and_has_no_error() -> void:
	assert_true(_joint().is_valid())
	assert_eq(_joint().validation_error(), "")


func test_an_unknown_type_is_rejected_and_says_so() -> void:
	var bad: RefCounted = _joint("wobble")
	assert_false(bad.is_valid())
	assert_string_contains(bad.validation_error(), "wobble")


func test_an_unknown_fastening_is_rejected_and_says_so() -> void:
	var bad: RefCounted = _joint(PartJoint.TYPE_RIGID, "sellotape")
	assert_false(bad.is_valid())
	assert_string_contains(bad.validation_error(), "sellotape")


func test_an_unmodeled_joint_material_is_rejected() -> void:
	var bad: RefCounted = _joint(PartJoint.TYPE_RIGID, PartJoint.FASTENING_RIVET, "unobtainium")
	assert_false(bad.is_valid())
	assert_string_contains(bad.validation_error(), "unobtainium")


func test_a_joint_from_a_part_to_itself_joins_nothing_and_is_rejected() -> void:
	var bad: RefCounted = PartJoint.new(
		"j", "blade", "blade", PartJoint.TYPE_RIGID, PartJoint.FASTENING_RIVET, "iron"
	)
	assert_false(bad.is_valid())
	assert_string_contains(bad.validation_error(), "blade")


func test_a_joint_needs_an_id_and_two_named_ends() -> void:
	assert_false(PartJoint.new(
		"", "a", "b", PartJoint.TYPE_RIGID, PartJoint.FASTENING_RIVET, "iron"
	).is_valid())
	assert_false(PartJoint.new(
		"j", "", "b", PartJoint.TYPE_RIGID, PartJoint.FASTENING_RIVET, "iron"
	).is_valid())


## The one cross-rule between the two vocabularies, and it is physically
## undeniable: a forge weld is a metallurgical bond that has made the two parts
## one piece of metal. There is nothing left to pivot about.
func test_a_forge_weld_cannot_hold_a_joint_that_moves() -> void:
	for type in [PartJoint.TYPE_PIVOT, PartJoint.TYPE_SLIDING,
			PartJoint.TYPE_SPRUNG, PartJoint.TYPE_SOCKET]:
		var bad: RefCounted = _joint(type, PartJoint.FASTENING_WELD, "iron", Vector3.UP)
		assert_false(bad.is_valid(), "a welded '%s' is not a thing" % type)
		assert_string_contains(bad.validation_error(), "weld")


func test_a_forge_weld_is_fine_on_a_rigid_joint() -> void:
	assert_true(_joint(PartJoint.TYPE_RIGID, PartJoint.FASTENING_WELD, "iron").is_valid())


## A pivot with no axis is not a pivot -- it has not said what it turns about.
func test_a_pivot_or_slider_without_an_axis_is_rejected() -> void:
	var pivot: RefCounted = _joint(PartJoint.TYPE_PIVOT, PartJoint.FASTENING_PIN, "iron",
		Vector3.ZERO)
	assert_false(pivot.is_valid())
	assert_string_contains(pivot.validation_error(), "axis")
	var slider: RefCounted = _joint(PartJoint.TYPE_SLIDING, PartJoint.FASTENING_FIT, "iron",
		Vector3.ZERO)
	assert_false(slider.is_valid())


# -- endpoint queries the graph leans on ----------------------------------

func test_a_joint_knows_which_parts_it_touches() -> void:
	var joint: RefCounted = _joint()
	assert_true(joint.connects("a"))
	assert_true(joint.connects("b"))
	assert_false(joint.connects("c"))


func test_a_joint_can_name_the_part_at_its_other_end() -> void:
	var joint: RefCounted = _joint()
	assert_eq(joint.other_end("a"), "b")
	assert_eq(joint.other_end("b"), "a")
	assert_eq(joint.other_end("c"), "", "a part it does not touch has no other end")
