extends GutTest

## The swing physics over a part graph -- docs/concept/emergent_crafting.md.
##
## The anchor test is test_there_is_an_optimum_head_mass_for_delivered_momentum.
## If the model were monotonic in mass it would be a stat table wearing a physics
## costume, and that test is what says so.

var PartMechanics: GDScript = preload("res://src/gameplay/part_mechanics.gd")
var PartGraph: GDScript = preload("res://src/gameplay/part_graph.gd")
var ItemPart: GDScript = preload("res://src/gameplay/item_part.gd")
var PartJoint: GDScript = preload("res://src/gameplay/part_joint.gd")
var ImpactResolver: GDScript = preload("res://src/gameplay/impact_resolver.gd")
var Assemblies: GDScript = preload("res://tests/fixtures/assembly_fixtures.gd")


## The calibration fixture: a hammer with a 33cm hickory haft and an iron head
## of the given diameter. THE reference geometry the actor's swing torque is
## solved for -- see PartMechanics.SWING_TORQUE_NM_AT_UNIT_STRENGTH.
func _hammer(head_diameter_cm: float) -> RefCounted:
	var graph: RefCounted = PartGraph.new()
	graph.add_part("haft", ItemPart.new(
		"wood", ItemPart.GEOMETRY_HAFT, ItemPart.ROLE_GRIP,
		{"length_cm": 33.0, "diameter_cm": 3.2}
	))
	graph.add_part("head", ItemPart.new(
		"iron", ItemPart.GEOMETRY_BULK, ItemPart.ROLE_WORKING,
		{"diameter_cm": head_diameter_cm}
	))
	graph.add_joint(PartJoint.new(
		"eye", "haft", "head", PartJoint.TYPE_RIGID, PartJoint.FASTENING_FIT, "wood"
	))
	return graph


## The diameter an iron sphere needs to mass `kg`, so the sweep below is a sweep
## over real HEAD MASS rather than over a diameter that only stands in for it.
func _iron_sphere_diameter_cm(kg: float) -> float:
	var volume_cm3 := kg * 1000.0 / 7.8
	return pow(6.0 * volume_cm3 / PI, 1.0 / 3.0)


# -- THE ANCHOR TEST -------------------------------------------------------
#
# A swung implement is a rotating rigid body: angular acceleration is
# torque/inertia, and the torque a human has left to accelerate it is what
# remains after holding it up. Too light and there is no mass to carry momentum;
# too heavy and the static hold eats the whole torque budget and it barely moves.
# So delivered momentum must RISE and then FALL, with the maximum strictly
# inside the sweep.

func test_there_is_an_optimum_head_mass_for_delivered_momentum() -> void:
	var masses: Array[float] = []
	var mass_kg := 0.2
	while mass_kg <= 12.001:
		masses.append(mass_kg)
		mass_kg += 0.2
	var momenta: Array[float] = []
	for head_mass in masses:
		momenta.append(PartMechanics.delivered_momentum(
			_hammer(_iron_sphere_diameter_cm(head_mass)), 1.0
		))

	var best := 0
	for i in range(momenta.size()):
		if momenta[i] > momenta[best]:
			best = i
	assert_gt(best, 0, "the optimum must not be the lightest head in the sweep")
	assert_lt(best, momenta.size() - 1,
		"the optimum must not be the heaviest head in the sweep")

	# Unimodal, not merely peaked somewhere: strictly rising up to the optimum,
	# never rising again after it. (Past the stall it is flat at zero -- the
	# actor cannot swing it at all -- so the falling half is asserted as
	# non-increasing plus a strict drop across the whole tail.)
	for i in range(1, best + 1):
		assert_gt(momenta[i], momenta[i - 1],
			"momentum must still be rising at %.1f kg" % masses[i])
	for i in range(best + 1, momenta.size()):
		assert_lte(momenta[i], momenta[i - 1],
			"momentum must never rise again past the optimum, at %.1f kg" % masses[i])
	assert_lt(momenta[momenta.size() - 1], momenta[best],
		"the heaviest head must deliver strictly less than the optimum")


## The heavy end is not an asymptote, it is a WALL: past a real mass the whole
## torque budget goes on holding the thing out and there is nothing left to
## accelerate with. That is the mechanism the optimum above exists because of,
## asserted on its own so it cannot quietly become a soft curve.
func test_a_head_too_heavy_to_hold_out_cannot_be_swung_at_all() -> void:
	var stalled: RefCounted = _hammer(_iron_sphere_diameter_cm(12.0))
	assert_eq(PartMechanics.net_swing_torque_nm(stalled, "haft", 1.0), 0.0)
	assert_eq(PartMechanics.delivered_momentum(stalled, 1.0), 0.0)
	assert_eq(PartMechanics.swing_time_s(stalled, 1.0), INF,
		"a swing that never happens takes no time, it takes forever")


