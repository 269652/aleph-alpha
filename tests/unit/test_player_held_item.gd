extends GutTest

## Contextual E: hold-in-hand pickup + charge/release throw (see docs/concept/
## stone.md). Empty-handed near a liftable stone, E picks it into the HAND
## (distinct from inventory); with something already in hand, pressing and
## HOLDING E charges the ChargeMeter's bouncing strengthometer, and
## releasing E throws it -- feeding the SAME momentum model
## (Throwable.impact_knockback) everything else in combat uses. Mirrors
## test_player_kick.gd's real-scene setup and test_earth_chunk_manager.gd's
## `_loaded_stones` injection convention.

const PlayerScene = preload("res://scenes/player.tscn")
const EarthChunkManager = preload("res://src/world/earth_chunk_manager.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")
const LiftableStone = preload("res://src/rendering/liftable_stone.gd")
const StoneSize = preload("res://src/world/stone_size.gd")
const ChargeMeter = preload("res://src/gameplay/charge_meter.gd")
const DroppedItem = preload("res://src/rendering/dropped_item.gd")
const Item = preload("res://src/gameplay/item.gd")
const ItemStack = preload("res://src/gameplay/item_stack.gd")
const Inventory = preload("res://src/gameplay/inventory.gd")

const TILE_SIZE := TerrainRenderer.TILE_SIZE

var tile_map_layer: TileMapLayer
var entities_parent: Node2D
var creatures_parent: Node2D
var chunk_manager: EarthChunkManager
var player: Player


func before_each():
	if not InputMap.has_action("pickup"):
		InputMap.add_action("pickup")
	if not InputMap.has_action("stash"):
		InputMap.add_action("stash")

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
	# A thrown stone (see Player._spawn_thrown_stone) is added directly under
	# the player's own parent -- this test node -- so clean those up too, not
	# just the fixtures created explicitly above.
	for node in get_tree().get_nodes_in_group(DroppedItem.GROUP_NAME):
		if is_instance_valid(node) and node.get_parent() == self:
			remove_child(node)
			node.free()
	remove_child(player)
	player.free()
	tile_map_layer.free()
	entities_parent.free()
	creatures_parent.free()
	Input.action_release("pickup")
	Input.action_release("stash")


func _add_stone(diameter_cm: float, offset: Vector2) -> LiftableStone:
	var stone := LiftableStone.new()
	stone.diameter_cm = diameter_cm
	stone.position = player.position + offset
	entities_parent.add_child(stone)
	chunk_manager._loaded_stones[Vector2i(0, 0)] = [stone]
	return stone


## A dropped item with a real, kickable-grade mass -- the SAME "physical
## object" set Kick already recognizes (see Player._nearest_kickable_
## dropped_item_near) -- the generic-item counterpart of _add_stone.
func _add_dropped_carrot(offset: Vector2) -> DroppedItem:
	var dropped := DroppedItem.new()
	dropped.item_stack = ItemStack.new(Item.new("carrot", "Carrot", "food", 20, 0.0, "", 0.0, 0.07), 1)
	dropped.position = player.position + offset
	add_child(dropped)
	return dropped


## A dropped item with NO modeled mass (item.gd's own "0.0 = not modeled"
## convention) -- most food/material drops today. Should stay OUT of the
## hand-hold system entirely and keep going straight to inventory via the
## ordinary sweep, unchanged.
func _add_dropped_hide(offset: Vector2) -> DroppedItem:
	var dropped := DroppedItem.new()
	dropped.item_stack = ItemStack.new(Item.new("hide", "Hide", "material", 40), 1)
	dropped.position = player.position + offset
	add_child(dropped)
	return dropped


func _tap_stash() -> void:
	Input.action_press("stash")
	player._stash_step()
	Input.action_release("stash")
	player._stash_step()


func test_starts_empty_handed():
	assert_false(player.is_holding_stone())


func test_pressing_e_near_a_liftable_stone_picks_it_into_the_hand_not_inventory():
	var stone := _add_stone(3.0, Vector2(5, 0))
	Input.action_press("pickup")
	player._pickup_step(0.016)
	assert_true(player.is_holding_stone())
	assert_true(stone.is_queued_for_deletion(), "the stone should have left the ground")
	assert_eq(player.inventory.count_of("rock"), 0, "it should go to the HAND, not straight to inventory")
	Input.action_release("pickup")
	player._pickup_step(0.016)


## With no stone nearby, E should behave exactly as the ordinary pickup sweep
## always has -- picking up other ground items normally.
func test_with_no_stone_nearby_e_still_does_the_ordinary_sweep():
	Input.action_press("pickup")
	player._pickup_step(0.016)
	assert_false(player.is_holding_stone())
	Input.action_release("pickup")
	player._pickup_step(0.016)


