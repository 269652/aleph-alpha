extends GutTest

## VillageMarket (docs/concept/npc.md "Local trade is NPC-to-NPC, not just
## player-to-shop"): one SETTLEMENT's real local food stock and price --
## distinct from shop.gd's fixed global player-facing catalog. A producer's
## real gathered surplus (see NpcProduction) feeds add_stock; a hungry
## non-producer NPC's own Wallet pays buy_meal.

const VillageMarket = preload("res://src/world/village_market.gd")
const Wallet = preload("res://src/gameplay/wallet.gd")

var market: VillageMarket


func before_each():
	market = VillageMarket.new()


func test_starts_with_no_stock():
	assert_eq(market.total_stock(), 0.0)
	assert_false(market.can_buy_meal())


func test_add_stock_accumulates_by_item_id():
	market.add_stock("meat", 1.5)
	market.add_stock("meat", 0.5)
	market.add_stock("fish", 2.0)
	assert_almost_eq(market.stock["meat"], 2.0, 0.001)
	assert_almost_eq(market.total_stock(), 4.0, 0.001)


func test_negative_add_stock_is_a_no_op():
	market.add_stock("meat", -1.0)
	assert_eq(market.total_stock(), 0.0)


func test_can_buy_meal_once_a_whole_unit_is_in_stock():
	market.add_stock("fruit", 0.9)
	assert_false(market.can_buy_meal(), "less than one whole unit -- not enough for a meal yet")
	market.add_stock("fruit", 0.1)
	assert_true(market.can_buy_meal())


func test_buy_meal_fails_with_no_stock():
	var wallet := Wallet.new()
	wallet.add(1000)
	assert_eq(market.buy_meal(wallet), "")
	assert_eq(wallet.balance, 1000, "a failed purchase must not touch the wallet")


func test_buy_meal_fails_when_the_wallet_cannot_afford_it():
	market.add_stock("meat", 5.0)
	var wallet := Wallet.new()
	wallet.add(VillageMarket.VILLAGE_LOCAL_FOOD_PRICE - 1)
	assert_eq(market.buy_meal(wallet), "")
	assert_almost_eq(market.stock["meat"], 5.0, 0.001, "a failed purchase must not touch stock")


func test_buy_meal_spends_the_village_local_price_and_removes_one_unit():
	market.add_stock("meat", 2.0)
	var wallet := Wallet.new()
	wallet.add(100)

	var bought := market.buy_meal(wallet)

	assert_eq(bought, "meat")
	assert_eq(wallet.balance, 100 - VillageMarket.VILLAGE_LOCAL_FOOD_PRICE)
	assert_almost_eq(market.stock["meat"], 1.0, 0.001)


## The village-local price is a distinct, informal villager-to-villager
## price -- not shop.gd's fixed player-facing catalog price for the closest
## real equivalent (cooked_meat).
func test_village_local_price_is_below_shops_cooked_meat_price():
	const Shop = preload("res://src/gameplay/shop.gd")
	assert_lt(VillageMarket.VILLAGE_LOCAL_FOOD_PRICE, Shop.CATALOG["cooked_meat"])


func test_village_local_price_is_positive():
	assert_gt(VillageMarket.VILLAGE_LOCAL_FOOD_PRICE, 0)


func test_buy_meal_picks_whichever_item_actually_has_a_whole_unit():
	market.add_stock("fish", 0.5)  # not enough on its own
	market.add_stock("meat", 1.0)
	var wallet := Wallet.new()
	wallet.add(100)
	assert_eq(market.buy_meal(wallet), "meat")


# -- remove_stock: the real draw-down VillageMarket also needs to serve as -
# -- docs/concept/timber_construction.md's own "it holds lumber the same --
# -- way" settlement material stock (the Settlement construction ledger's --
# -- own live integration draws real beam/plank down from here). All-or- ---
# -- nothing, mirroring StructureStock.remove_stock's own contract exactly -

func test_remove_stock_withdraws_the_requested_amount():
	market.add_stock("plank", 4.0)
	assert_true(market.remove_stock("plank", 4.0))
	assert_almost_eq(market.stock["plank"], 0.0, 0.001)


func test_remove_stock_fails_and_does_not_mutate_when_short():
	market.add_stock("plank", 2.0)
	assert_false(market.remove_stock("plank", 4.0))
	assert_almost_eq(market.stock["plank"], 2.0, 0.001)


func test_remove_stock_fails_for_an_item_with_no_stock_at_all():
	assert_false(market.remove_stock("beam", 1.0))
	assert_false(market.stock.has("beam"))