# -- the calibration anchor ------------------------------------------------
#
# One free constant in the whole model (the torque an actor delivers about the
# grip) and one measurement to fix it against: a one-handed framing hammer's
# striking face arrives at about 10 m/s. The reference hammer is a 33cm haft
# and a 5.3cm iron head -- 608 g, a 21oz framing head, the geometry a century
# of carpentry converged on.

const REFERENCE_HAMMER_HEAD_CM := 5.3


func _reference_hammer() -> RefCounted:
	return _hammer(REFERENCE_HAMMER_HEAD_CM)


func test_the_reference_hammer_is_a_real_framing_hammer() -> void:
	var hammer: RefCounted = _reference_hammer()
	assert_true(hammer.is_well_formed(), str(hammer.validation_errors()))
	# A 21oz framing head is ~0.6 kg; a whole framing hammer runs 700-900 g.
	assert_almost_eq(hammer.part("head").mass_kg(), 0.608, 0.01)
	assert_between(hammer.total_mass_kg(), 0.70, 0.90)


func test_the_reference_hammer_face_arrives_at_the_measured_framing_speed() -> void:
	var hammer: RefCounted = _reference_hammer()
	var face_speed: float = PartMechanics.swing_speed_rad_s(hammer, "haft", 1.0) \
		* PartMechanics.reach_cm(hammer, "haft") / 100.0
	assert_almost_eq(face_speed, PartMechanics.FRAMING_HAMMER_FACE_SPEED_MS, 0.01)


## The constant is the anchor SOLVED FOR, not a number that happens to work:
## re-derive it here from the same fixture and the same measurement, and it must
## come back to what the file ships.
func test_the_swing_torque_constant_is_the_framing_hammer_anchor_solved_for_torque() -> void:
	var hammer: RefCounted = _reference_hammer()
	var inertia: float = PartMechanics.moment_of_inertia(hammer, "haft")
	var reach_m: float = PartMechanics.reach_cm(hammer, "haft") / 100.0
	var required_omega: float = PartMechanics.FRAMING_HAMMER_FACE_SPEED_MS / reach_m
	var accelerating_torque: float = inertia * required_omega * required_omega \
		/ (2.0 * PartMechanics.SWING_ARC_RAD)
	var solved: float = accelerating_torque + PartMechanics.gravity_torque_nm(hammer, "haft")
	assert_almost_eq(solved, PartMechanics.SWING_TORQUE_NM_AT_UNIT_STRENGTH, 0.001)


## A consequence nobody put in, and the reason the constant scales with an
## actor at all: the stronger you are, the further out the stall wall moves, so
## the heaviest head still worth swinging gets heavier.
func test_a_stronger_actor_has_a_heavier_optimum_head() -> void:
	assert_gt(_optimum_head_mass_kg(1.6), _optimum_head_mass_kg(1.0))


func _optimum_head_mass_kg(actor_strength: float) -> float:
	var best_mass := 0.0
	var best_momentum := -1.0
	var mass_kg := 0.2
	while mass_kg <= 20.001:
		var momentum: float = PartMechanics.delivered_momentum(
			_hammer(_iron_sphere_diameter_cm(mass_kg)), actor_strength
		)
		if momentum > best_momentum:
			best_momentum = momentum
			best_mass = mass_kg
		mass_kg += 0.2
	return best_mass


# -- the pommel ------------------------------------------------------------
#
# Two facts about the same lump of iron, and the second one is why swords have
# them.

## Mass near the hand costs inertia; mass at the tip costs it as the SQUARE of
## the distance. Same sword, same total mass, one lump of iron in two places.
func test_a_pommel_lowers_moment_of_inertia_at_equal_total_mass() -> void:
	var at_the_grip: RefCounted = _sword_with_extra_bulk_on("grip")
	var at_the_tip: RefCounted = _sword_with_extra_bulk_on("blade")
	assert_almost_eq(at_the_grip.total_mass_kg(), at_the_tip.total_mass_kg(), 0.0001,
		"the two swords must differ only in WHERE the iron is")
	assert_lt(
		PartMechanics.moment_of_inertia(at_the_grip, "grip"),
		PartMechanics.moment_of_inertia(at_the_tip, "grip")
	)


