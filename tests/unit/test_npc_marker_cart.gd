extends GutTest

## A real villager who walks the store's round, pulling the Bollerwagen
## (docs/concept/village_warehouse.md, Mechanisms 4 and 5).
##
## Reported in play, twice: *"The warehouse also needs to bind a worker which
## then collects all ressources from every production building"*, then --
## after the first answer spawned a walker beside the villagers -- *"It
## should be a real NPC pulling the cart, not an additional sprite"*. So
## hauling is a TRADE here: the same three-part split the sawyer and the
## farmer already use -- VillageCart decides WHAT, LogisticsBehavior decides
## WHEN, and NpcMarker owns the world effect.

const NpcMarker = preload("res://src/rendering/npc_marker.gd")
const NpcIdentity = preload("res://src/world/npc_identity.gd")
const NpcPlanner = preload("res://src/world/npc_planner.gd")
const VillageMarket = preload("res://src/world/village_market.gd")
const VillageCart = preload("res://src/gameplay/village_cart.gd")
const CartMarker = preload("res://src/rendering/cart_marker.gd")
const CartLoad = preload("res://src/gameplay/cart_load.gd")
const NpcProduction = preload("res://src/world/npc_production.gd")

const TILE_SIZE := 16

const STORE_CELL := Vector2i(10, 10)
const MILL_CELL := Vector2i(16, 10)
const FORGE_CELL := Vector2i(4, 10)


static func _centre(cell: Vector2i) -> Vector2:
	return Vector2((float(cell.x) + 0.5) * TILE_SIZE, (float(cell.y) + 0.5) * TILE_SIZE)


## A world that answers the same per-building stock questions the real
## EarthChunkManager does -- including structure_stock_contents_at, which is
## how a carter reads a shelf without knowing in advance what is on it.
class StubCartWorld:
	var shelves: Dictionary = {}

	func _key(x: int, y: int) -> Vector2i:
		return Vector2i(x, y)

	func biome_at_global(_x: int, _y: int) -> String:
		return "grassland"

	func vegetation_density_near(_pos: Vector2) -> float:
		return 0.4

	func herbivore_population_near(_pos: Vector2) -> float:
		return 0.0

	func fish_population_near(_pos: Vector2) -> float:
		return 0.0

	func structure_stock_contents_at(x: int, y: int) -> Dictionary:
		return (shelves.get(_key(x, y), {}) as Dictionary).duplicate()

	func structure_stock_at(x: int, y: int, item_id: String) -> int:
		return int((shelves.get(_key(x, y), {}) as Dictionary).get(item_id, 0))

	func deposit_to_structure_at(x: int, y: int, item_id: String, count: int) -> void:
		var shelf: Dictionary = shelves.get(_key(x, y), {})
		shelf[item_id] = int(shelf.get(item_id, 0)) + count
		shelves[_key(x, y)] = shelf

	func withdraw_from_structure_at(x: int, y: int, item_id: String, count: int) -> bool:
		var shelf: Dictionary = shelves.get(_key(x, y), {})
		if int(shelf.get(item_id, 0)) < count:
			return false
		shelf[item_id] = int(shelf[item_id]) - count
		shelves[_key(x, y)] = shelf
		return true

	func total_on_shelf(cell: Vector2i) -> int:
		var carried := 0
		for item_id in shelves.get(cell, {}):
			carried += int(shelves[cell][item_id])
		return carried


class AllWorkPlanner:
	extends NpcPlanner.Planner
	func plan_day(_identity: NpcIdentity, _day_index: int) -> Array:
		var out: Array = []
		for block in ["morning", "midday", "evening", "night"]:
			out.append({"time_block": block, "location_tag": "warehouse", "activity": "work"})
		return out


class NeverWorkPlanner:
	extends NpcPlanner.Planner
	func plan_day(_identity: NpcIdentity, _day_index: int) -> Array:
		var out: Array = []
		for block in ["morning", "midday", "evening", "night"]:
			out.append({"time_block": block, "location_tag": "home", "activity": "sleep"})
		return out


var marker: NpcMarker
var world: StubCartWorld
var cart: CartMarker


func before_each():
	world = StubCartWorld.new()
	cart = CartMarker.new()
	cart.position = _centre(STORE_CELL)
	add_child_autofree(cart)
	marker = _carter_with(AllWorkPlanner.new(), VillageCart.OCCUPATION)


func after_each():
	if is_instance_valid(marker):
		remove_child(marker)
		marker.free()


func _carter_with(planner: NpcPlanner.Planner, occupation: String) -> NpcMarker:
	var built := NpcMarker.new()
	built.identity = NpcIdentity.new(1)
	built.identity.occupation = occupation
	built.home_position = _centre(STORE_CELL)
	built.workspot_position = _centre(STORE_CELL)
	built.landmarks = {"warehouse": _centre(STORE_CELL), "well": _centre(STORE_CELL)}
	built.position = _centre(STORE_CELL)
	built.set_planner(planner)
	built.setup(world, TILE_SIZE)
	built.setup_economy(VillageMarket.new())
	built.store_cell = STORE_CELL
	built.producer_cells = [MILL_CELL, FORGE_CELL]
	built.cart = cart
	add_child(built)
	return built



