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
const AnimalFitness = preload("res://src/world/animal_fitness.gd")
const TerrainPassability = preload("res://src/gameplay/terrain_passability.gd")
const EarthChunkGenerator = preload("res://src/world/earth_chunk_generator.gd")
const ConditionPenalty = preload("res://src/gameplay/condition_penalty.gd")
const Keybindings = preload("res://src/gameplay/keybindings.gd")
const MinableOre = preload("res://src/rendering/minable_ore.gd")
const SmashableStone = preload("res://src/rendering/smashable_stone.gd")
const Knapping = preload("res://src/gameplay/knapping.gd")
const StoneSize = preload("res://src/world/stone_size.gd")
const CaptureTool = preload("res://src/gameplay/capture_tool.gd")
const AmbientFlyerMarker = preload("res://src/rendering/ambient_flyer_marker.gd")
const BondedCompanionMarker = preload("res://src/rendering/bonded_companion_marker.gd")
const Item = preload("res://src/gameplay/item.gd")
const ProceduralItemSprite = preload("res://src/rendering/procedural_item_sprite.gd")
const DroppedItem = preload("res://src/rendering/dropped_item.gd")
const ItemStack = preload("res://src/gameplay/item_stack.gd")

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
	Input.action_release("fish")
	Input.action_release("block")


# -- a new player's starting kit (Player._ready()) --------------------------
# Superseded by the Starting Kit tab (docs/concept/starting_kit.md): a fresh
# Player used to auto-grant a fixed kit from _ready() itself (this test used
# to pin its exact contents, including a same-day report that added a glass
# bottle and butterfly net to that grant directly on `main`). That whole
# mechanism is gone now -- gear is the player's own choice, granted
# explicitly by World.grant_starter_items() AFTER the node is already in the
# tree (see the "starter kit" tests below) -- so the real contract left to
# pin here is the opposite of the old one: _ready() alone grants nothing.

func test_a_new_player_starts_completely_unequipped_before_any_grant():
	assert_null(player.equipped_item, "no automatic grant left in _ready() -- gear is the player's own choice now")
	for item_id in ["iron_sword", "iron_axe", "leather_helm", "leather_chest", "fishing_rod", "glass_bottle", "butterfly_net"]:
		assert_eq(player.inventory.count_of(item_id), 0, "%s: _ready() must not grant anything by itself" % item_id)


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


## The in-hand sprite must follow the item's sprite_id, not its raw id (see
## docs/concept/item_illustrations.md) -- a crafted/variant item can share a
## base item's art via a divergent sprite_id, and equip_item has to resolve
## art through that indirection rather than hard-coding `.id`.
func test_equipping_an_item_shows_its_sprite_id_art_not_its_raw_id():
	var variant := Item.new(
		"iron_sword_blessed", "Blessed Iron Sword", "weapon", 1, 25.0, "", 0.0, 0.0, "iron_sword"
	)
	player.inventory.add(variant, 1)

	assert_true(player.equip_item(variant))

	var expected := ProceduralItemSprite.new().generate_texture("iron_sword")
	assert_eq(
		player._character_view.tool_slot_texture().get_image().get_data(),
		expected.get_image().get_data(),
		"the held sprite should be iron_sword's art (the sprite_id), not iron_sword_blessed's"
	)


## -- item wear: accumulated combat fatigue (see docs/concept/item_durability.md) --
## Scoped to items with a real modeled material only (today: wooden_club/
## iron_sword/crude_blade -- ItemCatalog._WEAPON_MATERIAL_AND_VOLUME, the
## same gate weapon mass already uses), the same "not guessed at here"
## convention every other real-mass/real-material field in this codebase
## follows.

func test_a_connecting_attack_wears_the_held_weapon_with_modeled_material():
	var sword := _item_catalog.make("iron_sword")
	player.inventory.add(sword, 1)
	player.equip_item(sword)
	_creature_at("herbivore", Vector2(10, 0))

	player._perform_attack()

	assert_gt(sword.wear, 0.0, "a connecting attack must wear a real-material weapon")


func test_a_whiffed_attack_does_not_wear_the_weapon():
	var sword := _item_catalog.make("iron_sword")
	player.inventory.add(sword, 1)
	player.equip_item(sword)
	# No creature anywhere nearby -- this swing cannot connect.

	player._perform_attack()

	assert_almost_eq(sword.wear, 0.0, 0.0001, "a swing that hits nothing must not wear the weapon")


func test_attacking_with_an_unmodeled_material_item_never_accrues_wear():
	var axe := _item_catalog.make("iron_axe")  # no material modeled -- see item_catalog.gd
	player.inventory.add(axe, 1)
	player.equip_item(axe)
	_creature_at("herbivore", Vector2(10, 0))

	player._perform_attack()

	assert_almost_eq(axe.wear, 0.0, 0.0001, "an item with no modeled material must never accrue wear")


func test_blocking_a_real_hit_wears_the_equipped_weapon():
	var sword := _item_catalog.make("iron_sword")
	player.inventory.add(sword, 1)
	player.equip_item(sword)
	Input.action_press("block")

	player.take_damage(6.0)

	assert_gt(sword.wear, 0.0, "a block that actually absorbs a hit must wear the weapon")


func test_blocking_with_no_incoming_damage_does_not_wear_the_weapon():
	var sword := _item_catalog.make("iron_sword")
	player.inventory.add(sword, 1)
	player.equip_item(sword)
	Input.action_press("block")

	player.take_damage(0.0)

	assert_almost_eq(sword.wear, 0.0, 0.0001, "nothing was actually blocked, so nothing should wear")


func test_a_broken_weapon_is_no_longer_returned_by_held_weapon():
	var sword := _item_catalog.make("iron_sword")
	player.inventory.add(sword, 1)
	player.equip_item(sword)
	sword.wear = 9999.0

	assert_null(player._held_weapon(), "a weapon broken from fatigue must stop counting as held")


func test_a_broken_weapon_is_held_as_unarmed():
	var sword := _item_catalog.make("iron_sword")
	player.inventory.add(sword, 1)
	player.equip_item(sword)
	sword.wear = 9999.0

	assert_eq(player._held_kind(), "unarmed", "a broken sword must block/attack as bare hands, not as a sword")


func test_a_weapon_below_max_wear_is_still_held_normally():
	var sword := _item_catalog.make("iron_sword")
	player.inventory.add(sword, 1)
	player.equip_item(sword)
	sword.wear = 1.0  # far below iron's max_wear (56.0)

	assert_eq(player._held_weapon(), sword)
	assert_eq(player._held_kind(), "sword")


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


## The whole point of the fix: 5 filled stacks (every hotbar slot) must not
## stop a 6th item from reaching a key. A fresh player no longer starts with
## any inventory automatically (see grant_starter_items/docs/concept/
## starting_kit.md), so this test manufactures its own "hotbar already full"
## precondition with 5 other real, distinct items rather than depending on
## a global default that no longer exists.
func test_an_item_past_the_hotbars_capacity_can_still_be_assigned_and_equipped():
	var fillers := ["wood", "hide", "stick", "rock", "plant_fibre"]
	assert_eq(fillers.size(), player.hotbar.slot_count, "precondition: one filler per slot")
	for filler_id in fillers:
		player.inventory.add(_item_catalog.make(filler_id), 1)
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


# -- equip_armor now shows real armor on the rig, not just the numeric slot --
# (see docs/concept/item_illustrations.md and the regression comment above:
# equip_armor never called CharacterView at all before this).

func test_equipping_armor_shows_it_in_the_matching_character_view_slot():
	var helm := _item_catalog.make("leather_helm")
	player.inventory.add(helm, 1)

	assert_true(player.equip_armor(helm))

	assert_true(player._character_view.is_slot_equipped("head"))
	var expected := ProceduralItemSprite.new().generate_texture("leather_helm")
	assert_eq(
		player._character_view.slot_texture("head").get_image().get_data(),
		expected.get_image().get_data()
	)


func test_equipping_armor_in_each_slot_shows_up_in_that_slot():
	var chest := _item_catalog.make("leather_chest")
	player.inventory.add(chest, 1)
	assert_true(player.equip_armor(chest))
	assert_true(player._character_view.is_slot_equipped("chest"), "chest")

	var legs := _item_catalog.make("leather_legs")
	player.inventory.add(legs, 1)
	assert_true(player.equip_armor(legs))
	assert_true(player._character_view.is_slot_equipped("legs"), "legs")

	var boots := _item_catalog.make("leather_boots")
	player.inventory.add(boots, 1)
	assert_true(player.equip_armor(boots))
	assert_true(player._character_view.is_slot_equipped("feet"), "feet")


func test_unequipping_armor_hides_its_character_view_slot():
	var helm := _item_catalog.make("leather_helm")
	player.inventory.add(helm, 1)
	player.equip_armor(helm)

	assert_true(player.unequip_slot("head"))

	assert_false(player._character_view.is_slot_equipped("head"))


# -- ground-contact shadow (see DropShadow) -----------------------------------
# Reported directly: "the player has no silhouette shadow which should
# stretch with sun's elevation" -- every creature already gets one
# (CreatureMarker._sync_grounded_children / DropShadow.stretch_for_elevation),
# fed every frame by World from the real sun position, but nothing ever gave
# the player's own CharacterBody2D a shadow child at all.

func test_the_player_has_a_shadow_child():
	assert_not_null(player._shadow, "the player must have a shadow, the same as every creature")


