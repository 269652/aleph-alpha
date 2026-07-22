extends GutTest

const MeleeAttack = preload("res://src/gameplay/melee_attack.gd")
const Item = preload("res://src/gameplay/item.gd")

var attack: MeleeAttack


func before_each():
	attack = MeleeAttack.new()


func test_attack_damage_uses_the_equipped_weapons_damage():
	var sword := Item.new("iron_sword", "Iron Sword", "weapon", 1, 25.0)
	assert_eq(attack.attack_damage(sword, 5.0), 25.0)


func test_attack_damage_falls_back_to_unarmed_when_no_weapon():
	assert_eq(attack.attack_damage(null, 5.0), 5.0)


func test_attack_damage_ignores_a_non_weapon_item():
	var hide := Item.new("hide", "Hide", "material", 40)
	assert_eq(attack.attack_damage(hide, 5.0), 5.0)


func test_targets_in_range_includes_close_positions():
	var hits := attack.targets_in_range(Vector2.ZERO, [Vector2(5, 0), Vector2(500, 0)], 20.0)
	assert_eq(hits, [0])


func test_targets_in_range_excludes_far_positions():
	var hits := attack.targets_in_range(Vector2.ZERO, [Vector2(500, 0)], 20.0)
	assert_eq(hits, [])


func test_targets_in_range_can_include_multiple_hits():
	var hits := attack.targets_in_range(Vector2.ZERO, [Vector2(5, 0), Vector2(-5, 0)], 20.0)
	assert_eq(hits, [0, 1])


func test_knockback_vector_points_away_from_the_attacker():
	var knockback := attack.knockback_vector(Vector2.ZERO, Vector2(10, 0), 40.0)
	assert_almost_eq(knockback.x, 40.0, 0.001)
	assert_almost_eq(knockback.y, 0.0, 0.001)


func test_knockback_vector_magnitude_equals_the_force():
	var knockback := attack.knockback_vector(Vector2.ZERO, Vector2(3, 4), 10.0)
	assert_almost_eq(knockback.length(), 10.0, 0.001)


func test_knockback_vector_handles_exactly_overlapping_positions():
	var knockback := attack.knockback_vector(Vector2(5, 5), Vector2(5, 5), 10.0)
	assert_almost_eq(knockback.length(), 10.0, 0.001)