## Somebody who may take a shaft: a node in the puller group, which is what
## every real person in this world joins (CartMarker.PULLER_GROUP -- a thing
## that is not a person cannot pull a cart).
func _a_person() -> Node2D:
	var person := Node2D.new()
	person.add_to_group(CartMarker.PULLER_GROUP)
	add_child_autofree(person)
	return person


func _run(seconds: float, slice := 0.1) -> void:
	var elapsed := 0.0
	while elapsed < seconds:
		marker._process(slice)
		elapsed += slice


# -- the carter walks the round --------------------------------------------


## Out to whichever producer is really holding the most, not to whichever
## one a Dictionary happened to enumerate first.
func test_a_carter_walks_out_to_the_fullest_shelf():
	world.deposit_to_structure_at(MILL_CELL.x, MILL_CELL.y, "beam", 8)
	world.deposit_to_structure_at(FORGE_CELL.x, FORGE_CELL.y, "tool", 1)
	var before := marker.position
	_run(6.0)
	assert_lt(
		marker.position.distance_to(_centre(MILL_CELL)),
		before.distance_to(_centre(MILL_CELL)),
		"a carter with a full mill to empty sets out for it"
	)


## A village whose producers have nothing waiting sends nobody: the carter
## keeps the day's schedule like any other villager whose work has nothing
## in it.
func test_a_village_with_empty_shelves_keeps_its_carter_at_the_store():
	_run(6.0)
	assert_lt(
		marker.position.distance_to(_centre(STORE_CELL)), float(TILE_SIZE) * 2.0,
		"nothing is waiting, so there is nothing to walk to"
	)


## The trade is what decides it, not the wiring: a villager born to another
## trade never empties a shelf even when handed the same store and cart.
func test_a_villager_who_is_not_a_carter_never_walks_the_round():
	remove_child(marker)
	marker.free()
	marker = _carter_with(AllWorkPlanner.new(), "farmer")
	world.deposit_to_structure_at(MILL_CELL.x, MILL_CELL.y, "beam", 8)
	_run(60.0)
	assert_eq(world.total_on_shelf(MILL_CELL), 8, "somebody else's work is left alone")


# -- and the load really rides on the cart ----------------------------------


## The whole point of the wagon: what is collected leaves the producer's
## shelf and goes ON THE CART, not into the villager's pockets.
func test_what_the_carter_collects_leaves_the_shelf_and_rides_on_the_cart():
	world.deposit_to_structure_at(MILL_CELL.x, MILL_CELL.y, "beam", 8)
	for i in 1200:
		marker._process(0.1)
		if CartLoad.total(cart.stock) > 0:
			break
	assert_eq(int(cart.stock.get("beam", 0)), 8, "the beams are on the wagon")
	assert_eq(world.total_on_shelf(MILL_CELL), 0, "and really gone from the mill's shelf")
	assert_eq(
		int(marker.inventory.get("beam", 0)), 0,
		"a carter pulls the load, they do not pocket it"
	)


## And the store really receives it -- the far end of the same round.
func test_the_store_really_receives_what_the_cart_brought():
	world.deposit_to_structure_at(MILL_CELL.x, MILL_CELL.y, "beam", 8)
	for i in 3000:
		marker._process(0.1)
		if world.structure_stock_at(STORE_CELL.x, STORE_CELL.y, "beam") > 0:
			break
	assert_eq(
		world.structure_stock_at(STORE_CELL.x, STORE_CELL.y, "beam"), 8,
		"the round ends with the timber in the store"
	)
	assert_eq(CartLoad.total(cart.stock), 0, "and the wagon empty again")


## The cart is PULLED by a real villager: they take the shaft, and the wagon
## trails along behind them wherever the round goes.
func test_the_cart_is_pulled_along_behind_the_carter():
	world.deposit_to_structure_at(MILL_CELL.x, MILL_CELL.y, "beam", 8)
	cart.position = marker.position
	var travelled := 0.0
	var worst_gap := 0.0
	for i in 200:
		marker._process(0.1)
		cart._process(0.1)
		travelled = maxf(travelled, marker.position.distance_to(_centre(STORE_CELL)))
		worst_gap = maxf(worst_gap, cart.position.distance_to(marker.position))
	assert_eq(cart.held_by, marker, "a real villager has the shaft")
	assert_gt(travelled, float(TILE_SIZE), "precondition: the round really took them somewhere")
	# Close behind, never on top, at every step of the round: TRAIL_DISTANCE_PX
	# is the gap a cart keeps, and one frame of walking is the most it can
	# fall further back before FOLLOW_SPEED closes it again.
	assert_lte(
		worst_gap, CartMarker.TRAIL_DISTANCE_PX + NpcMarker.WALK_SPEED * 0.1,
		"and the wagon never got left behind"
	)


