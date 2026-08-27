extends GutTest

## The per-character unique skill net (docs/concept/skills.md "The genome net"):
## a procedurally generated cluster nobody else has, grafted onto the deepest
## notable of the character's most-resonant wedge.

const GenomeSkillNet = preload("res://src/gameplay/genome_skill_net.gd")
const SkillWeb = preload("res://src/gameplay/skill_web.gd")
const HeroDna = preload("res://src/gameplay/hero_dna.gd")

var net_builder: GenomeSkillNet
var web: SkillWeb


func before_each():
	net_builder = GenomeSkillNet.new()
	web = SkillWeb.new()


## A genome shaped exactly like HeroDna.roll()'s output, with the two fields the
## net actually reads pinned so a test can ask for a specific rarity/anchor
## instead of hunting for a seed that happens to roll one.
func _genome(seed_value: int, rarity: String, best_archetype: String = "mage") -> Dictionary:
	var resonance := {}
	for archetype in SkillWeb.ARCHETYPE_STAT_POOL:
		resonance[archetype] = 0.2
	resonance[best_archetype] = 0.9
	return {"seed_value": seed_value, "rarity": rarity, "resonance": resonance}


# --- size and budget ------------------------------------------------------

func test_a_common_genome_gets_only_the_signature_core():
	var net := net_builder.generate(_genome(1, HeroDna.RARITY_COMMON))
	assert_eq(net["node_ids"].size(), 1)
	assert_eq(net["node_ids"][0], GenomeSkillNet.CORE_NODE_ID)


func test_a_rarer_genome_gets_a_bigger_net():
	var common := net_builder.generate(_genome(1, HeroDna.RARITY_COMMON))
	var rare := net_builder.generate(_genome(1, HeroDna.RARITY_RARE))
	var legendary := net_builder.generate(_genome(1, HeroDna.RARITY_LEGENDARY))
	assert_lt(common["node_ids"].size(), rare["node_ids"].size())
	assert_lt(rare["node_ids"].size(), legendary["node_ids"].size())


func test_every_rarity_the_dna_roll_can_produce_has_a_declared_net_size():
	for rarity in [HeroDna.RARITY_COMMON, HeroDna.RARITY_RARE, HeroDna.RARITY_LEGENDARY]:
		assert_true(GenomeSkillNet.NET_NODE_COUNT.has(rarity), "%s has no net size" % rarity)
		assert_true(GenomeSkillNet.NET_BUDGET_UNITS.has(rarity), "%s has no net budget" % rarity)


## The balance constraint: a net cannot roll a big number, because there is no
## number to roll -- only a fixed budget to divide. Same discipline hero_dna.gd
## already applies to its stat modifiers.
func test_a_net_spends_exactly_its_raritys_budget():
	for rarity in [HeroDna.RARITY_COMMON, HeroDna.RARITY_RARE, HeroDna.RARITY_LEGENDARY]:
		for seed_value in range(0, 40):
			var net := net_builder.generate(_genome(seed_value, rarity))
			var spent := 0.0
			for node_id in net["node_ids"]:
				spent += float(net["nodes"][node_id]["budget_units"])
			assert_almost_eq(spent, float(GenomeSkillNet.NET_BUDGET_UNITS[rarity]), 0.0001,
				"%s net on seed %d overspent" % [rarity, seed_value])


func test_a_rarer_net_is_worth_more_than_a_commoner_one():
	assert_lt(float(GenomeSkillNet.NET_BUDGET_UNITS[HeroDna.RARITY_COMMON]),
		float(GenomeSkillNet.NET_BUDGET_UNITS[HeroDna.RARITY_RARE]))
	assert_lt(float(GenomeSkillNet.NET_BUDGET_UNITS[HeroDna.RARITY_RARE]),
		float(GenomeSkillNet.NET_BUDGET_UNITS[HeroDna.RARITY_LEGENDARY]))


## A budget "unit" is one of the biggest single node the shared web already
## grants for that same stat, so a net's numbers are scale-correct per stat
## (40 max health and 4 taming affinity are the same investment) without any
## per-stat table of its own.
func test_a_nodes_bonus_is_its_budget_share_of_the_webs_own_biggest_node_for_that_stat():
	var net := net_builder.generate(_genome(7, HeroDna.RARITY_LEGENDARY))
	for node_id in net["node_ids"]:
		var node: Dictionary = net["nodes"][node_id]
		var reference := net_builder.reference_bonus_for(String(node["stat_name"]))
		assert_gt(reference, 0.0, "%s references a stat the web never grants" % node_id)
		assert_almost_eq(float(node["bonus_amount"]),
			float(node["budget_units"]) * reference, 0.0001)


func test_every_net_node_carries_a_real_positive_bonus():
	for rarity in [HeroDna.RARITY_COMMON, HeroDna.RARITY_RARE, HeroDna.RARITY_LEGENDARY]:
		for seed_value in range(0, 25):
			var net := net_builder.generate(_genome(seed_value, rarity))
			for node_id in net["node_ids"]:
				assert_gt(float(net["nodes"][node_id]["bonus_amount"]), 0.0,
					"%s on seed %d is a node worth nothing" % [node_id, seed_value])


