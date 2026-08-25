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
const CreatureMarker = preload("res://src/rendering/creature_marker.gd")
const CreatureInfo = preload("res://src/world/creature_info.gd")
const RopeTether = preload("res://src/gameplay/rope_tether.gd")
const Taming = preload("res://src/gameplay/taming.gd")
const TerrainPassability = preload("res://src/gameplay/terrain_passability.gd")
const EarthChunkGenerator = preload("res://src/world/earth_chunk_generator.gd")

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
	Input.action_release("talk")


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
	# Hotbar slots hold an explicitly assigned item id now (see Hotbar), not
	# whatever happens to sit at that inventory index.
	player.assign_hotbar_slot(0, "furnace")

	var handled := player.activate_hotbar_slot(0)

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


# -- Player.craft's generalized recipe gating (see docs/concept/ -------------
# -- production_chains.md): the old hardcoded "if is_smelting_recipe(...) -----
# -- and not _has_heat_source(): return false" special case is replaced ------
# -- by a GENERIC read of CraftingRecipeBook's own "requires_structure"/ -----
# -- "required_skill" recipe fields -- proven here two ways: the smelting ----
# -- heat-gate itself must keep behaving EXACTLY as before (regression), -----
# -- and the SAME mechanism must gate a totally different recipe/structure ---
# -- (Sägewerk log shaping) with no new hardcoded branch. ---------------------

func _give(item_id: String, count: int = 1) -> void:
	player.inventory.add(_item_catalog.make(item_id), count)


## Regression: smelting recipes still refuse to craft with no heat source
## nearby -- the exact behavior _has_heat_source already had, now reached
## generically via requires_structure == "heat_source" instead of a
## hardcoded is_smelting_recipe branch.
func test_craft_iron_ingot_fails_with_no_heat_source_nearby():
	_give("iron_ore")
	_give("coal")

	assert_false(player.craft("iron_ingot"))
	assert_eq(player.inventory_counts().get("iron_ingot", 0), 0)
	# Nothing consumed on a blocked craft.
	assert_eq(player.inventory_counts().get("iron_ore", 0), 1)


## Regression: a placed CAMPFIRE still counts as a heat source for smelting
## (Player._has_heat_source accepts campfire OR furnace) -- the generalized
## "heat_source" category must not silently narrow this to furnace-only.
func test_craft_iron_ingot_succeeds_with_a_campfire_nearby():
	var tile := player.current_tile()
	chunk_manager.build_at_global(tile.x + 1, tile.y, "campfire")
	_give("iron_ore")
	_give("coal")

	assert_true(player.craft("iron_ingot"))
	assert_eq(player.inventory_counts().get("iron_ingot", 0), 1)


## Regression: a placed FURNACE also still counts.
func test_craft_iron_ingot_succeeds_with_a_furnace_nearby():
	var tile := player.current_tile()
	chunk_manager.build_at_global(tile.x + 1, tile.y, "furnace")
	_give("iron_ore")
	_give("coal")

	assert_true(player.craft("iron_ingot"))
	assert_eq(player.inventory_counts().get("iron_ingot", 0), 1)


## A recipe with NO requires_structure/required_skill (torch) is completely
## unaffected by the generalized gate -- proves the generalization is
## additive, not a behavior change for every other recipe.
func test_craft_torch_is_unaffected_by_the_generalized_gate():
	_give("wood")
	_give("hide")

	assert_true(player.craft("torch"))


## The SAME generic mechanism gates a totally different recipe/structure
## pair (log_to_balken requires "sagewerk", not "heat_source") with zero
## new code in Player.craft -- proves it's real generalization, not a
## second hardcoded special case for the Sägewerk.
func test_craft_log_to_balken_fails_without_a_nearby_sagewerk():
	_give("log", 3)

	assert_false(player.craft("log_to_balken"))
	assert_eq(player.inventory_counts().get("beam", 0), 0)


func test_craft_log_to_balken_succeeds_with_a_nearby_sagewerk():
	var tile := player.current_tile()
	chunk_manager.build_at_global(tile.x + 1, tile.y, "sagewerk")
	_give("log", 3)

	assert_true(player.craft("log_to_balken"))
	assert_eq(player.inventory_counts().get("beam", 0), 1)