func test_the_shadow_stretches_with_the_shared_sun_elevation():
	CreatureMarker.sun_elevation_deg = 90.0
	player._update_character_view(Vector2.DOWN)
	var overhead_stretch: float = player._shadow.scale.y

	CreatureMarker.sun_elevation_deg = 10.0
	player._update_character_view(Vector2.DOWN)
	assert_gt(
		player._shadow.scale.y, overhead_stretch,
		"a lower sun must stretch the player's shadow longer, exactly like a creature's"
	)


# -- gradual, depth-driven submersion (see CharacterView.set_submersion_depth) -
#
# Reported: "the players submerged tint should be improved and gradual based
# on water depth". _resolve_water_state (see test_player_river_water_state.gd)
# already computes real, continuous depth in meters -- it used to be
# discarded the moment it was collapsed into the coarse walking/wading/
# swimming/drowning mode string, which is why _update_character_view is the
# actual place this was lost: current_water_depth is the new channel that
# survives that collapse.

func test_update_character_view_passes_the_real_water_depth_through_to_the_rig():
	player.current_water_depth = 0.73
	player._update_character_view(Vector2.DOWN)
	assert_almost_eq(player._character_view._submersion_depth_meters, 0.73, 0.001)


func test_update_character_view_passes_zero_depth_through_on_dry_ground():
	player.current_water_depth = 0.0
	player._update_character_view(Vector2.DOWN)
	assert_almost_eq(player._character_view._submersion_depth_meters, 0.0, 0.001)


# -- mana: a new resource for spellcasting, kept off stamina by design (see
# docs/concept/survival.md's "Stamina scope: movement only, not combat" and
# docs/concept/spell_runtime.md) --------------------------------------------

func test_apply_class_sets_max_mana_from_the_archetypes_bonus():
	player.apply_class("mage", {"max_mana": 50.0})
	assert_almost_eq(player.max_mana, 50.0, 0.001)
	assert_almost_eq(player.mana, 50.0, 0.001, "a freshly applied class should start at full mana")


func test_apply_class_gives_a_non_caster_class_zero_mana():
	player.apply_class("warrior", {"max_mana": 0.0})
	assert_almost_eq(player.max_mana, 0.0, 0.001)


func test_mana_never_goes_negative_even_with_a_large_negative_bonus():
	player.apply_class("cursed", {"max_mana": -30.0})
	assert_almost_eq(player.max_mana, 0.0, 0.001)


func test_spend_mana_succeeds_when_affordable():
	player.apply_class("mage", {"max_mana": 50.0})
	assert_true(player.spend_mana(20.0))
	assert_almost_eq(player.mana, 30.0, 0.001)


func test_spend_mana_fails_and_changes_nothing_when_unaffordable():
	player.apply_class("mage", {"max_mana": 50.0})
	assert_false(player.spend_mana(999.0))
	assert_almost_eq(player.mana, 50.0, 0.001, "an unaffordable spend must not touch mana at all")


func test_mana_regenerates_over_time():
	player.apply_class("mage", {"max_mana": 50.0})
	player.spend_mana(10.0)

	player._regen_mana(5.0)

	assert_gt(player.mana, 40.0)
	assert_lte(player.mana, player.max_mana)


func test_mana_regeneration_never_exceeds_max_mana():
	player.apply_class("mage", {"max_mana": 50.0})
	player._regen_mana(10000.0)
	assert_almost_eq(player.mana, 50.0, 0.001)


## Pins MANA_REGEN_PER_SECOND against the real cost of the cheapest example
## spell (SpellBook/SpellExecutor), rather than an eyeballed number: a mage
## should be able to recast their cheapest spell within a handful of
## seconds of standing still, not instantly (free) and not after a long wait.
func test_mana_regen_lets_a_mage_recast_the_cheapest_spell_within_a_few_seconds():
	var SpellBook = preload("res://src/gameplay/spell_book.gd")
	var SpellExecutor = preload("res://src/gameplay/spell_executor.gd")
	var book := SpellBook.new()
	var executor := SpellExecutor.new()
	var cheapest := INF
	for spell_id in book.known_ids():
		cheapest = minf(cheapest, executor.cost_for(executor.cast_rule(book.ast_for(spell_id))))

	var seconds_to_recast := cheapest / Player.MANA_REGEN_PER_SECOND
	assert_gt(seconds_to_recast, 0.5, "mana regen must not make casting effectively free/instant")
	assert_lt(seconds_to_recast, 10.0, "mana regen must not make recasting an agonizing wait")


# -- spell-cast status effects (ignite/blight/freeze/root/slow/shield) ------
# See docs/concept/spell_runtime.md. Mirrors apply_venom/_venom_step's own
# shape (DebuffStack-tracked, ticked once per authority frame).

const SpellStatusEffects = preload("res://src/gameplay/spell_status_effects.gd")


func test_ignite_deals_real_damage_over_time():
	player.apply_spell_debuff(SpellStatusEffects.IGNITE, 3.0)
	var health_before := player.health

	player._spell_status_step(1.0)

	assert_lt(player.health, health_before)


func test_ignite_expires_after_its_duration():
	player.apply_spell_debuff(SpellStatusEffects.IGNITE, 1.0)
	player._spell_status_step(1.5)
	var health_after_expiry := player.health

	player._spell_status_step(1.0)

	assert_almost_eq(
		player.health, health_after_expiry, 0.001, "an expired ignite must deal no further damage"
	)


func test_freeze_roots_the_player_in_place():
	assert_false(player.is_rooted())
	player.apply_spell_debuff(SpellStatusEffects.FREEZE, 2.0)
	assert_true(player.is_rooted())


func test_root_also_roots_the_player_in_place():
	player.apply_spell_debuff(SpellStatusEffects.ROOT, 2.0)
	assert_true(player.is_rooted())


func test_being_rooted_expires_on_its_own():
	player.apply_spell_debuff(SpellStatusEffects.ROOT, 1.0)
	player._spell_status_step(1.5)
	assert_false(player.is_rooted())


func test_slow_reduces_the_players_speed_multiplier():
	assert_almost_eq(player._spell_speed_multiplier(), 1.0, 0.001)
	player.apply_spell_debuff(SpellStatusEffects.SLOW, 3.0)
	assert_almost_eq(player._spell_speed_multiplier(), SpellStatusEffects.SLOW_SPEED_MULTIPLIER, 0.001)


func test_shield_absorbs_damage_before_armor_mitigation():
	player.apply_shield(10.0, 4.0)
	var health_before := player.health

	player.take_damage(6.0)

	assert_almost_eq(player.health, health_before, 0.001, "a shield with enough absorb left must block the whole hit")


func test_shield_only_absorbs_up_to_its_remaining_pool():
	player.apply_shield(5.0, 4.0)

	player.take_damage(12.0)

	assert_almost_eq(
		player.health, player.max_health - 7.0, 0.001, "5 of the 12 damage should be absorbed, 7 should land"
	)


func test_shield_expires_after_its_duration():
	player.apply_shield(10.0, 1.0)
	player._shield_step(1.5)

	player.take_damage(6.0)

	assert_lt(player.health, player.max_health, "an expired shield must not still be absorbing")


# -- heal and knockback: the shared duck-typed methods SpellAtomEffects
# calls on ANY target (Player or CreatureMarker), same convention take_damage
# already established (see docs/concept/spell_runtime.md). --------------------

func test_heal_restores_health_up_to_the_max():
	player.take_damage(30.0)
	var damaged_health := player.health

	player.heal(10.0)

	assert_almost_eq(player.health, damaged_health + 10.0, 0.001)


func test_heal_never_exceeds_max_health():
	player.heal(9999.0)
	assert_almost_eq(player.health, player.max_health, 0.001)


func test_heal_does_nothing_to_a_dead_player():
	player.take_damage(9999.0)
	assert_true(player.is_dead)

	player.heal(10.0)

	assert_true(player.is_dead, "healing must not resurrect a dead player")


# -- casting a spell (docs/concept/spell_runtime.md) -------------------------

func test_casting_a_known_spell_spends_mana_and_hits_a_nearby_creature():
	player.apply_class("mage", {"max_mana": 50.0})
	var target := _creature_at("herbivore", Vector2(10, 0))
	var health_before: float = target.info.health

	assert_true(player.cast_spell("fire_bolt"))

	assert_lt(player.mana, 50.0, "casting must spend real mana")
	assert_lt(target.info.health, health_before, "Fire Bolt must actually damage the nearby target")


func test_casting_without_enough_mana_fails_and_sets_a_message():
	player.apply_class("mage", {"max_mana": 0.1})

	assert_false(player.cast_spell("fire_bolt"))

	assert_string_contains(player.cast_message.to_lower(), "mana")


func test_casting_without_enough_mana_spends_nothing():
	player.apply_class("mage", {"max_mana": 0.1})
	player.cast_spell("fire_bolt")
	assert_almost_eq(player.mana, 0.1, 0.001)


func test_casting_an_unknown_spell_id_does_nothing_and_fails():
	player.apply_class("mage", {"max_mana": 50.0})
	assert_false(player.cast_spell("not_a_real_spell"))
	assert_almost_eq(player.mana, 50.0, 0.001)


func test_casting_a_self_delivery_spell_heals_the_caster():
	player.apply_class("mage", {"max_mana": 50.0})
	player.take_damage(30.0)
	var health_before := player.health

	assert_true(player.cast_spell("minor_heal"))

	assert_gt(player.health, health_before)


func test_casting_with_nothing_in_range_still_spends_mana():
	# "even an affordable spell still has to land" (magic.md) -- casting
	# touch/projectile with no target nearby is a real, resolved cast that
	# simply hits nothing, not a refusal.
	player.apply_class("mage", {"max_mana": 50.0})
	assert_true(player.cast_spell("fire_bolt"))
	assert_lt(player.mana, 50.0)


