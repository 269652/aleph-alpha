extends GutTest

## The Bollerwagen on the map (docs/concept/village_warehouse.md,
## Mechanism 5): a real node that holds the load, follows whoever is pulling
## it, and turns to face the way it is going.

const CartMarker = preload("res://src/rendering/cart_marker.gd")
const CartLoad = preload("res://src/gameplay/cart_load.gd")

var cart: CartMarker


func before_each():
	cart = CartMarker.new()
	add_child_autofree(cart)


# -- the load is on the cart -------------------------------------------------

func test_a_fresh_cart_is_empty():
	assert_eq(CartLoad.total(cart.stock), 0)


func test_what_is_loaded_stays_on_the_cart():
	assert_eq(cart.load_on("beam", 4), 4)
	assert_eq(int(cart.stock["beam"]), 4)


## The point of the whole mechanism: a cart left standing somewhere is a
## cart that is still full.
func test_a_cart_left_standing_is_still_full():
	cart.load_on("wood", 6)
	cart.position = Vector2(400, 400)
	for i in 100:
		cart._process(0.1)
	assert_eq(int(cart.stock["wood"]), 6, "nobody is pulling it and nothing leaked out of it")


func test_unloading_hands_back_everything_and_empties_the_cart():
	cart.load_on("beam", 4)
	cart.load_on("plank", 2)
	var taken: Dictionary = cart.unload_all()
	assert_eq(int(taken["beam"]), 4)
	assert_eq(int(taken["plank"]), 2)
	assert_eq(CartLoad.total(cart.stock), 0, "the cart really is empty afterwards")


func test_a_full_cart_takes_no_more():
	assert_eq(cart.load_on("wood", CartLoad.CAPACITY), CartLoad.CAPACITY)
	assert_eq(cart.load_on("stone", 4), 0, "what will not fit is left on the shelf")


# -- and it follows whoever is pulling it -----------------------------------

func test_a_cart_follows_the_one_pulling_it():
	cart.position = Vector2.ZERO
	cart.pulled_toward = Vector2(200, 0)
	for i in 200:
		cart._process(0.1)
	assert_lt(cart.position.distance_to(Vector2(200, 0)), 32.0, "it comes along behind")


## Trailing, not standing on top of them: a cart is pulled BEHIND a person.
func test_a_cart_trails_rather_than_overlapping_its_puller():
	cart.position = Vector2.ZERO
	cart.pulled_toward = Vector2(200, 0)
	for i in 400:
		cart._process(0.1)
	assert_gt(cart.position.distance_to(Vector2(200, 0)), 1.0, "it does not climb into their pocket")


func test_a_cart_nobody_is_pulling_stays_where_it_was_left():
	cart.position = Vector2(120, 80)
	cart.pulled_toward = null
	for i in 100:
		cart._process(0.1)
	assert_eq(cart.position, Vector2(120, 80))


# -- and it faces the way it is going ---------------------------------------

func test_a_cart_faces_the_way_it_is_going():
	assert_eq(CartMarker.view_row_for(Vector2(1, 0)), CartMarker.ROW_EAST)
	assert_eq(CartMarker.view_row_for(Vector2(-1, 0)), CartMarker.ROW_WEST)
	assert_eq(CartMarker.view_row_for(Vector2(0, 1)), CartMarker.ROW_FRONT)
	assert_eq(CartMarker.view_row_for(Vector2(0, -1)), CartMarker.ROW_REAR)


## A cart standing still keeps whatever way it was last pointed rather than
## snapping to a default.
func test_a_standing_cart_keeps_the_way_it_was_pointed():
	assert_eq(CartMarker.view_row_for(Vector2.ZERO, CartMarker.ROW_WEST), CartMarker.ROW_WEST)


## The wheels turn only while it is moving -- a parked cart with spinning
## wheels is worse than one that does not animate at all.
func test_the_wheels_turn_only_while_it_rolls():
	var rolled: int = CartMarker.roll_frame_for(0.0, 4.0, CartMarker.ROLL_SECONDS_PER_FRAME)
	assert_eq(rolled, 0, "no distance covered, no turn of the wheel")
	assert_gt(CartMarker.roll_frame_for(CartMarker.ROLL_SECONDS_PER_FRAME * 3.0, 4.0, CartMarker.ROLL_SECONDS_PER_FRAME), 0)


func test_the_roll_cycles_rather_than_running_off_the_sheet():
	for i in 40:
		var frame: int = CartMarker.roll_frame_for(
			CartMarker.ROLL_SECONDS_PER_FRAME * float(i), 5.0, CartMarker.ROLL_SECONDS_PER_FRAME
		)
		assert_between(frame, 0, 4, "frame %d is off the sheet" % frame)
