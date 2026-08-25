extends GutTest

## The PoE-style passive web (docs/concept/skills.md): seven archetype wedges
## around a shared centre, joined only by gateway nodes, allocated by walking
## outward from your class's start node.

const SkillWeb = preload("res://src/gameplay/skill_web.gd")
const ClassArchetype = preload("res://src/gameplay/class_archetype.gd")

var web: SkillWeb


func before_each():
	web = SkillWeb.new()


# --- topology -------------------------------------------------------------

## WEDGE_SPAN/wedge_angle divide the circle by a declared WEDGE_COUNT rather
## than by ClassArchetype's live table (a const cannot call into it), so the two
## have to be pinned as agreeing or the layout silently drifts from the roster.
func test_the_layout_declares_one_wedge_per_archetype_the_class_table_holds():
	assert_eq(ClassArchetype.new().archetype_names().size(), SkillWeb.WEDGE_COUNT)


func test_every_archetype_has_exactly_one_start_node():
	for archetype in ClassArchetype.new().archetype_names():
		var start := web.start_node_for(archetype)
		assert_ne(start, "", "archetype %s has no start node" % archetype)
		assert_eq(web.node_info(start)["ring"], 0)
		assert_eq(web.node_info(start)["archetype"], archetype)


func test_start_nodes_are_distinct_per_archetype():
	var seen := {}
	for archetype in ClassArchetype.new().archetype_names():
		var start := web.start_node_for(archetype)
		assert_false(seen.has(start), "two archetypes share start node %s" % start)
		seen[start] = true


func test_unknown_archetype_has_no_start_node():
	assert_eq(web.start_node_for("necromancer"), "")


func test_every_node_belongs_to_a_known_archetype_or_is_a_gateway():
	var archetypes := ClassArchetype.new().archetype_names()
	for node_id in web.node_ids():
		var archetype: String = web.node_info(node_id)["archetype"]
		if archetype == "":
			assert_eq(web.node_info(node_id)["kind"], SkillWeb.KIND_GATEWAY,
				"%s has no archetype but is not a gateway" % node_id)
		else:
			assert_true(archetypes.has(archetype), "%s has unknown archetype %s" % [node_id, archetype])


func test_there_is_one_gateway_between_each_adjacent_pair_of_wedges():
	var gateways := []
	for node_id in web.node_ids():
		if web.node_info(node_id)["kind"] == SkillWeb.KIND_GATEWAY:
			gateways.append(node_id)
	assert_eq(gateways.size(), ClassArchetype.new().archetype_names().size())


func test_every_wedge_holds_the_same_number_of_nodes():
	var counts := {}
	for node_id in web.node_ids():
		var archetype: String = web.node_info(node_id)["archetype"]
		if archetype == "":
			continue
		counts[archetype] = int(counts.get(archetype, 0)) + 1
	var sizes := {}
	for archetype in counts:
		sizes[counts[archetype]] = true
	assert_eq(sizes.size(), 1, "wedges differ in size: %s" % [counts])


func test_no_two_nodes_share_a_position():
	var seen := {}
	for node_id in web.node_ids():
		var key := str(web.position_of(node_id).snapped(Vector2(0.001, 0.001)))
		assert_false(seen.has(key),
			"%s and %s occupy the same position %s" % [node_id, seen.get(key, ""), key])
		seen[key] = node_id


func test_radius_grows_strictly_with_ring_inside_a_wedge():
	var start := web.start_node_for("warrior")
	var previous := web.position_of(start).length()
	for ring in range(1, SkillWeb.OUTER_RING + 1):
		var ring_radius := -1.0
		for node_id in web.nodes_in_ring("warrior", ring):
			var radius := web.position_of(node_id).length()
			if ring_radius < 0.0:
				ring_radius = radius
			assert_almost_eq(radius, ring_radius, 0.001, "ring %d is not a real ring" % ring)
		assert_gt(ring_radius, previous, "ring %d is not further out than ring %d" % [ring, ring - 1])
		previous = ring_radius