func test_holding_e_after_picking_up_charges_the_meter():
	_add_stone(3.0, Vector2(5, 0))
	Input.action_press("pickup")
	player._pickup_step(0.016)  # this press: picks the stone into hand
	Input.action_release("pickup")
	player._pickup_step(0.016)  # release: nothing thrown yet (was the pickup press, not a charge)
	assert_true(player.is_holding_stone(), "should still be holding after the pickup release")

	Input.action_press("pickup")
	player._pickup_step(0.016)  # NEW press while already holding -- starts a charge
	assert_true(player.is_holding_stone())
	var fraction_early := player.hand_charge_fraction()

	for _i in 20:
		player._pickup_step(0.05)  # keep holding -- meter should keep bouncing
	var fraction_later := player.hand_charge_fraction()

	assert_true(player.is_holding_stone(), "still holding while charging, not yet thrown")
	# The meter should have visibly moved from its starting reading.
	assert_ne(fraction_early, fraction_later)
	Input.action_release("pickup")
	player._pickup_step(0.016)


func test_releasing_e_while_charging_throws_the_stone_and_empties_the_hand():
	_add_stone(3.0, Vector2(5, 0))
	Input.action_press("pickup")
	player._pickup_step(0.016)  # pick into hand
	Input.action_release("pickup")
	player._pickup_step(0.016)  # release (no-op, was the pickup press)

	Input.action_press("pickup")
	player._pickup_step(0.016)  # start charging
	for _i in 5:
		player._pickup_step(0.05)
	Input.action_release("pickup")
	player._pickup_step(0.016)  # release -> throw

	assert_false(player.is_holding_stone(), "the hand should be empty after throwing")


## The thrown stone should reappear in the world, further from the player
## than a bare NUDGE/KICK distance would put it -- a real momentum-driven
## throw, not a no-op.
func test_a_thrown_stone_reappears_further_from_the_player():
	_add_stone(3.0, Vector2(5, 0))
	Input.action_press("pickup")
	player._pickup_step(0.016)
	Input.action_release("pickup")
	player._pickup_step(0.016)

	Input.action_press("pickup")
	player._pickup_step(0.016)
	for _i in 5:
		player._pickup_step(0.05)
	Input.action_release("pickup")
	player._pickup_step(0.016)

	var thrown_stones := get_tree().get_nodes_in_group(DroppedItem.GROUP_NAME)
	var found := false
	for node in thrown_stones:
		if node is LiftableStone and not node.is_queued_for_deletion():
			var distance := player.position.distance_to(node.position)
			if distance > 1.0:
				found = true
	assert_true(found, "a thrown stone should have landed somewhere away from the player")


# -- generalized to any real physical object, not just stones (reported ----
# -- live: "pick up should put it in the hand first instead of the ---------
# -- inventory ... there should be an extra key to stash the item in hand --
# -- into inventory") -- a dropped item with a real, kickable-grade mass ---
# -- (the same set Kick already recognizes) is a hand object exactly like --
# -- a stone; one with no modeled mass (most food/material drops) is NOT, --
# -- and keeps going straight to inventory unchanged. -----------------------

func test_starts_holding_nothing_at_all():
	assert_false(player.is_holding_item())
	assert_false(player.is_holding_anything())


func test_pressing_e_near_a_kickable_dropped_item_picks_it_into_the_hand_not_inventory():
	var dropped := _add_dropped_carrot(Vector2(5, 0))
	Input.action_press("pickup")
	player._pickup_step(0.016)
	assert_true(player.is_holding_item())
	assert_true(player.is_holding_anything())
	assert_true(dropped.is_queued_for_deletion(), "the item should have left the ground")
	assert_eq(player.inventory.count_of("carrot"), 0, "it should go to the HAND, not straight to inventory")
	Input.action_release("pickup")
	player._pickup_step(0.016)


## The scope boundary: an item with NO real modeled mass (most food/
## material drops today) is not a hand-hold object -- it must keep going
## straight to inventory via the ordinary sweep, exactly as before this
## change.
func test_pressing_e_near_an_unmassed_dropped_item_still_goes_straight_to_inventory():
	_add_dropped_hide(Vector2(5, 0))
	Input.action_press("pickup")
	player._pickup_step(0.016)
	assert_false(player.is_holding_anything(), "an item with no modeled mass should never enter the hand")
	assert_eq(player.inventory.count_of("hide"), 1, "it should still go straight to inventory, unchanged")
	Input.action_release("pickup")
	player._pickup_step(0.016)


