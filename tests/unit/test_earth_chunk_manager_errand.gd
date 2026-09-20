extends GutTest

## docs/concept/errands.md: the give verb performed for real -- goods out of
## the player's hands, into the SAME Market object the shortfall projection
## reads, paid for out of the household's own finite purse, recorded as a
## witnessed event, all in one step or not at all.
##
## Uses the manager's own stores directly rather than loading a real chunk:
## every object here (Market, Household, Wallet, EventStore) is the real one
## the settlement step uses, and the transfer under test does not care which
## chunk they came from.

const EarthChunkManager = preload("res://src/world/earth_chunk_manager.gd")
const PlayerScene = preload("res://scenes/player.tscn")
const Player = preload("res://scenes/player.gd")
const Item = preload("res://src/gameplay/item.gd")
const ErrandDelivery = preload("res://src/gameplay/errand_delivery.gd")

var manager: EarthChunkManager
var tile_map_layer: TileMapLayer
var entities_parent: Node2D
var creatures_parent: Node2D
var player: Player

const SETTLEMENT_ID := "settlement:1_2"


func before_each():
	tile_map_layer = TileMapLayer.new()
	entities_parent = Node2D.new()
	creatures_parent = Node2D.new()
	add_child(tile_map_layer)
	add_child(entities_parent)
	manager = EarthChunkManager.new(tile_map_layer, entities_parent, creatures_parent)
	# The real scene, not a bare script: Player expects its own camera
	# and rig children, exactly as test_player.gd constructs it.
	player = PlayerScene.instantiate()
	add_child(player)


func after_each():
	player.queue_free()
	tile_map_layer.free()
	entities_parent.free()
	creatures_parent.free()


## A household that owns a purse, in a settlement that owns a market.
func _a_household_with(purse_gold: int) -> String:
	var household = manager.household_store().form_household("npc:77")
	household.wallet.balance = purse_gold
	return household.id


func _market():
	return manager.market_store().market_for(SETTLEMENT_ID)


func _offer(household_id: String, given: Array) -> Dictionary:
	return {
		"available": true,
		"label": "Give",
		"reason": "",
		"given": given,
		"household_id": household_id,
		"settlement_id": SETTLEMENT_ID,
	}


func _carry(item_id: String, count: int) -> void:
	player.inventory.add(Item.new(item_id, item_id.capitalize(), "material", 99), count)


# -- the goods really move ----------------------------------------------

func test_the_goods_leave_the_player_and_enter_the_settlements_own_market():
	var household_id := _a_household_with(100)
	_carry("rock", 5)
	var before: int = _market().stock_of("rock")

	manager.deliver_errand(_offer(household_id, [{"item_id": "rock", "count": 3}]), player)

	assert_eq(player.inventory.count_of("rock"), 2, "three rock left the player's hands")
	assert_eq(_market().stock_of("rock"), before + 3, "and arrived in the market the projection reads")


func test_delivering_nothing_moves_nothing():
	var household_id := _a_household_with(100)
	_carry("rock", 5)
	var deal: Dictionary = manager.deliver_errand(_offer(household_id, []), player)
	assert_eq(int(deal["units"]), 0)
	assert_eq(player.inventory.count_of("rock"), 5)
	assert_eq(_market().stock_of("rock"), 0)


## Pillar 2: atomic, or it did not happen. A player who cannot actually
## produce the goods must not have them taken, and the market must not gain
## stock from nowhere.
func test_an_offer_the_player_can_no_longer_meet_moves_nothing_at_all():
	var household_id := _a_household_with(100)
	_carry("rock", 1)
	var deal: Dictionary = manager.deliver_errand(_offer(household_id, [{"item_id": "rock", "count": 3}]), player)
	assert_eq(int(deal["units"]), 1, "it hands over what is really there")
	assert_eq(player.inventory.count_of("rock"), 0)
	assert_eq(_market().stock_of("rock"), 1, "and the market gains exactly that, never the promise")


# -- and it is paid for -------------------------------------------------

