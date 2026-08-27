extends GutTest

## See docs/concept/player_trade.md's "Getting a real price" -- the
## player transacts against the exact same real Market every NPC
## producer/consumer already reads and moves, with a real buy/sell spread
## around Market.price_for rather than a parallel player-only price table.

const PlayerTradeOffer = preload("res://src/emergence/player_trade_offer.gd")
const Market = preload("res://src/emergence/market.gd")

var market: Market


func before_each():
	market = Market.new()


func test_sell_price_is_below_the_neutral_market_price():
	market.add_stock("wood", 20)  # REFERENCE_STOCK -- neutral price 1.0
	var neutral := market.price_for("wood")
	assert_lt(PlayerTradeOffer.sell_price_for(market, "wood"), neutral)


func test_buy_price_is_above_the_neutral_market_price():
	market.add_stock("wood", 20)
	var neutral := market.price_for("wood")
	assert_gt(PlayerTradeOffer.buy_price_for(market, "wood"), neutral)


## The spread itself is a tested, pinned constant, not an eyeballed
## comment -- exact factors asserted here rather than just "less than"/
## "greater than", so a change to either constant is a deliberate,
## visible test update.
func test_sell_price_applies_the_exact_pinned_markup_factor():
	market.add_stock("wood", 20)
	var neutral := market.price_for("wood")
	assert_almost_eq(
		PlayerTradeOffer.sell_price_for(market, "wood"),
		neutral * PlayerTradeOffer.SELL_MARKUP_FACTOR,
		0.0001
	)


func test_buy_price_applies_the_exact_pinned_markup_factor():
	market.add_stock("wood", 20)
	var neutral := market.price_for("wood")
	assert_almost_eq(
		PlayerTradeOffer.buy_price_for(market, "wood"),
		neutral * PlayerTradeOffer.BUY_MARKUP_FACTOR,
		0.0001
	)


## A round trip (sell then immediately buy back the same item at the same
## settlement) must not be free money -- the buy price must exceed the
## sell price even at identical stock, or a player could arbitrage a
## single village infinitely.
func test_buy_price_always_exceeds_sell_price_at_the_same_stock():
	market.add_stock("wood", 20)
	assert_gt(
		PlayerTradeOffer.buy_price_for(market, "wood"),
		PlayerTradeOffer.sell_price_for(market, "wood")
	)


func test_can_sell_is_true_for_any_positive_count():
	assert_true(PlayerTradeOffer.can_sell(market, "wood", 5))


func test_can_sell_is_false_for_a_non_positive_count():
	assert_false(PlayerTradeOffer.can_sell(market, "wood", 0))


func test_can_buy_is_true_when_the_settlement_has_enough_stock():
	market.add_stock("wood", 10)
	assert_true(PlayerTradeOffer.can_buy(market, "wood", 5))


## A settlement's real stock is a real structural limit -- the player
## can't buy out goods that don't exist there yet, the same "no phantom
## output" discipline StructureStock.remove_stock already enforces.
func test_can_buy_is_false_when_the_settlement_lacks_enough_stock():
	market.add_stock("wood", 3)
	assert_false(PlayerTradeOffer.can_buy(market, "wood", 5))


func test_can_buy_is_false_for_an_item_with_no_stock_at_all():
	assert_false(PlayerTradeOffer.can_buy(market, "wood", 1))


func test_can_buy_is_false_for_a_non_positive_count():
	market.add_stock("wood", 10)
	assert_false(PlayerTradeOffer.can_buy(market, "wood", 0))
