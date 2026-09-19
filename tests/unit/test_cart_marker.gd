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


## Somebody who may take a shaft: a node in the puller group, which is what
## every real person in this world joins (see CartMarker.PULLER_GROUP -- a
## thing that is not a person cannot pull a cart).
func _a_person() -> Node2D:
	var person := Node2D.new()
	person.add_to_group(CartMarker.PULLER_GROUP)
	add_child_autofree(person)
	return person


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


# -- a real entity you can touch (Mechanism 6) ------------------------------
#
# Asked directly: "The cart should also be a real entity with hitbox and
# clicking on it shows the popup with inventory and the player should also be
# able to grab/pull it".

const HoverTargetFinder = preload("res://src/rendering/hover_target_finder.gd")
const EarthChunkManager = preload("res://src/world/earth_chunk_manager.gd")


## In the way, like the well beside it: a body on the ground floor's own
## collision layer, a child of the cart so it moves and is freed with it.
func test_a_cart_is_something_you_cannot_walk_through():
	var body: StaticBody2D = null
	for child in cart.get_children():
		if child is StaticBody2D:
			body = child
	assert_not_null(body, "a cart standing in the road is in the road")
	assert_eq(
		body.collision_layer, EarthChunkManager.GROUND_FLOOR_COLLISION_LAYER,
		"the same layer every wall piece uses, so nothing new has to learn about it"
	)
	var shapes := 0
	for child in body.get_children():
		if child is CollisionShape2D and child.shape != null:
			shapes += 1
	assert_gt(shapes, 0, "and the body really has a shape")


# -- it answers the cursor --------------------------------------------------

func test_a_cart_answers_the_hover_cursor():
	assert_true(cart.is_in_group(HoverTargetFinder.GROUP_NAME))
	assert_ne(cart.get_display_name(), "", "it says what it is")


## An empty cart and a loaded one are different things to walk up to.
func test_a_loaded_cart_says_so():
	var empty: String = cart.get_display_name()
	cart.load_on("beam", 4)
	assert_ne(cart.get_display_name(), empty, "a full wagon reads differently from an empty one")


## On the primary context slot -- exactly what that slot is for.
func test_taking_hold_is_offered_on_the_context_slot():
	var actions: Array = cart.get_hover_actions()
	assert_eq(actions.size(), 1, "one thing to do with a cart: take it, or let it go")
	assert_eq(actions[0].get("action"), "primary_action")
	var free_verb: String = actions[0].get("verb")
	cart.take_hold(_a_person(), true)
	assert_ne(
		cart.get_hover_actions()[0].get("verb"), free_verb,
		"and once you have it, the offer is to let it go"
	)


# -- clicking it shows what is in it ----------------------------------------

func test_a_cart_reports_its_load_in_the_shape_the_panel_reads():
	cart.load_on("beam", 4)
	cart.load_on("plank", 2)
	var report: Dictionary = cart.report()
	assert_false(report.is_empty())
	assert_eq(int((report["stock"] as Dictionary)["beam"]), 4)
	assert_eq(int(report["storage_capacity"]), CartLoad.CAPACITY, "the whole wagon is the shelf")
	assert_ne(String(report.get("title", "")), "", "named by itself, not by a building catalog")
	assert_false(bool(report.get("is_home", false)), "nobody lives in a cart")


## The report is a snapshot, not the cart's own store handed out: a panel
## that kept the live dictionary could edit the load by drawing it.
func test_the_report_does_not_hand_out_the_carts_own_load():
	cart.load_on("beam", 4)
	var report: Dictionary = cart.report()
	(report["stock"] as Dictionary)["beam"] = 99
	assert_eq(int(cart.stock["beam"]), 4)


# -- and it changes hands ---------------------------------------------------

func test_a_free_cart_can_be_taken():
	var carter := _a_person()
	assert_null(cart.held_by, "a fresh cart is parked")
	assert_true(cart.take_hold(carter))
	assert_eq(cart.held_by, carter)


