extends GutTest

## SettlementFood: one settlement's REAL total food stock, summed across BOTH
## of the two unrelated things this project calls "the market" -- the
## persisted emergence Market (see market.gd, MarketStore) and the live
## VillageMarket villagers actually eat out of (see village_market.gd,
## NpcEconomy).
##
## SettlementState.food_stock reads only the FIRST of those, and nothing in
## live play ever stocks it, so every settlement's carrying capacity is 0 and
## every settlement classifies DECLINING forever (see
## EarthChunkManager.step_settlements). Meanwhile real villagers really do
## gather real food into the OTHER market every day (NpcProduction) and the
## player really does sell food into it (Player.sell_food_to_village) -- that
## stock exists, it was simply invisible to the classification.
##
## SettlementState itself is deliberately left exactly as it is: its
## food_stock keeps its current "the emergence Market's food" meaning, and
## this module is the new capacity source callers use instead.

const Market = preload("res://src/emergence/market.gd")
const VillageMarket = preload("res://src/world/village_market.gd")
const SettlementState = preload("res://src/emergence/settlement_state.gd")
const SettlementFood = preload("res://src/emergence/settlement_food.gd")
const EntityRef = preload("res://src/emergence/entity_ref.gd")
const StructureStock = preload("res://src/emergence/structure_stock.gd")


## Stand-ins for a spawned NpcMarker and its NpcEconomy. The only thing
## SettlementFood ever reads off a spawned village node is
## `node.economy.market`, so the test builds exactly that shape -- a real
## villager would mean a real EarthChunkManager, whose single update() costs
## ~60 seconds.
class FakeEconomy extends RefCounted:
	var market

	func _init(village_market = null) -> void:
		market = village_market


class FakeVillager extends RefCounted:
	var economy

	func _init(fake_economy = null) -> void:
		economy = fake_economy


## A landmark/prop node: VillageRenderer.spawn_village returns these in the
## same Array as its villagers, and they have no `economy` at all.
class FakeProp extends RefCounted:
	pass


func _villager_with_market(village_market) -> FakeVillager:
	return FakeVillager.new(FakeEconomy.new(village_market))


# -- food_stock sums BOTH markets -------------------------------------------

func test_food_stock_sums_the_emergence_market_and_the_live_village_market():
	var market := Market.new()
	market.add_stock("meat", 5)
	var village := VillageMarket.new()
	village.add_stock("fruit", 3.0)
	assert_eq(SettlementFood.food_stock(market, village), 8)


func test_settlement_states_own_food_stock_still_sees_only_the_emergence_market():
	# SettlementState is untouched by this slice: the same two markets that
	# read as 8 above must still read as 5 through the old accessor, so
	# nothing already depending on its meaning silently changes.
	var market := Market.new()
	market.add_stock("meat", 5)
	var village := VillageMarket.new()
	village.add_stock("fruit", 3.0)
	assert_eq(SettlementState.food_stock(market), 5)
	assert_eq(SettlementFood.food_stock(market, village), 8)


func test_food_stock_counts_only_food_typed_village_stock():
	# A VillageMarket also holds construction lumber (see its own
	# remove_stock doc comment) -- beams must not feed anybody.
	var village := VillageMarket.new()
	village.add_stock("fruit", 2.0)
	village.add_stock("beam", 10.0)
	assert_eq(SettlementFood.food_stock(null, village), 2)


func test_food_stock_ignores_an_unknown_village_item_id():
	var village := VillageMarket.new()
	village.add_stock("not_a_real_item", 5.0)
	assert_eq(SettlementFood.food_stock(null, village), 0)


# -- either market may be absent --------------------------------------------

func test_food_stock_handles_an_absent_emergence_market():
	var village := VillageMarket.new()
	village.add_stock("fruit", 4.0)
	assert_eq(SettlementFood.food_stock(null, village), 4)


func test_food_stock_handles_an_absent_village_market():
	var market := Market.new()
	market.add_stock("meat", 5)
	assert_eq(SettlementFood.food_stock(market, null), 5)


func test_food_stock_of_two_absent_markets_is_zero():
	assert_eq(SettlementFood.food_stock(null, null), 0)


# -- village stock is float, and only WHOLE meals feed anyone ----------------

func test_a_village_stock_below_one_whole_meal_feeds_nobody():
	# VillageMarket.buy_meal only ever draws from an item holding a whole
	# FOOD_UNITS_PER_MEAL, so half a fruit is not half a household's food --
	# it is nobody's.
	var village := VillageMarket.new()
	village.add_stock("fruit", VillageMarket.FOOD_UNITS_PER_MEAL * 0.5)
	assert_eq(SettlementFood.food_stock(null, village), 0)


