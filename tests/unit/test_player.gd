extends GutTest

## Covers the placeable-structure mechanics added to Player: arming a
## placeable item from the hotbar/inventory, placing it into the world
## (consuming one on success only), returning it to the inventory on destroy,
## and real placed-structure proximity gating cooking/smelting (replacing the
## old "carried in inventory" stand-in). Instantiates the real player.tscn
## (mirroring test_character_view.gd) against a real EarthChunkManager
## (mirroring test_earth_chunk_manager.gd's fixtures) so the actual wiring is
## exercised, not a stub.

const PlayerScene = preload("res://scenes/player.tscn")
const EarthChunkManager = preload("res://src/world/earth_chunk_manager.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")
const ItemCatalog = preload("res://src/gameplay/item_catalog.gd")

const TILE_SIZE := TerrainRenderer.TILE_SIZE

var tile_map_layer: TileMapLayer
var entities_parent: Node2D
var creatures_parent: Node2D
var chunk_manager: EarthChunkManager
var player: Player
var _item_catalog := ItemCatalog.new()


func before_each():
	tile_map_layer = TileMapLayer.new()
	entities_parent = Node2D.new()
	creatures_parent = Node2D.new()
	chunk_manager = EarthChunkManager.new(tile_map_layer, entities_parent, creatures_parent)
	chunk_manager.update(Vector2i(0, 0))  # loads chunks (-2..2, -2..2) around the origin

	player = PlayerScene.instantiate()
	# Name it after this (solo) tree's own multiplayer id, matching how
	# World names a real player node (see World's `_players.get_node_or_null
	# (str(multiplayer.get_unique_id()))`) -- Player._is_local_player_instance
	# keys off that match (multiplayer.has_multiplayer_peer() is true even
	# solo, see its doc comment), and local-input binding/reading (WASD,
	# build, destroy) only happens for the locally-controlled instance.
	player.name = str(multiplayer.get_unique_id())
	add_child(player)
	player.position = Vector2(4 * TILE_SIZE, 4 * TILE_SIZE)  # tile (4, 4), inside the loaded area
	player.setup(chunk_manager, TILE_SIZE)
	player._last_facing_direction = Vector2.DOWN  # faces tile (4, 5)


func after_each():
	remove_child(player)
	player.free()
	tile_map_layer.free()
	entities_parent.free()
	creatures_parent.free()
	Input.action_release("build")
	Input.action_release("destroy")


## The tile the player is facing (see TileTargeting.facing_tile), matching
## the DOWN facing set in before_each.
func _facing_tile() -> Vector2i:
	return player.current_tile() + Vector2i(0, 1)


## A full press+release cycle so _build_step's rising-edge latch fires exactly
## once and resets, ready for another tap later in the same test.
func _tap_build() -> void:
	Input.action_press("build")
	player._build_step()
	Input.action_release("build")
	player._build_step()


func _tap_destroy() -> void:
	Input.action_press("destroy")
	player._destroy_step()
	Input.action_release("destroy")
	player._destroy_step()


func _stack_index_of(item_id: String) -> int:
	var stacks := player.inventory.stacks()
	for i in stacks.size():
		if stacks[i].item.id == item_id:
			return i
	return -1


# -- arming a placeable from the hotbar/inventory ------------------------------

func test_activate_item_id_arms_a_placeable_item():
	player.inventory.add(_item_catalog.make("campfire"), 1)

	var handled := player.activate_item_id("campfire")

	assert_true(handled)
	assert_eq(player._selected_placeable_item.id, "campfire")


func test_activate_hotbar_slot_arms_a_placeable_item():
	player.inventory.add(_item_catalog.make("furnace"), 1)
	var index := _stack_index_of("furnace")

	var handled := player.activate_hotbar_slot(index)

	assert_true(handled)
	assert_eq(player._selected_placeable_item.id, "furnace")


# -- build-input: placement, consumption, and the unarmed regression path -----

func test_build_step_places_bare_earth_when_nothing_is_armed():
	var target := _facing_tile()

	_tap_build()

	assert_eq(chunk_manager.modification_at_global(target.x, target.y), TerrainRenderer.EARTH_TILE_ID)