# --- anchoring ------------------------------------------------------------

func test_the_net_anchors_in_the_genomes_most_resonant_wedge():
	for archetype in SkillWeb.ARCHETYPE_STAT_POOL:
		var net := net_builder.generate(_genome(3, HeroDna.RARITY_RARE, archetype))
		assert_eq(net["anchor_archetype"], archetype)


func test_the_net_hangs_off_a_real_notable_of_that_wedge():
	var net := net_builder.generate(_genome(3, HeroDna.RARITY_RARE, "ranger"))
	var anchor: String = net["anchor_node_id"]
	assert_true(web.has(anchor), "anchor %s is not a node of the web" % anchor)
	assert_eq(web.node_info(anchor)["archetype"], "ranger")
	assert_eq(web.node_info(anchor)["kind"], SkillWeb.KIND_NOTABLE)


func test_every_net_node_grants_a_stat_its_anchor_wedge_is_about():
	for archetype in SkillWeb.ARCHETYPE_STAT_POOL:
		var pool: Array = SkillWeb.ARCHETYPE_STAT_POOL[archetype]
		for seed_value in range(0, 20):
			var net := net_builder.generate(_genome(seed_value, HeroDna.RARITY_LEGENDARY, archetype))
			for node_id in net["node_ids"]:
				var stat: String = net["nodes"][node_id]["stat_name"]
				assert_true(pool.has(stat), "%s granted %s, not a %s stat" % [node_id, stat, archetype])


func test_a_genome_with_no_resonance_at_all_still_anchors_somewhere_real():
	var net := net_builder.generate({"seed_value": 5, "rarity": HeroDna.RARITY_RARE, "resonance": {}})
	assert_true(SkillWeb.ARCHETYPE_STAT_POOL.has(net["anchor_archetype"]))
	assert_true(web.has(net["anchor_node_id"]))


# --- determinism and uniqueness -------------------------------------------

func test_the_same_genome_generates_the_same_net():
	var first := net_builder.generate(_genome(4242, HeroDna.RARITY_LEGENDARY))
	var second := net_builder.generate(_genome(4242, HeroDna.RARITY_LEGENDARY))
	assert_eq(first["name"], second["name"])
	assert_eq(first["node_ids"], second["node_ids"])
	for node_id in first["node_ids"]:
		assert_eq(first["nodes"][node_id], second["nodes"][node_id])


## "a genuine 'this is MY character' hook, not just a reskin" -- if most seeds
## produced the same net the whole feature would be decoration.
func test_different_genomes_generate_genuinely_different_nets():
	var signatures := {}
	for seed_value in range(0, 120):
		var net := net_builder.generate(_genome(seed_value, HeroDna.RARITY_RARE))
		var parts := []
		for node_id in net["node_ids"]:
			var node: Dictionary = net["nodes"][node_id]
			parts.append("%s:%.2f" % [node["stat_name"], node["budget_units"]])
		signatures["%s|%s" % [net["name"], "/".join(parts)]] = true
	assert_gt(signatures.size(), 60, "120 genomes only produced %d distinct nets" % signatures.size())


func test_the_net_carries_a_generated_name():
	var net := net_builder.generate(_genome(11, HeroDna.RARITY_RARE))
	assert_ne(String(net["name"]), "")
	for node_id in net["node_ids"]:
		assert_ne(String(net["nodes"][node_id]["title"]), "")


func test_net_node_ids_never_collide_with_the_shared_webs_own():
	for node_id in net_builder.generate(_genome(9, HeroDna.RARITY_LEGENDARY))["node_ids"]:
		assert_false(web.has(node_id), "%s collides with a shared web node" % node_id)


# --- shape ----------------------------------------------------------------

func test_the_net_is_one_connected_cluster_hanging_off_its_anchor():
	var net := net_builder.generate(_genome(6, HeroDna.RARITY_LEGENDARY))
	var reached := {String(net["anchor_node_id"]): true}
	var frontier := [String(net["anchor_node_id"])]
	while not frontier.is_empty():
		var current: String = frontier.pop_back()
		for neighbour in net["edges"].get(current, []):
			if reached.has(neighbour):
				continue
			reached[neighbour] = true
			frontier.append(neighbour)
	for node_id in net["node_ids"]:
		assert_true(reached.has(node_id), "%s hangs off nothing" % node_id)


func test_net_nodes_sit_beyond_the_shared_webs_outermost_ring():
	var net := net_builder.generate(_genome(6, HeroDna.RARITY_LEGENDARY))
	var rim := SkillWeb.START_RADIUS + SkillWeb.RING_STEP * float(SkillWeb.OUTER_RING)
	for node_id in net["node_ids"]:
		var position: Vector2 = net["nodes"][node_id]["position"]
		assert_gt(position.length(), rim, "%s sits on top of the shared web" % node_id)