func test_stone_pickup_still_takes_priority_over_a_dropped_item_when_both_are_near():
	_add_stone(3.0, Vector2(5, 0))
	_add_dropped_carrot(Vector2(5, 0))
	Input.action_press("pickup")
	player._pickup_step(0.016)
	assert_true(player.is_holding_stone())
	assert_false(player.is_holding_item(), "only one thing occupies the hand at a time")
	Input.action_release("pickup")
	player._pickup_step(0.016)


func test_releasing_e_while_charging_throws_the_held_item_and_empties_the_hand():
	_add_dropped_carrot(Vector2(5, 0))
	Input.action_press("pickup")
	player._pickup_step(0.016)  # pick into hand
	Input.action_release("pickup")
	player._pickup_step(0.016)  # release (no-op, was the pickup press)

	Input.action_press("pickup")
	player._pickup_step(0.016)  # start charging
	for _i in 5:
		player._pickup_step(0.05)
	Input.action_release("pickup")
	player._pickup_step(0.016)  # release -> throw

	assert_false(player.is_holding_anything(), "the hand should be empty after throwing")


func test_a_thrown_held_item_reappears_as_a_real_dropped_item_away_from_the_player():
	_add_dropped_carrot(Vector2(5, 0))
	Input.action_press("pickup")
	player._pickup_step(0.016)
	Input.action_release("pickup")
	player._pickup_step(0.016)

	Input.action_press("pickup")
	player._pickup_step(0.016)
	for _i in 5:
		player._pickup_step(0.05)
	Input.action_release("pickup")
	player._pickup_step(0.016)

	var found := false
	for node in get_tree().get_nodes_in_group(DroppedItem.GROUP_NAME):
		if node is DroppedItem and not node.is_queued_for_deletion() and node.item_stack != null:
			if node.item_stack.item.id == "carrot" and player.position.distance_to(node.position) > 1.0:
				found = true
	assert_true(found, "a thrown carrot should have landed as a real dropped item, away from the player")


# -- the stash key: the deliberate "put this down" complement to E's -------
# -- "pick this up into hand" ------------------------------------------------

func test_stash_does_nothing_when_holding_nothing():
	_tap_stash()
	assert_false(player.is_holding_anything())


func test_stash_puts_a_held_stone_into_inventory_as_rock():
	_add_stone(3.0, Vector2(5, 0))
	Input.action_press("pickup")
	player._pickup_step(0.016)
	Input.action_release("pickup")
	player._pickup_step(0.016)
	assert_true(player.is_holding_stone(), "precondition: the stone should be in hand")

	var expected_rock := StoneSize.rock_yield(3.0)
	_tap_stash()
	assert_false(player.is_holding_anything(), "the hand should be empty after stashing")
	assert_eq(player.inventory.count_of("rock"), expected_rock)


func test_stash_puts_a_held_item_into_inventory():
	_add_dropped_carrot(Vector2(5, 0))
	Input.action_press("pickup")
	player._pickup_step(0.016)
	Input.action_release("pickup")
	player._pickup_step(0.016)
	assert_true(player.is_holding_item(), "precondition: the carrot should be in hand")

	_tap_stash()
	assert_false(player.is_holding_anything(), "the hand should be empty after stashing")
	assert_eq(player.inventory.count_of("carrot"), 1)


## Stashing never silently discards anything: whatever doesn't fit in a
## full inventory drops as a real ground item at the player's feet instead.
func test_stash_drops_the_overflow_at_the_players_feet_when_inventory_is_full():
	player.inventory = Inventory.new(1)
	player.inventory.add(Item.new("wood", "Wood", "material", 40), 1)  # fills the only slot

	_add_dropped_carrot(Vector2(5, 0))
	Input.action_press("pickup")
	player._pickup_step(0.016)
	Input.action_release("pickup")
	player._pickup_step(0.016)
	assert_true(player.is_holding_item(), "precondition: the carrot should be in hand")

	_tap_stash()
	assert_false(player.is_holding_anything(), "stashing always empties the hand, even on overflow")
	assert_eq(player.inventory.count_of("carrot"), 0, "the full inventory should not have taken it")

	var found := false
	for node in get_tree().get_nodes_in_group(DroppedItem.GROUP_NAME):
		if node is DroppedItem and not node.is_queued_for_deletion() and node.item_stack != null:
			if node.item_stack.item.id == "carrot" and player.position.distance_to(node.position) < 1.0:
				found = true
	assert_true(found, "the carrot that didn't fit should be dropped at the player's own feet, not lost")
