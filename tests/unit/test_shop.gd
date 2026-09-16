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


## docs/concept/workforce.md's own "Selling it" section: the first blueprint
## goes into this SAME flat catalog every merchant already sells from --
## deliberately no second merchant type or stocking mechanism yet, matching
## this file's own documented "Phase 1 simplification" exactly.
func test_shop_sells_the_first_house_blueprint():
	assert_true(shop.known_item_ids().has("blueprint_small_house"))


func test_shop_sells_the_cottage_blueprint():
	assert_true(shop.known_item_ids().has("blueprint_cottage"))


func test_shop_sells_the_manor_blueprint():
	assert_true(shop.known_item_ids().has("blueprint_manor"))


## A merchant never sells a blueprint the player cannot actually build
## (docs/concept/building.md "Player building re-route": the ten two-story
## blueprints have no whole-building form yet, so they leave the shelf
## until the catalog grows one) -- every blueprint on sale maps to a real
## catalog house.
func test_every_blueprint_on_sale_raises_a_real_whole_building():
	var EarthChunkManager = load("res://src/world/earth_chunk_manager.gd")
	var found := 0
	for item_id in shop.known_item_ids():
		if catalog.kind_of(item_id) != "blueprint":
			continue
		found += 1
		var recipe_id: String = EarthChunkManager.BLUEPRINT_RECIPE_BY_ITEM_ID.get(item_id, "")
		assert_ne(EarthChunkManager.BUILDING_ID_BY_RECIPE_ID.get(recipe_id, ""), "", "%s has no whole-building form" % item_id)
	assert_eq(found, 3, "exactly the three buildable tiers are on sale")


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


# -- selling: the other half of the faucet -------------------------------------
#
# concept/economy.md's "Selling to the market" currency faucet. Buying already
# reads the local price and draws stock down; selling is its mirror -- it pays
# the local price and pushes stock UP, which lowers what the next unit fetches.
# That is the whole strategic point: flood one village with one good and you
# crash what it pays you for the next.
#
# The merchant buys low and sells high, like every merchant. The spread is not
# asserted as a number anywhere -- it is pinned by the property that matters,
# that you can never make money going round the loop.

func _stocked_market() -> Market:
	var market := Market.new()
	shop.stock_initial_goods(market)
	return market


func test_a_merchant_pays_less_than_they_charge():
	var market := _stocked_market()
	for item_id in shop.known_item_ids():
		assert_lt(shop.sell_price_of(item_id, market), shop.market_price_of(item_id, market))


## THE invariant, and the reason the spread constant is allowed to exist:
## buying a unit and immediately selling it back must lose money at EVERY
## stock level, or the shop is a money printer. Swept rather than spot-checked,
## because the ratio between adjacent prices is tightest at low stock -- the
## one place a plausible-looking spread silently breaks.
func test_buying_then_selling_back_always_loses_money():
	for stock in range(1, 41):
		var market := _market_with("iron_sword", stock)
		var wallet := Wallet.new()
		wallet.add(1000000)
		var inventory := Inventory.new(12)
		var before := wallet.balance
		assert_true(
			shop.buy(wallet, inventory, catalog, "iron_sword", market),
			"precondition: affordable at stock %d" % stock
		)
		assert_true(shop.sell(wallet, inventory, "iron_sword", market), "sell back at stock %d" % stock)
		assert_lt(
			wallet.balance, before,
			"buying and selling back at stock %d turned a profit" % stock
		)


func test_selling_credits_gold_and_removes_the_item():
	var market := _stocked_market()
	var wallet := Wallet.new()
	var inventory := Inventory.new(12)
	inventory.add(catalog.make("cooked_meat"), 1)
	var expected := shop.sell_price_of("cooked_meat", market)

	assert_true(shop.sell(wallet, inventory, "cooked_meat", market))

	assert_eq(wallet.balance, expected)
	assert_eq(inventory.count_of("cooked_meat"), 0)


## The mirror of "money does not create physical goods": selling a real item
## puts a real item into the village's stock, where the next buyer can find it.
func test_selling_puts_the_item_into_the_markets_stock():
	var market := _stocked_market()
	var before := market.stock_of("cooked_meat")
	var inventory := Inventory.new(12)
	inventory.add(catalog.make("cooked_meat"), 1)

	shop.sell(Wallet.new(), inventory, "cooked_meat", market)

	assert_eq(market.stock_of("cooked_meat"), before + 1)