func test_a_wedges_nodes_all_sit_inside_its_own_angular_span():
	var archetypes := ClassArchetype.new().archetype_names()
	for i in archetypes.size():
		var centre := web.wedge_angle(i)
		for node_id in web.node_ids():
			if web.node_info(node_id)["archetype"] != archetypes[i]:
				continue
			var angle := web.position_of(node_id).angle()
			var offset: float = absf(angle_difference(angle, centre))
			assert_lte(offset, SkillWeb.WEDGE_SPAN * 0.5 + 0.001,
				"%s sits outside its own wedge" % node_id)


# --- connectivity ---------------------------------------------------------

func test_every_node_is_reachable_from_every_start_node():
	for archetype in ClassArchetype.new().archetype_names():
		var reached := _flood_from(web.start_node_for(archetype))
		assert_eq(reached.size(), web.node_ids().size(),
			"web is not fully connected from the %s start" % archetype)


func test_edges_are_symmetric():
	for node_id in web.node_ids():
		for neighbour in web.neighbors(node_id):
			assert_true(web.neighbors(neighbour).has(node_id),
				"%s -> %s is a one-way edge" % [node_id, neighbour])


func test_the_only_cross_wedge_edges_run_through_gateways():
	for node_id in web.node_ids():
		var here: String = web.node_info(node_id)["archetype"]
		if here == "":
			continue
		for neighbour in web.neighbors(node_id):
			var there: String = web.node_info(neighbour)["archetype"]
			if there == here:
				continue
			assert_eq(web.node_info(neighbour)["kind"], SkillWeb.KIND_GATEWAY,
				"%s reaches %s in another wedge without a gateway" % [node_id, neighbour])


func test_neighbors_of_an_unknown_node_is_empty():
	assert_eq(web.neighbors("not_a_node"), [])


func _flood_from(start_id: String) -> Dictionary:
	var reached := {start_id: true}
	var frontier := [start_id]
	while not frontier.is_empty():
		var current: String = frontier.pop_back()
		for neighbour in web.neighbors(current):
			if reached.has(neighbour):
				continue
			reached[neighbour] = true
			frontier.append(neighbour)
	return reached


# --- allocation -----------------------------------------------------------

func test_your_own_start_node_is_allocable_from_an_empty_web():
	assert_true(web.can_allocate(web.start_node_for("mage"), {}, 99, "mage", {}))


func test_another_archetypes_start_node_is_not_allocable_from_an_empty_web():
	assert_false(web.can_allocate(web.start_node_for("warrior"), {}, 99, "mage", {}))


func test_a_node_two_steps_out_is_not_allocable_before_the_step_between_it():
	var start := web.start_node_for("mage")
	var ring_two: String = web.nodes_in_ring("mage", 2)[0]
	assert_false(web.can_allocate(ring_two, {start: true}, 99, "mage", {}))


func test_a_node_becomes_allocable_once_a_neighbour_is_allocated():
	var start := web.start_node_for("mage")
	var ring_one: String = web.nodes_in_ring("mage", 1)[0]
	assert_true(web.can_allocate(ring_one, {start: true}, 99, "mage", {}))


func test_an_already_allocated_node_is_not_allocable_again():
	var start := web.start_node_for("mage")
	assert_false(web.can_allocate(start, {start: true}, 99, "mage", {}))


func test_an_unaffordable_node_is_not_allocable():
	assert_false(web.can_allocate(web.start_node_for("mage"), {}, 0, "mage", {}))


func test_an_unknown_node_is_not_allocable():
	assert_false(web.can_allocate("not_a_node", {}, 99, "mage", {}))


func test_allocate_returns_a_new_dictionary_without_mutating_the_input():
	var original := {}
	var result := web.allocate(web.start_node_for("mage"), original)
	assert_eq(original.size(), 0)
	assert_eq(result.size(), 1)