## required_skill's first real consumer (docs/concept/timber_construction.md's
## "generalized, not hardcoded" section): the sagewerk recipe itself needs
## real Carpentry, read live via SkillTree.total_bonus -- with none
## allocated, the craft is refused even though every material input is on
## hand.
func test_craft_sagewerk_fails_without_enough_carpentry_skill():
	_give("log", 8)
	_give("wood", 4)

	assert_false(player.craft("sagewerk"))
	assert_eq(player.inventory_counts().get("sagewerk", 0), 0)
	# Nothing consumed on a blocked craft.
	assert_eq(player.inventory_counts().get("log", 0), 8)


## Allocating the real carpentry_1 + carpentry_2 nodes (the same total_bonus
## read Player._chop_step's own CARPENTRY_LEVEL_FOR_SAWING check uses)
## clears the skill gate.
func test_craft_sagewerk_succeeds_with_enough_carpentry_skill():
	_give("log", 8)
	_give("wood", 4)
	player.allocated_nodes = {"carpentry_1": true, "carpentry_2": true}

	assert_true(player.craft("sagewerk"))
	assert_eq(player.inventory_counts().get("sagewerk", 0), 1)


# -- collecting a Sägewerk's real StructureStock straight into inventory ------
#
# docs/concept/timber_construction.md's "Storage, logistics, and the
# autonomous dependency chain" section: shaped beam/plank now credits the
# Sägewerk's own StructureStock instead of dropping on the ground (see
# LumberjackMarker._step_production) -- a player with no Storage/Logistics
# built yet needs a real, direct way to collect it, mirroring the swing-driven
# interaction convention _chop_step/_butcher_step already establish.

func test_collect_step_withdraws_real_beam_and_plank_stock_into_inventory():
	var tile := player.current_tile()
	chunk_manager.build_at_global(tile.x + 1, tile.y, "sagewerk")
	chunk_manager.deposit_to_structure_at(tile.x + 1, tile.y, "beam", 3)
	chunk_manager.deposit_to_structure_at(tile.x + 1, tile.y, "plank", 2)

	player._collect_step()

	assert_eq(player.inventory_counts().get("beam", 0), 3)
	assert_eq(player.inventory_counts().get("plank", 0), 2)
	assert_eq(chunk_manager.structure_stock_at(tile.x + 1, tile.y, "beam"), 0)
	assert_eq(chunk_manager.structure_stock_at(tile.x + 1, tile.y, "plank"), 0)


func test_collect_step_no_ops_with_a_nearby_sagewerk_but_nothing_stocked():
	var tile := player.current_tile()
	chunk_manager.build_at_global(tile.x + 1, tile.y, "sagewerk")

	player._collect_step()

	assert_eq(player.inventory_counts().get("beam", 0), 0)
	assert_eq(player.inventory_counts().get("plank", 0), 0)


func test_collect_step_no_ops_with_no_sagewerk_nearby():
	chunk_manager.deposit_to_structure_at(0, 0, "beam", 3)  # nowhere real, no sagewerk built

	player._collect_step()

	assert_eq(player.inventory_counts().get("beam", 0), 0)


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
	player.assign_hotbar_slot(0, "leather_helm")

	assert_true(player.activate_hotbar_slot(0))

	assert_eq(player.equipment.equipped_in("head").id, "leather_helm")


# -- assignable hotbar (drag an item onto a slot) -----------------------------
#
# The hotbar used to just mirror the first 5 inventory stacks, so an item
# further down the pack could never be put on a number key at all -- the
# reported "can't drag the rod into the hotbar / can't equip it by any other
# means". Slots are now explicitly assignable.

func test_assigning_an_item_to_a_hotbar_slot_makes_that_slot_activate_it():
	player.inventory.add(_item_catalog.make("fishing_rod"), 1)

	player.assign_hotbar_slot(4, "fishing_rod")

	assert_eq(player.hotbar.item_id_at(4), "fishing_rod")
	assert_true(player.activate_hotbar_slot(4))
	assert_eq(player.equipment.equipped_in("weapon").id, "fishing_rod")