func test_no_two_net_nodes_share_a_position():
	var net := net_builder.generate(_genome(6, HeroDna.RARITY_LEGENDARY))
	var seen := {}
	for node_id in net["node_ids"]:
		var key := str((net["nodes"][node_id]["position"] as Vector2).snapped(Vector2(0.001, 0.001)))
		assert_false(seen.has(key), "%s overlaps %s" % [node_id, seen.get(key, "")])
		seen[key] = node_id


# --- grafting onto the web ------------------------------------------------

func test_grafting_adds_every_net_node_to_the_web():
	var net := net_builder.generate(_genome(2, HeroDna.RARITY_LEGENDARY))
	web.graft(net)
	for node_id in net["node_ids"]:
		assert_true(web.has(node_id))
		assert_eq(web.node_info(node_id)["kind"], SkillWeb.KIND_SIGNATURE)


func test_a_grafted_net_node_belongs_to_its_anchor_wedge_so_resonance_applies():
	var net := net_builder.generate(_genome(2, HeroDna.RARITY_LEGENDARY, "artisan"))
	web.graft(net)
	var core: String = net["node_ids"][0]
	assert_eq(web.node_info(core)["archetype"], "artisan")
	assert_lt(web.point_cost(core, {"artisan": 1.0}), web.point_cost(core, {"artisan": 0.0}))


## The net is a reward for having walked your own wedge to its end, not a free
## extra: it is only reachable through the notable it is grafted onto.
func test_a_grafted_net_is_only_reachable_through_its_anchor():
	var net := net_builder.generate(_genome(2, HeroDna.RARITY_RARE, "mage"))
	web.graft(net)
	var core: String = net["node_ids"][0]
	var start := web.start_node_for("mage")
	assert_false(web.can_allocate(core, {start: true}, 99, "mage", {}))
	assert_true(web.can_allocate(core, {String(net["anchor_node_id"]): true}, 99, "mage", {}))


func test_a_grafted_net_node_contributes_to_the_players_totals():
	var net := net_builder.generate(_genome(2, HeroDna.RARITY_RARE, "mage"))
	web.graft(net)
	var core: String = net["node_ids"][0]
	var stat: String = net["nodes"][core]["stat_name"]
	assert_almost_eq(web.total_bonus(stat, {core: true}, {}),
		float(net["nodes"][core]["bonus_amount"]), 0.0001)


func test_a_grafted_net_node_keeps_its_generated_position():
	var net := net_builder.generate(_genome(2, HeroDna.RARITY_RARE))
	web.graft(net)
	var core: String = net["node_ids"][0]
	assert_eq(web.position_of(core), net["nodes"][core]["position"])


func test_grafting_leaves_the_shared_web_untouched():
	var before := web.node_ids().size()
	var net := net_builder.generate(_genome(2, HeroDna.RARITY_LEGENDARY))
	web.graft(net)
	assert_eq(web.node_ids().size(), before + net["node_ids"].size())
	assert_true(web.has("vitality_1"), "grafting should not disturb the shared web")


func test_grafting_the_same_net_twice_does_not_duplicate_it():
	var net := net_builder.generate(_genome(2, HeroDna.RARITY_RARE))
	web.graft(net)
	var after_first := web.node_ids().size()
	web.graft(net)
	assert_eq(web.node_ids().size(), after_first)


# --- calibration against the real web -------------------------------------

## NET_BUDGET_UNITS[common] is not a free-floating number: a common signature
## node has to be worth about what the shared web's own notable tier is worth,
## or the "this is MY character" node is either a trinket or a trap. Measured
## against the real table rather than asserted as a magic number.
func test_a_common_net_is_worth_about_one_of_the_webs_own_notables():
	var ratios := []
	for node_id in web.node_ids():
		var info := web.node_info(node_id)
		if info["kind"] != SkillWeb.KIND_NOTABLE:
			continue
		var reference := net_builder.reference_bonus_for(String(info["stat_name"]))
		if reference <= 0.0:
			continue
		ratios.append(float(info["bonus_amount"]) / reference)
	ratios.sort()
	assert_gt(ratios.size(), 0, "expected notables to measure against")
	var common := float(GenomeSkillNet.NET_BUDGET_UNITS[HeroDna.RARITY_COMMON])
	assert_gte(common, float(ratios[0]), "a common net is worth less than the weakest notable")
	assert_lte(common, float(ratios[ratios.size() - 1]),
		"a common net out-values the strongest notable")


## A legendary net is meant to be BROAD, not spiky: more nodes and more total
## worth, but never one node that eclipses the best thing the shared web has for
## that stat. One unit IS that best thing, so the cap is simply 1.0.
func test_no_single_net_node_ever_out_values_the_webs_biggest_node_for_its_stat():
	for rarity in [HeroDna.RARITY_COMMON, HeroDna.RARITY_RARE, HeroDna.RARITY_LEGENDARY]:
		for seed_value in range(0, 60):
			var net := net_builder.generate(_genome(seed_value, rarity))
			for node_id in net["node_ids"]:
				assert_lte(float(net["nodes"][node_id]["budget_units"]), 1.0,
					"%s on seed %d out-values a keystone" % [node_id, seed_value])
