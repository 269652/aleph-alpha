extends GutTest

## SettlementState: carrying capacity and growth/decline status (see
## docs/emergence/04-settlements-cities-infrastructure.md "Carrying
## capacity": "Population capacity depends on food, water, housing, jobs,
## sanitation, security, transport, trade, climate, and disease. Population
## should move toward capacity rather than use arbitrary growth").
##
## Deliberately FOOD-only for this first slice (avoid premature complexity):
## food is the one input this project already has live, real data for (via
## Market, Phase 5) -- water/housing/job/sanitation simulation do not exist
## yet either, so deriving capacity from them would mean inventing the very
## systems this slice is trying to avoid inventing.

const Market = preload("res://src/emergence/market.gd")
const SettlementState = preload("res://src/emergence/settlement_state.gd")


# -- food_stock reads real market stock, not a synthetic total --------------

func test_food_stock_sums_only_food_typed_items():
	var market := Market.new()
	market.add_stock("meat", 5)
	market.add_stock("apple", 3)
	market.add_stock("wood", 100)  # a material, not food -- must not count
	assert_eq(SettlementState.food_stock(market), 8)


func test_food_stock_of_an_empty_market_is_zero():
	assert_eq(SettlementState.food_stock(Market.new()), 0)


func test_food_stock_ignores_an_unknown_item_id():
	var market := Market.new()
	market.add_stock("not_a_real_item", 5)
	assert_eq(SettlementState.food_stock(market), 0)


# -- carrying_capacity is derived from food, not a flat constant -------------

func test_carrying_capacity_of_an_empty_market_is_zero():
	assert_eq(SettlementState.carrying_capacity(Market.new()), 0)


func test_carrying_capacity_rises_with_more_food():
	var market := Market.new()
	market.add_stock("meat", SettlementState.FOOD_PER_HOUSEHOLD * 3)
	assert_eq(SettlementState.carrying_capacity(market), 3)


# -- status_for classifies growth/decline, with a dead band to avoid flicker -

func test_status_is_growing_well_below_capacity():
	assert_eq(SettlementState.status_for(1, 10), SettlementState.GROWING)


func test_status_is_declining_well_above_capacity():
	assert_eq(SettlementState.status_for(10, 1), SettlementState.DECLINING)


func test_status_is_stable_right_at_capacity():
	assert_eq(SettlementState.status_for(5, 5), SettlementState.STABLE)


## An empty settlement with no food and no households is not "declining" --
## there is nothing there yet to be under pressure.
func test_status_with_no_food_and_no_households_is_stable_not_declining():
	assert_eq(SettlementState.status_for(0, 0), SettlementState.STABLE)


## Households with genuinely zero food IS real pressure -- a village that
## exists but has nothing to eat is declining, not merely "at capacity."
func test_status_with_households_but_zero_food_is_declining():
	assert_eq(SettlementState.status_for(3, 0), SettlementState.DECLINING)


func test_every_documented_status_exists():
	var expected := ["growing", "stable", "declining"]
	for status in expected:
		assert_true(SettlementState.STATUSES.has(status), "missing status: %s" % status)