## A carter only ever takes a free cart, so two of them never fight over one.
func test_a_cart_somebody_else_holds_is_not_free_to_take():
	var other := _a_person()
	assert_true(cart.take_hold(other))
	assert_false(cart.take_hold(_a_person()), "somebody already has the shaft")
	assert_eq(cart.held_by, other)


## The player's hold displaces: a villager is not going to wrestle them for
## a wagon, and being refused by an NPC's claim reads as a bug.
func test_taking_hold_by_force_always_wins():
	var other := _a_person()
	var thief := _a_person()
	cart.take_hold(other)
	assert_true(cart.take_hold(thief, true))
	assert_eq(cart.held_by, thief)


func test_letting_go_parks_it_where_it_stands_and_still_loaded():
	var carter := _a_person()
	cart.load_on("beam", 5)
	cart.position = Vector2(300, 220)
	cart.take_hold(carter)
	cart.let_go(carter)
	assert_null(cart.held_by)
	for i in 100:
		cart._process(0.1)
	assert_eq(cart.position, Vector2(300, 220), "a parked cart stays where it was left")
	assert_eq(int(cart.stock["beam"]), 5, "with the load still in it")


## Only the one holding it can let go of it.
func test_somebody_who_is_not_holding_it_cannot_let_it_go():
	var other := _a_person()
	cart.take_hold(other)
	cart.let_go(_a_person())
	assert_eq(cart.held_by, other)


## Held means followed: the cart is told where its holder is every frame,
## without anybody having to drive pulled_toward by hand.
func test_a_held_cart_follows_whoever_is_holding_it():
	var holder := _a_person()
	holder.position = Vector2(200, 0)
	cart.position = Vector2.ZERO
	cart.take_hold(holder)
	for i in 200:
		cart._process(0.1)
	assert_lt(cart.position.distance_to(holder.position), 32.0, "it comes along behind")


## A holder that has been freed is not a holder: a cart whose carter's chunk
## unloaded is parked, not chasing a dangling reference.
func test_a_cart_whose_holder_is_gone_is_parked_again():
	var holder := Node2D.new()
	holder.add_to_group(CartMarker.PULLER_GROUP)
	add_child(holder)
	cart.take_hold(holder)
	remove_child(holder)
	holder.free()
	cart._process(0.1)
	assert_null(cart.held_by, "nobody is holding it any more")


# -- only a person may take the shaft ---------------------------------------
#
# Reported three times now, in the same words each time: *"the cart is not
# being pulled by a worker, but by a floor tile???"*, *"It should be a real
# NPC pulling the cart, not an additional sprite"*, *"The cart is still town
# by a floor tile instead of an actual dedicated worker NPC"*.
#
# Answering it once more with "the wiring is right now" is not enough: what
# the report keeps describing is a thing that is not a person pulling a
# wagon, so the rule is that a thing that is not a person CANNOT.

const NpcMarker = preload("res://src/rendering/npc_marker.gd")
const NpcIdentity = preload("res://src/world/npc_identity.gd")
const LogisticsMarker = preload("res://src/rendering/logistics_marker.gd")


func test_a_villager_may_take_the_shaft():
	var villager := NpcMarker.new()
	villager.identity = NpcIdentity.new(7)
	add_child_autofree(villager)

	assert_true(cart.take_hold(villager))
	assert_eq(cart.held_by, villager)


## Anything that is not a person is refused, forced or not -- there is no
## way left to end up with scenery towing a wagon across the village.
func test_a_thing_that_is_not_a_person_can_never_take_the_shaft():
	var scenery := Node2D.new()
	add_child_autofree(scenery)

	assert_false(cart.take_hold(scenery), "scenery does not pull carts")
	assert_false(cart.take_hold(scenery, true), "and forcing it does not make it a person")
	assert_null(cart.held_by)


## The old porter is not a person in this sense either. It is a small
## purpose-built walker for the single-tile placeables, and giving it a cart
## is exactly the mistake the report has been describing: its own class no
## longer carries the machinery at all.
func test_the_placeable_scale_porter_has_no_cart_to_pull():
	var porter := LogisticsMarker.new()
	add_child_autofree(porter)
	assert_false(
		"cart" in porter,
		"a placeable's porter carries in its arms; the Bollerwagen is the carter's"
	)
