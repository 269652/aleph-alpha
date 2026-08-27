extends GutTest

## WorldBoss: a promoted world-boss-tier individual (see
## src/gameplay/world_boss_fitness.gd, docs/concept/worldbosses.md).

const WorldBoss = preload("res://src/emergence/world_boss.gd")


func test_a_new_boss_starts_active():
	var boss := WorldBoss.new("creature:1", "predator", 900.0, 800.0, [], 1.0)
	assert_eq(boss.status, WorldBoss.ACTIVE)


func test_a_new_boss_preserves_its_fields():
	var phases := [{"hp_threshold": 0.5, "ability": "enrage"}]
	var boss := WorldBoss.new("creature:1", "predator", 900.0, 800.0, phases, 1.0)
	assert_eq(boss.individual_id, "creature:1")
	assert_eq(boss.species, "predator")
	assert_eq(boss.score, 900.0)
	assert_eq(boss.threshold, 800.0)
	assert_eq(boss.phases, phases)
	assert_eq(boss.created_at, 1.0)


func test_id_is_empty_until_a_store_assigns_it():
	var boss := WorldBoss.new("creature:1", "predator", 900.0, 800.0, [], 1.0)
	assert_eq(boss.id, "")
