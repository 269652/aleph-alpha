extends GutTest

const SkillTree = preload("res://src/gameplay/skill_tree.gd")

var tree: SkillTree


func before_each():
	tree = SkillTree.new()


func test_can_allocate_true_when_affordable_and_not_taken():
	var node_id: String = tree.node_ids()[0]
	assert_true(tree.can_allocate(node_id, {}, 999))


func test_can_allocate_false_when_too_expensive():
	var node_id: String = tree.node_ids()[0]
	assert_false(tree.can_allocate(node_id, {}, 0))


func test_can_allocate_false_when_already_allocated():
	var node_id: String = tree.node_ids()[0]
	var allocated := {node_id: true}
	assert_false(tree.can_allocate(node_id, allocated, 999))


func test_can_allocate_false_for_unknown_node_id():
	assert_false(tree.can_allocate("not_a_real_node", {}, 999))


func test_allocate_adds_node_without_mutating_input():
	var node_id: String = tree.node_ids()[0]
	var original := {}
	var result := tree.allocate(node_id, original)
	assert_true(result.has(node_id))
	assert_false(original.has(node_id))


func test_allocate_on_already_allocated_node_is_noop():
	var node_id: String = tree.node_ids()[0]
	var allocated := {node_id: true}
	var result := tree.allocate(node_id, allocated)
	assert_eq(result, allocated)


func test_allocate_on_unknown_node_id_is_noop():
	var allocated := {}
	var result := tree.allocate("not_a_real_node", allocated)
	assert_eq(result, allocated)


func test_total_bonus_sums_across_multiple_allocated_nodes_of_same_stat():
	var matching_ids: Array = []
	for node_id in tree.node_ids():
		if tree._nodes[node_id]["stat_name"] == "max_health":
			matching_ids.append(node_id)
	assert_gte(matching_ids.size(), 2, "expected at least 2 max_health nodes to test summation")
	var allocated := {}
	var expected_total: float = 0.0
	for node_id in matching_ids:
		allocated[node_id] = true
		expected_total += tree._nodes[node_id]["bonus_amount"]
	assert_almost_eq(tree.total_bonus("max_health", allocated), expected_total, 0.0001)


func test_total_bonus_ignores_nodes_of_different_stat_name():
	var health_node_id: String = ""
	var other_node_id: String = ""
	for node_id in tree.node_ids():
		var stat_name: String = tree._nodes[node_id]["stat_name"]
		if stat_name == "max_health" and health_node_id == "":
			health_node_id = node_id
		elif stat_name != "max_health" and other_node_id == "":
			other_node_id = node_id
	var allocated := {health_node_id: true, other_node_id: true}
	assert_almost_eq(tree.total_bonus("max_health", allocated), tree._nodes[health_node_id]["bonus_amount"], 0.0001)


func test_total_bonus_is_zero_for_stat_with_nothing_allocated():
	assert_eq(tree.total_bonus("max_health", {}), 0.0)


func test_node_ids_returns_every_defined_node():
	assert_gte(tree.node_ids().size(), 5)


func test_node_ids_cover_at_least_two_stat_names():
	var stat_names := {}
	for node_id in tree.node_ids():
		stat_names[tree._nodes[node_id]["stat_name"]] = true
	assert_gte(stat_names.size(), 2)


func test_node_info_exposes_stat_bonus_and_cost_for_display():
	var info = tree.node_info("vitality_1")
	assert_eq(info["stat_name"], "max_health")
	assert_eq(info["bonus_amount"], 10.0)
	assert_eq(info["point_cost"], 1)


func test_node_info_of_unknown_node_is_empty():
	assert_true(tree.node_info("nope").is_empty())