## The whole point of the fix: the player starts with 5 stacks, which used to
## fill every hotbar slot -- so a 6th item could never reach a key at all.
## It must still be assignable.
func test_an_item_past_the_hotbars_capacity_can_still_be_assigned_and_equipped():
	player.inventory.add(_item_catalog.make("stone_pickaxe"), 1)
	assert_gt(
		_stack_index_of("stone_pickaxe"), player.hotbar.slot_count - 1,
		"precondition: pickaxe should sit past the hotbar's slot count"
	)

	player.assign_hotbar_slot(0, "stone_pickaxe")

	assert_true(player.activate_hotbar_slot(0))
	assert_eq(player.equipment.equipped_in("weapon").id, "stone_pickaxe")


func test_activating_an_empty_hotbar_slot_is_a_no_op():
	player.hotbar.clear_slot(3)
	assert_false(player.activate_hotbar_slot(3))


## Newly picked-up items should still reach the bar on their own while slots
## remain free, so the assignable hotbar doesn't make early play worse.
func test_hotbar_auto_fills_free_slots_from_the_inventory():
	for i in player.hotbar.slot_count:
		player.hotbar.clear_slot(i)
	player.inventory.add(_item_catalog.make("wood"), 1)

	player.sync_hotbar()

	var filled := 0
	for i in player.hotbar.slot_count:
		if player.hotbar.item_id_at(i) != "":
			filled += 1
	assert_gt(filled, 0, "sync_hotbar should auto-fill free slots from what's held")


func test_sync_hotbar_never_overwrites_an_explicit_assignment():
	player.inventory.add(_item_catalog.make("stone_pickaxe"), 1)
	player.assign_hotbar_slot(0, "stone_pickaxe")

	player.sync_hotbar()

	assert_eq(player.hotbar.item_id_at(0), "stone_pickaxe")


## An item you've used up shouldn't keep occupying a key.
func test_sync_hotbar_clears_slots_for_items_no_longer_held():
	player.inventory.add(_item_catalog.make("stone_pickaxe"), 1)
	player.assign_hotbar_slot(0, "stone_pickaxe")
	player.inventory.remove("stone_pickaxe", 1)

	player.sync_hotbar()

	assert_ne(player.hotbar.item_id_at(0), "stone_pickaxe")


# -- fishing visuals: cast, bobber, attraction (see FishingCast) -------------
#
# Reported gap: casting had no rod-throw motion, no landing point shown, and
# no reaction from nearby fish or when a bite starts. Exercises
# _start_cast_visuals/_end_cast_visuals directly (same "bypass the near-water
# input gate" approach _land_a_fish already uses above) rather than through
# the full input flow, since whether the test's fixed real-terrain spawn tile
# happens to be near water isn't something a test should depend on.

func test_start_cast_visuals_shows_the_bobber_at_the_cast_point():
	assert_false(player._bobber.visible)

	player._start_cast_visuals()

	assert_true(player._bobber.visible)
	var expected := player._fishing_cast.cast_point(player.position, player._last_facing_direction)
	assert_almost_eq(player._bobber.global_position.x, expected.x, 0.01)
	assert_almost_eq(player._bobber.global_position.y, expected.y, 0.01)


func test_start_cast_visuals_plays_the_rod_throw_swing():
	player._start_cast_visuals()
	# play_attack_swing arms a countdown consumed over SWING_DURATION --
	# still mid-swing immediately after casting.
	assert_gt(player._character_view._swing_time_remaining, 0.0)


func test_start_cast_visuals_attracts_nearby_fish():
	var fish := preload("res://src/rendering/fish_marker.gd").new()
	fish.position = player.position + Vector2(10, 0)
	creatures_parent.add_child(fish)
	chunk_manager._loaded_fish[Vector2i(0, 0)] = [fish]

	player._start_cast_visuals()

	assert_not_null(fish.attract_target)
	fish.free()


