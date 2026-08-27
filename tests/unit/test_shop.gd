extends GutTest

## Shop: a merchant's goods for sale (docs/concept/npc.md's villages /
## docs/concept/economy.md's "Selling to the market"). Phase 1
## simplification: one fixed shared catalog every merchant sells from, not a
## per-NPC inventory -- see docs/progress.md's NPC section.

const Shop = preload("res://src/gameplay/shop.gd")
const Wallet = preload("res://src/gameplay/wallet.gd")
const Inventory = preload("res://src/gameplay/inventory.gd")
const ItemCatalog = preload("res://src/gameplay/item_catalog.gd")

var shop := Shop.new()
var catalog := ItemCatalog.new()


func test_known_item_ids_are_all_real_catalog_items():
	for item_id in shop.known_item_ids():
		assert_true(catalog.has(item_id), "shop sells an unknown item id: %s" % item_id)


func test_price_of_a_known_item_is_positive():
	for item_id in shop.known_item_ids():
		assert_gt(shop.price_of(item_id), 0)


func test_price_of_an_unknown_item_is_zero():
	assert_eq(shop.price_of("not_a_real_item"), 0)


func test_can_afford_true_when_wallet_covers_the_price():
	var item_id: String = shop.known_item_ids()[0]
	assert_true(shop.can_afford(shop.price_of(item_id), item_id))


func test_can_afford_false_when_wallet_is_short():
	var item_id: String = shop.known_item_ids()[0]
	assert_false(shop.can_afford(shop.price_of(item_id) - 1, item_id))


func test_buy_deducts_the_price_and_adds_the_item():
	var item_id: String = shop.known_item_ids()[0]
	var wallet := Wallet.new()
	wallet.add(shop.price_of(item_id) + 100)
	var inventory := Inventory.new(12)

	assert_true(shop.buy(wallet, inventory, catalog, item_id))

	assert_eq(wallet.balance, 100)
	assert_eq(inventory.count_of(item_id), 1)


func test_buy_fails_and_changes_nothing_when_unaffordable():
	var item_id: String = shop.known_item_ids()[0]
	var wallet := Wallet.new()
	wallet.add(shop.price_of(item_id) - 1)
	var inventory := Inventory.new(12)

	assert_false(shop.buy(wallet, inventory, catalog, item_id))

	assert_eq(wallet.balance, shop.price_of(item_id) - 1)
	assert_eq(inventory.count_of(item_id), 0)


func test_buy_fails_for_an_unknown_item():
	var wallet := Wallet.new()
	wallet.add(1000)
	assert_false(shop.buy(wallet, Inventory.new(12), catalog, "not_a_real_item"))


# -- prices come from the local market ----------------------------------------
#
# The shop's CATALOG is the BASE price in absolute gold; Market.price_for is a
# dimensionless scarcity multiplier that is exactly 1.0 at Market.REFERENCE_STOCK
# (see src/emergence/market.gd). So the seam is one multiplication and invents
# no new number: a village with reference stock charges precisely what the flat
# catalog charged before, and every deviation from that is a real shortage or a
# real glut the simulation produced.
#
# This is docs/emergence/03-contracts-property-economy.md's "Do not use one
# global price", which the flat catalog was the last violation of.

const Market = preload("res://src/emergence/market.gd")


func _market_with(item_id: String, stock: int) -> Market:
	var market := Market.new()
	market.add_stock(item_id, stock)
	return market


## The backwards-compatibility anchor, and the reason no number had to be
## invented: at the neutral stock level the market price IS the catalog price.
func test_at_reference_stock_the_market_price_is_the_catalog_price():
	for item_id in shop.known_item_ids():
		var market := _market_with(item_id, Market.REFERENCE_STOCK)
		assert_eq(shop.market_price_of(item_id, market), shop.price_of(item_id))


func test_scarcity_raises_the_price_above_the_catalog():
	var market := _market_with("iron_sword", Market.REFERENCE_STOCK / 4)
	assert_gt(shop.market_price_of("iron_sword", market), shop.price_of("iron_sword"))


func test_a_glut_lowers_the_price_below_the_catalog():
	var market := _market_with("iron_sword", Market.REFERENCE_STOCK * 4)
	assert_lt(shop.market_price_of("iron_sword", market), shop.price_of("iron_sword"))


## Two villages, two stock levels, two prices for the same sword -- which is
## the whole point: where you shop starts to matter.
func test_two_markets_with_different_stock_charge_different_prices():
	var scarce := _market_with("iron_sword", 2)
	var flush := _market_with("iron_sword", 60)
	assert_gt(shop.market_price_of("iron_sword", scarce), shop.market_price_of("iron_sword", flush))


## No market (no settlement nearby, or a merchant not tied to one) falls back
## to the flat catalog rather than to free goods.
func test_without_a_market_the_price_is_the_catalog_price():
	for item_id in shop.known_item_ids():
		assert_eq(shop.market_price_of(item_id, null), shop.price_of(item_id))