## The whole point of the gateway ring: another archetype's wedge is reachable,
## but only by walking through a gateway you paid for.
func test_a_neighbouring_wedge_is_entered_through_a_gateway_not_directly():
	var mage_start := web.start_node_for("mage")
	var gateway := ""
	for neighbour in web.neighbors(mage_start):
		if web.node_info(neighbour)["kind"] == SkillWeb.KIND_GATEWAY:
			gateway = neighbour
			break
	assert_ne(gateway, "", "a start node should flank at least one gateway")
	var other_start := ""
	for neighbour in web.neighbors(gateway):
		if neighbour != mage_start:
			other_start = neighbour
			break
	assert_ne(other_start, "", "a gateway should join two start nodes")
	assert_false(web.can_allocate(other_start, {mage_start: true}, 99, "mage", {}))
	assert_true(web.can_allocate(other_start, {mage_start: true, gateway: true}, 99, "mage", {}))


# --- resonance ------------------------------------------------------------

func test_neutral_resonance_costs_exactly_the_authored_base_cost():
	for node_id in web.node_ids():
		var archetype: String = web.node_info(node_id)["archetype"]
		var resonance := {archetype: SkillWeb.NEUTRAL_RESONANCE}
		assert_eq(web.point_cost(node_id, resonance), int(web.node_info(node_id)["point_cost"]),
			"%s is not charged at face value for a neutral genome" % node_id)


func test_a_missing_resonance_entry_is_treated_as_neutral():
	var node_id := web.start_node_for("mage")
	assert_eq(web.point_cost(node_id, {}), web.point_cost(node_id, {"mage": SkillWeb.NEUTRAL_RESONANCE}))


func test_high_resonance_never_costs_more_than_low_resonance():
	for node_id in web.node_ids():
		var archetype: String = web.node_info(node_id)["archetype"]
		var cheap := web.point_cost(node_id, {archetype: 1.0})
		var dear := web.point_cost(node_id, {archetype: 0.0})
		assert_lte(cheap, dear, "%s costs more at high resonance than at low" % node_id)


func test_a_dissonant_genome_pays_strictly_more_for_a_real_investment():
	# A single 1-point node can't get any cheaper than 1, so the claim is made
	# against a node with real weight -- a keystone.
	var keystone: String = web.nodes_in_ring("mage", SkillWeb.OUTER_RING)[0]
	assert_gt(web.point_cost(keystone, {"mage": 0.0}), web.point_cost(keystone, {"mage": 1.0}))


func test_no_node_is_ever_free_however_resonant_the_genome():
	for node_id in web.node_ids():
		var archetype: String = web.node_info(node_id)["archetype"]
		assert_gte(web.point_cost(node_id, {archetype: 1.0}), 1,
			"%s became free at maximum resonance" % node_id)


## classes.md's resolution in arithmetic: dissonance lengthens the road, it never
## closes it. The worst case must stay a small finite multiple of face value.
func test_dissonance_never_gates_a_node_behind_an_unpayable_cost():
	for node_id in web.node_ids():
		var archetype: String = web.node_info(node_id)["archetype"]
		var worst := web.point_cost(node_id, {archetype: 0.0})
		var base := int(web.node_info(node_id)["point_cost"])
		assert_lte(worst, int(ceil(base * SkillWeb.MAX_COST_MULTIPLIER)),
			"%s costs more than the declared dissonance ceiling" % node_id)


func test_gateways_are_always_charged_at_neutral_whatever_the_genome():
	var gateway := ""
	for node_id in web.node_ids():
		if web.node_info(node_id)["kind"] == SkillWeb.KIND_GATEWAY:
			gateway = node_id
			break
	var resonant := {}
	var dissonant := {}
	for archetype in ClassArchetype.new().archetype_names():
		resonant[archetype] = 1.0
		dissonant[archetype] = 0.0
	assert_eq(web.point_cost(gateway, resonant), web.point_cost(gateway, dissonant))
	assert_eq(web.point_cost(gateway, resonant), int(web.node_info(gateway)["point_cost"]))