## _end_cast_visuals in isolation, separate from a real catch resolution
## below -- catch_nearest_fish would otherwise free this same nearby test
## fish as an unrelated side effect (ATTRACTION_RADIUS < FISH_CATCH_RADIUS,
## so anything close enough to be attracted is also close enough to be
## "caught"), touching a freed object.
func test_end_cast_visuals_hides_the_bobber_and_releases_attraction():
	var fish := preload("res://src/rendering/fish_marker.gd").new()
	fish.position = player.position + Vector2(10, 0)
	creatures_parent.add_child(fish)
	chunk_manager._loaded_fish[Vector2i(0, 0)] = [fish]
	player._start_cast_visuals()
	assert_not_null(fish.attract_target, "precondition: the cast should have attracted it")

	player._end_cast_visuals()

	assert_false(player._bobber.visible)
	assert_null(fish.attract_target)
	fish.free()


func test_resolving_a_catch_hides_the_bobber():
	player._start_cast_visuals()
	assert_true(player._bobber.visible)

	_land_a_fish()
	player._fishing_step(0.0)

	assert_false(player._bobber.visible)


## Regression: _ready() used to leave a solid red placeholder square
## permanently equipped in the head slot ("demo equipment until a real
## inventory system exists") -- reported as "a red square on its head", with
## no relation to any actually-worn armor (equip_armor never touches
## CharacterView at all). A fresh spawn should show no head-slot decoration.
func test_spawning_does_not_leave_a_placeholder_head_slot_equipped():
	assert_false(player._character_view.is_slot_equipped("head"))


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


# -- talking to a nearby villager (see NpcGreeting, EarthChunkManager.
# nearest_npc_near) -----------------------------------------------------------

const NpcGreeting = preload("res://src/world/npc_greeting.gd")


func _add_fake_npc_near_player(seed_value: int = 1) -> NpcMarker:
	var npc := NpcMarker.new()
	npc.identity = NpcIdentity.new(seed_value)
	npc.position = player.position
	creatures_parent.add_child(npc)
	chunk_manager._loaded_villages[Vector2i(0, 0)] = [npc]
	return npc


func _tap_talk() -> void:
	Input.action_press("talk")
	player._talk_step(0.0)
	Input.action_release("talk")
	player._talk_step(0.0)


func test_talking_with_no_villager_nearby_shows_a_no_one_message():
	_tap_talk()
	assert_string_contains(player.talk_message, "No one")


func test_talking_near_a_villager_shows_that_villagers_own_greeting():
	var npc := _add_fake_npc_near_player(7)
	var greeting := NpcGreeting.new()

	_tap_talk()

	assert_eq(player.talk_message, greeting.greeting_for(npc.identity))
	npc.free()


# -- selling food into a village (see VillageMarket, docs/concept/npc.md
# "Local trade is NPC-to-NPC, not just player-to-shop" extended here to a
# player-initiated sale; docs/concept/progression.md "Ecological literacy") --

const VillageMarket = preload("res://src/world/village_market.gd")
const EcologicalLiteracy = preload("res://src/gameplay/ecological_literacy.gd")


## Like _add_fake_npc_near_player, but with a real VillageMarket wired up (see
## NpcMarker.setup_economy) -- what a producer/non-merchant villager actually
## has, unlike the plain talk-only fixture above.
func _add_fake_npc_with_market_near_player(seed_value: int = 3) -> NpcMarker:
	var npc := NpcMarker.new()
	npc.identity = NpcIdentity.new(seed_value)
	npc.position = player.position
	creatures_parent.add_child(npc)
	chunk_manager._loaded_villages[Vector2i(0, 0)] = [npc]
	npc.setup_economy(VillageMarket.new())
	return npc


func test_sell_food_to_village_fails_without_enough_of_the_item():
	var market := VillageMarket.new()
	assert_false(player.sell_food_to_village(market, "cherry", 1))
	assert_eq(market.total_stock(), 0.0)


func test_sell_food_to_village_moves_the_item_into_the_markets_real_stock():
	player.inventory.add(_item_catalog.make("cherry"), 3)
	var market := VillageMarket.new()

	assert_true(player.sell_food_to_village(market, "cherry", 2))

	assert_eq(player.inventory.count_of("cherry"), 1)
	assert_almost_eq(market.stock.get("cherry", 0.0), 2.0, 0.001)