func test_selling_something_you_do_not_have_fails_and_changes_nothing():
	var market := _stocked_market()
	var wallet := Wallet.new()
	var before := market.stock_of("iron_sword")
	assert_false(shop.sell(wallet, Inventory.new(12), "iron_sword", market))
	assert_eq(wallet.balance, 0)
	assert_eq(market.stock_of("iron_sword"), before)


## A merchant deals in what they deal in. Every other item in the game has no
## price anywhere -- Item carries no value field -- so buying it would mean
## inventing a number with nothing behind it.
func test_a_merchant_will_not_buy_what_they_do_not_deal_in():
	var market := _stocked_market()
	var inventory := Inventory.new(12)
	inventory.add(catalog.make("wood"), 1)
	assert_false(shop.sell(Wallet.new(), inventory, "wood", market))
	assert_eq(inventory.count_of("wood"), 1, "a refused sale must not consume the item")


## The payoff: dumping one good on one village drives down what it will pay.
func test_flooding_a_village_with_one_good_crashes_what_it_pays():
	var market := _stocked_market()
	var wallet := Wallet.new()
	var inventory := Inventory.new(64)
	inventory.add(catalog.make("cooked_meat"), 60)
	var first := shop.sell_price_of("cooked_meat", market)

	for _i in 40:
		shop.sell(wallet, inventory, "cooked_meat", market)

	assert_lt(
		shop.sell_price_of("cooked_meat", market), first,
		"forty units into one village should be worth less per unit than the first"
	)


## Scarcity cuts the other way too: a village short of something pays over the
## odds for it, which is what makes carrying goods somewhere worth the walk.
func test_a_village_short_of_something_pays_more_for_it():
	var scarce := _market_with("iron_sword", 2)
	var flush := _market_with("iron_sword", 60)
	assert_gt(shop.sell_price_of("iron_sword", scarce), shop.sell_price_of("iron_sword", flush))


func test_selling_without_a_market_pays_the_flat_catalog_spread():
	var wallet := Wallet.new()
	var inventory := Inventory.new(12)
	inventory.add(catalog.make("cooked_meat"), 1)
	assert_true(shop.sell(wallet, inventory, "cooked_meat", null))
	assert_eq(wallet.balance, shop.sell_price_of("cooked_meat", null))
	assert_gt(wallet.balance, 0, "a sale must be worth something even with no local market")

# -- food is sold, eaten, and gone; tools and blueprints are traded in ------
#
## Reported directly: "the food should be actually consumed and not stay at
## 20 cooked meat." stock_initial_goods used to refill ANY item that hit
## zero every time the player came near a merchant -- so the 20 cooked meat
## it seeds, which SettlementState counts as the village's own food stock,
## could never actually run out: a permanent five households of carrying
## capacity that nobody ever ate. Food is now seeded ONCE per market (the
## merchant's opening inventory, persisted as Market.shop_food_seeded) and
## never restocked by the shop again -- what the village eats is gone until
## its own economy (producers, the granary, trade, the bakehouse) replaces
## it, and its price climbs with scarcity like everything else. Tools and
## blueprints keep restocking when sold out: the merchant trades those in
## from afar, and nothing else in the game supplies them.

func test_food_is_seeded_once_and_never_restocked_by_the_shop():
	var market := Market.new()
	shop.stock_initial_goods(market)
	assert_eq(market.stock_of("cooked_meat"), Market.REFERENCE_STOCK, "the merchant arrives with meat")
	assert_true(market.remove_stock("cooked_meat", Market.REFERENCE_STOCK), "the village eats all of it")

	shop.stock_initial_goods(market)

	assert_eq(market.stock_of("cooked_meat"), 0, "eaten food stays eaten -- the shop does not conjure more")


func test_tools_and_blueprints_still_restock_when_sold_out():
	var market := Market.new()
	shop.stock_initial_goods(market)
	assert_true(market.remove_stock("torch", Market.REFERENCE_STOCK))
	shop.stock_initial_goods(market)
	assert_eq(market.stock_of("torch"), Market.REFERENCE_STOCK, "traded in from afar")


func test_the_food_seed_survives_a_save_and_reload():
	var market := Market.new()
	shop.stock_initial_goods(market)
	market.remove_stock("cooked_meat", Market.REFERENCE_STOCK)
	var restored = Market.from_dict(market.to_dict())
	shop.stock_initial_goods(restored)
	assert_eq(restored.stock_of("cooked_meat"), 0, "a reload must not reset the merchant's larder")
