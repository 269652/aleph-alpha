extends GutTest

const ClassArchetype = preload("res://src/gameplay/class_archetype.gd")

var archetype: ClassArchetype

const _EXPECTED_NAMES := ["warrior", "mage", "ranger", "beastmaster", "artisan", "herbalist", "overseer"]
const _STAT_KEYS := ["max_health", "attack_damage", "max_mana", "max_stamina"]


func before_each():
	archetype = ClassArchetype.new()


func test_archetype_names_contains_all_seven_named_archetypes():
	var names: Array = archetype.archetype_names()
	for expected_name in _EXPECTED_NAMES:
		assert_true(names.has(expected_name), "expected archetype_names() to contain '%s'" % expected_name)


func test_archetype_names_has_exactly_seven_entries():
	assert_eq(archetype.archetype_names().size(), 7)


func test_stats_for_returns_non_trivial_dictionary_for_each_known_archetype():
	for archetype_name in _EXPECTED_NAMES:
		var stats: Dictionary = archetype.stats_for(archetype_name)
		var has_non_zero := false
		for key in _STAT_KEYS:
			if stats[key] != 0.0:
				has_non_zero = true
		assert_true(has_non_zero, "expected '%s' to have at least one non-zero stat" % archetype_name)


func test_stats_for_every_known_archetype_has_the_same_stat_keys():
	for archetype_name in _EXPECTED_NAMES:
		var stats: Dictionary = archetype.stats_for(archetype_name)
		for key in _STAT_KEYS:
			assert_true(stats.has(key), "expected '%s' stats to have key '%s'" % [archetype_name, key])


func test_stats_for_unknown_name_returns_all_zero_with_correct_keys():
	var stats: Dictionary = archetype.stats_for("not_a_real_archetype")
	for key in _STAT_KEYS:
		assert_true(stats.has(key), "expected unknown-archetype stats to still have key '%s'" % key)
		assert_eq(stats[key], 0.0)


func test_is_known_true_for_a_real_archetype():
	assert_true(archetype.is_known("warrior"))


func test_is_known_false_for_an_unknown_archetype():
	assert_false(archetype.is_known("not_a_real_archetype"))


func test_respec_equals_stats_for_a_known_archetype():
	var respec_stats: Dictionary = archetype.respec("mage")
	var direct_stats: Dictionary = archetype.stats_for("mage")
	assert_eq(respec_stats, direct_stats)


func test_warrior_has_higher_attack_damage_than_mage():
	var warrior_stats: Dictionary = archetype.stats_for("warrior")
	var mage_stats: Dictionary = archetype.stats_for("mage")
	assert_gt(warrior_stats["attack_damage"], mage_stats["attack_damage"])


func test_mage_has_higher_max_mana_than_warrior():
	var warrior_stats: Dictionary = archetype.stats_for("warrior")
	var mage_stats: Dictionary = archetype.stats_for("mage")
	assert_gt(mage_stats["max_mana"], warrior_stats["max_mana"])


func test_warrior_has_higher_max_health_than_mage():
	var warrior_stats: Dictionary = archetype.stats_for("warrior")
	var mage_stats: Dictionary = archetype.stats_for("mage")
	assert_gt(warrior_stats["max_health"], mage_stats["max_health"])