## The real, tested claim: selling into a genuinely hungry market (can't
## currently buy even one meal -- VillageMarket.can_buy_meal() reads false)
## awards more XP than selling into a well-stocked one.
func test_selling_into_a_hungry_village_awards_more_xp_than_a_well_stocked_one():
	player.inventory.add(_item_catalog.make("cherry"), 2)

	var hungry_market := VillageMarket.new()
	assert_false(hungry_market.can_buy_meal(), "precondition: genuinely hungry, no stock at all")
	var xp_before := player.experience.total_xp
	player.sell_food_to_village(hungry_market, "cherry", 1)
	var hungry_xp_gained := player.experience.total_xp - xp_before
	assert_eq(
		hungry_xp_gained,
		EcologicalLiteracy.VILLAGE_SALE_XP_BASE + EcologicalLiteracy.VILLAGE_FEEDING_XP_BONUS
	)

	var stocked_market := VillageMarket.new()
	stocked_market.add_stock("meat", 10.0)
	assert_true(stocked_market.can_buy_meal(), "precondition: well-stocked")
	xp_before = player.experience.total_xp
	player.sell_food_to_village(stocked_market, "cherry", 1)
	var stocked_xp_gained := player.experience.total_xp - xp_before
	assert_eq(stocked_xp_gained, EcologicalLiteracy.VILLAGE_SALE_XP_BASE)

	assert_gt(hungry_xp_gained, stocked_xp_gained, "feeding a genuinely hungry village should earn more")


## The trade key (T) already buys from a MERCHANT (see _shop_step above);
## with no merchant near but a real villager in reach, it now falls back to
## selling the player's own food into that villager's market instead.
func test_trade_key_sells_food_to_a_nearby_villager_when_no_merchant_is_near():
	var npc := _add_fake_npc_with_market_near_player()
	player.inventory.add(_item_catalog.make("cherry"), 1)

	_tap_trade()

	assert_eq(player.inventory.count_of("cherry"), 0)
	assert_almost_eq(npc.economy.market.stock.get("cherry", 0.0), 1.0, 0.001)
	assert_string_contains(player.trade_message, "Sold")
	npc.free()


func test_trade_key_with_a_villager_near_but_no_food_shows_a_no_food_message():
	var npc := _add_fake_npc_with_market_near_player()
	_tap_trade()
	assert_string_contains(player.trade_message, "No food")
	npc.free()


## Unchanged from before this feature existed: no merchant AND no villager at
## all still shows the original message.
func test_trade_key_with_nobody_nearby_still_shows_the_original_no_merchant_message():
	_tap_trade()
	assert_string_contains(player.trade_message, "No merchant")


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


# -- venomous snake bites (see docs/concept/ecosystem_dynamics.md's Species
# roster and CreatureMarker._try_attack) -----------------------------------

const VenomModel = preload("res://src/gameplay/venom_model.gd")


func test_apply_venom_adds_an_active_venom_debuff():
	player.apply_venom()
	assert_eq(player.active_venom_debuffs.size(), 1)
	assert_eq(player.active_venom_debuffs[0]["debuff_id"], VenomModel.DEBUFF_ID)


func test_venom_step_deals_damage_over_time_while_active():
	player.apply_venom()
	var before := player.health

	player._venom_step(1.0)

	assert_lt(player.health, before)


func test_venom_step_does_nothing_without_an_active_venom_debuff():
	var before := player.health

	player._venom_step(1.0)

	assert_eq(player.health, before)


func test_venom_step_expires_after_its_duration():
	player.apply_venom()

	player._venom_step(VenomModel.DURATION_SECONDS + 1.0)

	assert_eq(player.active_venom_debuffs.size(), 0)


func test_repeated_bites_stack_venom_up_to_the_cap():
	for i in VenomModel.MAX_STACKS + 5:
		player.apply_venom()
	assert_eq(player.active_venom_debuffs[0]["stacks"], VenomModel.MAX_STACKS)


# -- disease spillover: routed through Sickness, NOT a new debuff module
# (see docs/concept/disease.md "Player spillover") ---------------------------

const DiseaseModel = preload("res://src/gameplay/disease_model.gd")
const Carcass = preload("res://src/rendering/carcass.gd")


func test_apply_disease_bite_with_zero_exposure_never_infects():
	player.apply_disease_bite(DiseaseModel.PREDATOR, 0.0)
	assert_eq(player.sickness_id, "")


