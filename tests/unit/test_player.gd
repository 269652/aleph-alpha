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
	Input.action_release("trade")


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


func _tap_trade() -> void:
	Input.action_press("trade")
	player._shop_step(0.0)
	Input.action_release("trade")
	player._shop_step(0.0)


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
	assert_eq(player.inventory_counts().get("cooked_meat", 0), 0)


# -- catching a real, visible fish flavors the catch message ------------------
#
# The abstract fishing minigame (see FishingSession/FishingMinigame) already
# decides success/rarity/reward on its own; this only covers the NEW piece --
# when a real FishMarker happens to be nearby, catching removes it and names
## its species in the message, without changing what's actually rewarded.

const FishMarker = preload("res://src/rendering/fish_marker.gd")


## Drives the real FishingSession to CAUGHT deterministically (bait_quality 1.0
## biases toward the minimum bite delay; a bounded advance loop reaches BITING
## well within FishingMinigame.MAX_BITE_DELAY).
func _land_a_fish() -> void:
	player._fishing.cast(1, 1.0)
	for i in 40:
		if player._fishing.phase() == "biting":
			break
		player._fishing.advance(0.5)
	player._fishing.react()


func test_catching_a_fish_near_a_real_fish_marker_removes_it_and_names_it_in_the_message():
	var fish := FishMarker.new()
	fish.species = "goldfish"
	fish.position = player.position
	creatures_parent.add_child(fish)
	chunk_manager._loaded_fish[Vector2i(0, 0)] = [fish]

	_land_a_fish()
	player._fishing_step(0.0)

	assert_false(is_instance_valid(fish), "the nearby fish marker should be freed on catch")
	assert_string_contains(player.fishing_message, "goldfish")


# -- equipping a weapon/tool updates the paperdoll, not just the in-hand sprite -----
#
# Previously equip_item only set Player.equipped_item and the in-hand sprite;
# Player.equipment (what the inventory window's Character screen paperdoll
# actually reads, see World._equipped_map) was never touched for
# weapons/tools -- only equip_armor updated it. Clicking a weapon/tool in the
# inventory produced no visible feedback on the Character screen at all.

func test_equipping_a_tool_updates_the_paperdolls_weapon_slot():
	var rod := _item_catalog.make("fishing_rod")
	player.inventory.add(rod, 1)

	assert_true(player.equip_item(rod))

	assert_eq(player.equipment.equipped_in("weapon"), rod)


func test_equipping_a_weapon_via_activate_item_id_updates_the_paperdoll():
	player.inventory.add(_item_catalog.make("iron_sword"), 1)

	assert_true(player.activate_item_id("iron_sword"))

	assert_eq(player.equipment.equipped_in("weapon").id, "iron_sword")


## activate_hotbar_slot didn't special-case armor before calling equip_item
## (which rejects non-weapon/tool kinds outright) -- armor from the numbered
## hotbar always silently failed, even though the same item worked fine via
## the inventory window's click handler (activate_item_id).
func test_activate_hotbar_slot_equips_armor_via_the_armor_path():
	player.inventory.add(_item_catalog.make("leather_helm"), 1)

	assert_true(player.activate_hotbar_slot(_stack_index_of("leather_helm")))

	assert_eq(player.equipment.equipped_in("head").id, "leather_helm")


func test_catching_a_fish_with_no_marker_nearby_still_shows_a_generic_message():
	_land_a_fish()
	player._fishing_step(0.0)

	assert_string_contains(player.fishing_message, "Caught")


# -- shopping at a merchant villager (see VillageRenderer, Shop) --------------

const NpcMarker = preload("res://src/rendering/npc_marker.gd")
const NpcIdentity = preload("res://src/world/npc_identity.gd")
const Shop = preload("res://src/gameplay/shop.gd")


func _add_fake_merchant_near_player() -> NpcMarker:
	var merchant := NpcMarker.new()
	merchant.identity = NpcIdentity.new(1)
	merchant.identity.occupation = "merchant"
	merchant.position = player.position
	creatures_parent.add_child(merchant)
	chunk_manager._loaded_villages[Vector2i(0, 0)] = [merchant]
	return merchant