func test_partial_units_of_two_different_foods_do_not_add_up_to_a_meal():
	var village := VillageMarket.new()
	village.add_stock("fruit", VillageMarket.FOOD_UNITS_PER_MEAL * 0.5)
	village.add_stock("meat", VillageMarket.FOOD_UNITS_PER_MEAL * 0.5)
	assert_eq(SettlementFood.food_stock(null, village), 0)


func test_whole_meals_count_and_the_leftover_fraction_does_not():
	var village := VillageMarket.new()
	village.add_stock("fruit", VillageMarket.FOOD_UNITS_PER_MEAL * 2.5)
	assert_eq(SettlementFood.food_stock(null, village), 2)


# -- carrying_capacity reuses SettlementState's own real constant ------------

func test_carrying_capacity_divides_by_settlement_states_own_food_per_household():
	var village := VillageMarket.new()
	# Whole meals: _village_food_stock counts whole FOOD_UNITS_PER_MEAL per
	# item (half a fruit feeds nobody), and the per-household draw is a
	# measured 1.2 rather than a whole number -- so carrying three households
	# takes the next whole unit up from 3.6, not 3.6 itself.
	village.add_stock("fruit", ceil(SettlementState.FOOD_PER_HOUSEHOLD * 3.0))
	assert_eq(SettlementFood.carrying_capacity(null, village), 3)


func test_carrying_capacity_of_two_absent_markets_is_zero():
	assert_eq(SettlementFood.carrying_capacity(null, null), 0)


# -- the actual behaviour change this module exists for ----------------------

func test_a_settlement_fed_only_by_its_village_market_stops_declining():
	var emergence_market := Market.new()  # never stocked in live play -- the bug
	var village := VillageMarket.new()
	var household_count := 2
	village.add_stock("fruit", float(SettlementState.FOOD_PER_HOUSEHOLD * household_count * 3))

	var old_capacity := SettlementState.carrying_capacity(emergence_market)
	assert_eq(
		SettlementState.status_for(household_count, old_capacity),
		SettlementState.DECLINING,
		"the old emergence-market-only path sees no food at all"
	)

	var new_capacity := SettlementFood.carrying_capacity(emergence_market, village)
	assert_eq(
		SettlementState.status_for(household_count, new_capacity),
		SettlementState.GROWING,
		"the food the villagers really gathered is real headroom"
	)


func test_a_settlement_with_exactly_enough_village_food_reads_stable():
	var household_count := 4
	var village := VillageMarket.new()
	village.add_stock("fruit", ceil(SettlementState.FOOD_PER_HOUSEHOLD * float(household_count)))
	var capacity := SettlementFood.carrying_capacity(Market.new(), village)
	assert_eq(SettlementState.status_for(household_count, capacity), SettlementState.STABLE)


func test_a_settlement_with_no_food_in_either_market_still_declines():
	# Summing both markets must not turn DECLINING into an unreachable
	# label: a genuinely starving settlement still declines.
	var capacity := SettlementFood.carrying_capacity(Market.new(), VillageMarket.new())
	assert_eq(SettlementState.status_for(2, capacity), SettlementState.DECLINING)


# -- finding a settlement's live VillageMarket among the loaded villages -----

func test_village_market_for_finds_the_market_of_that_settlements_own_chunk():
	var chunk := Vector2i(3, -7)
	var village := VillageMarket.new()
	var loaded := {chunk: [_villager_with_market(village)]}
	assert_eq(SettlementFood.village_market_for(EntityRef.for_settlement(chunk), loaded), village)


func test_village_market_for_ignores_another_settlements_chunk():
	var loaded := {Vector2i(1, 1): [_villager_with_market(VillageMarket.new())]}
	assert_null(SettlementFood.village_market_for(EntityRef.for_settlement(Vector2i(3, -7)), loaded))


func test_village_market_for_is_null_when_the_chunk_is_not_loaded():
	assert_null(SettlementFood.village_market_for(EntityRef.for_settlement(Vector2i(0, 0)), {}))


func test_village_market_for_skips_spawned_nodes_that_are_not_villagers():
	var chunk := Vector2i(2, 2)
	var village := VillageMarket.new()
	var loaded := {chunk: [FakeProp.new(), _villager_with_market(village)]}
	assert_eq(SettlementFood.village_market_for(EntityRef.for_settlement(chunk), loaded), village)