func test_build_step_places_the_armed_item_and_consumes_one_from_inventory():
	player.inventory.add(_item_catalog.make("campfire"), 2)
	player.activate_item_id("campfire")
	var before_count: int = player.inventory_counts().get("campfire", 0)
	var target := _facing_tile()

	_tap_build()

	assert_eq(chunk_manager.modification_at_global(target.x, target.y), "campfire")
	assert_eq(player.inventory_counts().get("campfire", 0), before_count - 1)


func test_build_step_does_not_consume_inventory_when_placement_fails():
	player.position = Vector2(1000 * TILE_SIZE, 1000 * TILE_SIZE)  # far outside the loaded chunks
	player.inventory.add(_item_catalog.make("campfire"), 1)
	player.activate_item_id("campfire")
	var before_count: int = player.inventory_counts().get("campfire", 0)

	_tap_build()

	assert_eq(player.inventory_counts().get("campfire", 0), before_count)


func test_build_step_does_nothing_when_the_armed_item_has_run_out():
	player.inventory.add(_item_catalog.make("campfire"), 1)
	player.activate_item_id("campfire")
	player.inventory.remove("campfire", 1)  # ran out after arming
	var target := _facing_tile()

	_tap_build()

	assert_eq(chunk_manager.modification_at_global(target.x, target.y), "")


# -- destroy-input: giving the item back ---------------------------------------

func test_destroy_step_returns_a_placed_structure_item_to_the_inventory():
	var target := _facing_tile()
	chunk_manager.build_at_global(target.x, target.y, "campfire")
	var before_count: int = player.inventory_counts().get("campfire", 0)

	_tap_destroy()

	assert_eq(chunk_manager.modification_at_global(target.x, target.y), "")
	assert_eq(player.inventory_counts().get("campfire", 0), before_count + 1)


func test_destroy_step_gives_nothing_back_for_plain_bare_earth():
	var target := _facing_tile()
	chunk_manager.build_at_global(target.x, target.y, TerrainRenderer.EARTH_TILE_ID)
	var counts_before: Dictionary = player.inventory_counts().duplicate()

	_tap_destroy()

	assert_eq(chunk_manager.modification_at_global(target.x, target.y), "")
	assert_eq(player.inventory_counts(), counts_before)


func test_destroy_step_does_nothing_when_there_is_no_modification():
	var counts_before: Dictionary = player.inventory_counts().duplicate()

	_tap_destroy()

	assert_eq(player.inventory_counts(), counts_before)


# -- real placed-structure proximity gates cooking/smelting --------------------

func test_has_campfire_false_when_nothing_is_placed():
	assert_false(player._has_campfire())


func test_has_campfire_true_when_a_placed_campfire_is_near():
	var tile := player.current_tile()
	chunk_manager.build_at_global(tile.x + 1, tile.y, "campfire")

	assert_true(player._has_campfire())


func test_has_campfire_false_when_the_campfire_is_out_of_range():
	var tile := player.current_tile()
	chunk_manager.build_at_global(tile.x + player.HEAT_SOURCE_RADIUS_TILES + 5, tile.y, "campfire")

	assert_false(player._has_campfire())


## Proves the fix: merely carrying a campfire (the old proxy behavior) no
## longer counts -- it must actually be placed in the world.
func test_has_campfire_false_when_only_carried_in_inventory_not_placed():
	player.inventory.add(_item_catalog.make("campfire"), 1)

	assert_false(player._has_campfire())


func test_has_heat_source_true_for_a_nearby_placed_furnace():
	var tile := player.current_tile()
	chunk_manager.build_at_global(tile.x, tile.y + 1, "furnace")

	assert_true(player._has_heat_source())


func test_cook_succeeds_when_a_campfire_is_placed_nearby():
	var tile := player.current_tile()
	chunk_manager.build_at_global(tile.x + 1, tile.y, "campfire")
	player.inventory.add(_item_catalog.make("meat"), 1)

	var cooked := player.cook("meat")

	assert_true(cooked)
	assert_eq(player.inventory_counts().get("cooked_meat", 0), 1)


func test_cook_fails_when_a_campfire_is_only_carried_not_placed():
	player.inventory.add(_item_catalog.make("campfire"), 1)
	player.inventory.add(_item_catalog.make("meat"), 1)

	var cooked := player.cook("meat")

	assert_false(cooked)
