extends GutTest

## Dispatches one spell atom step's real effect against a resolved target
## (docs/concept/spell_runtime.md). Tested against the real Player, since
## Player already implements every duck-typed method a target needs
## (take_damage/heal/apply_knockback/apply_spell_debuff/apply_shield) --
## CreatureMarker implements the same methods and is covered by its own
## integration tests, not re-verified here (this file is about dispatch,
## not about which target class receives it).

const SpellAtomEffects = preload("res://src/gameplay/spell_atom_effects.gd")
const SpellStatusEffects = preload("res://src/gameplay/spell_status_effects.gd")
const PlayerScene = preload("res://scenes/player.tscn")

var effects := SpellAtomEffects.new()
var target: Player


func before_each():
	target = PlayerScene.instantiate()
	add_child(target)
	target.apply_class("mage", {"max_mana": 50.0})


func after_each():
	remove_child(target)
	target.free()


func test_fire_damage_deals_real_damage():
	var health_before := target.health
	var applied := effects.apply_to_target("fire_damage", {"magnitude": 20.0}, target, Vector2.ZERO, Vector2.RIGHT)
	assert_true(applied)
	assert_almost_eq(target.health, health_before - 20.0, 0.001)


func test_every_damage_atom_deals_damage():
	for atom_id in ["fire_damage", "frost_damage", "shock_damage", "poison_damage"]:
		target.health = target.max_health
		effects.apply_to_target(atom_id, {"magnitude": 10.0}, target, Vector2.ZERO, Vector2.RIGHT)
		assert_lt(target.health, target.max_health, "%s should deal damage" % atom_id)


func test_minor_heal_restores_health():
	target.take_damage(30.0)
	var health_before := target.health

	var applied := effects.apply_to_target("minor_heal", {"magnitude": 10.0}, target, Vector2.ZERO, Vector2.RIGHT)

	assert_true(applied)
	assert_almost_eq(target.health, health_before + 10.0, 0.001)


func test_major_heal_restores_more_than_minor_heal():
	target.take_damage(90.0)
	var after_minor_would_be := target.health + 6.0

	effects.apply_to_target("major_heal", {"magnitude": 15.0}, target, Vector2.ZERO, Vector2.RIGHT)

	assert_gt(target.health, after_minor_would_be)


func test_push_knocks_the_target_away_from_the_caster():
	var applied := effects.apply_to_target("push", {"magnitude": 50.0}, target, Vector2(-10, 0), Vector2.RIGHT)
	assert_true(applied)
	var velocity := target._knockback_velocity(Vector2.ZERO, 0.05)
	assert_gt(velocity.x, 0.0, "pushed away from a caster to the left should move the target right")


func test_pull_knocks_the_target_toward_the_caster():
	var applied := effects.apply_to_target("pull", {"magnitude": 50.0}, target, Vector2(-10, 0), Vector2.RIGHT)
	assert_true(applied)
	var velocity := target._knockback_velocity(Vector2.ZERO, 0.05)
	assert_lt(velocity.x, 0.0, "pulled toward a caster to the left should move the target left")


func test_status_atoms_apply_the_matching_debuff():
	var cases := {
		"ignite": SpellStatusEffects.IGNITE,
		"blight": SpellStatusEffects.BLIGHT,
		"freeze": SpellStatusEffects.FREEZE,
		"root": SpellStatusEffects.ROOT,
		"slow": SpellStatusEffects.SLOW,
		"illuminate": SpellStatusEffects.ILLUMINATE,
		"calm": SpellStatusEffects.CALM,
		"fear": SpellStatusEffects.FEAR,
		"suppress_mutation": SpellStatusEffects.SUPPRESS_MUTATION,
		"summon_wisp": SpellStatusEffects.SUMMON_WISP,
	}
	for atom_id in cases:
		target.active_spell_debuffs = []
		var applied := effects.apply_to_target(atom_id, {"duration": 3.0}, target, Vector2.ZERO, Vector2.RIGHT)
		assert_true(applied, "%s should apply" % atom_id)
		assert_true(
			target._debuff_stack.stacks_of(target.active_spell_debuffs, cases[atom_id]) > 0,
			"%s should leave a real tracked debuff on the target" % atom_id
		)


func test_shield_grants_a_real_absorb_pool():
	var applied := effects.apply_to_target(
		"shield", {"magnitude": 10.0, "duration": 4.0}, target, Vector2.ZERO, Vector2.RIGHT
	)
	assert_true(applied)
	var health_before := target.health
	target.take_damage(5.0)
	assert_almost_eq(target.health, health_before, 0.001, "the fresh shield should absorb a small hit entirely")


func test_teleport_moves_the_target_along_the_facing_direction():
	var start := target.position
	var applied := effects.apply_to_target("teleport", {"magnitude": 100.0}, target, start, Vector2.RIGHT)
	assert_true(applied)
	assert_almost_eq(target.position.x, start.x + 100.0, 0.01)
	assert_almost_eq(target.position.y, start.y, 0.01)


func test_teleport_fails_with_no_facing_direction():
	var applied := effects.apply_to_target("teleport", {"magnitude": 100.0}, target, target.position, Vector2.ZERO)
	assert_false(applied, "a spell can't teleport somewhere undefined")


func test_gravity_shift_applies_a_real_shove():
	var applied := effects.apply_to_target(
		"gravity_shift", {"magnitude": 20.0, "duration": 2.0}, target, Vector2(-10, 0), Vector2.RIGHT
	)
	assert_true(applied)
	var velocity := target._knockback_velocity(Vector2.ZERO, 0.05)
	assert_gt(velocity.length(), 0.0, "gravity_shift must produce a real, if approximated, force")


func test_apply_to_target_returns_false_for_an_unrecognized_atom():
	assert_false(effects.apply_to_target("not_a_real_atom", {}, target, Vector2.ZERO, Vector2.RIGHT))


func test_apply_to_target_returns_false_for_a_null_target():
	assert_false(effects.apply_to_target("fire_damage", {"magnitude": 10.0}, null, Vector2.ZERO, Vector2.RIGHT))