func test_village_market_for_is_null_when_no_villager_has_a_market_yet():
	var chunk := Vector2i(2, 2)
	var loaded := {chunk: [FakeVillager.new(null), _villager_with_market(null)]}
	assert_null(SettlementFood.village_market_for(EntityRef.for_settlement(chunk), loaded))


# -- structure-held food: the third container (docs/concept/milling_and_ ---
# -- baking.md, "Food that counts") ------------------------------------------
#
## Bread a Bakery bakes, or a Storage holds once hauled, lives in a
## structure's own StructureStock -- neither market. It is real food the
## settlement owns, so it counts, filtered through the SAME catalog category
## as both markets (a Storage also holds lumber and wheat; neither feeds
## anyone).

func _stock_with(items: Dictionary) -> StructureStock:
	var stock := StructureStock.new()
	for item_id in items:
		stock.add_stock(item_id, items[item_id])
	return stock


func test_food_stock_counts_food_held_in_the_settlements_structures():
	var storage := _stock_with({"bread": 8, "wood": 20, "wheat": 12})
	var bakery := _stock_with({"bread": 3, "flour": 4})
	assert_eq(SettlementFood.food_stock(null, null, null, [storage, bakery]), 11)


func test_structure_food_adds_to_both_markets():
	var market := Market.new()
	market.add_stock("meat", 5)
	var village := VillageMarket.new()
	village.add_stock("fruit", 3.0)
	var storage := _stock_with({"bread": 8})
	assert_eq(SettlementFood.food_stock(market, village, null, [storage]), 16)
	assert_eq(
		SettlementFood.carrying_capacity(market, village, null, [storage]),
		int(16.0 / SettlementState.FOOD_PER_HOUSEHOLD)
	)


func test_no_structures_at_all_changes_nothing():
	var market := Market.new()
	market.add_stock("meat", 5)
	assert_eq(SettlementFood.food_stock(market, null, null, []), 5)
	assert_eq(SettlementFood.food_stock(market, null), 5)


# -- the food shortfall the build decision can act on ------------------------
#
## A DECLINING settlement is short of the one food it can raise by
## construction: bread (its chain is resolver data -- farm/mill/bakery;
## meat/fruit/fish are gathered by occupations, never built). The need is
## exactly the loaves that lift the settlement out of DECLINING, so the
## decision asks for a real, bounded amount rather than "some food".

func test_no_food_shortfall_while_the_settlement_is_not_declining():
	var market := Market.new()
	market.add_stock("meat", 40)  # capacity 10 for 5 households: GROWING
	assert_eq(SettlementFood.food_shortfall_for(5, market, null), {})


func test_no_food_shortfall_for_a_settlement_with_no_households():
	assert_eq(SettlementFood.food_shortfall_for(0, null, null), {})


func test_a_declining_settlement_is_short_of_bread_by_exactly_what_lifts_it_out():
	var market := Market.new()
	market.add_stock("meat", 4)  # capacity 1 for 5 households: DECLINING
	var shortfall: Dictionary = SettlementFood.food_shortfall_for(5, market, null)

	assert_eq(shortfall.get("missing", [])[0]["item_id"], SettlementFood.STAPLE_FOOD_ID)
	var need: int = shortfall["missing"][0]["need"]
	assert_gt(need, 0)
	# Exactly enough: with that many more loaves the settlement is no longer
	# DECLINING, and with one fewer it still is.
	var enough := Market.new()
	enough.add_stock("meat", 4)
	enough.add_stock("bread", need)
	assert_ne(SettlementState.status_for(5, SettlementFood.carrying_capacity(enough, null)), SettlementState.DECLINING)
	var one_short := Market.new()
	one_short.add_stock("meat", 4)
	one_short.add_stock("bread", need - 1)
	assert_eq(SettlementState.status_for(5, SettlementFood.carrying_capacity(one_short, null)), SettlementState.DECLINING)


func test_the_food_shortfall_carries_the_shape_the_build_decision_reads():
	var shortfall: Dictionary = SettlementFood.food_shortfall_for(3, null, null)
	assert_true(shortfall.has("missing"))
	assert_eq(shortfall["missing"].size(), 1)
	assert_true(shortfall["missing"][0].has("item_id"))
	assert_true(shortfall["missing"][0].has("need"))
	assert_eq(shortfall.get("kind"), "food")


func test_structure_held_bread_counts_toward_clearing_the_shortfall():
	var storage := _stock_with({"bread": 40})
	assert_eq(SettlementFood.food_shortfall_for(5, null, null, null, [storage]), {})
