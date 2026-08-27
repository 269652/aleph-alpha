extends GutTest

## See docs/concept/player_trade.md's "Settlement discovery" -- a
## settlement is a real, permanent trading partner once discovered, the
## same "once explored, always explored" persistence ExploredTiles
## already uses.

const DiscoveredSettlements = preload("res://src/emergence/discovered_settlements.gd")

var store: DiscoveredSettlements


func before_each():
	store = DiscoveredSettlements.new()


func test_an_undiscovered_settlement_is_not_discovered():
	assert_false(store.is_discovered("settlement:1"))


func test_mark_discovered_makes_it_discovered():
	store.mark_discovered("settlement:1", 100.0)
	assert_true(store.is_discovered("settlement:1"))


func test_discovered_at_reports_the_world_age_it_was_first_discovered():
	store.mark_discovered("settlement:1", 100.0)
	assert_eq(store.discovered_at("settlement:1"), 100.0)


func test_discovered_at_on_an_undiscovered_settlement_is_negative():
	assert_lt(store.discovered_at("settlement:1"), 0.0)


## Once explored, always explored -- a settlement's discovery moment is
## real history, not a value a later query call can retroactively change.
func test_marking_discovered_again_does_not_overwrite_the_original_world_age():
	store.mark_discovered("settlement:1", 100.0)
	store.mark_discovered("settlement:1", 500.0)
	assert_eq(store.discovered_at("settlement:1"), 100.0)


func test_discovered_ids_lists_every_discovered_settlement():
	store.mark_discovered("settlement:1", 100.0)
	store.mark_discovered("settlement:2", 200.0)
	var ids := store.discovered_ids()
	assert_eq(ids.size(), 2)
	assert_true(ids.has("settlement:1"))
	assert_true(ids.has("settlement:2"))


func test_discovered_ids_is_empty_for_a_fresh_store():
	assert_eq(store.discovered_ids(), [])


func test_to_dict_and_from_dict_round_trip():
	store.mark_discovered("settlement:1", 100.0)
	store.mark_discovered("settlement:2", 200.0)
	var restored := DiscoveredSettlements.from_dict(store.to_dict())
	assert_true(restored.is_discovered("settlement:1"))
	assert_eq(restored.discovered_at("settlement:2"), 200.0)