func test_apply_knockback_overrides_the_velocity_for_its_duration():
	player.apply_knockback(Vector2(100, 0))

	var velocity := player._knockback_velocity(Vector2.ZERO, 0.05)

	assert_gt(velocity.x, 0.0, "a rightward knockback should produce a rightward velocity override")


func test_knockback_velocity_falls_back_to_the_input_velocity_once_expired():
	assert_eq(player._knockback_velocity(Vector2(5, 0), 0.016), Vector2(5, 0))


func test_knockback_velocity_overrides_even_nonzero_input_while_active():
	player.apply_knockback(Vector2(100, 0))

	var velocity := player._knockback_velocity(Vector2(-999, -999), 0.05)

	assert_gt(velocity.x, 0.0, "the shove must win over normal movement input while it plays out")


func test_catching_a_fish_with_no_marker_nearby_still_shows_a_generic_message():
	_land_a_fish()
	player._fishing_step(0.0)

	assert_string_contains(player.fishing_message, "Caught")


# -- the real "fish" input action is the whole loop's entry point ------------
#
# Every fishing test above deliberately bypasses the near-water input gate
# (see the "fishing visuals" section's own comment above) by driving
# FishingSession directly. This section goes through the REAL entry point
# instead -- the "fish" action (Keybindings.ACTIONS, default key F) -- forcing
# a real ocean tile next to the player so _near_water() is genuinely true,
# then taps the actual input action through the whole cast -> bite -> react ->
# caught cycle, the same call shape a real playthrough makes, all the way to a
# real item landing in the inventory (docs/concept/fishing.md's fishing loop).

const FishingMinigame = preload("res://src/gameplay/fishing_minigame.gd")


## Overwrites one tile's biome directly on the loaded chunk -- the same
## reach-into-the-chunk convention test_stone_renderer.gd/test_fish_renderer.gd
## already use, rather than depending on where real Earth terrain happens to
## put land/ocean at this fixed test spawn point (see the "fishing visuals"
## section's own comment on exactly that risk).
func _set_biome_at(global_tile: Vector2i, biome_name: String) -> void:
	var chunk_coord := Vector2i(
		floori(float(global_tile.x) / EarthChunkManager.CHUNK_SIZE),
		floori(float(global_tile.y) / EarthChunkManager.CHUNK_SIZE)
	)
	var chunk = chunk_manager._loaded_chunks[chunk_coord]
	var local := Vector2i(
		posmod(global_tile.x, EarthChunkManager.CHUNK_SIZE),
		posmod(global_tile.y, EarthChunkManager.CHUNK_SIZE)
	)
	chunk.biome[local.y * EarthChunkManager.CHUNK_SIZE + local.x] = biome_name


## Sums every fish-family item id a catch can reward (see
## Player.FISH_ITEM_ID_BY_RARITY) -- the exact rarity is a deterministic hash
## roll off position/cast-count, not something a caller should have to
## predict just to prove a catch reached the inventory.
func _fish_item_count(counts: Dictionary) -> int:
	return counts.get("fish", 0) + counts.get("rare_fish", 0) + counts.get("legendary_fish", 0)


func test_pressing_fish_away_from_water_does_not_start_a_session():
	# Land on every cardinal neighbor, overriding whatever the real terrain
	# there actually is -- _near_water() must read false regardless.
	var tile := player.current_tile()
	_set_biome_at(tile, "grassland")
	for offset in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		_set_biome_at(tile + offset, "grassland")
	assert_false(player._near_water(), "precondition: forced land on every side")

	Input.action_press("fish")
	player._fishing_step(0.0)
	Input.action_release("fish")

	assert_eq(player._fishing.phase(), "idle", "no water nearby -- the fish key must not start a cast")


func test_the_real_fish_key_entry_point_lands_a_caught_fish_in_the_inventory():
	_set_biome_at(player.current_tile() + Vector2i(1, 0), "ocean")
	assert_true(player._near_water(), "precondition: a forced ocean neighbor should satisfy _near_water")
	# A fresh player no longer carries one automatically (see
	# grant_starter_items/docs/concept/starting_kit.md) -- this test is
	# about the fish-key entry point, not about starter-kit selection, so
	# it grants its own rod rather than depending on a global default.
	player.inventory.add(_item_catalog.make("fishing_rod"), 1)
	assert_true(player._has_fishing_rod(), "precondition: a forced grant should satisfy _has_fishing_rod")
	var before := _fish_item_count(player.inventory_counts())

	# Cast: a real key press, gated by the real near-water/has-rod checks,
	# starting the real FishingSession.
	Input.action_press("fish")
	player._fishing_step(0.0)
	Input.action_release("fish")
	assert_eq(player._fishing.phase(), "waiting", "the fish key next to water should start a real cast")

	# Wait for the bite: a delta past the maximum possible bite delay forces
	# WAITING -> BITING in one step deterministically, without needing to
	# predict the unbiased (bait_quality 0.0, see Player._fishing_step's own
	# cast call) roll a real cast makes through this entry point.
	player._fishing_step(FishingMinigame.MAX_BITE_DELAY + 1.0)
	assert_eq(player._fishing.phase(), "biting", "should be biting once the bite delay has fully elapsed")

	# React: a second real key press within the bite window lands the fish.
	Input.action_press("fish")
	player._fishing_step(0.0)
	Input.action_release("fish")
	assert_eq(player._fishing.phase(), "caught", "reacting during BITING should land the fish")

	# Resolve: the reward is granted at the TOP of the *next* step (see
	# _fishing_step's own CAUGHT branch) -- the same two-call shape
	# _land_a_fish's own callers already use throughout this file.
	player._fishing_step(0.0)

	var after := _fish_item_count(player.inventory_counts())
	assert_gt(after, before, "a real catch through the fish key should add a real fish item to the inventory")
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


# -- toxic mushrooms: real poisoning, per-species severity (see
# docs/concept/mushrooms.md's "Eating one") -- mirrors apply_venom/
# _venom_step's own shape (DebuffStack-tracked, once-per-authority-frame),
# plus identification by real experience rather than a purchased skill
# point (see that doc's "Identification" section for why).

const MushroomSpecies = preload("res://src/world/mushroom_species.gd")
const MushroomToxin = preload("res://src/gameplay/mushroom_toxin.gd")


func test_eating_an_edible_mushroom_causes_no_harm():
	player.inventory.add(_item_catalog.make("chanterelle"), 1)
	var health_before := player.health

	assert_true(player.eat_food("chanterelle"))

	assert_eq(player.health, health_before)
	assert_eq(player.active_mushroom_toxin_debuffs.size(), 0)


func test_eating_a_toxic_mushroom_applies_the_toxin_debuff():
	player.inventory.add(_item_catalog.make("psylo"), 1)

	assert_true(player.eat_food("psylo"))

	assert_eq(player.active_mushroom_toxin_debuffs.size(), 1)
	assert_eq(player.active_mushroom_toxin_debuffs[0]["debuff_id"], MushroomToxin.DEBUFF_ID)


func test_mushroom_toxin_step_deals_damage_over_time_while_active():
	player.inventory.add(_item_catalog.make("psylo"), 1)
	player.eat_food("psylo")
	var before := player.health

	player._mushroom_toxin_step(1.0)

	assert_lt(player.health, before)


func test_mushroom_toxin_step_does_nothing_without_an_active_debuff():
	var before := player.health
	player._mushroom_toxin_step(1.0)
	assert_eq(player.health, before)


func test_mushroom_toxin_step_expires_after_its_duration():
	player.inventory.add(_item_catalog.make("psylo"), 1)
	player.eat_food("psylo")

	player._mushroom_toxin_step(MushroomToxin.DURATION_SECONDS + 1.0)

	assert_eq(player.active_mushroom_toxin_debuffs.size(), 0)


func test_every_eaten_mushroom_counts_toward_identification_toxic_or_not():
	player.inventory.add(_item_catalog.make("chanterelle"), 1)
	player.inventory.add(_item_catalog.make("psylo"), 1)

	player.eat_food("chanterelle")
	player.eat_food("psylo")

	assert_eq(player.mushrooms_eaten, 2)


func test_knows_mushrooms_is_false_before_enough_real_encounters():
	assert_false(player.knows_mushrooms())


func test_knows_mushrooms_becomes_true_after_enough_real_encounters():
	for id in MushroomSpecies.IDS:
		player.inventory.add(_item_catalog.make(id), 1)
		player.eat_food(id)
	assert_true(player.knows_mushrooms())


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
## the same shape test_the_measured_catch_rate_matches_the_model
## (test_creature_marker.gd) already uses for a chance that's real but not
## 100%.
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

func _horse_at(offset: Vector2, wander_seed: int = 9) -> CreatureMarker:
	var marker := CreatureMarker.new()
	marker.info = CreatureInfo.new("horse", 1)
	marker.wander_seed = wander_seed
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
	player._throw_capture_tool()
	assert_true(horse.is_restrained(), "a horse within reach should be caught")


## The throw is short on purpose: closing with a wary animal first is the part
## that makes stalking one feel like something.
func test_a_horse_out_of_reach_is_not_caught():
	_hold_lasso()
	var horse := _horse_at(Vector2(Player.LASSO_RANGE * 2.0, 0))
	player._throw_capture_tool()
	assert_false(horse.is_restrained())


func test_the_throw_takes_the_nearest_animal():
	_hold_lasso()
	var far := _horse_at(Vector2(Player.LASSO_RANGE * 0.9, 0))
	var near := _horse_at(Vector2(Player.LASSO_RANGE * 0.2, 0))
	player._throw_capture_tool()
	assert_true(near.is_restrained())
	assert_false(far.is_restrained(), "the rope only goes round one neck")


