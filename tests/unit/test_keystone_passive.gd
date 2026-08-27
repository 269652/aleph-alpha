extends GutTest

const KeystonePassive = preload("res://src/gameplay/keystone_passive.gd")

const _BASELINE_STAT_BUMP := 5.0

var keystone: KeystonePassive


func before_each():
	keystone = KeystonePassive.new()


func test_can_unlock_true_exactly_at_required_node_count():
	for id in keystone.keystone_ids():
		var required := _required_node_count(id)
		assert_true(keystone.can_unlock(id, required), "expected can_unlock true at exactly required_node_count for '%s'" % id)


func test_can_unlock_true_when_allocated_node_count_exceeds_requirement():
	for id in keystone.keystone_ids():
		var required := _required_node_count(id)
		assert_true(keystone.can_unlock(id, required + 10), "expected can_unlock true above required_node_count for '%s'" % id)


func test_can_unlock_false_when_below_requirement():
	for id in keystone.keystone_ids():
		var required := _required_node_count(id)
		if required <= 0:
			continue
		assert_false(keystone.can_unlock(id, required - 1), "expected can_unlock false below required_node_count for '%s'" % id)


func test_can_unlock_false_for_unknown_keystone_id_regardless_of_node_count():
	assert_false(keystone.can_unlock("not_a_real_keystone", 0))
	assert_false(keystone.can_unlock("not_a_real_keystone", 999))


func test_keystone_ids_returns_at_least_three_defined_keystones():
	assert_gte(keystone.keystone_ids().size(), 3)


## Every keystone resolves to real info -- but that info is no longer
## guaranteed to be a nonzero STAT bonus: a reveal-type keystone (e.g.
## land_sense, see below) deliberately carries an empty stat_name instead
## (its payoff is real information becoming visible, not a number going up).
func test_keystone_ids_returns_every_defined_keystone():
	var ids: Array = keystone.keystone_ids()
	for id in ids:
		var info: Dictionary = keystone.keystone_info(id)
		assert_false(info.is_empty(), "expected '%s' to resolve to real keystone info" % id)


func test_bonus_for_returns_correct_stat_and_amount_for_known_keystone():
	var id: String = keystone.keystone_ids()[0]
	var bonus: Dictionary = keystone.bonus_for(id)
	assert_true(bonus.has("stat_name"))
	assert_true(bonus.has("bonus_amount"))
	assert_ne(bonus["stat_name"], "")
	assert_gt(bonus["bonus_amount"], 0.0)


func test_bonus_for_returns_empty_sentinel_for_unknown_keystone_id():
	var bonus: Dictionary = keystone.bonus_for("not_a_real_keystone")
	assert_eq(bonus["stat_name"], "")
	assert_eq(bonus["bonus_amount"], 0.0)


func test_at_least_two_keystones_have_different_required_node_counts():
	var ids: Array = keystone.keystone_ids()
	var required_counts := {}
	for id in ids:
		required_counts[_required_node_count(id)] = true
	assert_gt(required_counts.size(), 1, "expected keystones to have varying required_node_count values (real tiering)")


func test_keystone_bonus_amount_is_meaningfully_larger_than_a_baseline_stat_bump():
	for id in keystone.keystone_ids():
		var bonus: Dictionary = keystone.bonus_for(id)
		if bonus["stat_name"] == "":
			continue  # reveal-type keystone (e.g. land_sense) -- deliberately no stat bump
		assert_gt(bonus["bonus_amount"], _BASELINE_STAT_BUMP, "expected '%s' bonus_amount to exceed baseline of %f" % [id, _BASELINE_STAT_BUMP])


func _required_node_count(keystone_id: String) -> int:
	# Binary-search-free probe: find the smallest allocated_node_count at which can_unlock flips true.
	for count in range(0, 51):
		if keystone.can_unlock(keystone_id, count):
			return count
	return -1


func test_keystone_info_exposes_gate_and_bonus_for_display():
	var info = keystone.keystone_info("iron_skin")
	assert_eq(info["stat_name"], "max_health")
	assert_eq(info["bonus_amount"], 60.0)
	assert_eq(info["required_node_count"], 3)


func test_keystone_info_of_unknown_is_empty():
	assert_true(keystone.keystone_info("nope").is_empty())


# -- land_sense: a REVEAL keystone, not a stat bump (docs/concept/
# progression.md "Ecological literacy" -- the Naturalist branch's payoff is
# real ecosystem info becoming visible, not a number going up) -------------

func test_land_sense_keystone_carries_no_stat_bonus():
	var bonus: Dictionary = keystone.bonus_for("land_sense")
	assert_eq(bonus["stat_name"], "")
	assert_eq(bonus["bonus_amount"], 0.0)


func test_land_sense_keystone_info_carries_a_real_reveal_description():
	var info := keystone.keystone_info("land_sense")
	assert_eq(info["stat_name"], "")
	assert_ne(info.get("description", ""), "", "expected a real UI description for a non-stat keystone")


func test_land_sense_required_node_count():
	assert_eq(_required_node_count("land_sense"), 2)