## Sickness.infection_chance never reaches a guaranteed 1.0 by design (real
## exposure never means CERTAIN infection) -- retried across many rolls
## (each apply_disease_bite call draws a fresh seed off an incrementing
## counter) is the deterministic-enough way to prove this path CAN succeed,
## the same shape TamingSystem's own catch-rate tests already use for a
## chance that's real but not 100%.
func test_apply_disease_bite_can_infect_the_player():
	var infected := false
	for i in 50:
		player.sickness_id = ""
		player.apply_disease_bite(DiseaseModel.PREDATOR, 1.0)
		if player.sickness_id != "":
			infected = true
			break
	assert_true(infected, "a full-exposure bite should eventually infect across many rolls")
	assert_eq(player.sickness_id, DiseaseModel.PREDATOR)
	assert_gt(player.sickness_severity, 0.0)


func test_apply_disease_bite_does_nothing_while_already_sick():
	player.sickness_id = "existing"
	player.sickness_severity = 0.4
	player.apply_disease_bite(DiseaseModel.CARRION, 1.0)
	assert_eq(player.sickness_id, "existing")
	assert_eq(player.sickness_severity, 0.4)


func test_sickness_step_increases_severity_while_sick():
	player.sickness_id = "flu_test"
	player.sickness_severity = 0.1
	player._sickness_step(5.0)
	assert_gt(player.sickness_severity, 0.1)


func test_sickness_step_does_nothing_while_healthy():
	player._sickness_step(5.0)
	assert_eq(player.sickness_severity, 0.0)


## Not fatal outright (docs/concept/disease.md), a real ongoing tax instead --
## stamina regen, the same lever _food_buff_step's own "sustenance" buff
## already uses in reverse.
func test_sickness_step_drains_stamina_while_sick():
	player.sickness_id = "flu_test"
	player.sickness_severity = 1.0
	var before: float = player.survival.stamina
	player._sickness_step(1.0)
	assert_lt(player.survival.stamina, before)


func test_butchering_a_contaminated_carcass_can_expose_the_player():
	var carcass := Carcass.new()
	carcass.species = "boar"
	carcass.contaminated = true
	carcass.position = player.position
	add_child_autofree(carcass)

	var infected := false
	for i in 50:
		player.sickness_id = ""
		carcass._parts_taken = 0  # re-arm butcher() so each loop iteration takes a part
		player._butcher_step()
		if player.sickness_id != "":
			infected = true
			break
	assert_true(infected, "butchering a contaminated carcass should eventually infect the player")
	assert_eq(player.sickness_id, DiseaseModel.CARRION)


func test_butchering_a_clean_carcass_never_exposes_the_player():
	var carcass := Carcass.new()
	carcass.species = "boar"
	carcass.contaminated = false
	carcass.position = player.position
	add_child_autofree(carcass)

	player._butcher_step()

	assert_eq(player.sickness_id, "")


# -- taming: throwing the lasso (see docs/concept/taming.md) ------------------

func _horse_at(offset: Vector2) -> CreatureMarker:
	var marker := CreatureMarker.new()
	marker.info = CreatureInfo.new("horse", 1)
	marker.wander_seed = 9
	# Added to the TEST's own node, not the bare creatures_parent: that one is
	# never inside the SceneTree, so a marker under it never joins the
	# creature group the throw scans.
	add_child_autofree(marker)
	marker.setup(chunk_manager, TILE_SIZE)
	marker.position = player.position + offset
	return marker


func _hold_lasso() -> void:
	player.equipped_item = _item_catalog.make("lasso")


func test_throwing_the_lasso_catches_a_horse_within_reach():
	_hold_lasso()
	var horse := _horse_at(Vector2(Player.LASSO_RANGE * 0.5, 0))
	player._throw_lasso()
	assert_true(horse.is_restrained(), "a horse within reach should be caught")


## The throw is short on purpose: closing with a wary animal first is the part
## that makes stalking one feel like something.
func test_a_horse_out_of_reach_is_not_caught():
	_hold_lasso()
	var horse := _horse_at(Vector2(Player.LASSO_RANGE * 2.0, 0))
	player._throw_lasso()
	assert_false(horse.is_restrained())


