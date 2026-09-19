extends GutTest

## Plans outliving a reload (see BuildPlanPersistence,
## docs/concept/planner_mode.md's pillar 3: a wireframe is world state, not
## screen state, because walking back to one later is the whole point).
##
## Mirrors WorldClockPersistence's own shape exactly -- SAVE_PATH, save,
## load, wipe, and an empty default on a missing file, the contract
## PlayerSave.load_data and EventStorePersistence.load_store already follow.

const BuildPlanPersistence = preload("res://src/world/build_plan_persistence.gd")
const BuildPlanLedger = preload("res://src/world/build_plan_ledger.gd")
const BuildPlan = preload("res://src/world/build_plan.gd")

const TEST_PATH := "user://test_build_plans.bin"

var store: BuildPlanPersistence


func before_each():
	store = BuildPlanPersistence.new()
	store.wipe(TEST_PATH)


func after_each():
	store.wipe(TEST_PATH)


func _anywhere(_cell: Vector2i) -> bool:
	return true


func _ledger_with_two_plans() -> BuildPlanLedger:
	var ledger := BuildPlanLedger.new()
	ledger.plan(Vector2i(1, 2), Vector2i(3, 4), "house_small", 11.0, _anywhere)
	ledger.plan(Vector2i(-5, 6), Vector2i(0, 0), BuildPlan.PAVEMENT_BLUEPRINT_ID, 22.0, _anywhere)
	return ledger


func test_a_saved_plan_comes_back_with_every_field_it_went_in_with():
	store.save(_ledger_with_two_plans(), TEST_PATH)
	var restored: BuildPlanLedger = store.load_ledger(TEST_PATH)
	assert_eq(restored.count(), 2)
	var house = restored.plan_at(Vector2i(1, 2), Vector2i(3, 4))
	assert_not_null(house, "the house is where it was planned")
	assert_eq(house.blueprint_id, "house_small")
	assert_eq(house.planned_at, 11.0)


## A negative chunk coordinate is an ordinary place in this world, and a
## round trip that mangled it would move somebody's plan across the map.
func test_a_plan_in_a_negative_chunk_survives_the_round_trip():
	store.save(_ledger_with_two_plans(), TEST_PATH)
	var restored: BuildPlanLedger = store.load_ledger(TEST_PATH)
	assert_not_null(restored.plan_at(Vector2i(-5, 6), Vector2i(0, 0)))


## The restored ledger must be a working ledger, not just a bag of records:
## its overlap refusal has to know about what it loaded, or reloading would
## silently allow a second plan on top of an existing one.
func test_a_restored_ledger_still_refuses_to_overlap_what_it_loaded():
	store.save(_ledger_with_two_plans(), TEST_PATH)
	var restored: BuildPlanLedger = store.load_ledger(TEST_PATH)
	assert_eq(
		restored.plan(Vector2i(1, 2), Vector2i(3, 4), "house_small", 0.0, _anywhere), "",
		"the loaded house still stands there"
	)


func test_no_save_yet_loads_an_empty_ledger_rather_than_failing():
	assert_eq(store.load_ledger(TEST_PATH).count(), 0)
	assert_false(store.has_save(TEST_PATH))


## A file written by an older build, or truncated by a crash mid-write,
## must leave the player with no plans rather than a broken game -- the
## same "narrows, never crashes" contract the rest of this codebase keeps.
func test_a_corrupt_file_loads_empty_instead_of_crashing():
	var file := FileAccess.open(TEST_PATH, FileAccess.WRITE)
	file.store_string("this is not a plan file")
	file.close()
	assert_eq(store.load_ledger(TEST_PATH).count(), 0)


func test_wiping_really_removes_the_plans():
	store.save(_ledger_with_two_plans(), TEST_PATH)
	assert_true(store.has_save(TEST_PATH))
	store.wipe(TEST_PATH)
	assert_false(store.has_save(TEST_PATH))
	assert_eq(store.load_ledger(TEST_PATH).count(), 0)


## Saving an empty ledger is how cancelling the last plan persists -- it
## must write an empty file rather than leaving the previous one standing.
func test_saving_an_empty_ledger_clears_what_was_there():
	store.save(_ledger_with_two_plans(), TEST_PATH)
	store.save(BuildPlanLedger.new(), TEST_PATH)
	assert_eq(store.load_ledger(TEST_PATH).count(), 0)