func test_neutral_resonance_grants_exactly_the_authored_bonus():
	for node_id in web.node_ids():
		var info := web.node_info(node_id)
		var resonance := {info["archetype"]: SkillWeb.NEUTRAL_RESONANCE}
		assert_almost_eq(web.effective_bonus(node_id, resonance), float(info["bonus_amount"]), 0.0001,
			"%s does not grant face value for a neutral genome" % node_id)


func test_resonant_investment_grants_more_and_dissonant_grants_less():
	var node_id: String = web.nodes_in_ring("warrior", 1)[0]
	var face := float(web.node_info(node_id)["bonus_amount"])
	assert_gt(web.effective_bonus(node_id, {"warrior": 1.0}), face)
	assert_lt(web.effective_bonus(node_id, {"warrior": 0.0}), face)


func test_a_dissonant_node_still_grants_a_real_positive_bonus():
	for node_id in web.node_ids():
		var info := web.node_info(node_id)
		if float(info["bonus_amount"]) <= 0.0:
			continue
		assert_gt(web.effective_bonus(node_id, {info["archetype"]: 0.0}), 0.0,
			"%s grants nothing at all at zero resonance" % node_id)


## land_sense-style reveal nodes carry an empty stat_name and zero bonus; scaling
## zero by anything is still zero, so they need no special case.
func test_a_reveal_node_grants_no_stat_at_any_resonance():
	var reveal := ""
	for node_id in web.node_ids():
		if web.node_info(node_id)["stat_name"] == "":
			reveal = node_id
			break
	assert_ne(reveal, "", "expected at least one reveal node in the web")
	assert_almost_eq(web.effective_bonus(reveal, {}), 0.0, 0.0001)


# --- totals ---------------------------------------------------------------

func test_total_bonus_sums_only_allocated_nodes_of_that_stat():
	var allocated := {}
	var expected := 0.0
	for node_id in web.node_ids():
		if web.node_info(node_id)["stat_name"] != "max_health":
			continue
		allocated[node_id] = true
		expected += float(web.node_info(node_id)["bonus_amount"])
	assert_gt(expected, 0.0, "expected some max_health nodes in the web")
	var resonance := {}
	for archetype in ClassArchetype.new().archetype_names():
		resonance[archetype] = SkillWeb.NEUTRAL_RESONANCE
	assert_almost_eq(web.total_bonus("max_health", allocated, resonance), expected, 0.0001)


func test_total_bonus_ignores_unknown_and_deallocated_nodes():
	var allocated := {"not_a_node": true, web.start_node_for("warrior"): false}
	assert_almost_eq(web.total_bonus("max_health", allocated, {}), 0.0, 0.0001)


# --- refund / respec ------------------------------------------------------

func test_a_leaf_node_can_be_refunded():
	var start := web.start_node_for("warrior")
	var ring_one: String = web.nodes_in_ring("warrior", 1)[0]
	assert_true(web.can_refund(ring_one, {start: true, ring_one: true}, "warrior"))


func test_refunding_a_node_that_others_hang_off_would_orphan_them():
	var start := web.start_node_for("warrior")
	var ring_one: String = web.nodes_in_ring("warrior", 1)[0]
	assert_false(web.can_refund(start, {start: true, ring_one: true}, "warrior"))


func test_refund_removes_the_node_without_mutating_the_input():
	var start := web.start_node_for("warrior")
	var allocated := {start: true}
	var result := web.refund(start, allocated)
	assert_true(allocated.has(start))
	assert_false(result.has(start))


func test_an_unallocated_node_cannot_be_refunded():
	assert_false(web.can_refund(web.start_node_for("warrior"), {}, "warrior"))


# --- legacy node reuse ----------------------------------------------------