## Predators now join the Roped class (see docs/concept/taming.md's "Any
## animal, the right tool"): a lynx has a neck exactly like a horse does, so
## the SAME lasso is the right tool -- what changes is how hard it fights
## the rope once caught, tested at the taming.gd/creature_marker level, not
## whether the throw lands here at all.
func test_the_lasso_now_catches_a_predator_too():
	_hold_lasso()
	var lynx := CreatureMarker.new()
	lynx.info = CreatureInfo.new("lynx", 1)
	add_child_autofree(lynx)
	lynx.setup(chunk_manager, TILE_SIZE)
	lynx.position = player.position + Vector2(8, 0)
	player._throw_capture_tool()
	assert_true(lynx.is_restrained(), "a lynx has a neck like a horse does")


## World-boss-scale species stay excluded regardless of tool -- see
## docs/concept/taming.md's "Boss-scale creatures get their tool now;
## actually holding one stays a follow-up."
func test_the_lasso_never_catches_a_world_boss_species():
	_hold_lasso()
	var boss := CreatureMarker.new()
	boss.info = CreatureInfo.new("krampus", 1)
	add_child_autofree(boss)
	boss.setup(chunk_manager, TILE_SIZE)
	boss.position = player.position + Vector2(8, 0)
	player._throw_capture_tool()
	assert_false(boss.is_restrained())


## Leading is nothing more than an anchor that walks with the player: the
## animal is pulled along and can never end up past the end of the rope.
func test_a_led_horse_is_towed_along_behind_the_player():
	_hold_lasso()
	var horse := _horse_at(Vector2(16, 0))
	# Worn down on purpose, so it stays caught for the whole walk: a healthy
	# horse would usually fight the rope off partway through (which is its
	# right, and is tested elsewhere) and leave this test asserting nothing.
	horse.info.health = horse.info.max_health * 0.05
	player._throw_capture_tool()
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
## Feeding is a GESTURE now, not something that happens because you stood
## nearby. It used to fire from _lasso_step every frame whenever a carrot was
## in the bag and the animal was in range -- so the "relationship" the whole
## mechanic rests on reduced, in play, to standing still (see
## docs/concept/taming.md, "feeding as an offer that can be refused"). The
## player now offers, on the primary action key, holding the food.
func _offer_food_to(horse: CreatureMarker) -> void:
	player.equipped_item = _item_catalog.make("carrot")
	player._perform_animal_action(horse, 0)


func test_offering_food_to_a_full_horse_costs_no_carrots():
	_hold_lasso()
	var horse := _horse_at(Vector2(8, 0))
	player._throw_capture_tool()
	player.inventory.add(_item_catalog.make("carrot"), 3)
	horse._needs.hunger = 0.0
	_offer_food_to(horse)
	assert_eq(player.inventory.count_of("carrot"), 3)
	assert_eq(horse.trust, 0.0)


## _offer_food_to puts a carrot in HAND, and feeding now reaches for the held
## one before the bag (see Player.offer_treat_to) -- so the meal comes out of
## the hand and the bag is untouched. That is the reported fix: a carrot picked
## off the ground lands in the hand, not the bag.
func test_offering_food_to_a_hungry_horse_spends_a_carrot_and_earns_trust():
	_hold_lasso()
	var horse := _horse_at(Vector2(8, 0))
	player._throw_capture_tool()
	player.inventory.add(_item_catalog.make("carrot"), 3)
	horse._needs.hunger = 1.0
	_offer_food_to(horse)
	assert_null(player.equipped_item, "the held carrot is the one eaten")
	assert_eq(player.inventory.count_of("carrot"), 3, "the bag is untouched")
	assert_gt(horse.trust, 0.0)


## The defect the gesture exists to fix: walking past your own tied, hungry
## horse with carrots in the bag must no longer feed it by itself.
func test_standing_next_to_a_hungry_horse_no_longer_feeds_it_by_itself():
	_hold_lasso()
	var horse := _horse_at(Vector2(8, 0))
	player._throw_capture_tool()
	player.inventory.add(_item_catalog.make("carrot"), 3)
	horse._needs.hunger = 1.0

	for _frame in 30:
		player._lasso_step(1.0 / 60.0)

	assert_eq(player.inventory.count_of("carrot"), 3, "nothing was offered")
	assert_eq(horse.trust, 0.0, "and nothing was earned")


## The primary slot is whatever the animal most needs, so on a tied hungry
## horse with food in hand it has to BE feeding -- the reported case.
func test_the_primary_action_on_a_tied_hungry_horse_is_feeding_it():
	_hold_lasso()
	var horse := _horse_at(Vector2(8, 0))
	player._throw_capture_tool()
	player.equipped_item = _item_catalog.make("carrot")
	horse._needs.hunger = 1.0
	var actions := player.animal_actions_for(horse)
	assert_gt(actions.size(), 0, "a tied hungry horse should offer something")
	assert_eq(actions[0]["verb"], "Feed")

# -- capture tools: snare/trap/net (see docs/concept/taming.md's "Any
# animal, the right tool") ----------------------------------------------------

func _hold_tool(item_id: String) -> void:
	player.equipped_item = _item_catalog.make(item_id)


func _creature_at(species: String, offset: Vector2) -> CreatureMarker:
	var marker := CreatureMarker.new()
	marker.info = CreatureInfo.new(species, 1)
	marker.wander_seed = 9
	add_child_autofree(marker)
	marker.setup(chunk_manager, TILE_SIZE)
	marker.position = player.position + offset
	return marker


func _flyer_at(species: String, offset: Vector2) -> AmbientFlyerMarker:
	var flyer := AmbientFlyerMarker.new()
	flyer.species = species
	add_child_autofree(flyer)
	flyer.position = player.position + offset
	return flyer


func test_held_capture_tool_id_reports_whichever_of_the_five_tools_is_equipped():
	_hold_tool("snare")
	assert_eq(player._held_capture_tool_id(), "snare")


func test_held_capture_tool_id_is_empty_for_a_non_capture_item():
	player.equipped_item = _item_catalog.make("iron_sword")
	assert_eq(player._held_capture_tool_id(), "")


func test_held_capture_tool_id_is_empty_with_bare_hands():
	player.equipped_item = null
	assert_eq(player._held_capture_tool_id(), "")


## A snare, not a lasso, is the right tool for a legless body.
func test_a_snare_catches_a_snake_the_lasso_cannot():
	_hold_tool("lasso")
	var snake := _creature_at("nonvenomous_snake", Vector2(8, 0))
	player._throw_capture_tool()
	assert_false(snake.is_restrained(), "the lasso is the wrong tool for a legless body")

	_hold_tool("snare")
	player._throw_capture_tool()
	assert_true(snake.is_restrained())


## A trap, not a lasso, is the right tool at-or-below a mouse's own
## world_scale (a rope loop has a real minimum practical diameter).
func test_a_trap_catches_a_mouse_the_lasso_cannot():
	_hold_tool("lasso")
	var mouse := _creature_at("mouse", Vector2(8, 0))
	player._throw_capture_tool()
	assert_false(mouse.is_restrained(), "the lasso is the wrong tool for something mouse-sized")

	_hold_tool("trap")
	player._throw_capture_tool()
	assert_true(mouse.is_restrained())


## A snare offered to a horse does nothing -- "using the wrong tool on a
## creature simply does nothing" (taming.md), not a new failure state.
func test_a_snare_does_not_catch_a_horse():
	_hold_tool("snare")
	var horse := _horse_at(Vector2(8, 0))
	player._throw_capture_tool()
	assert_false(horse.is_restrained())


# -- capture tools: the net (a real probability roll, docs/concept/ ---------
# -- capture_dsl.md) ----------------------------------------------------------
#
## Netting used to be instant and deterministic; it now rolls
## CaptureExecutor.resolve_catch, and a success LOADS the net
## (Item.captive_species) instead of instantly granting a curiosity item --
## the player then chooses Release or, with a glass bottle, Put into bottle.

## Presses the capture key against `flyer` until it is either caught or a
## generous attempt budget runs out -- the real per-attempt odds (base 0.65
## at middling boldness) make 40 consecutive misses astronomically unlikely
## ((0.35)^40 ~= 1e-18), so this is the correct way to test a real
## probability without forcing a fake deterministic short-circuit -- the
## same idea test_the_measured_catch_rate_matches_the_model in
## test_creature_marker.gd already uses for the lasso.
func _net_until_caught(flyer: AmbientFlyerMarker, max_attempts: int = 40) -> void:
	var attempts := 0
	while is_instance_valid(flyer) and not flyer.is_queued_for_deletion() and attempts < max_attempts:
		player._throw_capture_tool()
		attempts += 1
	assert_true(
		not is_instance_valid(flyer) or flyer.is_queued_for_deletion(),
		"expected a catch within %d attempts at ~65%% each" % max_attempts
	)


func test_netting_a_butterfly_without_menagerie_eventually_loads_the_net():
	_hold_tool("butterfly_net")
	var monarch := _flyer_at("monarch", Vector2(8, 0))
	_net_until_caught(monarch)
	assert_eq(player.equipped_item.captive_species, "monarch")


func test_netting_a_bird_without_menagerie_also_loads_the_net():
	_hold_tool("butterfly_net")
	var sparrow := _flyer_at("sparrow", Vector2(8, 0))
	_net_until_caught(sparrow)
	assert_eq(player.equipped_item.captive_species, "sparrow")