func test_the_throw_takes_the_nearest_animal():
	_hold_lasso()
	var far := _horse_at(Vector2(Player.LASSO_RANGE * 0.9, 0))
	var near := _horse_at(Vector2(Player.LASSO_RANGE * 0.2, 0))
	player._throw_lasso()
	assert_true(near.is_restrained())
	assert_false(far.is_restrained(), "the rope only goes round one neck")


## Predators are not tameable with a rope and a carrot, so the throw must not
## even land on one.
func test_the_lasso_does_not_catch_a_predator():
	_hold_lasso()
	var lynx := CreatureMarker.new()
	lynx.info = CreatureInfo.new("lynx", 1)
	add_child_autofree(lynx)
	lynx.setup(chunk_manager, TILE_SIZE)
	lynx.position = player.position + Vector2(8, 0)
	player._throw_lasso()
	assert_false(lynx.is_restrained())


## Leading is nothing more than an anchor that walks with the player: the
## animal is pulled along and can never end up past the end of the rope.
func test_a_led_horse_is_towed_along_behind_the_player():
	_hold_lasso()
	var horse := _horse_at(Vector2(16, 0))
	# Worn down on purpose, so it stays caught for the whole walk: a healthy
	# horse would usually fight the rope off partway through (which is its
	# right, and is tested elsewhere) and leave this test asserting nothing.
	horse.info.health = horse.info.max_health * 0.05
	player._throw_lasso()
	assert_true(horse.is_restrained(), "precondition: the throw landed")
	for step in 400:
		player.position = Vector2(float(step) * 0.6, 0)
		player._lasso_step(1.0 / 60.0)
		horse._process(1.0 / 60.0)
	assert_true(horse.is_restrained(), "an exhausted horse should still be on the rope")
	assert_lte(
		horse.position.distance_to(player.position), RopeTether.ROPE_LENGTH + 0.01,
		"a led horse must stay within the rope"
	)


## A carrot only leaves the inventory when it actually bought something --
## walking a full horse past your carrots must not eat them.
func test_feeding_a_full_horse_costs_no_carrots():
	_hold_lasso()
	var horse := _horse_at(Vector2(8, 0))
	player._throw_lasso()
	player.inventory.add(_item_catalog.make("carrot"), 3)
	horse._needs.hunger = 0.0
	player._lasso_step(1.0 / 60.0)
	assert_eq(player.inventory.count_of("carrot"), 3)
	assert_eq(horse.trust, 0.0)


func test_feeding_a_hungry_horse_spends_a_carrot_and_earns_trust():
	_hold_lasso()
	var horse := _horse_at(Vector2(8, 0))
	player._throw_lasso()
	player.inventory.add(_item_catalog.make("carrot"), 3)
	horse._needs.hunger = 1.0
	player._lasso_step(1.0 / 60.0)
	assert_eq(player.inventory.count_of("carrot"), 2, "one carrot, one meal")
	assert_gt(horse.trust, 0.0)


# -- orders and riding (see docs/concept/taming.md) --------------------------

func _tamed_horse_at(offset: Vector2) -> CreatureMarker:
	var horse := _horse_at(offset)
	horse.restrain_to(horse.position)
	while not horse.is_tame():
		horse._needs.hunger = 1.0
		horse.feed_treat()
	horse.release()
	return horse


func test_the_order_key_cycles_a_tamed_animal_between_follow_and_stay():
	var horse := _tamed_horse_at(Vector2(12, 0))
	var first: int = horse.order
	player._cycle_order()
	assert_ne(horse.order, first, "the order should have changed")
	player._cycle_order()
	assert_eq(horse.order, first, "and come back round")


func test_a_wild_animal_ignores_the_order_key():
	var horse := _horse_at(Vector2(12, 0))
	player._cycle_order()
	assert_false(horse.is_tame())


## A following horse is told where its owner is every frame, so it can
## actually come to them.
func test_a_following_horse_is_told_where_its_owner_is():
	var horse := _tamed_horse_at(Vector2(12, 0))
	horse.set_order(Taming.ORDER_FOLLOW)
	player.position = Vector2(300, 300)
	player._lasso_step(1.0 / 60.0)
	assert_eq(horse.follow_target, player.position)