## The web must not re-declare bonuses that skill_tree.gd/keystone_passive.gd
## already own, or the two tables can silently drift apart.
func test_legacy_nodes_keep_the_bonus_their_own_table_declares():
	const SkillTree = preload("res://src/gameplay/skill_tree.gd")
	var tree := SkillTree.new()
	for node_id in tree.node_ids():
		assert_true(web.has(node_id), "legacy node %s is missing from the web" % node_id)
		var legacy := tree.node_info(node_id)
		var placed := web.node_info(node_id)
		assert_eq(placed["stat_name"], legacy["stat_name"], "%s stat drifted" % node_id)
		assert_almost_eq(float(placed["bonus_amount"]), float(legacy["bonus_amount"]), 0.0001,
			"%s bonus drifted" % node_id)
		assert_eq(int(placed["point_cost"]), int(legacy["point_cost"]), "%s cost drifted" % node_id)


func test_legacy_keystones_keep_the_bonus_their_own_table_declares():
	const KeystonePassive = preload("res://src/gameplay/keystone_passive.gd")
	var keystones := KeystonePassive.new()
	for keystone_id in keystones.keystone_ids():
		assert_true(web.has(keystone_id), "legacy keystone %s is missing from the web" % keystone_id)
		var legacy := keystones.keystone_info(keystone_id)
		var placed := web.node_info(keystone_id)
		assert_eq(placed["stat_name"], legacy["stat_name"], "%s stat drifted" % keystone_id)
		assert_almost_eq(float(placed["bonus_amount"]), float(legacy["bonus_amount"]), 0.0001,
			"%s bonus drifted" % keystone_id)
		assert_eq(placed["kind"], SkillWeb.KIND_KEYSTONE)


# --- DNA-flavoured shared nodes -------------------------------------------

func test_a_flavoured_node_resolves_to_one_of_its_own_declared_variants():
	var flavoured := web.flavored_node_ids()
	assert_gt(flavoured.size(), 0, "expected some DNA-flavoured nodes")
	for node_id in flavoured:
		var variants: Array = web.node_info(node_id)["variants"]
		var chosen := web.flavored_variant(node_id, 12345)
		var found := false
		for variant in variants:
			if variant["stat_name"] == chosen["stat_name"]:
				found = true
		assert_true(found, "%s resolved to a variant it does not declare" % node_id)


func test_a_flavoured_node_resolves_the_same_way_for_the_same_dna_seed():
	var node_id: String = web.flavored_node_ids()[0]
	assert_eq(web.flavored_variant(node_id, 777), web.flavored_variant(node_id, 777))


func test_different_dna_seeds_can_resolve_a_flavoured_node_differently():
	var node_id: String = web.flavored_node_ids()[0]
	var seen := {}
	for seed_value in range(0, 200):
		seen[web.flavored_variant(node_id, seed_value)["stat_name"]] = true
	assert_gt(seen.size(), 1, "%s always resolves to the same variant" % node_id)


func test_an_unflavoured_node_resolves_to_its_own_plain_stat():
	var node_id := web.start_node_for("warrior")
	var info := web.node_info(node_id)
	assert_eq(web.flavored_variant(node_id, 42)["stat_name"], info["stat_name"])


## Flavour must be cosmetic-to-balance: every variant of a node has to be worth
## the same, or the flavour roll becomes a second power lottery on top of DNA's.
func test_every_variant_of_a_flavoured_node_carries_the_same_bonus_amount():
	for node_id in web.flavored_node_ids():
		var info := web.node_info(node_id)
		for variant in info["variants"]:
			assert_almost_eq(float(variant["bonus_amount"]), float(info["bonus_amount"]), 0.0001,
				"%s has a variant worth more than the node itself" % node_id)


func test_most_nodes_stay_unflavoured_so_the_map_is_still_readable():
	assert_lt(float(web.flavored_node_ids().size()) / float(web.node_ids().size()), 0.25)
