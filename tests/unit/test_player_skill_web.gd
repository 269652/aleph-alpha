extends GutTest

## Player <-> passive web (docs/concept/skills.md): the character's own class
## start, DNA resonance exchange rate, grafted genome net and free respec, as the
## live Player actually experiences them rather than as pure-logic modules.

const PlayerScene = preload("res://scenes/player.tscn")
const SkillWeb = preload("res://src/gameplay/skill_web.gd")
const HeroDna = preload("res://src/gameplay/hero_dna.gd")
const KeystonePassive = preload("res://src/gameplay/keystone_passive.gd")

var player: Player
var web := SkillWeb.new()


func before_each():
	player = PlayerScene.instantiate()
	add_child(player)


func after_each():
	remove_child(player)
	player.free()


func _with_points(count: int) -> void:
	player.experience.unspent_points = count


# --- the class start node -------------------------------------------------

## PoE hands you your class's start node for free; paying a level-up point for
## "you are a mage" would be a tax on existing.
func test_a_new_character_already_stands_on_their_own_classs_start_node():
	player.apply_class("mage", {})
	assert_true(player.allocated_nodes.get(web.start_node_for("mage"), false))


func test_the_free_start_node_costs_no_points():
	_with_points(3)
	player.apply_class("mage", {})
	assert_eq(player.experience.unspent_points, 3)


func test_the_free_start_node_still_grants_its_own_bonus():
	var before := player.max_health
	player.apply_class("warrior", {})
	var granted: float = web.node_info(web.start_node_for("warrior"))["bonus_amount"]
	assert_almost_eq(player.max_health, before + granted, 0.001)


func test_choosing_a_class_twice_does_not_grant_the_start_node_twice():
	player.apply_class("warrior", {})
	var once := player.max_health
	player.apply_class("warrior", {})
	assert_almost_eq(player.max_health, once, 0.001)


# --- pathing --------------------------------------------------------------

func test_a_node_two_steps_out_cannot_be_taken_before_the_step_between_it():
	player.apply_class("mage", {})
	_with_points(99)
	var ring_two: String = web.nodes_in_ring("mage", 2)[0]
	assert_false(player.allocate_skill(ring_two))
	assert_false(player.allocated_nodes.has(ring_two))


func test_a_node_next_to_one_you_own_can_be_taken():
	player.apply_class("mage", {})
	_with_points(99)
	var ring_one: String = web.nodes_in_ring("mage", 1)[0]
	assert_true(player.allocate_skill(ring_one))
	assert_true(player.allocated_nodes.get(ring_one, false))


func test_another_archetypes_wedge_is_still_reachable_the_long_way_round():
	player.apply_class("mage", {})
	_with_points(99)
	var gateway := ""
	for neighbour in web.neighbors(web.start_node_for("mage")):
		if web.node_info(neighbour)["kind"] == SkillWeb.KIND_GATEWAY:
			gateway = neighbour
			break
	assert_true(player.allocate_skill(gateway), "a gateway off your own start should be takeable")
	var other := ""
	for neighbour in web.neighbors(gateway):
		if neighbour != web.start_node_for("mage"):
			other = neighbour
			break
	assert_true(player.allocate_skill(other), "the next wedge should open once the gateway is paid")


func test_taking_a_node_spends_exactly_what_it_costs_this_character():
	player.apply_class("mage", {})
	_with_points(10)
	var ring_one: String = web.nodes_in_ring("mage", 1)[0]
	var cost := player.skill_point_cost(ring_one)
	assert_true(player.allocate_skill(ring_one))
	assert_eq(player.experience.unspent_points, 10 - cost)


func test_a_node_you_cannot_pay_for_is_refused():
	player.apply_class("mage", {})
	_with_points(0)
	assert_false(player.allocate_skill(web.nodes_in_ring("mage", 1)[0]))


# --- DNA resonance --------------------------------------------------------

