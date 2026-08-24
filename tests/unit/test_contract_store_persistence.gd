extends GutTest

## ContractStorePersistence: pure I/O for the emergence contract store --
## mirrors EventStorePersistence/MemoryStorePersistence/
## HouseholdStorePersistence/PlayerSave's role exactly.

const ContractStorePersistence = preload("res://src/emergence/contract_store_persistence.gd")
const ContractStore = preload("res://src/emergence/contract_store.gd")
const Contract = preload("res://src/emergence/contract.gd")

const TEST_PATH := "user://test_contract_store.bin"

var persistence: ContractStorePersistence


func before_each():
	persistence = ContractStorePersistence.new()


func after_each():
	if FileAccess.file_exists(TEST_PATH):
		DirAccess.remove_absolute(TEST_PATH)


func test_has_save_is_false_when_no_file_exists():
	assert_false(persistence.has_save(TEST_PATH))


func test_save_then_load_round_trips_a_real_store():
	var store := ContractStore.new()
	var contract := store.propose("rent", ["household:1"], ["10 wood/week"], "shelter", -1.0, 1.0)
	store.accept(contract.id, 2.0)

	persistence.save(store, TEST_PATH)
	var restored: ContractStore = persistence.load_store(TEST_PATH)

	assert_eq(restored.get_contract(contract.id).status, Contract.ACCEPTED)
	assert_eq(restored.contracts_for("household:1").size(), 1)


func test_loading_with_no_save_file_returns_an_empty_store():
	var restored: ContractStore = persistence.load_store(TEST_PATH)
	assert_eq(restored.contracts_for("household:1"), [])


func test_wipe_removes_an_existing_save():
	persistence.save(ContractStore.new(), TEST_PATH)
	persistence.wipe(TEST_PATH)
	assert_false(persistence.has_save(TEST_PATH))


func test_wipe_on_a_missing_save_does_not_error():
	persistence.wipe(TEST_PATH)
	assert_false(persistence.has_save(TEST_PATH))