func test_market_price_of_an_unknown_item_is_zero():
	assert_eq(shop.market_price_of("not_a_real_item", _market_with("not_a_real_item", 5)), 0)


# -- buying is a real transaction against real stock --------------------------

func test_buying_at_a_market_charges_the_market_price_not_the_catalog_price():
	var market := _market_with("iron_sword", 2)
	var wallet := Wallet.new()
	wallet.add(10000)
	var before := wallet.balance
	# Read the price BEFORE buying: the purchase itself draws stock down, which
	# moves the price -- asking again afterwards would be quoting the next
	# customer's price, not the one just paid.
	var expected := shop.market_price_of("iron_sword", market)
	assert_gt(expected, shop.price_of("iron_sword"), "precondition: scarce here")
	assert_true(shop.buy(wallet, Inventory.new(12), catalog, "iron_sword", market))
	assert_eq(before - wallet.balance, expected)


## docs/emergence/03's invariant 4, "Money does not create physical goods":
## a purchase takes the item OUT of the market it came from.
func test_buying_draws_the_item_out_of_the_markets_stock():
	var market := _market_with("iron_sword", 10)
	var wallet := Wallet.new()
	wallet.add(10000)
	shop.buy(wallet, Inventory.new(12), catalog, "iron_sword", market)
	assert_eq(market.stock_of("iron_sword"), 9)


## Same invariant from the other side: you cannot buy what is not there, at
## any price. A sold-out village is a real reason to travel.
func test_an_item_the_market_has_none_of_cannot_be_bought():
	var market := _market_with("iron_sword", 0)
	var wallet := Wallet.new()
	wallet.add(10000)
	var before := wallet.balance
	assert_false(shop.buy(wallet, Inventory.new(12), catalog, "iron_sword", market))
	assert_eq(wallet.balance, before, "a failed purchase must not spend anything")


func test_buying_without_a_market_still_works_at_the_catalog_price():
	var wallet := Wallet.new()
	wallet.add(10000)
	var before := wallet.balance
	assert_true(shop.buy(wallet, Inventory.new(12), catalog, "iron_sword"))
	assert_eq(before - wallet.balance, shop.price_of("iron_sword"))


func test_cannot_afford_the_market_price_means_no_purchase():
	var market := _market_with("iron_sword", 1)
	var wallet := Wallet.new()
	wallet.add(shop.price_of("iron_sword"))  # enough at catalog, not at scarcity
	assert_false(shop.buy(wallet, Inventory.new(12), catalog, "iron_sword", market))
	assert_eq(market.stock_of("iron_sword"), 1, "a failed purchase must not move stock")


# -- a merchant has real stock ------------------------------------------------
#
# MarketStore.market_for creates a fresh EMPTY market on first access, and an
# empty market prices at Market.REFERENCE_STOCK / 1 = 20x. Wiring the shop to
# the market without stocking it would therefore not add scarcity pricing, it
# would multiply every price in the game by twenty. A merchant who sells
# swords has swords; that is what makes the neutral price neutral.

func test_a_freshly_stocked_market_prices_exactly_at_the_catalog():
	var market := Market.new()
	shop.stock_initial_goods(market)
	for item_id in shop.known_item_ids():
		assert_eq(
			shop.market_price_of(item_id, market), shop.price_of(item_id),
			"a newly stocked merchant must charge the plain catalog price for %s" % item_id
		)


func test_stocking_initial_goods_covers_every_item_the_shop_sells():
	var market := Market.new()
	shop.stock_initial_goods(market)
	for item_id in shop.known_item_ids():
		assert_gt(market.stock_of(item_id), 0, "merchant has no %s to sell" % item_id)


## Idempotent like every other _if_new/form_* in this codebase: stocking a
## market twice must not double a merchant's goods, or founding logic running
## again would quietly halve the town's prices.
func test_stocking_a_market_twice_does_not_double_the_stock():
	var market := Market.new()
	shop.stock_initial_goods(market)
	var after_first := market.stock_of("iron_sword")
	shop.stock_initial_goods(market)
	assert_eq(market.stock_of("iron_sword"), after_first)


## The payoff, end to end: clear a merchant out and the price climbs for what
## is left. Prices respond to what the player actually did.
func test_buying_a_merchant_out_raises_the_price_of_what_remains():
	var market := Market.new()
	shop.stock_initial_goods(market)
	var wallet := Wallet.new()
	wallet.add(1000000)
	var inventory := Inventory.new(64)
	var opening := shop.market_price_of("iron_sword", market)

	for _i in 15:
		shop.buy(wallet, inventory, catalog, "iron_sword", market)

	assert_gt(
		shop.market_price_of("iron_sword", market), opening,
		"buying most of a merchant's swords should make the rest dearer"
	)
