extends GutTest

## Taking hold of a handcart (docs/concept/village_warehouse.md, Mechanism 6).
##
## Asked directly: *"the player should also be able to grab/pull it"*. The
## primary context slot is exactly the right key for it -- what that slot does
## is decided by whatever is under the cursor and the state it is in -- and a
## cart offers one verb that flips: Take Hold, then Let Go.
##
## Mirrors test_player_held_item.gd's real-scene setup.

const PlayerScene = preload("res://scenes/player.tscn")
const EarthChunkManager = preload("res://src/world/earth_chunk_manager.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")
const CartMarker = preload("res://src/rendering/cart_marker.gd")

const TILE_SIZE := TerrainRenderer.TILE_SIZE

var tile_map_layer: TileMapLayer
var entities_parent: Node2D
var creatures_parent: Node2D
var chunk_manager: EarthChunkManager
var player: Player


func before_each():
	tile_map_layer = TileMapLayer.new()
	entities_parent = Node2D.new()
	creatures_parent = Node2D.new()
	chunk_manager = EarthChunkManager.new(tile_map_layer, entities_parent, creatures_parent)
	chunk_manager.update(Vector2i(0, 0))

	player = PlayerScene.instantiate()
	player.name = str(multiplayer.get_unique_id())
	add_child(player)
	player.position = Vector2(4 * TILE_SIZE, 4 * TILE_SIZE)
	player.setup(chunk_manager, TILE_SIZE)


func after_each():
	remove_child(player)
	player.free()
	tile_map_layer.free()
	entities_parent.free()
	creatures_parent.free()


func _cart_at(offset: Vector2) -> CartMarker:
	var cart := CartMarker.new()
	cart.position = player.position + offset
	add_child_autofree(cart)
	return cart



## Somebody who may take a shaft: a node in the puller group, which is what
## every real person in this world joins (CartMarker.PULLER_GROUP -- a thing
## that is not a person cannot pull a cart).
func _a_person() -> Node2D:
	var person := Node2D.new()
	person.add_to_group(CartMarker.PULLER_GROUP)
	add_child_autofree(person)
	return person


func test_the_nearest_cart_within_reach_is_the_one_taken():
	var near := _cart_at(Vector2(8, 0))
	var far := _cart_at(Vector2(Player.LASSO_RANGE - 4.0, 0))

	player.toggle_cart_hold()

	assert_eq(near.held_by, player, "the one you are standing at")
	assert_null(far.held_by)


## Out of arm's reach is out of reach: a cart across the village is not
## grabbed from where you stand.
func test_a_cart_out_of_reach_is_not_taken():
	var cart := _cart_at(Vector2(Player.LASSO_RANGE * 3.0, 0))

	player.toggle_cart_hold()

	assert_null(cart.held_by, "you have to walk to it")


## One verb that flips, which is what the hover tooltip already promises:
## Take Hold, then Let Go.
func test_the_same_key_lets_go_of_a_cart_already_held():
	var cart := _cart_at(Vector2(8, 0))
	player.toggle_cart_hold()
	assert_eq(cart.held_by, player, "precondition")

	player.toggle_cart_hold()

	assert_null(cart.held_by, "pressed again, the player lets go")


## The player's hold displaces a villager's: being refused by an NPC's claim
## reads as a bug, and a villager is not going to wrestle them for a wagon.
func test_the_player_takes_a_cart_a_villager_is_already_pulling():
	var cart := _cart_at(Vector2(8, 0))
	var carter := _a_person()
	cart.take_hold(carter)

	player.toggle_cart_hold()

	assert_eq(cart.held_by, player, "the shaft changes hands")


## And the wagon really follows them, load and all -- the whole point of
## being able to take it.
func test_a_cart_the_player_took_comes_with_them():
	var cart := _cart_at(Vector2(8, 0))
	cart.load_on("beam", 5)
	player.toggle_cart_hold()

	player.position += Vector2(200, 0)
	for i in 200:
		cart._process(0.1)

	assert_lt(cart.position.distance_to(player.position), 32.0, "it came along behind")
	assert_eq(int(cart.stock["beam"]), 5, "still loaded")


## Letting go of one cart never quietly parks another the player never had.
func test_letting_go_only_releases_the_cart_the_player_holds():
	var mine := _cart_at(Vector2(8, 0))
	# Plainly further off, so "the nearer one" is not a coin toss.
	var theirs := _cart_at(Vector2(0, 40))
	var carter := _a_person()
	theirs.take_hold(carter)
	player.toggle_cart_hold()
	assert_eq(mine.held_by, player, "precondition: the nearer one")

	player.toggle_cart_hold()

	assert_null(mine.held_by)
	assert_eq(theirs.held_by, carter, "somebody else's wagon is left alone")


## Nothing near, nothing happens -- and nothing crashes.
func test_pressing_it_with_no_cart_nearby_does_nothing():
	player.toggle_cart_hold()
	assert_true(true, "no cart, no effect")