## classes.md's soft resonance, as the player actually meets it: the same node,
## same place on the map, a different price.
func test_a_resonant_character_pays_less_for_the_same_node_than_a_dissonant_one():
	var keystone: String = web.nodes_in_ring("mage", SkillWeb.OUTER_RING)[0]
	player.apply_class("mage", {})
	player.dna_resonance = {"mage": 1.0}
	var resonant := player.skill_point_cost(keystone)
	player.dna_resonance = {"mage": 0.0}
	var dissonant := player.skill_point_cost(keystone)
	assert_lt(resonant, dissonant)


func test_a_resonant_character_gains_more_from_the_same_node():
	var node_id := "vitality_1"
	player.apply_class("warrior", {})
	player.dna_resonance = {"warrior": 1.0}
	_with_points(99)
	var before := player.max_health
	player.allocate_skill(node_id)
	var resonant_gain := player.max_health - before

	var neutral: Player = PlayerScene.instantiate()
	add_child_autofree(neutral)
	neutral.apply_class("warrior", {})
	neutral.dna_resonance = {"warrior": SkillWeb.NEUTRAL_RESONANCE}
	neutral.experience.unspent_points = 99
	var neutral_before := neutral.max_health
	neutral.allocate_skill(node_id)
	assert_gt(resonant_gain, neutral.max_health - neutral_before)


## Never a gate: the dissonant road is longer, not closed.
func test_a_dissonant_character_can_still_reach_everything_given_the_points():
	player.apply_class("mage", {})
	player.dna_resonance = {"mage": 0.0}
	_with_points(999)
	var ring_one: String = web.nodes_in_ring("mage", 1)[0]
	assert_true(player.allocate_skill(ring_one))


# --- the genome net -------------------------------------------------------

func test_a_dna_seed_grafts_the_characters_own_unique_net():
	player.apply_class("mage", {})
	player.apply_dna_seed(20260825)
	assert_false(player.genome_net.is_empty(), "no net was generated")
	for node_id in player.genome_net["node_ids"]:
		assert_true(player.skill_web.has(node_id), "%s was never grafted" % node_id)


func test_two_characters_with_different_dna_get_different_nets():
	player.apply_dna_seed(11)
	var first := String(player.genome_net["name"])
	var other: Player = PlayerScene.instantiate()
	add_child_autofree(other)
	other.apply_dna_seed(999)
	assert_ne(first, String(other.genome_net["name"]))


func test_the_net_is_only_takeable_once_its_anchor_notable_is_owned():
	player.apply_class("mage", {})
	player.apply_dna_seed(20260825)
	_with_points(999)
	var core: String = player.genome_net["node_ids"][0]
	assert_false(player.allocate_skill(core), "the net should not be free-floating")
	player.allocated_nodes[String(player.genome_net["anchor_node_id"])] = true
	assert_true(player.allocate_skill(core))


func test_applying_the_same_dna_seed_twice_does_not_duplicate_the_net():
	player.apply_dna_seed(7)
	var count := player.skill_web.node_ids().size()
	player.apply_dna_seed(7)
	assert_eq(player.skill_web.node_ids().size(), count)


func test_a_dna_seed_also_sets_the_resonance_it_rolled():
	player.apply_dna_seed(4242)
	assert_eq(player.dna_resonance, HeroDna.new().roll(4242)["resonance"])


func test_the_dna_seed_survives_a_save_and_reload():
	player.apply_class("mage", {})
	player.apply_dna_seed(31337)
	var restored: Player = PlayerScene.instantiate()
	add_child_autofree(restored)
	restored.apply_save_dict(player.to_save_dict())
	assert_eq(restored.dna_seed, 31337)
	assert_eq(String(restored.genome_net["name"]), String(player.genome_net["name"]))


# --- keystones ------------------------------------------------------------