func test_a_flyer_out_of_net_range_is_left_alone():
	_hold_tool("butterfly_net")
	var monarch := _flyer_at("monarch", Vector2(Player.LASSO_RANGE * 2.0, 0))
	player._throw_capture_tool()
	assert_true(is_instance_valid(monarch))
	assert_eq(player.equipped_item.captive_species, "")


func test_the_measured_net_catch_rate_matches_the_model():
	var trials := 60
	var caught := 0
	for i in trials:
		_hold_tool("butterfly_net")  # fresh, empty net each trial
		var flyer := _flyer_at("monarch", Vector2(8, 0))
		player._throw_capture_tool()
		if not is_instance_valid(flyer) or flyer.is_queued_for_deletion():
			caught += 1
	var observed := float(caught) / float(trials)
	# Model: CapturePhysics.catch_chance(0.65, middling boldness) == 0.65.
	assert_between(observed, 0.45, 0.85, "observed catch rate %f, expected near 0.65" % observed)


func test_a_bolder_flyer_is_measurably_easier_to_catch_than_a_shy_one():
	var trials := 40
	var bold_catches := 0
	var shy_catches := 0
	for i in trials:
		_hold_tool("butterfly_net")
		var bold := _flyer_at("monarch", Vector2(8, 0))
		bold.traits = {"boldness": 1.0}
		player._throw_capture_tool()
		if not is_instance_valid(bold) or bold.is_queued_for_deletion():
			bold_catches += 1

		_hold_tool("butterfly_net")
		var shy := _flyer_at("monarch", Vector2(8, 0))
		shy.traits = {"boldness": 0.0}
		player._throw_capture_tool()
		if not is_instance_valid(shy) or shy.is_queued_for_deletion():
			shy_catches += 1
	assert_gt(
		bold_catches, shy_catches,
		"a bold flyer (0.80 chance) should be caught more often than a shy one (0.50 chance)"
	)


# -- releasing a loaded net ---------------------------------------------------

func test_the_capture_key_catches_when_empty_and_releases_when_loaded():
	_hold_tool("butterfly_net")
	var monarch := _flyer_at("monarch", Vector2(8, 0))
	_net_until_caught(monarch)
	assert_ne(player.equipped_item.captive_species, "")
	player._throw_capture_tool()  # the SAME key, now loaded -> releases instead of throwing
	assert_eq(player.equipped_item.captive_species, "", "the same key released the loaded net")


func test_releasing_an_empty_net_does_nothing():
	_hold_tool("butterfly_net")
	player._release_net()
	assert_eq(player.equipped_item.captive_species, "")


# -- put into bottle (docs/concept/capture_dsl.md's "on transfer") -----------

func _load_net_with(species: String) -> void:
	_hold_tool("butterfly_net")
	var flyer := _flyer_at(species, Vector2(8, 0))
	_net_until_caught(flyer)


## The player starts with an empty glass bottle in the pack (see the
## starting grant in Player); the tests below that need an EMPTY pack say so
## explicitly rather than assuming one.
func _drop_every_bottle() -> void:
	player.inventory.remove("glass_bottle", player.inventory.count_of("glass_bottle"))


func test_bottling_a_loaded_net_grants_a_loaded_bottle_and_consumes_an_empty_one():
	_load_net_with("monarch")
	player.inventory.add(_item_catalog.make("glass_bottle"), 1)
	var empty_before := player.inventory.count_of("glass_bottle", "")
	player._bottle_captive()
	assert_eq(player.equipped_item.captive_species, "", "the net empties once its catch is bottled")

	var found_species := ""
	for stack in player.inventory.stacks():
		if stack != null and stack.item.id == "glass_bottle" and stack.item.captive_species != "":
			found_species = stack.item.captive_species
	assert_eq(found_species, "monarch", "a loaded glass_bottle should carry the species that moved")
	assert_eq(player.inventory.count_of("glass_bottle", ""), empty_before - 1, "exactly one EMPTY bottle was spent")


func test_bottling_without_a_glass_bottle_does_nothing():
	_load_net_with("monarch")
	_drop_every_bottle()
	player._bottle_captive()
	assert_eq(player.equipped_item.captive_species, "monarch", "no bottle on hand -- the net stays loaded")


func test_bottling_an_empty_net_does_nothing_even_with_a_bottle():
	_hold_tool("butterfly_net")
	player.inventory.add(_item_catalog.make("glass_bottle"), 1)
	var before := player.inventory.count_of("glass_bottle")
	player._bottle_captive()
	assert_eq(player.inventory.count_of("glass_bottle"), before, "nothing to bottle -- the bottle is not spent")


## The secondary_action slot's fallback (CaptureItemActions, see its own test
## file for the pure scoring logic) -- this is the Player-level wiring.
func test_secondary_action_offers_put_into_bottle_when_loaded_and_a_bottle_is_on_hand():
	_load_net_with("monarch")
	player.inventory.add(_item_catalog.make("glass_bottle"), 1)
	player._perform_context_action(1, "secondary_action")
	assert_eq(player.equipped_item.captive_species, "", "the secondary action slot actually bottled it")


func test_secondary_action_does_nothing_for_an_empty_net():
	_hold_tool("butterfly_net")
	player.inventory.add(_item_catalog.make("glass_bottle"), 1)
	var before := player.inventory.count_of("glass_bottle")
	player._perform_context_action(1, "secondary_action")
	assert_eq(player.inventory.count_of("glass_bottle"), before, "nothing loaded -- the bottle is not spent")


# -- bottling never spends a LOADED bottle (found at the 2026-09-05 merge) ----
#
## main now grants an empty glass bottle from the start, which exposed two
## real bugs in one code path: Inventory.add merged a freshly loaded bottle
## into the empty stack by id alone (the creature vanished), and "Put into
## bottle" counted and could spend a LOADED bottle as if it were empty. These
## pin the player-facing half; test_inventory.gd pins the inventory half.

func test_bottling_with_the_starting_bottle_keeps_the_creature():
	_load_net_with("monarch")
	assert_eq(player.inventory.count_of("glass_bottle", ""), 1, "the starting empty bottle")
	player._bottle_captive()
	assert_eq(player.equipped_item.captive_species, "")
	assert_eq(player.inventory.count_of("glass_bottle", "monarch"), 1, "the monarch is in a bottle, not lost in a merge")
	assert_eq(player.inventory.count_of("glass_bottle", ""), 0, "the empty bottle was the one spent")


func test_a_loaded_bottle_is_never_spent_to_bottle_a_second_catch():
	_load_net_with("monarch")
	player._bottle_captive()
	# The only bottle left holds the monarch. Net a sparrow and try again,
	# through the secondary-action slot as a player would.
	var sparrow := _flyer_at("sparrow", Vector2(8, 0))
	_net_until_caught(sparrow)
	player._perform_context_action(1, "secondary_action")
	player._bottle_captive()
	assert_eq(player.equipped_item.captive_species, "sparrow", "the net stays loaded: no EMPTY bottle to put it in")
	assert_eq(player.inventory.count_of("glass_bottle", "monarch"), 1, "the monarch's bottle is untouched")
	assert_eq(player.inventory.count_of("glass_bottle"), 1, "no bottle was conjured or consumed")


# -- menagerie bonding: unaffected in shape, just gated behind the roll now --
# (docs/concept/taming.md's Kinship path -- Beastmaster's `menagerie`
# keystone turns a netted flyer into a real bonded companion instead of
# loading the net. Allocated directly on the web -- see this lane's own
# HANDOFF note on why menagerie is not (yet) read through unlocked_
# keystones alone.)

func test_netting_a_flyer_with_menagerie_bonds_a_companion_instead_of_loading_the_net():
	player.allocated_nodes["menagerie"] = true
	_hold_tool("butterfly_net")
	var monarch := _flyer_at("monarch", Vector2(8, 0))
	_net_until_caught(monarch)
	assert_eq(player.equipped_item.captive_species, "", "bonded instantly -- never loaded into the net")
	assert_eq(player.bonded_companions.size(), 1)
	assert_eq(player.bonded_companions[0].get("species"), "monarch")


## The unlocked_keystones shape (land_sense/berserkers_fury/etc.) is honored
## too, in case menagerie ever moves fully into that mechanism.
func test_netting_a_flyer_with_menagerie_via_unlocked_keystones_also_bonds():
	player.unlocked_keystones["menagerie"] = true
	_hold_tool("butterfly_net")
	var robin := _flyer_at("robin", Vector2(8, 0))
	_net_until_caught(robin)
	assert_eq(player.bonded_companions.size(), 1)


func test_bonded_companions_are_capped():
	player.allocated_nodes["menagerie"] = true
	for i in Player.BONDED_COMPANION_CAP:
		_hold_tool("butterfly_net")  # a fresh, empty net for each attempt
		var bee := _flyer_at("bee", Vector2(8, 0))
		_net_until_caught(bee)
	assert_eq(player.bonded_companions.size(), Player.BONDED_COMPANION_CAP)

	# One more, past the cap: falls back to loading the net instead of
	# silently discarding the catch.
	_hold_tool("butterfly_net")
	var bee := _flyer_at("bee", Vector2(8, 0))
	_net_until_caught(bee)
	assert_eq(player.bonded_companions.size(), Player.BONDED_COMPANION_CAP)
	assert_eq(player.equipped_item.captive_species, "bee")


func test_bonding_a_companion_spawns_its_live_marker():
	player.allocated_nodes["menagerie"] = true
	_hold_tool("butterfly_net")
	var monarch := _flyer_at("monarch", Vector2(8, 0))
	_net_until_caught(monarch)
	assert_eq(player._bonded_markers.size(), 1)
	assert_true(player._bonded_markers[0] is BondedCompanionMarker)
	assert_eq(player._bonded_markers[0].species, "monarch")


