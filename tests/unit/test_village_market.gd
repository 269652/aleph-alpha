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


# -- Only real FOOD is a meal. A VillageMarket also holds construction ------
# -- lumber (see remove_stock above), and SettlementFood._village_food_stock -
# -- already filters that stock through ItemCatalog.kind_of(id) == "food" ---
# -- before a settlement counts as fed. can_buy_meal/buy_meal must read the -
# -- SAME real category: NpcEconomy's wage gate reads can_buy_meal directly, -
# -- so an unfiltered market would pay a subsistence wage and "feed" a beam -
# -- to a villager in a settlement SettlementFood correctly reports starving.

const ItemCatalog = preload("res://src/gameplay/item_catalog.gd")


## A catalog that knows one id the shipped ItemCatalog never will -- stands
## in for a real ItemCatalog with a CraftedItemRegistry attached (see
## ItemCatalog._crafted_registry), i.e. emergent/crafted food.
class _CraftedFoodCatalog:
	extends RefCounted

	func kind_of(item_id: String) -> String:
		return "food" if item_id == "emergent_stew" else ""


func test_a_market_holding_only_lumber_cannot_sell_a_meal():
	market.add_stock("beam", 10.0)
	market.add_stock("plank", 10.0)
	assert_false(market.can_buy_meal(), "lumber is not a meal, however much of it is stocked")


func test_buy_meal_refuses_lumber_and_touches_neither_wallet_nor_stock():
	market.add_stock("beam", 10.0)
	var wallet := Wallet.new()
	wallet.add(100)
	assert_eq(market.buy_meal(wallet), "")
	assert_eq(wallet.balance, 100, "a refused purchase must not touch the wallet")
	assert_almost_eq(market.stock["beam"], 10.0, 0.001, "a refused purchase must not touch stock")


func test_buy_meal_skips_lumber_and_picks_the_real_food_behind_it():
	market.add_stock("beam", 10.0)  # stocked first, so iteration reaches it first
	market.add_stock("meat", 2.0)
	var wallet := Wallet.new()
	wallet.add(100)

	assert_eq(market.buy_meal(wallet), "meat")
	assert_almost_eq(market.stock["beam"], 10.0, 0.001, "lumber is never eaten")
	assert_almost_eq(market.stock["meat"], 1.0, 0.001)


## Pinned to the catalog itself rather than a hand-written list of "which
## ids are food" -- the same single source SettlementFood filters on.
func test_meal_eligibility_matches_the_item_catalogs_own_food_category():
	var catalog := ItemCatalog.new()
	for item_id in ["meat", "fish", "fruit", "nut", "beam", "plank", "log", "hide"]:
		var one_item_market = VillageMarket.new()
		one_item_market.add_stock(item_id, VillageMarket.FOOD_UNITS_PER_MEAL)
		assert_eq(
			one_item_market.can_buy_meal(),
			catalog.kind_of(item_id) == "food",
			"%s: meal eligibility must follow ItemCatalog.kind_of" % item_id
		)


func test_an_item_no_catalog_knows_is_not_a_meal():
	market.add_stock("not_a_real_item", 5.0)
	assert_false(market.can_buy_meal())


## The seam a caller holding a catalog that knows emergent/crafted food ids
## (Player._item_catalog, say) can hand in, so a real cooked dish the shipped
## table never listed still feeds a villager.
func test_an_injected_catalog_decides_what_counts_as_food():
	market.item_catalog = _CraftedFoodCatalog.new()
	market.add_stock("emergent_stew", 2.0)
	assert_true(market.can_buy_meal(), "the injected catalog calls this food")

	var wallet := Wallet.new()
	wallet.add(100)
	assert_eq(market.buy_meal(wallet), "emergent_stew")
