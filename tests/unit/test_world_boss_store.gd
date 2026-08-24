extends GutTest

## WorldBossStore: promotes, finds, and defeats world bosses (see
## docs/concept/worldbosses.md "World bosses: emergent apex predators").

const WorldBossStore = preload("res://src/emergence/world_boss_store.gd")
const WorldBoss = preload("res://src/emergence/world_boss.gd")

var store: WorldBossStore


func before_each():
	store = WorldBossStore.new()


func test_promoting_assigns_a_real_id():
	var boss := store.promote("creature:1", "predator", 900.0, 800.0, [], 1.0)
	assert_eq(boss.id, "boss_0_predator")


func test_promoting_twice_assigns_different_ids():
	var first := store.promote("creature:1", "predator", 900.0, 800.0, [], 1.0)
	var second := store.promote("creature:2", "herbivore", 500.0, 400.0, [], 1.0)
	assert_ne(first.id, second.id)


func test_get_boss_finds_it_by_id():
	var boss := store.promote("creature:1", "predator", 900.0, 800.0, [], 1.0)
	assert_eq(store.get_boss(boss.id).individual_id, "creature:1")


func test_get_boss_for_an_unknown_id_is_null():
	assert_null(store.get_boss("boss_999_predator"))


## Every promotion this individual has ever had, active or defeated -- the
## same "history is kept" shape InstitutionStore.institutions_for already
## uses.
func test_bosses_for_lists_every_promotion_active_or_defeated():
	var boss := store.promote("creature:1", "predator", 900.0, 800.0, [], 1.0)
	store.defeat(boss.id, 2.0)
	assert_eq(store.bosses_for("creature:1").size(), 1)
	assert_eq(store.bosses_for("creature:1")[0].status, WorldBoss.DEFEATED)


func test_bosses_for_an_unpromoted_individual_is_empty():
	assert_eq(store.bosses_for("creature:999"), [])


func test_active_boss_for_finds_an_active_promotion():
	var boss := store.promote("creature:1", "predator", 900.0, 800.0, [], 1.0)
	assert_eq(store.active_boss_for("creature:1").id, boss.id)


func test_active_boss_for_an_unpromoted_individual_is_null():
	assert_null(store.active_boss_for("creature:999"))


## A defeated boss no longer counts as "already promoted" -- the same
## "dissolved does not block re-forming" reasoning
## InstitutionStore.active_institution_for already establishes.
func test_active_boss_for_a_defeated_boss_is_null():
	var boss := store.promote("creature:1", "predator", 900.0, 800.0, [], 1.0)
	store.defeat(boss.id, 2.0)
	assert_null(store.active_boss_for("creature:1"))


func test_defeating_an_active_boss_marks_it_defeated():
	var boss := store.promote("creature:1", "predator", 900.0, 800.0, [], 1.0)
	assert_true(store.defeat(boss.id, 2.0))
	assert_eq(store.get_boss(boss.id).status, WorldBoss.DEFEATED)


func test_defeating_an_already_defeated_boss_fails():
	var boss := store.promote("creature:1", "predator", 900.0, 800.0, [], 1.0)
	store.defeat(boss.id, 2.0)
	assert_false(store.defeat(boss.id, 3.0))


func test_defeating_an_unknown_boss_fails():
	assert_false(store.defeat("boss_999_predator", 2.0))


func test_to_dicts_and_from_dicts_round_trip_a_whole_store():
	var phases := [{"hp_threshold": 0.5, "ability": "enrage"}]
	var boss := store.promote("creature:1", "predator", 900.0, 800.0, phases, 1.0)
	store.defeat(boss.id, 2.0)
	store.promote("creature:2", "herbivore", 500.0, 400.0, [], 3.0)

	var restored := WorldBossStore.from_dicts(store.to_dicts())

	assert_eq(restored.get_boss(boss.id).status, WorldBoss.DEFEATED)
	assert_eq(restored.get_boss(boss.id).phases, phases)
	assert_eq(restored.active_boss_for("creature:2").species, "herbivore")


## from_dicts must resume the id sequence past whatever it restored, the
## same "ordinal counter never collides after a reload" guarantee
## InstitutionStore/ContractStore's own from_dicts already provide.
func test_from_dicts_resumes_the_ordinal_sequence():
	store.promote("creature:1", "predator", 900.0, 800.0, [], 1.0)
	var restored := WorldBossStore.from_dicts(store.to_dicts())
	var next_boss: WorldBoss = restored.promote("creature:2", "herbivore", 500.0, 400.0, [], 2.0)
	assert_eq(next_boss.id, "boss_1_herbivore")