## Bonded companions survive a save/load round trip via to_save_dict /
## apply_save_dict, the same as every other piece of persisted player state.
func test_bonded_companions_persist_across_a_save_and_load_round_trip():
	player.allocated_nodes["menagerie"] = true
	_hold_tool("butterfly_net")
	_flyer_at("monarch", Vector2(8, 0))
	player._throw_capture_tool()
	var saved := player.to_save_dict()

	player.apply_save_dict(saved)

	assert_eq(player.bonded_companions.size(), 1)
	assert_eq(player.bonded_companions[0].get("species"), "monarch")
	assert_eq(player._bonded_markers.size(), 1, "a live marker should be respawned on load")


# -- HUD: the capture-result message (see docs/concept/taming.md) ------------

func test_lasso_message_reads_a_loaded_result_after_netting():
	_hold_tool("butterfly_net")
	var monarch := _flyer_at("monarch", Vector2(8, 0))
	_net_until_caught(monarch)
	player._lasso_step(1.0 / 60.0)
	assert_eq(player.lasso_message, "Caught! Net is full.")


## These two assert the message names the TOOL in hand, which is still the
## point. The KEY half changed: they used to pin the literal phrase "press the
## lasso key", which was the reported defect -- there is no key called that,
## and a player who rebound the throw was being told to press something that
## does not exist. The prompt now names the live binding
## (Keybindings.display_key_for), so these read it off the InputMap the same
## way rather than hard-coding a letter that a rebind would falsify.
func test_lasso_message_prompts_for_a_flyer_with_the_net_held_and_nothing_caught_yet():
	_hold_tool("butterfly_net")
	player._lasso_step(1.0 / 60.0)
	assert_eq(
		player.lasso_message,
		"Net ready — press %s near a flyer." % Keybindings.display_key_for("lasso")
	)


func test_lasso_message_names_whichever_tool_is_held():
	_hold_tool("snare")
	player._lasso_step(1.0 / 60.0)
	assert_eq(
		player.lasso_message,
		"Snare ready — press %s near an animal." % Keybindings.display_key_for("lasso")
	)


## And the defect itself, pinned so it cannot come back: no prompt may name an
## action instead of the key it is on.
func test_no_capture_prompt_calls_a_key_by_its_action_name():
	for tool in ["butterfly_net", "snare", "lasso"]:
		_hold_tool(tool)
		player._lasso_step(1.0 / 60.0)
		assert_false(
			player.lasso_message.contains("the lasso key"),
			"prompt for %s still names the action instead of the key" % tool
		)


# -- orders and riding (see docs/concept/taming.md) --------------------------

func _tamed_horse_at(offset: Vector2, wander_seed: int = 9) -> CreatureMarker:
	var horse := _horse_at(offset, wander_seed)
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


## The test above (and _tamed_horse_at itself) reach a tamed animal by
## calling restrain_to/feed_treat directly on the CreatureMarker, skipping
## the player's own verbs entirely. test_an_animal_told_to_follow_closes_on_
## its_owner (tests/unit/test_creature_marker.gd) separately proves a
## follow-ordered animal actually closes distance over real frames. Neither
## proves the two halves are wired together: this drives the real throw
## (_throw_capture_tool) and the real feed gesture (offer_treat_to) until
## trust is full, lets the rope go the same way perform_rope_verb's "nothing
## left to tie to" branch does, and then runs real frames on both nodes to
## show a horse tamed by hand actually walks to its owner -- not merely that
## a field flipped.
func test_a_horse_tamed_through_the_real_catch_and_feed_flow_follows_its_owner():
	_hold_lasso()
	var horse := _horse_at(Vector2(20, 0))

	player._throw_capture_tool()
	assert_true(horse.is_restrained(), "the real throw should have caught it")

	while not horse.is_tame():
		horse._needs.hunger = 1.0
		player.equipped_item = _item_catalog.make("carrot")
		assert_true(player.offer_treat_to(horse), "a hungry, restrained horse should take the carrot")

	# The rope has nothing left to do once trust is full (docs/concept/
	# taming.md, section 6). This is the same release perform_rope_verb
	# reaches when no tree is nearby to tie off to instead, done directly so
	# the test does not depend on whether real procedural terrain happens to
	# place one within TIE_RANGE of this fixed position.
	horse.release()
	player._lassoed = null
	assert_eq(
		horse.order, Taming.ORDER_FOLLOW,
		"follow is the order a freshly tamed animal already carries, with no order key pressed"
	)

	horse.position = player.position + Vector2(150, 0)
	var start_distance := horse.position.distance_to(player.position)
	for _i in 900:
		player._lasso_step(1.0 / 60.0)
		horse._process(1.0 / 60.0)

	assert_false(horse.is_restrained(), "it should be following, not on a rope")
	assert_lt(
		horse.position.distance_to(player.position), start_distance,
		"a horse tamed by hand should come to its owner, exactly as one ordered to FOLLOW directly does"
	)


# -- riding -------------------------------------------------------------------

func test_mounting_a_tamed_horse_makes_the_player_faster():
	var horse := _tamed_horse_at(Vector2(12, 0))
	assert_eq(player.current_speed(), Player.BASE_SPEED, "on foot to begin with")
	assert_true(player._try_mount())
	assert_true(player.is_mounted())
	# Wiring proof: current_speed() must consult THIS horse's own fitness
	# (see AnimalFitness), not just reapply the flat Taming.MOUNTED_SPEED
	# baseline regardless of which individual is under the saddle.
	var fitness := AnimalFitness.new()
	var expected_speed: float = Taming.mounted_speed_for(
		fitness.fitness_score(fitness.phenotype_for(horse.wander_seed))
	)
	assert_eq(player.current_speed(), expected_speed)
	assert_not_null(horse)


## The same player, mounting two DIFFERENT individual horses, rides at two
## different speeds -- proving mounted speed is genuinely per-individual
## rather than the old flat constant that made every horse identical to ride.
func test_two_different_horses_carry_the_same_player_at_different_speeds():
	var weak_horse := _tamed_horse_at(Vector2(12, 0), 1)
	player._try_mount()
	var weak_speed := player.current_speed()
	player._dismount()
	weak_horse.position = Vector2(10000, 10000)  # well outside LASSO_RANGE

	var strong_horse := _tamed_horse_at(Vector2(12, 0), 2)
	player._try_mount()
	var strong_speed := player.current_speed()

	assert_ne(weak_speed, strong_speed, "different individuals must not ride identically")
	assert_not_null(weak_horse)
	assert_not_null(strong_horse)


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


## No rope in inventory -> no climbing gear. The default player fixture
## starts with none, so this is the honest baseline case.
func test_has_climbing_gear_is_false_without_a_rope_in_inventory():
	assert_false(player._has_climbing_gear())


## The real climbing_rope item (docs/concept/transportation.md,
## item_catalog.gd) now exists -- carrying one (not equipping/wielding it,
## per terrain_relief.md's own "carrying" framing) must flip
## _has_climbing_gear() true, the same "raw inventory count" pattern
## _has_fishing_rod() already uses rather than an equipped-item check.
func test_has_climbing_gear_is_true_when_a_climbing_rope_is_in_inventory():
	player.inventory.add(_item_catalog.make("climbing_rope"), 1)
	assert_true(player._has_climbing_gear())


## Wiring tests for the survival-neglect consequence (ConditionPenalty, see
## docs/concept/survival.md's "What poor condition costs you"): fitness is the
## single accumulator every unmet need feeds, and until now nothing read it at
## all, so hunger and thirst had literally zero mechanical effect.

## _authority_step reads the local input actions directly. World normally
## registers every Keybindings action onto the InputMap at runtime (there is
## no static [input] section in project.godot); these tests drive the step
## without a World, so they register the registry themselves -- otherwise
## every frame pushes an engine "has_action" error per action read. Same
## trick test_player_kick.gd's before_each uses for its one action.
func _register_all_keybindings() -> void:
	for entry in Keybindings.ACTIONS:
		if not InputMap.has_action(entry["action"]):
			InputMap.add_action(entry["action"])


## NOTE on why these compare a RATIO against a control rather than just
## asserting "it got slower": two consecutive _authority_step calls do not
## produce a byte-identical multiplier even with nothing changed (the
## water/weather state settles by a fraction of a percent per frame), so a
## bare assert_lt passes on that drift alone and would have been a false
## green. The control run isolates the drift; the ratio is then compared to
## what ConditionPenalty itself says the penalty should be.

func test_poor_condition_slows_the_player_down():
	_register_all_keybindings()
	player.survival.fitness = 1.0
	player._authority_step(0.016)
	var healthy: float = player.current_speed_multiplier
	player.survival.fitness = 0.0
	player._authority_step(0.016)
	assert_almost_eq(
		player.current_speed_multiplier / healthy,
		ConditionPenalty.speed_multiplier(0.0),
		0.01,
		"a player whose overall condition has collapsed should move slower, by exactly the penalty the module states"
	)