func test_trading_with_no_merchant_nearby_shows_a_no_merchant_message():
	_tap_trade()
	assert_string_contains(player.trade_message, "No merchant")


func test_trading_near_a_merchant_buys_an_item_and_shows_a_message():
	var merchant := _add_fake_merchant_near_player()
	var shop := Shop.new()
	# Some catalog items (e.g. fishing_rod) may already be in the player's
	# starting inventory -- compare before/after rather than assuming 0.
	var item_id: String = shop.known_item_ids()[0]
	var before: int = player.inventory_counts().get(item_id, 0)
	player.wallet.add(shop.price_of(item_id))

	_tap_trade()

	assert_eq(player.wallet.balance, 0)
	assert_eq(player.inventory_counts().get(item_id, 0), before + 1)
	assert_string_contains(player.trade_message, "Bought")
	merchant.free()


func test_trading_without_enough_gold_shows_a_not_enough_gold_message():
	var merchant := _add_fake_merchant_near_player()
	player.wallet.balance = 0

	_tap_trade()

	assert_string_contains(player.trade_message, "Not enough gold")
	merchant.free()


func test_repeated_purchases_cycle_through_different_items():
	var merchant := _add_fake_merchant_near_player()
	var shop := Shop.new()
	var total_cost := 0
	for item_id in shop.known_item_ids():
		total_cost += shop.price_of(item_id)
	player.wallet.add(total_cost)

	var bought := {}
	for i in shop.known_item_ids().size():
		_tap_trade()
		for item_id in shop.known_item_ids():
			if player.inventory_counts().get(item_id, 0) > 0:
				bought[item_id] = true

	assert_gt(bought.size(), 1, "repeated purchases should buy more than one distinct item")
	merchant.free()


# -- rare/legendary fish grant a real buff on eating --------------------------

const FoodConsumption = preload("res://src/gameplay/food_consumption.gd")


func test_eating_a_rare_fish_grants_a_sustenance_buff():
	player.inventory.add(_item_catalog.make("rare_fish"), 1)
	assert_true(player.eat_food("rare_fish"))

	var buff := FoodConsumption.buff_in_category(player.active_food_buffs, "sustenance")
	assert_eq(buff.buff, "stamina_regen")
	assert_gt(buff.time_remaining, 0.0)


func test_eating_a_legendary_fish_grants_a_combat_buff():
	player.inventory.add(_item_catalog.make("legendary_fish"), 1)
	assert_true(player.eat_food("legendary_fish"))

	var buff := FoodConsumption.buff_in_category(player.active_food_buffs, "combat")
	assert_eq(buff.buff, "damage_boost")
	assert_gt(buff.time_remaining, 0.0)


func test_eating_a_plain_fish_grants_no_buff():
	player.inventory.add(_item_catalog.make("fish"), 1)
	assert_true(player.eat_food("fish"))

	assert_eq(player.active_food_buffs.size(), 0)


func test_damage_buff_multiplier_is_higher_after_eating_a_legendary_fish():
	var before := player._damage_buff_multiplier()

	player.inventory.add(_item_catalog.make("legendary_fish"), 1)
	player.eat_food("legendary_fish")

	assert_gt(player._damage_buff_multiplier(), before)


func test_food_buff_step_boosts_stamina_regen_while_the_sustenance_buff_is_active():
	player.survival.stamina = 0.0
	player.inventory.add(_item_catalog.make("rare_fish"), 1)
	player.eat_food("rare_fish")

	player._food_buff_step(1.0)

	assert_gt(player.survival.stamina, 0.0)


func test_food_buff_step_does_nothing_extra_without_an_active_sustenance_buff():
	player.survival.stamina = 0.0

	player._food_buff_step(1.0)

	assert_eq(player.survival.stamina, 0.0)


func test_food_buff_step_expires_the_buff_after_its_duration():
	player.inventory.add(_item_catalog.make("rare_fish"), 1)
	player.eat_food("rare_fish")

	player._food_buff_step(10000.0)  # comfortably longer than any buff duration

	assert_eq(player.active_food_buffs.size(), 0)