func test_a_keystone_still_needs_its_node_count_gate_as_well_as_a_path():
	player.apply_class("warrior", {})
	_with_points(999)
	# Walk straight out to the keystone, so the PATH exists...
	for node_id in ["vitality_1", "vitality_2", "juggernaut"]:
		assert_true(player.allocate_skill(node_id), "could not path via %s" % node_id)
	# ...and iron_skin's own required_node_count (3) is met by exactly those
	# three plus the free start, so it opens.
	assert_true(player.unlock_keystone("iron_skin"))
	assert_true(player.unlocked_keystones.get("iron_skin", false))


func test_a_keystone_with_no_path_to_it_is_refused_however_many_nodes_are_owned():
	player.apply_class("warrior", {})
	_with_points(999)
	for node_id in ["vitality_1", "vitality_2", "juggernaut"]:
		player.allocate_skill(node_id)
	assert_false(player.unlock_keystone("archmage"), "a mage keystone is not next door")


## The observable payoff, not just the flag: unlock_keystone runs through the
## SAME allocate_skill -> _apply_web_node path an ordinary node does (see
## Player.unlock_keystone's own doc comment), so iron_skin's own real
## bonus_amount -- read from KeystonePassive's table, not re-typed here --
## has to land on max_health exactly the way vitality_1's does. A passing
## unlocked_keystones flag alone (the shape every other test in this section
## checks) would still be true if _apply_web_node were never called at all.
func test_unlocking_a_keystone_grants_its_own_real_bonus_to_the_live_player():
	player.apply_class("warrior", {})
	_with_points(999)
	for node_id in ["vitality_1", "vitality_2", "juggernaut"]:
		player.allocate_skill(node_id)
	var before_health := player.max_health
	var granted: float = KeystonePassive.new().bonus_for("iron_skin")["bonus_amount"]

	assert_true(player.unlock_keystone("iron_skin"))

	assert_almost_eq(player.max_health, before_health + granted, 0.001)
	assert_almost_eq(player.health, player.max_health, 0.001,
		"a keystone's health bonus should heal the gained amount, same as any other node")


# --- free respec ----------------------------------------------------------

func test_refunding_a_node_gives_back_what_it_cost_and_removes_its_bonus():
	player.apply_class("warrior", {})
	_with_points(10)
	var before_health := player.max_health
	player.allocate_skill("vitality_1")
	assert_true(player.refund_skill("vitality_1"))
	assert_eq(player.experience.unspent_points, 10)
	assert_almost_eq(player.max_health, before_health, 0.001)


func test_refunding_cannot_orphan_the_rest_of_the_build():
	player.apply_class("warrior", {})
	_with_points(10)
	player.allocate_skill("vitality_1")
	player.allocate_skill("vitality_2")
	assert_false(player.refund_skill("vitality_1"), "vitality_2 hangs off it")


func test_refunding_a_node_you_never_took_does_nothing():
	player.apply_class("warrior", {})
	_with_points(4)
	assert_false(player.refund_skill("vitality_1"))
	assert_eq(player.experience.unspent_points, 4)


func test_refunding_a_keystone_forgets_it_was_unlocked():
	player.apply_class("warrior", {})
	_with_points(999)
	for node_id in ["vitality_1", "vitality_2", "juggernaut"]:
		player.allocate_skill(node_id)
	player.unlock_keystone("iron_skin")
	assert_true(player.refund_skill("iron_skin"))
	assert_false(player.unlocked_keystones.get("iron_skin", false))


# --- stats read on demand -------------------------------------------------

## meat_yield/carpentry_level are read fresh at use time rather than folded into
## a cached stat (see Player._apply_skill_stat) -- they have to come from the web
## at this character's exchange rate too, not from the old flat table.
func test_an_on_demand_stat_is_read_from_the_web_at_this_characters_rate():
	player.apply_class("ranger", {})
	player.dna_resonance = {"ranger": 1.0}
	_with_points(99)
	player.allocate_skill("butchering_1")
	var resonant := player.skill_bonus("meat_yield")
	player.dna_resonance = {"ranger": 0.0}
	assert_gt(resonant, player.skill_bonus("meat_yield"))
	assert_gt(player.skill_bonus("meat_yield"), 0.0)