func test_unattended_hunger_eventually_slows_the_player_down_via_condition():
	_register_all_keybindings()
	# CONTROL: the same number of steps, well fed, to measure the drift.
	for i in 100:
		player.survival.hunger = 0.0
		player.survival.thirst = 0.0
		player.survival.warmth = 1.0
		player.survival.fitness = 1.0
		player._authority_step(1.0)
	var well_fed: float = player.current_speed_multiplier

	for i in 100:
		# Isolate hunger: thirst and cold feed the same accumulator, and this
		# test is about hunger specifically having a consequence at all.
		player.survival.hunger = 1.0  # starving
		player.survival.thirst = 0.0
		player.survival.warmth = 1.0
		player._authority_step(1.0)
	assert_lt(player.survival.fitness, 0.5, "precondition: sustained starvation should have run condition down")
	assert_lt(
		player.current_speed_multiplier / well_fed,
		ConditionPenalty.speed_multiplier(0.5),
		"hunger left unattended must have a real mechanical consequence (docs/concept/survival.md, 'Debuffs, not death')"
	)


## Every slot has to actually DO its verb. Feed was easy to get right and the
## rest were routed through _lasso_step, which reads the lasso key itself --
## so pressing the slot re-read an input that was not down and did nothing at
## all, while the prompt cheerfully advertised the verb.
func test_the_release_slot_actually_lets_the_animal_go():
	_hold_lasso()
	var horse := _horse_at(Vector2(8, 0))
	player._throw_capture_tool()
	assert_true(horse.is_restrained(), "precondition: caught")

	var actions := player.animal_actions_for(horse)
	var slot := -1
	for i in actions.size():
		if actions[i]["verb"] == "Release":
			slot = i
	assert_gt(slot, -1, "a held animal should offer Release")

	player._perform_animal_action(horse, slot)
	assert_false(horse.is_restrained(), "pressing Release must let it go")


func test_the_lasso_slot_actually_throws_the_rope():
	_hold_lasso()
	var horse := _horse_at(Vector2(8, 0))
	var actions := player.animal_actions_for(horse)
	assert_eq(actions[0]["verb"], "Lasso", "precondition: a rope in hand offers the throw")

	player._perform_animal_action(horse, 0)
	assert_true(horse.is_restrained(), "pressing Lasso must catch it")

# -- _smash_step: real Player-level integration, not just the pure yield tables -
#
# OreYield, Knapping, MinableOre and SmashableStone all already have thorough
# unit coverage on their own (test_ore_yield.gd, test_knapping.gd,
# test_minable_ore.gd, test_smashable_stone.gd) -- calling mine()/smash()
# directly with hand-picked arguments. Nothing had ever exercised
# Player._smash_step ITSELF: does a live swing actually compute and pass
# through the right pickaxe_power/carrying_rock, not just "do these pure
# functions behave correctly in isolation". Reported live (playtest,
# 2026-08-28): "mining an ore spawns only stones" and boulders never seem to
# yield a sharp stone.

func test_smash_step_mines_ore_with_an_equipped_pickaxe_not_just_stone():
	var ore := MinableOre.new()
	ore.ore_type = "iron"
	ore.ore_seed = 42
	ore.position = player.position + Vector2(5, 5)  # well inside ATTACK_RANGE (20px)
	add_child_autofree(ore)

	_give("stone_pickaxe", 1)
	assert_true(player.equip_item(_item_catalog.make("stone_pickaxe")))

	watch_signals(WorldItemBus)
	player._smash_step()

	var dropped_ids: Array = []
	for i in get_signal_emit_count(WorldItemBus, "item_dropped"):
		dropped_ids.append(get_signal_parameters(WorldItemBus, "item_dropped", i)[0].item.id)
	assert_true(
		dropped_ids.has("iron_ore"),
		"expected iron_ore among a pickaxe-equipped mine's drops, got %s" % [dropped_ids]
	)


## The documented other half of the same behavior (docs/progress.md: "with a
## stone_pickaxe equipped ... it drops ore + stone, bare-handed only stone")
## -- pinned here at the same Player-integration level as the equipped case
## above, not just in OreYield's own pure-function tests.
func test_smash_step_mines_only_stone_with_bare_hands():
	var ore := MinableOre.new()
	ore.ore_type = "iron"
	ore.ore_seed = 42
	ore.position = player.position + Vector2(5, 5)
	add_child_autofree(ore)

	watch_signals(WorldItemBus)
	player._smash_step()

	var dropped_ids: Array = []
	for i in get_signal_emit_count(WorldItemBus, "item_dropped"):
		dropped_ids.append(get_signal_parameters(WorldItemBus, "item_dropped", i)[0].item.id)
	assert_eq(dropped_ids, ["stone"], "bare-handed mining should chip only stone, by design")


func test_smash_step_yields_a_sharp_shard_when_carrying_a_rock():
	# Deterministic per stone_seed, same scanning approach as
	# test_smashable_stone.gd's own test_smashing_with_a_rock_in_hand_can_
	# also_yield_sharp_shards -- pin a real success rather than accepting
	# either outcome.
	var knapping := Knapping.new()
	var lucky_seed := -1
	for candidate in 100:
		if knapping.shard_yield(candidate) > 0:
			lucky_seed = candidate
			break
	assert_gt(lucky_seed, -1, "expected at least one shard-yielding seed in 0..99")

	var stone := SmashableStone.new()
	stone.stone_seed = lucky_seed
	stone.position = player.position + Vector2(5, 5)
	add_child_autofree(stone)

	_give("rock", 1)

	watch_signals(WorldItemBus)
	# Real repeated swings, same pacing test_smashable_stone.gd's own
	# _hits_to_break() uses -- only the final, BREAKING strike carries the
	# knapping roll (see SmashableStone.smash), so this still yields exactly
	# one shard stack regardless of how many strikes the default size takes.
	for _i in StoneSize.hits_to_smash(stone.diameter_cm):
		player._smash_step()

	var dropped_ids: Array = []
	for i in get_signal_emit_count(WorldItemBus, "item_dropped"):
		dropped_ids.append(get_signal_parameters(WorldItemBus, "item_dropped", i)[0].item.id)
	assert_true(
		dropped_ids.has("sharp_shard"),
		"expected a sharp_shard among a rock-carrying smash's drops, got %s" % [dropped_ids]
	)


## Reported: "Carrots never end up in the inventory with a carrot in hand".
##
## A pulled carrot becomes a GROUND item, and E picks a ground item into the
## HAND, not the bag (see _try_pick_item_into_hand -- pickup_nearby only runs
## when the hand grab found nothing). So the ordinary way to end up with a
## carrot is holding one. AnimalActions offers Feed on exactly that -- a carrot
## in hand -- while offer_treat_to spent one out of the INVENTORY, so the prompt
## appeared and the press did nothing. The player is holding the food the game
## is telling them to use.
func test_feeding_spends_the_carrot_that_is_actually_in_hand():
	_hold_lasso()
	var horse := _horse_at(Vector2(8, 0))
	player._throw_capture_tool()
	horse._needs.hunger = 1.0
	player.equipped_item = _item_catalog.make("carrot")

	assert_true(player.offer_treat_to(horse), "a carrot in hand should feed")

	assert_gt(horse.trust, 0.0, "and earn trust")
	assert_null(player.equipped_item, "the carrot in hand is eaten")


## The bag still works when that is where the carrot is -- stashed with H, or
## bought. Whichever the player has, feeding should reach for it.
func test_feeding_still_spends_a_carrot_from_the_bag():
	_hold_lasso()
	var horse := _horse_at(Vector2(8, 0))
	player._throw_capture_tool()
	horse._needs.hunger = 1.0
	player.inventory.add(_item_catalog.make("carrot"), 2)

	assert_true(player.offer_treat_to(horse))

	assert_eq(player.inventory.count_of("carrot"), 1)
	assert_gt(horse.trust, 0.0)


## The hand goes first: a player holding one out is offering THAT carrot, and
## eating from the bag instead would leave the held one sitting there while the
## stock quietly drained.
func test_the_held_carrot_is_offered_before_the_bag_is_opened():
	_hold_lasso()
	var horse := _horse_at(Vector2(8, 0))
	player._throw_capture_tool()
	horse._needs.hunger = 1.0
	player.equipped_item = _item_catalog.make("carrot")
	player.inventory.add(_item_catalog.make("carrot"), 2)

	player.offer_treat_to(horse)

	assert_eq(player.inventory.count_of("carrot"), 2, "the bag was not touched")
	assert_null(player.equipped_item, "the held one was")


## A refused feed must not eat anything, from either place.
func test_a_refused_feed_costs_no_carrot_from_hand():
	_hold_lasso()
	var horse := _horse_at(Vector2(8, 0))
	player._throw_capture_tool()
	horse._needs.hunger = 0.0
	player.equipped_item = _item_catalog.make("carrot")

	assert_false(player.offer_treat_to(horse))

	assert_not_null(player.equipped_item, "a full animal eats nothing")


# -- reported again, live: "When you pick up carrots or potatoes from the ---
# -- world they never make it into the inventory to feed horse or so." -----
#
# Every test above simulates "a carrot in hand" by poking `equipped_item`
# directly. That is not how a real player ever ends up holding one: a pulled
# wild carrot/potato becomes a ground item (WildCropMarker._finish_pull),
# and E picks a ground item with a real, kickable-grade mass -- which a
# carrot/potato now has, see ItemCatalog._PRODUCE_MASS_KG -- into
# `_hand_item_stack` (Player._try_pick_item_into_hand), NOT `equipped_item`.
# `equipped_item` is a completely different field: Player.equip_item()
# explicitly refuses anything that isn't a weapon or tool, so a food-kind
# item can structurally never reach it through ordinary play. The tests
# above kept passing by poking a field a real carrot pickup never touches,
# so this gap shipped invisibly. These two drive the REAL pickup path.

func _add_dropped_carrot(offset: Vector2) -> DroppedItem:
	var dropped := DroppedItem.new()
	dropped.item_stack = ItemStack.new(_item_catalog.make("carrot"), 1)
	dropped.position = player.position + offset
	# Needs real scene-tree membership, same reason test_player_kick.gd's
	# identical helper parents under `self` -- nearest_kickable_dropped_item_near
	# finds it via its own group, joined in _ready().
	add_child(dropped)
	return dropped