## The counter-intuitive one, and the proof this is physics rather than a stat
## table: take the pommel OFF and the sword gets 27% lighter and SLOWER.
##
## The mechanism is not the one you would guess. The moment of inertia about the
## hand barely moves (the pommel sits close to the grip, so it was never
## contributing much of it). What changes is the BALANCE POINT: without the
## counterweight it runs away down the blade, and the gravity torque -- the
## static cost of just holding the thing out -- goes UP even though there is
## less sword to hold. That eats the torque budget, and what is left accelerates
## an almost unchanged inertia more slowly.
func test_removing_the_pommel_makes_the_sword_slower_even_though_it_gets_lighter() -> void:
	var sword: RefCounted = Assemblies.sword()
	var stripped: RefCounted = Assemblies.sword_without_pommel()

	assert_lt(stripped.total_mass_kg(), sword.total_mass_kg(),
		"taking the pommel off must genuinely remove mass")
	assert_gt(
		absf(PartMechanics.balance_point_cm(stripped, "grip")),
		absf(PartMechanics.balance_point_cm(sword, "grip")),
		"without its counterweight the balance point runs down the blade"
	)
	assert_gt(
		PartMechanics.gravity_torque_nm(stripped, "grip"),
		PartMechanics.gravity_torque_nm(sword, "grip"),
		"a LIGHTER sword that is harder to hold out -- that is the pommel's job"
	)
	assert_gt(
		PartMechanics.swing_time_s(stripped, 1.0),
		PartMechanics.swing_time_s(sword, 1.0),
		"and so the lighter sword is the slower one"
	)


func _sword_with_extra_bulk_on(attach_to: String) -> RefCounted:
	var graph: RefCounted = Assemblies.sword_without_pommel()
	graph.add_part("extra", ItemPart.new(
		"iron", ItemPart.GEOMETRY_BULK, ItemPart.ROLE_COUNTERWEIGHT, {"diameter_cm": 4.5}
	))
	graph.add_joint(PartJoint.new(
		"extra_joint", attach_to, "extra", PartJoint.TYPE_RIGID,
		PartJoint.FASTENING_RIVET, "iron"
	))
	return graph


# -- honesty about the inertia model ---------------------------------------

## moment_of_inertia adds each part's own moment about its own centre using the
## slender-rod result rather than a per-geometry inertia tensor. This is the
## test that says how much that simplification can possibly be worth: the
## parallel-axis (m d^2) terms dominate it several times over, so refining the
## own-moment terms could only ever move the answer by a fraction of a fraction.
## It is NOT negligible, though -- an 80cm blade is a long rod -- which is why
## the own moment is summed at all rather than dropped.
func test_the_parallel_axis_term_dominates_the_own_moment_term() -> void:
	var sword: RefCounted = Assemblies.sword()
	var parallel_axis := 0.0
	for part_id in sword.part_ids():
		var arm_m: float = PartMechanics.offset_cm(sword, "grip", part_id) / 100.0
		parallel_axis += sword.part(part_id).mass_kg() * arm_m * arm_m
	var own_moment: float = PartMechanics.moment_of_inertia(sword, "grip") - parallel_axis
	assert_gt(own_moment, 0.0, "the own-moment terms are real and are summed")
	assert_gt(parallel_axis, 5.0 * own_moment,
		"but where the mass sits dominates what shape each lump is")


# -- does the model produce a real sword? ----------------------------------
#
# Two independent falsifiable checks the calibration was NOT fitted to. The
# torque constant came from a hammer; if the same constant also produces a
# plausible sword, that is evidence rather than arithmetic.

## A sword cut takes about a quarter of a second. Nothing here was tuned to make
## that true -- it falls out of an 80cm blade's inertia against a torque budget
## solved for on a hammer.
func test_the_arming_sword_swings_in_the_time_a_real_sword_cut_takes() -> void:
	assert_between(PartMechanics.swing_time_s(Assemblies.sword(), 1.0), 0.15, 0.50)


## And it arrives hard enough to cut, against the threshold the impact model
## already ships. Reads ImpactResolver's own symbol, never a copy of 3.0.
func test_the_arming_sword_arrives_above_the_shipped_cut_threshold() -> void:
	assert_gt(
		PartMechanics.delivered_momentum(Assemblies.sword(), 1.0),
		ImpactResolver.T_CUT
	)