func test_the_household_pays_the_player_out_of_its_own_purse():
	var household_id := _a_household_with(100)
	_carry("rock", 3)
	var purse_before: int = manager.household_store().get_household(household_id).wallet.balance
	var player_before: int = player.wallet.balance

	var deal: Dictionary = manager.deliver_errand(_offer(household_id, [{"item_id": "rock", "count": 3}]), player)

	var paid := int(deal["paid"])
	assert_gt(paid, 0, "a real delivery is really paid for")
	assert_eq(player.wallet.balance, player_before + paid, "the player is paid")
	assert_eq(
		manager.household_store().get_household(household_id).wallet.balance,
		purse_before - paid,
		"out of the household's own purse, not from nowhere"
	)


func test_a_poor_household_takes_the_goods_pays_what_it_has_and_owes_the_rest():
	var household_id := _a_household_with(1)
	_carry("rock", 3)

	var deal: Dictionary = manager.deliver_errand(_offer(household_id, [{"item_id": "rock", "count": 3}]), player)

	assert_eq(_market().stock_of("rock"), 3, "the goods still move")
	assert_eq(player.wallet.balance, 1, "it pays every coin it had")
	assert_eq(manager.household_store().get_household(household_id).wallet.balance, 0)
	assert_gt(int(deal["debt"]), 0, "and carries the rest as a debt")


func test_the_purse_is_never_overdrawn():
	var household_id := _a_household_with(0)
	_carry("rock", 3)
	manager.deliver_errand(_offer(household_id, [{"item_id": "rock", "count": 3}]), player)
	assert_eq(manager.household_store().get_household(household_id).wallet.balance, 0)
	assert_eq(player.wallet.balance, 0)


# -- the world remembers ------------------------------------------------

func test_a_delivery_is_recorded_as_a_real_event_the_village_witnessed():
	var household_id := _a_household_with(100)
	_carry("rock", 3)
	var before: int = manager.event_store().events_for_entity(SETTLEMENT_ID).size()

	manager.deliver_errand(_offer(household_id, [{"item_id": "rock", "count": 3}]), player)

	var after: Array = manager.event_store().events_for_entity(SETTLEMENT_ID)
	assert_eq(after.size(), before + 1, "the settlement witnessed it")
	assert_eq(String(after[-1].type), EarthChunkManager.ERRAND_DELIVERED_EVENT_TYPE)


func test_a_delivery_that_moved_nothing_records_nothing():
	var household_id := _a_household_with(100)
	var before: int = manager.event_store().events_for_entity(SETTLEMENT_ID).size()
	manager.deliver_errand(_offer(household_id, []), player)
	assert_eq(manager.event_store().events_for_entity(SETTLEMENT_ID).size(), before)


# -- the shortage really ends -------------------------------------------

## The point of the whole verb: the projection stops reporting the shortage
## because the shortage is over, not because a flag was set.
func test_delivering_the_shortfall_ends_what_the_projection_reports():
	var household_id := _a_household_with(100)
	var recipe_book = manager._recipe_book
	var inputs: Array = recipe_book.recipe_inputs("bread")
	if inputs.is_empty():
		pass_test("the recipe book has no bread recipe to test against")
		return
	var occupations := {household_id: "baker"}
	var shortfalls_before: Array = Quest.production_shortfall_quests_for(
		SETTLEMENT_ID, occupations, _market(), recipe_book
	)
	assert_false(shortfalls_before.is_empty(), "precondition: an empty market is short")

	var missing: Array = shortfalls_before[0]["missing"]
	var given: Array = []
	for entry in missing:
		_carry(String(entry["item_id"]), int(entry["need"]))
		given.append({"item_id": String(entry["item_id"]), "count": int(entry["need"])})

	manager.deliver_errand(_offer(household_id, given), player)

	assert_true(
		Quest.production_shortfall_quests_for(SETTLEMENT_ID, occupations, _market(), recipe_book).is_empty(),
		"the projection reports no shortage, because there is none"
	)

const Quest = preload("res://src/emergence/quest.gd")
