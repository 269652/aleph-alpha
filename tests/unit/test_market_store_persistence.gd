extends GutTest

## MarketStorePersistence: pure I/O for the emergence market store -- mirrors
## EventStorePersistence/.../ContractStorePersistence/PlayerSave's role
## exactly.

const MarketStorePersistence = preload("res://src/emergence/market_store_persistence.gd")
const MarketStore = preload("res://src/emergence/market_store.gd")

const TEST_PATH := "user://test_market_store.bin"

var persistence: MarketStorePersistence


func before_each():
	persistence = MarketStorePersistence.new()


func after_each():
	if FileAccess.file_exists(TEST_PATH):
		DirAccess.remove_absolute(TEST_PATH)


func test_has_save_is_false_when_no_file_exists():
	assert_false(persistence.has_save(TEST_PATH))


func test_save_then_load_round_trips_a_real_store():
	var store := MarketStore.new()
	store.market_for("settlement:0_0").add_stock("wood", 5)

	persistence.save(store, TEST_PATH)
	var restored: MarketStore = persistence.load_store(TEST_PATH)

	assert_eq(restored.market_for("settlement:0_0").stock_of("wood"), 5)


func test_loading_with_no_save_file_returns_an_empty_store():
	var restored: MarketStore = persistence.load_store(TEST_PATH)
	assert_eq(restored.market_for("settlement:0_0").stock_of("wood"), 0)


func test_wipe_removes_an_existing_save():
	persistence.save(MarketStore.new(), TEST_PATH)
	persistence.wipe(TEST_PATH)
	assert_false(persistence.has_save(TEST_PATH))


func test_wipe_on_a_missing_save_does_not_error():
	persistence.wipe(TEST_PATH)
	assert_false(persistence.has_save(TEST_PATH))
