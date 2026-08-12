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