func test_a_carrot_picked_up_into_the_hand_feeds_a_hungry_horse():
	_add_dropped_carrot(Vector2(5, 0))
	assert_true(
		player._try_pick_item_into_hand(),
		"a light dropped carrot should be pickable into the hand"
	)
	assert_true(player.is_holding_item(), "the carrot should now be the held item")

	_hold_lasso()
	var horse := _horse_at(Vector2(8, 0))
	player._throw_capture_tool()
	horse._needs.hunger = 1.0

	assert_true(
		player.offer_treat_to(horse),
		"a carrot picked up off the ground into the hand should feed, exactly like one directly equipped"
	)
	assert_gt(horse.trust, 0.0, "and earn trust")
	assert_false(player.is_holding_item(), "the carrot actually in hand should be the one spent")


## The prompt has the same gap: AnimalActions.for_animal was only ever asked
## about `equipped_item`, so a player who had just picked a carrot up off the
## ground -- the ordinary way to have one at all -- was never even OFFERED
## "Feed" as a primary/secondary action in the first place.
func test_animal_actions_offers_feed_for_a_carrot_picked_up_into_the_hand():
	_add_dropped_carrot(Vector2(5, 0))
	player._try_pick_item_into_hand()

	_hold_lasso()
	var horse := _horse_at(Vector2(8, 0))
	player._throw_capture_tool()
	horse._needs.hunger = 1.0

	var verbs := []
	for action in player.animal_actions_for(horse):
		verbs.append(action["verb"])
	assert_true(
		verbs.has("Feed"),
		"holding a picked-up carrot at a hungry, restrained horse should offer Feed"
	)


# -- the net is a device with a real mesh (docs/concept/capture_dsl.md, -------
# -- 2026-09-05) ------------------------------------------------------------------
#
## What the net holds is read off the subject's body and the bag's geometry
## (a 10 mm mesh, a 30 cm mouth), never off a species list: a bee or a fly
## slips straight through and the message says so; a pond fish in range is a
## target like a flyer and leaves the water through the rod's own catch path;
## a trout or a koi is too big for the mouth.

func _fish_at(species: String, offset: Vector2) -> FishMarker:
	var fish := FishMarker.new()
	fish.species = species
	fish.wander_seed = 17
	creatures_parent.add_child(fish)
	fish.position = player.position + offset
	var loaded: Array = chunk_manager._loaded_fish.get(Vector2i(0, 0), [])
	loaded.append(fish)
	chunk_manager._loaded_fish[Vector2i(0, 0)] = loaded
	return fish


## Like _net_until_caught, for any net target -- a fish has no flyer type.
func _net_until_gone(target: Node, max_attempts: int = 40) -> void:
	var attempts := 0
	while is_instance_valid(target) and not target.is_queued_for_deletion() and attempts < max_attempts:
		player._throw_capture_tool()
		attempts += 1
	assert_true(
		not is_instance_valid(target) or target.is_queued_for_deletion(),
		"expected a catch within %d attempts at ~65%% each" % max_attempts
	)


func _throw_repeatedly(times: int) -> void:
	for i in times:
		player._throw_capture_tool()


func test_a_bee_slips_through_the_net_and_the_message_says_so():
	_hold_tool("butterfly_net")
	var bee := _flyer_at("bee", Vector2(8, 0))
	_throw_repeatedly(8)
	assert_true(is_instance_valid(bee) and not bee.is_queued_for_deletion(), "a 6 mm bee passes a 10 mm mesh")
	assert_eq(player.equipped_item.captive_species, "")
	player._lasso_step(1.0 / 60.0)
	assert_string_contains(player.lasso_message, "bee")
	assert_string_contains(player.lasso_message, "slips through")


func test_a_fly_slips_through_the_net_too():
	_hold_tool("butterfly_net")
	var fly := _flyer_at("fly", Vector2(8, 0))
	_throw_repeatedly(8)
	assert_true(is_instance_valid(fly) and not fly.is_queued_for_deletion())
	player._lasso_step(1.0 / 60.0)
	assert_string_contains(player.lasso_message, "slips through")


func test_a_goldfish_in_range_is_netted_out_of_the_water():
	_hold_tool("butterfly_net")
	var goldfish := _fish_at("goldfish", Vector2(8, 0))
	_net_until_gone(goldfish)
	assert_eq(player.equipped_item.captive_species, "goldfish")
	player._lasso_step(1.0 / 60.0)
	assert_eq(player.lasso_message, "Caught! Net is full.")


func test_a_koi_is_too_big_for_the_net_and_the_message_says_so():
	_hold_tool("butterfly_net")
	var koi := _fish_at("koi", Vector2(8, 0))
	_throw_repeatedly(8)
	assert_true(is_instance_valid(koi) and not koi.is_queued_for_deletion(), "a 55 cm koi does not go through a 30 cm mouth")
	assert_eq(player.equipped_item.captive_species, "")
	player._lasso_step(1.0 / 60.0)
	assert_string_contains(player.lasso_message, "koi")
	assert_string_contains(player.lasso_message, "too big")


func test_a_fish_out_of_net_range_is_left_alone():
	_hold_tool("butterfly_net")
	var goldfish := _fish_at("goldfish", Vector2(Player.LASSO_RANGE * 2.0, 0))
	_throw_repeatedly(3)
	assert_true(is_instance_valid(goldfish))
	assert_eq(player.equipped_item.captive_species, "")


func test_a_netted_fish_loads_the_net_and_never_bonds_even_with_menagerie():
	player.allocated_nodes["menagerie"] = true
	_hold_tool("butterfly_net")
	var goldfish := _fish_at("goldfish", Vector2(8, 0))
	_net_until_gone(goldfish)
	assert_eq(player.equipped_item.captive_species, "goldfish")
	assert_eq(player.bonded_companions.size(), 0, "a fish is not a companion that follows you on land")


func test_the_nearer_of_a_flyer_and_a_fish_is_the_one_the_net_goes_for():
	_hold_tool("butterfly_net")
	var monarch := _flyer_at("monarch", Vector2(40, 0))
	var goldfish := _fish_at("goldfish", Vector2(8, 0))
	_net_until_gone(goldfish)
	assert_true(is_instance_valid(monarch) and not monarch.is_queued_for_deletion(), "the farther flyer was never the target")
	assert_eq(player.equipped_item.captive_species, "goldfish")


func test_a_bottled_fish_is_bottled_like_anything_else():
	_hold_tool("butterfly_net")
	player.inventory.add(_item_catalog.make("glass_bottle"), 1)
	var goldfish := _fish_at("goldfish", Vector2(8, 0))
	_net_until_gone(goldfish)
	player._bottle_captive()
	assert_eq(player.equipped_item.captive_species, "")
	player._lasso_step(1.0 / 60.0)
	assert_eq(player.lasso_message, "Bottled the Goldfish.")


# -- starter kit (docs/concept/starting_kit.md) -------------------------------
#
# Replaces the old hardcoded, identical-for-everyone _ready() grant -- see
# StarterKit for the curated pool a player actually picks 3 of.

func test_grant_starter_items_adds_each_chosen_item_to_inventory():
	player.grant_starter_items(["stone_pickaxe", "rough_compass", "lasso"])
	var counts := player.inventory_counts()
	assert_eq(counts.get("stone_pickaxe", 0), 1)
	assert_eq(counts.get("rough_compass", 0), 1)
	assert_eq(counts.get("lasso", 0), 1)


func test_grant_starter_items_skips_an_unknown_id_gracefully():
	player.grant_starter_items(["not_a_real_item_zzz", "lasso"])
	assert_eq(player.inventory_counts().get("lasso", 0), 1)
	assert_false(player.inventory_counts().has("not_a_real_item_zzz"))


func test_grant_starter_items_equips_the_first_weapon_choice():
	player.grant_starter_items(["stone_pickaxe", "crude_blade", "lasso"])
	assert_eq(player.equipped_item.id, "crude_blade")


func test_grant_starter_items_equips_the_first_tool_when_no_weapon_was_chosen():
	# equip_item() already accepts weapon- OR tool-kind (player.gd's own
	# equip_item) -- a {pickaxe, compass, lasso} pick shouldn't leave the
	# player bare-handed just because nothing is literally a weapon.
	player.grant_starter_items(["stone_pickaxe", "rough_compass", "lasso"])
	assert_eq(player.equipped_item.id, "stone_pickaxe")


func test_grant_starter_items_leaves_the_player_bare_handed_when_neither_kind_was_chosen():
	# Every pool item today is weapon- or tool-kind, so this can't actually
	# happen from StarterKit.POOL -- exercised directly (an empty list, the
	# simplest case with neither kind present) to pin the documented
	# fallback regardless.
	assert_null(player.equipped_item, "precondition: nothing equipped yet")
	player.grant_starter_items([])
	assert_null(player.equipped_item)


func test_a_granted_weapons_mass_matches_the_catalogs_real_mass():
	# Locks in a fix that falls out of using catalog.make() uniformly: the
	# OLD hardcoded grant built its sword via bare Item.new(...), which
	# never set mass_kg (always 0.0) unlike every other real source of an
	# iron_sword.
	player.grant_starter_items(["iron_sword"])
	assert_eq(player.equipped_item.mass_kg, _item_catalog.make("iron_sword").mass_kg)
	assert_gt(player.equipped_item.mass_kg, 0.0, "a real iron sword must not be massless")