# -- riding -------------------------------------------------------------------

func test_mounting_a_tamed_horse_makes_the_player_faster():
	var horse := _tamed_horse_at(Vector2(12, 0))
	assert_eq(player.current_speed(), Player.BASE_SPEED, "on foot to begin with")
	assert_true(player._try_mount())
	assert_true(player.is_mounted())
	assert_eq(player.current_speed(), Taming.MOUNTED_SPEED)
	assert_not_null(horse)


func test_an_untamed_horse_cannot_be_ridden():
	var horse := _horse_at(Vector2(12, 0))
	assert_false(player._try_mount())
	assert_false(player.is_mounted())
	assert_false(horse.is_tame())


## A tamed boar follows and stays; it is not a horse.
func test_a_species_that_cannot_carry_a_person_is_not_a_mount():
	var boar := _horse_at(Vector2(12, 0))
	boar.info = CreatureInfo.new("boar", 1)
	boar.restrain_to(boar.position)
	while not boar.is_tame():
		boar._needs.hunger = 1.0
		boar.feed_treat()
	boar.release()
	assert_false(player._try_mount())


func test_a_horse_out_of_reach_cannot_be_mounted():
	var horse := _tamed_horse_at(Vector2(Player.LASSO_RANGE * 4.0, 0))
	assert_false(player._try_mount())
	assert_not_null(horse)


func test_dismounting_puts_the_player_back_on_foot():
	var _horse := _tamed_horse_at(Vector2(12, 0))
	player._try_mount()
	player._dismount()
	assert_false(player.is_mounted())
	assert_eq(player.current_speed(), Player.BASE_SPEED)


## The mount travels with the rider rather than being left behind -- riding a
## horse that stayed put would be a very strange kind of riding.
func test_the_mount_travels_with_its_rider():
	var horse := _tamed_horse_at(Vector2(12, 0))
	player._try_mount()
	player.position = Vector2(600, -220)
	player._lasso_step(1.0 / 60.0)
	assert_almost_eq(horse.position.distance_to(player.position), 0.0, 1.0)


# -- terrain slope: soft slowdown + hard refusal (see docs/concept/terrain_relief.md) -

func test_terrain_speed_multiplier_matches_terrain_passability_for_the_real_tile():
	var tile := player.current_tile()
	var slope := chunk_manager.slope_at_global(tile.x, tile.y)
	var expected := TerrainPassability.speed_multiplier(slope)
	assert_almost_eq(player._terrain_speed_multiplier(tile), expected, 0.0001)


func test_terrain_blocks_movement_is_false_when_not_moving():
	assert_false(player._terrain_blocks_movement(Vector2.ZERO))


## Wiring test: whatever the real slope at the look-ahead tile actually is,
## _terrain_blocks_movement must agree with TerrainPassability.is_passable
## for that exact slope -- proving the look-ahead/wrap/query chain reaches
## the same real data a direct call would, not that any particular real
## coordinate happens to be steep or flat.
func test_terrain_blocks_movement_agrees_with_terrain_passability_for_the_lookahead_tile():
	var input_direction := Vector2.DOWN
	var look_ahead := player.position + input_direction * player.TERRAIN_CHECK_DISTANCE_PX
	var raw := Vector2i(floori(look_ahead.x / TILE_SIZE), floori(look_ahead.y / TILE_SIZE))
	var world_size := Vector2i(EarthChunkGenerator.WORLD_WIDTH_TILES, EarthChunkGenerator.WORLD_HEIGHT_TILES)
	var ahead_tile: Vector2i = player._world_coordinates.wrap(raw, world_size)
	var slope := chunk_manager.slope_at_global(ahead_tile.x, ahead_tile.y)
	var expected := not TerrainPassability.is_passable(slope, player._has_climbing_gear())
	assert_eq(player._terrain_blocks_movement(input_direction), expected)


## Honest current state (see docs/progress.md's Transportation section): no
## climbing-rope item/equipment concept exists yet, so this always reads
## false. Exists so the day a real rope is built, this test starts failing
## loudly rather than the hook silently staying wired to "never."
func test_has_climbing_gear_is_false_until_a_real_rope_exists():
	assert_false(player._has_climbing_gear())