## Off the clock the round is dropped rather than paused, and the cart is
## left standing WHERE IT IS with the load still in it -- the feature, not a
## gap: *"if the worker leaves it somewhere it's actually full of
## ressources"*.
func test_off_the_clock_the_cart_is_left_standing_and_still_loaded():
	remove_child(marker)
	marker.free()
	marker = _carter_with(NeverWorkPlanner.new(), VillageCart.OCCUPATION)
	cart.load_on("beam", 5)
	world.deposit_to_structure_at(MILL_CELL.x, MILL_CELL.y, "beam", 8)
	_run(60.0)
	assert_eq(int(cart.stock.get("beam", 0)), 5, "nothing leaked out of a parked wagon")
	assert_eq(world.total_on_shelf(MILL_CELL), 8, "and an off-duty carter empties nothing")


# -- and the wagon really changes hands (Mechanism 6) -----------------------
#
# Asked directly: "the player should also be able to grab/pull it". A carter
# only ever takes a FREE cart, and one who has lost the shaft drops the round
# rather than walking it empty-handed.


func test_a_carter_takes_hold_of_the_wagon_they_pull():
	world.deposit_to_structure_at(MILL_CELL.x, MILL_CELL.y, "beam", 8)
	_run(6.0)
	assert_eq(cart.held_by, marker, "the carter has the shaft")


## A cart somebody else is already pulling is not this carter's to take.
func test_a_carter_never_takes_a_wagon_somebody_else_is_pulling():
	var thief := _a_person()
	cart.take_hold(thief)
	world.deposit_to_structure_at(MILL_CELL.x, MILL_CELL.y, "beam", 8)
	_run(30.0)
	assert_eq(cart.held_by, thief, "the shaft is not wrested off them")


## And nothing is moved into a wagon the carter is not holding: a shelf
## emptied into somebody else's cart would be goods vanishing.
func test_a_carter_without_the_shaft_empties_nothing():
	var thief := _a_person()
	cart.take_hold(thief)
	world.deposit_to_structure_at(MILL_CELL.x, MILL_CELL.y, "beam", 8)
	_run(120.0)
	assert_eq(world.total_on_shelf(MILL_CELL), 8, "the mill keeps what nobody could carry")
	assert_eq(CartLoad.total(cart.stock), 0, "and the wagon stays empty")


## A wagon abandoned in a field is village property again the moment nobody
## is holding it.
func test_a_carter_reclaims_a_parked_wagon():
	var thief := _a_person()
	cart.take_hold(thief)
	world.deposit_to_structure_at(MILL_CELL.x, MILL_CELL.y, "beam", 8)
	_run(10.0)
	assert_eq(cart.held_by, thief, "precondition: somebody else had it")

	cart.let_go(thief)
	_run(20.0)

	assert_eq(cart.held_by, marker, "the village's own carter picks it up again")


## Off the clock the carter lets go, so a wagon is not dragged home to bed --
## it stands where the round ended, still loaded (Mechanism 5's whole point).
func test_an_off_duty_carter_lets_the_wagon_go():
	world.deposit_to_structure_at(MILL_CELL.x, MILL_CELL.y, "beam", 8)
	_run(10.0)
	assert_eq(cart.held_by, marker, "precondition: on the clock, they have it")

	remove_child(marker)
	marker.free()
	marker = _carter_with(NeverWorkPlanner.new(), VillageCart.OCCUPATION)
	_run(10.0)

	assert_null(cart.held_by, "a parked wagon is free for whoever needs it next")


# -- the delivery is what credits the village (Mechanism 7) -----------------
#
# Reported in play: "The FarmHouse seems to be harvesting something but none
# of it makes it into storage... it's always 0". The producer is paid at
# their own scythe; the village's sellable stock is credited at the moment
# the goods really reach the store.


func test_delivering_a_load_credits_the_villages_own_stock():
	world.deposit_to_structure_at(MILL_CELL.x, MILL_CELL.y, "beam", 8)
	var market: VillageMarket = marker.economy.market
	assert_eq(float(market.stock.get("beam", 0.0)), 0.0, "precondition: the village has none yet")

	for i in 3000:
		marker._process(0.1)
		if world.structure_stock_at(STORE_CELL.x, STORE_CELL.y, "beam") > 0:
			break

	assert_eq(
		float(market.stock.get("beam", 0.0)), 8.0,
		"the village can sell what really arrived, and only that"
	)


## Once, not twice: the goods are counted when they land, and a shelf the
## carter has already emptied has nothing left to count.
func test_a_load_is_credited_once_however_long_the_round_runs():
	world.deposit_to_structure_at(MILL_CELL.x, MILL_CELL.y, "beam", 8)
	var market: VillageMarket = marker.economy.market
	_run(400.0)
	assert_eq(float(market.stock.get("beam", 0.0)), 8.0, "eight beams, counted eight times over")
