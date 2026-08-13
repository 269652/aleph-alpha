extends CharacterBody2D
class_name Player

const EquipmentMaterial = preload("res://src/gameplay/equipment_material.gd")
const WetnessTracker = preload("res://src/gameplay/wetness_tracker.gd")
const WaterMovementModel = preload("res://src/gameplay/water_movement_model.gd")
const Health = preload("res://src/gameplay/health.gd")
const MeleeAttack = preload("res://src/gameplay/melee_attack.gd")
const TileTargeting = preload("res://src/gameplay/tile_targeting.gd")
const Item = preload("res://src/gameplay/item.gd")
const Inventory = preload("res://src/gameplay/inventory.gd")
const SurvivalMeters = preload("res://src/gameplay/survival_meters.gd")
const Wallet = preload("res://src/gameplay/wallet.gd")
const CraftingRecipeBook = preload("res://src/gameplay/crafting_recipe_book.gd")
const ExperienceTrack = preload("res://src/gameplay/experience_track.gd")
const SkillTree = preload("res://src/gameplay/skill_tree.gd")
const KeystonePassive = preload("res://src/gameplay/keystone_passive.gd")
const Equipment = preload("res://src/gameplay/equipment.gd")
const Smelting = preload("res://src/gameplay/smelting.gd")
const FishingSession = preload("res://src/gameplay/fishing_session.gd")
const MaterialDamage = preload("res://src/gameplay/material_damage.gd")
const Block = preload("res://src/gameplay/block.gd")
const HotbarAction = preload("res://src/gameplay/hotbar_action.gd")
const CampfireCooking = preload("res://src/gameplay/campfire_cooking.gd")
const FoodConsumption = preload("res://src/gameplay/food_consumption.gd")
const Shop = preload("res://src/gameplay/shop.gd")
const Hotbar = preload("res://src/gameplay/hotbar.gd")
const FishingCast = preload("res://src/gameplay/fishing_cast.gd")
const ProceduralBobberSprite = preload("res://src/rendering/procedural_bobber_sprite.gd")
const HeroAppearance = preload("res://src/rendering/hero_appearance.gd")
const ItemCatalog = preload("res://src/gameplay/item_catalog.gd")
const CreatureMarker = preload("res://src/rendering/creature_marker.gd")
const ChoppableTree = preload("res://src/rendering/choppable_tree.gd")
const SmashableStone = preload("res://src/rendering/smashable_stone.gd")
const DroppedItem = preload("res://src/rendering/dropped_item.gd")
const ItemStack = preload("res://src/gameplay/item_stack.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")
const ProceduralItemSprite = preload("res://src/rendering/procedural_item_sprite.gd")
const BiomeClassifier = preload("res://src/world/biome_classifier.gd")
const WorldCoordinates = preload("res://src/world/world_coordinates.gd")
const EarthChunkGenerator = preload("res://src/world/earth_chunk_generator.gd")
const EarthChunkManager = preload("res://src/world/earth_chunk_manager.gd")

const BASE_SPEED := 80.0
const PLAYER_SIZE := 12
## Camera2D zoom -- bumped from the original 3x so pixel art (sprites,
## terrain, water) reads clearly across a full 1280x720+ window instead of
## only a small slice of it. Applied in _ready() rather than left as a bare
## number in player.tscn, so it's a tested constant (see test_player_camera.gd)
## rather than an eyeballed scene property.
const CAMERA_ZOOM := Vector2(4, 4)
## How far (in pixels) position must change between frames for a non-authority
## proxy to consider itself "moving" for animation purposes, vs. jitter.
const PROXY_MOVEMENT_EPSILON := 0.5

## A melee swing: an AOE hit around the player (not aimed/single-target),
## with damage and knockback -- the "tactical mechanic beyond plain damage
## trading" Phase 3's definition of done asks for. Damage comes from the
## equipped weapon (UNARMED_DAMAGE if empty-handed).
const ATTACK_RANGE := 20.0
const UNARMED_DAMAGE := 5.0
const ATTACK_COOLDOWN := 0.5
const KNOCKBACK_FORCE := 60.0
## Base per-swing damage against wood before the material model's weapon-kind
## multiplier (see MaterialDamage/_chop_step): an axe lands 3x this (15.0, the
## historical AXE_DAMAGE tuning), a sword 0.5x, bare hands 0.25x.
const BASE_CHOP_DAMAGE := 5.0
## Mining power of a stone pickaxe -- feeds OreYield's ore-count scaling (see
## _pickaxe_power / MinableOre.mine).
const PICKAXE_POWER := 1.0
## Radius (px) within which the pickup action (default E) sweeps up ground
## items -- roughly two tiles, so you grab a small pile around you at once.
const PICKUP_RADIUS := 34.0
## How long the weapon's swing animation plays, in seconds -- shorter than
## ATTACK_COOLDOWN so the blade snaps back to rest before the next swing can
## start, rather than looking like it's still mid-swing when idle.
const SWING_DURATION := 0.2
const INVENTORY_SLOTS := 12

## How close (in tiles, Chebyshev/square distance -- see
## EarthChunkManager.has_structure_near) the player must stand to a placed
## campfire/furnace to cook or smelt: "standing near the fire" range, not
## room-scale -- a few tiles so you don't have to be pixel-perfect on top of
## it, but you can't use one clear across a base either.
const HEAT_SOURCE_RADIUS_TILES := 3

## How much a single eaten food item relieves hunger by (see eat_food()).
const EAT_HUNGER_RELIEF := 0.4
## Thirst relief per second while standing in deep-enough water to be
## "swimming" (see current_mode) -- reuses the existing swim-state check
## rather than a separate water-source concept.
const DRINK_RATE_PER_SECOND := 0.1

## Emitted whenever the inventory or equipped weapon changes, for the HUD.
signal inventory_changed

## Exposed so the demo scene can be tweaked in the editor to test different
## swim/drown scenarios without a full inventory system yet.
@export var body_weight := 10.0
@export var max_swimmable_weight := 50.0
@export var worn_material: EquipmentMaterial

var wetness := 0.0
var current_mode := "walking"
var current_speed_multiplier := 1.0

## Aggressive/healthy predators and boars attack the player back (see
## CreatureMarker._try_attack), so take_damage() has a live caller. Reaching
## 0 health sets is_dead and freezes the player in place (see
## _authority_step) for RESPAWN_DELAY seconds, then respawns at
## respawn_position (set by World when this Player is first spawned) with
## full health -- no graveyard/corpse-recovery system yet (see
## docs/progress.md), just a straight reset.
@export var max_health := 100.0
var health := max_health
var is_dead := false
const DEAD_MODULATE := Color(0.35, 0.35, 0.35, 1.0)

## Where this player respawns -- set by World right after its initial spawn
## placement, so death always returns to known-good (dry land) ground.
var respawn_position := Vector2.ZERO
const RESPAWN_DELAY := 3.0
var _respawn_accumulator := 0.0

var inventory := Inventory.new(INVENTORY_SLOTS)
## The single item currently in hand. It alone decides attack damage (if it's
## a weapon), tree-felling speed (fast for an axe, slow for a sword, slowest
## bare-handed), and mining power (only a pickaxe mines ore). Swapped by
## equip_item (from the hotbar or inventory). Null == bare hands.
var equipped_item: Item
## The placeable structure (campfire/furnace) armed for the next build-input
## press (see activate_hotbar_slot/activate_item_id dispatching HotbarAction.
## PLACE to _arm_placeable, and _build_step). Independent of equipped_item --
## arming a structure doesn't change what's drawn in hand. Persists until a
## different placeable is armed (mirrors equipped_item's own persist-until-
## switched behavior); it does NOT auto-clear when the stack runs out, see
## _build_step's doc comment. Null == nothing armed, i.e. build does today's
## plain bare-earth terraforming.
var _selected_placeable_item: Item
var survival := SurvivalMeters.new()
## Active timed buffs from eating rare/legendary fish (see
## FoodConsumption.FISH_BUFFS) -- category-slotted, ticked down in
## _food_buff_step. Empty means no active buff in any category.
var active_food_buffs: Array = []
var wallet := Wallet.new()
## How many number-key hotbar slots exist. World derives its HUD row's slot
## count from this (see World.HOTBAR_SLOT_COUNT), so the two can't drift.
const HOTBAR_SLOT_COUNT := 5
## Which item id sits on each hotbar key (see Hotbar). Explicitly assignable
## by dragging an item onto a slot, with empty slots auto-filled from the
## inventory -- so an item buried past the first few stacks can still be put
## on a key, which the old mirror-the-first-5-stacks hotbar made impossible.
var hotbar := Hotbar.new(HOTBAR_SLOT_COUNT)
var experience := ExperienceTrack.new()
var skill_tree := SkillTree.new()
var keystones := KeystonePassive.new()
## Worn armor (see Equipment): reduces incoming damage by its total armor.
var equipment := Equipment.new()
## node_id/keystone_id -> true for every allocated skill (see SkillTree /
## concept/progression.md). Skill bonuses fold into derived stats.
var allocated_nodes: Dictionary = {}
var unlocked_keystones: Dictionary = {}
## Skill-tree attack bonus, kept as a cached sum applied in _perform_attack.
var _skill_attack_bonus := 0.0
## Points a keystone costs to unlock (on top of its node-count gate).
const KEYSTONE_POINT_COST := 2
## Chosen class name (see ClassArchetype) and the attack bonus its stat lens
## grants -- applied by apply_class at character creation.
var character_class := "warrior"
var class_attack_bonus := 0.0
## Health gained per level (see ExperienceTrack / concept/progression.md).
const HEALTH_PER_LEVEL := 8.0
## XP awarded per level of a defeated creature.
const XP_PER_KILL := 6
## A hit always lands at least this much even against heavy armor -- armor
## mitigates, it doesn't make you invulnerable.
const MIN_ARMORED_DAMAGE := 1.0
var _crafting_recipe_book := CraftingRecipeBook.new()
var _smelting := Smelting.new()
var _fishing := FishingSession.new()
var _last_fish_input := false
var _pending_fish_pressed := false
var _fishing_cast_count := 0
var _fishing_result_message := ""
var _fishing_result_timer := 0.0
## The current fishing prompt/result, read by the HUD ("" == nothing to show).
var fishing_message := ""
## How long a caught/missed message lingers on the HUD.
const FISH_MESSAGE_DURATION := 2.5
## Fish granted per catch, scaled by the rolled rarity (see FishingMinigame).
const FISH_REWARD_BY_RARITY := {"common": 1, "uncommon": 1, "rare": 2, "legendary": 3}
## Which catalog item a catch's rarity becomes -- rare/legendary get their own
## buff-granting item (see FoodConsumption.FISH_BUFFS); common/uncommon stay
## the plain "fish" everyone already knows.
const FISH_ITEM_ID_BY_RARITY := {"rare": "rare_fish", "legendary": "legendary_fish"}
## How far a real, visible FishMarker (see FishRenderer) can be from the
## player and still be the one that "was" caught -- generous enough to cover
## a pond fish a few tiles out while standing at the shore.
const FISH_CATCH_RADIUS := 64.0

## -- Fishing visuals: a real cast, a bobber, and nearby fish reacting --
## Previously casting was invisible (no rod-throw motion, no landing point
## shown, no reaction from nearby fish, no signal when a bite starts) --
## reported as "no animation of the rod being thrown into water and also
## doesn't attract near fish and also no animation when fish bites".
var _fishing_cast := FishingCast.new()
var _bobber: Sprite2D
## Where the line landed for the current cast -- fixed at cast time, not
## re-derived from a possibly-changed facing while the line is out.
var _bobber_target := Vector2.ZERO
## How far around the bobber fish start steering toward it (see
## EarthChunkManager.set_attraction_point).
const ATTRACTION_RADIUS := 48.0
## The bobber's dip while a fish is biting -- the visible "something's
## pulling on the line" cue, on top of the HUD text prompt.
const BITE_BOB_AMPLITUDE_PX := 2.5
const BITE_BOB_SPEED := 14.0

## -- Shopping at a merchant villager (see VillageRenderer, Shop) --
## Phase 1 simplification: press the trade key near any merchant NPC to buy
## one item, cycling through Shop.CATALOG so repeated presses don't just buy
## the same cheapest thing forever -- no dedicated shop UI yet (that, and
## selling the player's own goods, are open follow-ups; see
## docs/progress.md's NPC section).
var _shop := Shop.new()
var _last_trade_input := false
var _pending_trade_pressed := false
var _trade_attempt_count := 0
var _trade_result_message := ""
var _trade_result_timer := 0.0
## The current shopping prompt/result, read by the HUD ("" == nothing to show).
var trade_message := ""
const TRADE_MESSAGE_DURATION := 2.5
## How close a merchant villager must be to trade with.
const TRADE_RADIUS := 48.0
var _item_catalog := ItemCatalog.new()

var _chunk_manager: EarthChunkManager
var _tile_size: int
var _wetness_tracker := WetnessTracker.new()
var _water_movement_model := WaterMovementModel.new()
var _biome_classifier := BiomeClassifier.new()
var _world_coordinates := WorldCoordinates.new()
var _health := Health.new()
var _melee_attack := MeleeAttack.new()
var _material_damage := MaterialDamage.new()
var _block := Block.new()
var _hotbar_action := HotbarAction.new()
var _campfire_cooking := CampfireCooking.new()
var _item_sprite_generator := ProceduralItemSprite.new()
var _tile_targeting := TileTargeting.new()
var _attack_cooldown_remaining := 0.0
var _last_attack_input_state := false
var _last_build_input_state := false
var _last_destroy_input_state := false
var _last_pickup_input_state := false

## Authority-side: last input direction received from the owning client (or
## read directly from Input, in the no-networking singleplayer fallback).
var _pending_input_direction := Vector2.ZERO
var _pending_attack_pressed := false
var _pending_block_pressed := false
var _pending_build_pressed := false
var _pending_destroy_pressed := false
var _pending_pickup_pressed := false
## Non-authority proxy side: for inferring facing/animation from replicated
## position deltas, since only position itself is replicated.
var _last_position := Vector2.ZERO
var _last_facing_direction := Vector2.DOWN

@onready var _character_view: CharacterView = $CharacterView
@onready var _collision_shape: CollisionShape2D = $CollisionShape2D
@onready var _camera: Camera2D = $Camera2D


func _ready() -> void:
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	_last_position = position
	_camera.zoom = CAMERA_ZOOM
	# So creature AI (CreatureMarker) can sense the player as a threat/target.
	add_to_group("player")
	_setup_replication()

	if _is_local_player_instance():
		_bind_wasd_movement()

	if worn_material == null:
		worn_material = EquipmentMaterial.new()
		worn_material.weight = 2.0
		worn_material.water_weight = 8.0
		worn_material.absorption_rate = 0.15
		worn_material.dry_rate = 0.05

	var shape := RectangleShape2D.new()
	shape.size = Vector2(PLAYER_SIZE, PLAYER_SIZE)
	_collision_shape.shape = shape

	# The fishing bobber (see _fishing_step) -- hidden until a line is cast.
	_bobber = Sprite2D.new()
	_bobber.texture = ProceduralBobberSprite.new().generate_texture()
	_bobber.visible = false
	_bobber.top_level = true  # world position, independent of the player's own transform
	add_child(_bobber)

	# Keep the hotbar reconciled with what's actually carried (see
	# sync_hotbar) from one place, rather than at every inventory mutation.
	inventory_changed.connect(sync_hotbar)

	# Start carrying a sword AND an axe; the sword is what's held at first (so
	# attacks land harder than fists and it looks like a weapon). The axe sits
	# in the inventory -- equip it from the hotbar/inventory to swap what's in
	# hand (see equip_item), which is what makes it chop trees fast (the held
	# item alone decides attack/chop/mine effectiveness).
	var sword := Item.new("iron_sword", "Iron Sword", "weapon", 1, 15.0)
	inventory.add(sword, 1)
	inventory.add(Item.new("iron_axe", "Iron Axe", "tool", 1), 1)
	# A couple of leather pieces so the equipment paperdoll (inventory screen)
	# is discoverable from the first minute -- click them to wear them.
	inventory.add(_item_catalog.make("leather_helm"), 1)
	inventory.add(_item_catalog.make("leather_chest"), 1)
	# A fishing rod so the fishing loop is discoverable -- stand by water and
	# press the fish key (default F).
	inventory.add(_item_catalog.make("fishing_rod"), 1)
	equip_item(sword)

	inventory_changed.emit()


## Server-authoritative movement: this node's authority is always the server
## (peer 1, the default -- never reassigned to the connecting client), so a
## client's own avatar is still just a non-authority proxy locally. Only
## `position` is replicated; everything else visual is inferred locally (see
## _proxy_step) so no extra network traffic is needed for it.
func _setup_replication() -> void:
	var sync := MultiplayerSynchronizer.new()
	var config := SceneReplicationConfig.new()
	config.add_property(NodePath(".:position"))
	config.property_set_replication_mode(NodePath(".:position"), SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
	sync.replication_config = config
	add_child(sync)


func _is_local_player_instance() -> bool:
	return not multiplayer.has_multiplayer_peer() or name.to_int() == multiplayer.get_unique_id()


## Whether this player should read the keyboard directly (rather than from a
## client's replicated RPC input). True in single-player and for a listen
## server's own avatar; false on a dedicated server simulating a remote
## client's avatar. NOTE: `multiplayer.has_multiplayer_peer()` is true even in
## single-player, so we key off local-instance identity, not peer presence --
## the earlier `not has_multiplayer_peer()` check silently disabled all
## keyboard input in single-player.
## Also false while DevConsole holds keyboard focus: movement/attack/build/
## destroy all poll Input.is_action_pressed/get_vector directly, which (unlike
## Godot's Control focus system) isn't suppressed just because a LineEdit has
## focus -- typing "d" into the console would otherwise also walk the player
## east.
func _controlled_locally() -> bool:
	return _is_local_player_instance() and is_multiplayer_authority() and not ConsoleFocus.is_open


## Registers WASD movement actions at runtime rather than hand-editing
## project.godot's input map (a hand-typed InputEventKey resource literal
## there is an easy way to silently corrupt the whole project file).
func _bind_wasd_movement() -> void:
	_bind_key_action("move_left", KEY_A)
	_bind_key_action("move_right", KEY_D)
	_bind_key_action("move_up", KEY_W)
	_bind_key_action("move_down", KEY_S)
	_bind_key_action("attack", KEY_SPACE)
	_bind_key_action("block", KEY_SHIFT)
	_bind_key_action("pickup", KEY_E)
	_bind_key_action("fish", KEY_F)
	_bind_key_action("trade", KEY_T)
	_bind_key_action("build", KEY_B)
	_bind_key_action("destroy", KEY_Q)


func _bind_key_action(action_name: String, keycode: Key) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)
	if not InputMap.action_get_events(action_name).is_empty():
		return  # already bound (e.g. a second Player instance in the same run)
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	InputMap.action_add_event(action_name, event)


## Must be called before the first _physics_process, to give this player
## access to the streamed world it's walking (or, for a non-authority proxy,
## rendering) on.
func setup(chunk_manager: EarthChunkManager, tile_size: int) -> void:
	_chunk_manager = chunk_manager
	_tile_size = tile_size


## No-op once already dead: freezes health at 0 and, since there's no
## respawn system yet (a separate, larger, not-yet-scoped feature -- see
## docs/progress.md), leaves the player in a visibly-dead but otherwise
## inert state (see _authority_step's early-out) rather than continuing to
## process hits against a corpse.
func take_damage(amount: float) -> void:
	if is_dead:
		return
	if is_blocking():
		amount = _block.blocked_damage(amount, _held_kind())
	# Worn armor soaks a flat chunk of any real hit (see Equipment), but never
	# reduces a hit to nothing -- at least MIN_ARMORED_DAMAGE always lands.
	if amount > 0.0:
		amount = maxf(MIN_ARMORED_DAMAGE, amount - equipment.total_armor())
	health = _health.take_damage(health, amount)
	if _health.is_dead(health):
		is_dead = true
		modulate = DEAD_MODULATE


## Full reset back to respawn_position after RESPAWN_DELAY seconds dead (see
## _authority_step) -- no inventory/item loss, no corpse to recover, just a
## clean restart, consistent with this project's honest "no death-stakes
## system yet" scope.
func _respawn() -> void:
	is_dead = false
	health = max_health
	modulate = Color.WHITE
	_respawn_accumulator = 0.0
	position = respawn_position


func is_set_up() -> bool:
	return _chunk_manager != null


## Applies a class archetype's stat lens at character creation (see
## ClassArchetype / concept/progression.md): a max-health offset (bumping the
## bar) and an attack-damage bonus. A starting bias, not a lock.
## `appearance` is the look authored in the character creator (see MainMenu /
## HeroAppearance). Empty (the default) rolls one from the player's stable
## node name -- the multiplayer peer id -- as a stand-in dna seed, which is
## what non-interactive spawns (dedicated server, --connect) and tests get.
func apply_class(class_name_value: String, stats: Dictionary, appearance: Dictionary = {}) -> void:
	character_class = class_name_value
	max_health = maxf(20.0, 100.0 + float(stats.get("max_health", 0.0)))
	health = max_health
	class_attack_bonus = float(stats.get("attack_damage", 0.0))
	if _character_view != null:
		var look := appearance
		if look.is_empty():
			look = HeroAppearance.new().appearance_for(class_name_value, name.hash())
		_character_view.apply_appearance(look)


## Awards XP (see ExperienceTrack); each level gained bumps max health and heals
## to full (a durable level-up payoff). Returns the number of levels gained.
func gain_experience(amount: int) -> int:
	var levels := experience.add_xp(amount)
	if levels > 0:
		max_health += HEALTH_PER_LEVEL * levels
		health = max_health
	return levels


## Allocates a skill-tree node if affordable (see SkillTree), spending its
## point cost and applying its stat bonus immediately. Returns true on success.
func allocate_skill(node_id: String) -> bool:
	if not skill_tree.can_allocate(node_id, allocated_nodes, experience.unspent_points):
		return false
	var info := skill_tree.node_info(node_id)
	if not experience.spend_points(int(info.get("point_cost", 1))):
		return false
	allocated_nodes = skill_tree.allocate(node_id, allocated_nodes)
	_apply_skill_stat(info.get("stat_name", ""), float(info.get("bonus_amount", 0.0)))
	return true


## Unlocks a keystone passive if its node-count gate is met and the player can
## pay KEYSTONE_POINT_COST (see KeystonePassive). Returns true on success.
func unlock_keystone(keystone_id: String) -> bool:
	if unlocked_keystones.get(keystone_id, false):
		return false
	if not keystones.can_unlock(keystone_id, allocated_nodes.size()):
		return false
	if not experience.spend_points(KEYSTONE_POINT_COST):
		return false
	unlocked_keystones[keystone_id] = true
	var info := keystones.keystone_info(keystone_id)
	_apply_skill_stat(info.get("stat_name", ""), float(info.get("bonus_amount", 0.0)))
	return true


## Applies a skill/keystone stat bonus to the live character. max_health also
## heals the gained amount; attack_damage accrues into the swing bonus. Other
## stats (stamina_regen) are recorded via the allocation but not yet fed back
## into their meters (a known gap noted in concept/progression.md).
func _apply_skill_stat(stat_name: String, amount: float) -> void:
	if stat_name == "max_health":
		max_health += amount
		health += amount
	elif stat_name == "attack_damage":
		_skill_attack_bonus += amount


## Activates hotbar slot `index` (0-based) against whatever item id is
## assigned to it (see Hotbar) -- weapons/tools get equipped, food/potions get
## used, raw materials do nothing (see HotbarAction). Returns true if
## something happened; false for an empty slot or an item no longer held.
## Called from World on a number-key press or a hotbar click.
func activate_hotbar_slot(index: int) -> bool:
	var item_id := hotbar.item_id_at(index)
	if item_id == "":
		return false
	return activate_item_id(item_id)


## Puts `item_id` on hotbar slot `index` -- what dropping an inventory item
## onto a hotbar slot does (see InventoryWindow/World's drag-and-drop).
func assign_hotbar_slot(index: int, item_id: String) -> void:
	hotbar.assign(index, item_id)


## Reconciles the hotbar against what's actually held: drops slots for items
## no longer carried, then auto-fills empty slots from the inventory (never
## overwriting an explicit assignment). Called whenever the inventory changes.
func sync_hotbar() -> void:
	var held_ids: Array = []
	for stack in inventory.stacks():
		held_ids.append(stack.item.id)
	hotbar.prune_missing(held_ids)
	hotbar.auto_fill(held_ids)


## Activates the held item with this id (see HotbarAction) -- used by the
## inventory window's click-to-use. Returns true if something happened.
func activate_item_id(item_id: String) -> bool:
	for stack in inventory.stacks():
		if stack.item.id == item_id:
			match _hotbar_action.action_for(stack.item.kind):
				HotbarAction.EQUIP:
					if stack.item.kind == "armor":
						return equip_armor(stack.item)
					return equip_item(stack.item)
				HotbarAction.USE:
					return _use_food(stack.item.id)
				HotbarAction.PLACE:
					return _arm_placeable(stack.item)
				_:
					return false
	return false


## Arms `item` (a "placeable" kind -- campfire/furnace) so the next
## build-input press places it into the world instead of doing plain
## bare-earth terraforming (see _build_step). Always succeeds for a placeable
## item -- HotbarAction.action_for already gated the caller to only reach here
## for kind "placeable".
func _arm_placeable(item) -> bool:
	_selected_placeable_item = item
	return true


## Equips an armor piece from the inventory into its slot (see Equipment):
## removes it from the inventory, and returns any displaced piece to the
## inventory. Returns true on success.
func equip_armor(item) -> bool:
	if not item.is_equippable():
		return false
	inventory.remove(item.id, 1)
	var displaced = equipment.equip(item)
	if displaced != null:
		inventory.add(displaced, 1)
	inventory_changed.emit()
	return true


## Removes the armor worn in `slot` back into the inventory (see the inventory
## paperdoll). Returns true if something was unequipped.
func unequip_slot(slot: String) -> bool:
	var item = equipment.unequip(slot)
	if item == null:
		return false
	inventory.add(item, 1)
	inventory_changed.emit()
	return true


## Using a food item: if it's a raw item that can be cooked and the player is
## standing near a placed campfire (their heat source), cook it instead of
## eating it raw (see CampfireCooking) -- otherwise just eat it. So clicking
## raw meat next to a built campfire turns it into cooked meat.
func _use_food(item_id: String) -> bool:
	if cook(item_id):
		return true
	return eat_food(item_id)


## Cooks one unit of a raw food item into its cooked form (see CampfireCooking)
## if the player is near a placed campfire. Returns false (no-op) if the item
## can't be cooked or there's no campfire nearby.
func cook(item_id: String) -> bool:
	if not _campfire_cooking.can_cook(item_id, _has_campfire()):
		return false
	var cooked := _campfire_cooking.cooked_output(item_id)
	if cooked == "" or not _item_catalog.has(cooked):
		return false
	if inventory.remove(item_id, 1) <= 0:
		return false
	inventory.add(_item_catalog.make(cooked), 1)
	return true


## True while a placed campfire (see EarthChunkManager.has_structure_near) is
## within HEAT_SOURCE_RADIUS_TILES of the player's current tile -- a real
## world-proximity check, not an inventory count: carrying an unplaced
## campfire in your pack no longer counts.
func _has_campfire() -> bool:
	return _has_structure_near_player("campfire")


## A heat source for smelting/cooking: a placed campfire or the sturdier
## placed furnace (see concept/smelting.md), within HEAT_SOURCE_RADIUS_TILES
## of the player.
func _has_heat_source() -> bool:
	return _has_structure_near_player("campfire") or _has_structure_near_player("furnace")


## How much faster stamina regenerates each second while a "sustenance"
## category buff (rare fish -- see FoodConsumption.FISH_BUFFS) is active, on
## top of SurvivalMeters.advance's own passive regen.
const STAMINA_BUFF_REGEN_PER_SECOND := 0.1
## Melee damage multiplier while a "combat" category buff (legendary fish) is
## active.
const DAMAGE_BOOST_MULTIPLIER := 1.3


## Authority-only: ticks down active_food_buffs and applies whatever ongoing
## effect the currently-active buffs grant (currently: extra stamina regen
## while a "sustenance" buff is up). The "combat" damage-boost buff instead
## reads live at attack time -- see _damage_buff_multiplier.
func _food_buff_step(delta: float) -> void:
	active_food_buffs = FoodConsumption.advance_food_buffs(active_food_buffs, delta)
	var sustenance := FoodConsumption.buff_in_category(active_food_buffs, "sustenance")
	if sustenance.buff == "stamina_regen":
		survival.rest(STAMINA_BUFF_REGEN_PER_SECOND * delta)


## Melee damage multiplier from an active "combat" category food buff (see
## FoodConsumption.FISH_BUFFS's legendary_fish entry) -- 1.0 (no change) when
## none is active.
func _damage_buff_multiplier() -> float:
	var combat := FoodConsumption.buff_in_category(active_food_buffs, "combat")
	return DAMAGE_BOOST_MULTIPLIER if combat.buff == "damage_boost" else 1.0


func _has_structure_near_player(structure_id: String) -> bool:
	if _chunk_manager == null:
		return false
	var tile := current_tile()
	return _chunk_manager.has_structure_near(tile.x, tile.y, structure_id, HEAT_SOURCE_RADIUS_TILES)


## Equips a weapon or tool as the single held item (drawn in hand, and the
## sole driver of attack/chop/mine effectiveness). The item stays in the
## inventory -- equipping just makes it active and updates the drawn sprite,
## so switching from sword to axe visibly puts the axe in hand and makes trees
## fell fast. Also updates the paperdoll's "weapon" slot (see equipment,
## Item.equip_slot_name) so the inventory window's Character screen actually
## shows what's equipped instead of staying permanently empty for
## weapons/tools (only equip_armor used to touch `equipment`). Non-equippable
## kinds (materials/food) are a no-op.
func equip_item(item) -> bool:
	if item.kind != "weapon" and item.kind != "tool":
		return false
	equipped_item = item
	equipment.equip(item)
	_character_view.equip_weapon(_item_sprite_generator.generate_texture(item.id))
	inventory_changed.emit()
	return true


## Consumes one unit of a "food"-kind item from the inventory to relieve
## hunger (see SurvivalMeters.eat) -- called from World when the player
## clicks a food row in the inventory window. Returns false (no-op) if the
## player doesn't actually hold a food item with this id.
func eat_food(item_id: String) -> bool:
	for stack in inventory.stacks():
		if stack.item.id == item_id and stack.item.kind == "food":
			inventory.remove(item_id, 1)
			survival.eat(EAT_HUNGER_RELIEF)
			# Rare/legendary catches (see FoodConsumption.FISH_BUFFS) grant a
			# timed buff directly on eating -- no cooking/recipe required.
			if FoodConsumption.FISH_BUFFS.has(item_id):
				active_food_buffs = FoodConsumption.apply_food_buff(
					active_food_buffs, FoodConsumption.FISH_BUFFS[item_id]
				)
			return true
	return false


## item_id -> total count held across every stack, for CraftingRecipeBook's
## pure can_craft()/craft() (which only knows about counts, not Inventory's
## multi-stack storage) and the crafting UI's affordability display.
func inventory_counts() -> Dictionary:
	return _inventory_counts()


func _inventory_counts() -> Dictionary:
	var counts := {}
	for stack in inventory.stacks():
		counts[stack.item.id] = counts.get(stack.item.id, 0) + stack.count
	return counts


## Crafts recipe_id (see CraftingRecipeBook) if the inventory holds enough
## inputs: removes exactly the consumed amount of each input (the delta
## between the pre-craft count and CraftingRecipeBook's reported remaining
## count) and adds the output via ItemCatalog. Returns false (no-op, nothing
## removed or added) if the recipe is unknown or inputs are insufficient.
func craft(recipe_id: String) -> bool:
	# Smelting recipes (ore + coal -> ingot) need a heat source present, like
	# cooking does (see Smelting / concept/smelting.md).
	if _smelting.is_smelting_recipe(recipe_id) and not _has_heat_source():
		return false
	var counts := _inventory_counts()
	var result := _crafting_recipe_book.craft(recipe_id, counts)
	if not result.success:
		return false

	for item_id in counts:
		var consumed: int = counts[item_id] - int(result.remaining_counts.get(item_id, 0))
		if consumed > 0:
			inventory.remove(item_id, consumed)

	if _item_catalog.has(result.output_item_id):
		var output_item := _item_catalog.make(result.output_item_id)
		var overflow: int = inventory.add(output_item, result.output_count)
		if overflow > 0:
			# A full inventory must never silently eat the crafted item (the
			# consumed inputs rarely free a whole slot) -- drop what didn't
			# fit at the player's feet as a pick-up-able ground item instead.
			WorldItemBus.item_dropped.emit(ItemStack.new(output_item, overflow), position)
	inventory_changed.emit()
	return true


## Converts _last_facing_direction into the 4-way string WeaponSwing/
## CharacterView.play_attack_swing expect, mirroring CharacterView.set_facing's
## own dominant-axis logic.
func _facing_string() -> String:
	if absf(_last_facing_direction.x) > absf(_last_facing_direction.y):
		return "right" if _last_facing_direction.x > 0.0 else "left"
	return "down" if _last_facing_direction.y > 0.0 else "up"


func current_tile() -> Vector2i:
	var raw := Vector2i(floori(position.x / _tile_size), floori(position.y / _tile_size))
	var world_size := Vector2i(EarthChunkGenerator.WORLD_WIDTH_TILES, EarthChunkGenerator.WORLD_HEIGHT_TILES)
	return _world_coordinates.wrap(raw, world_size)


func _physics_process(delta: float) -> void:
	if is_multiplayer_authority():
		_authority_step(delta)
	else:
		_proxy_step()

	if _is_local_player_instance() and not is_multiplayer_authority() and multiplayer.has_multiplayer_peer():
		_submit_input.rpc_id(1, _read_local_input())
		_submit_attack.rpc_id(1, Input.is_action_pressed("attack"))
		_submit_build.rpc_id(1, Input.is_action_pressed("build"))
		_submit_destroy.rpc_id(1, Input.is_action_pressed("destroy"))


## Runs only on the authority (the server, or this same instance in the
## no-networking singleplayer fallback): the real simulation -- water
## depth/wetness/movement resolution and actual collision via move_and_slide.
func _authority_step(delta: float) -> void:
	if _chunk_manager == null:
		return
	if is_dead:
		_respawn_accumulator += delta
		if _respawn_accumulator >= RESPAWN_DELAY:
			_respawn()
		return  # frozen in place until the respawn timer above fires

	var tile := current_tile()
	var water_result := _resolve_water_state(tile, delta)
	current_mode = water_result.mode
	current_speed_multiplier = water_result.speed_multiplier * _weather_speed_multiplier()

	var input_direction := _read_local_input() if _controlled_locally() else _pending_input_direction
	velocity = input_direction * BASE_SPEED * current_speed_multiplier
	move_and_slide()
	_wrap_position()

	_last_facing_direction = input_direction if input_direction.length() > 0.01 else _last_facing_direction
	_update_character_view(input_direction)

	survival.advance(delta)
	# Standing in any water (wading in the shallows or swimming) lets you drink
	# from it -- the "drink from water tiles" option. Wading is the easy way to
	# quench thirst without getting fully soaked.
	if current_mode == "swimming" or current_mode == "wading":
		survival.drink(DRINK_RATE_PER_SECOND * delta)
	if _chunk_manager != null:
		survival.regulate_temperature(_chunk_manager.ambient_warmth(position), wetness, delta)

	_attack_step(delta)
	_pickup_step()
	_build_step()
	_destroy_step()
	_fishing_step(delta)
	_food_buff_step(delta)
	_shop_step(delta)


## Combined weather + exposure movement penalty (see WeatherModel /
## SurvivalMeters): rain and storm slow you, and being freezing slows you
## further (stiff, sluggish). 1.0 when the world isn't wired (isolated tests).
const FREEZING_SPEED_PENALTY := 0.75
func _weather_speed_multiplier() -> float:
	var m := 1.0
	if _chunk_manager != null:
		m *= _chunk_manager.weather_speed_modifier(position)
	if survival.is_freezing():
		m *= FREEZING_SPEED_PENALTY
	return m


## Authority-only: resolves a melee swing on the rising edge of the attack
## input (not held-repeat), gated by ATTACK_COOLDOWN.
func _attack_step(delta: float) -> void:
	_attack_cooldown_remaining = maxf(0.0, _attack_cooldown_remaining - delta)

	var attack_pressed := (
		Input.is_action_pressed("attack") if _controlled_locally() else _pending_attack_pressed
	)
	var just_pressed := attack_pressed and not _last_attack_input_state
	_last_attack_input_state = attack_pressed

	# No swinging while swimming -- the weapon is stowed in the water (see
	# CharacterView.set_movement_state's visual stowing).
	if just_pressed and _attack_cooldown_remaining <= 0.0 and current_mode != "swimming":
		_perform_attack()


func _perform_attack() -> void:
	_attack_cooldown_remaining = ATTACK_COOLDOWN
	_character_view.play_attack_swing(_facing_string(), SWING_DURATION)

	var creatures := get_tree().get_nodes_in_group(CreatureMarker.GROUP_NAME)
	var positions: Array = []
	for creature in creatures:
		positions.append(creature.position)

	var base_damage := _melee_attack.attack_damage(_held_weapon(), UNARMED_DAMAGE) + class_attack_bonus + _skill_attack_bonus
	var damage := _material_damage.effective_damage(base_damage, _held_kind(), "flesh") * _damage_buff_multiplier()
	var hit_indices := _melee_attack.targets_in_range(position, positions, ATTACK_RANGE)
	for index in hit_indices:
		var creature: CreatureMarker = creatures[index]
		var knockback := _melee_attack.knockback_vector(position, creature.position, KNOCKBACK_FORCE)
		creature.apply_knockback(knockback)
		creature.take_damage(damage)
		# A hit that kills the creature awards XP scaled by its level (see
		# ExperienceTrack / concept/progression.md).
		if creature.is_queued_for_deletion() and creature.info != null:
			gain_experience(XP_PER_KILL * creature.info.level)

	_chop_step()
	_smash_step()
	_harvest_grass_step()


## Smashing/mining: a swing that reaches a rock node (shared "stone" group)
## does one of two things. An ore-bearing node (MinableOre, has mine()) is
## mined -- with a pickaxe equipped it yields ore + stone, bare-handed only
## stone (see OreYield). A plain boulder (SmashableStone, has smash()) always
## yields a rock; carrying another rock knaps sharp shards off it with a tested
## probability (see Knapping) -- rock-on-rock, the first tool technology.
func _smash_step() -> void:
	var stones := get_tree().get_nodes_in_group(SmashableStone.GROUP_NAME)
	var positions: Array = []
	for stone in stones:
		positions.append(stone.position)

	var carrying_rock: bool = _inventory_counts().get("rock", 0) > 0
	var pickaxe_power := _pickaxe_power()
	for index in _melee_attack.targets_in_range(position, positions, ATTACK_RANGE):
		var node = stones[index]
		if node.has_method("mine"):
			node.mine(pickaxe_power)
		elif node.has_method("smash"):
			node.smash(carrying_rock)


## Mining power of the currently-equipped tool: a pickaxe mines ore, anything
## else (or nothing) has zero mining power (bare-handed).
func _pickaxe_power() -> float:
	if equipped_item != null and equipped_item.is_pickaxe():
		return PICKAXE_POWER
	return 0.0


## Harvesting: a swing over a mature tall-grass patch tears it up for plant
## fibre (see EarthChunkManager.harvest_grass_near) -- the lashing material in
## the stick+shard+fibre crude-blade recipe.
func _harvest_grass_step() -> void:
	if _chunk_manager != null:
		_chunk_manager.harvest_grass_near(position)


## The held item's material-model kind (see MaterialDamage/Block), used for
## attacks, blocking, AND chopping -- so what's in hand is the single thing
## that matters: an axe chops wood fast (and blocks/cuts like an axe), a sword
## chops slowly but blocks best, bare hands (or a non-weapon tool like a
## pickaxe) are weakest at both.
func _held_kind() -> String:
	if equipped_item == null:
		return "unarmed"
	if equipped_item.is_axe():
		return "axe"
	return "sword" if equipped_item.is_weapon() else "unarmed"


## The held item as an attack weapon, or null if it isn't one (bare-hands /
## holding a tool) -- feeds MeleeAttack.attack_damage.
func _held_weapon():
	return equipped_item if equipped_item != null and equipped_item.is_weapon() else null


## True while the block input is held (and the player is alive): incoming
## damage is reduced weapon-dependently (see Block); blocking, like attacking,
## costs no stamina -- combat stays purely cooldown-based (see
## concept/survival.md's "Stamina scope: movement only, not combat").
func is_blocking() -> bool:
	if is_dead:
		return false
	return Input.is_action_pressed("block") if _controlled_locally() else _pending_block_pressed


## Felling: any swing damages ChoppableTrees in range through the material
## damage model (see MaterialDamage), scaled by the HELD item -- an axe chops
## at full efficiency (3x wood multiplier), a sword hacks weakly (0.5x, so a
## tree takes many more swings), bare hands barely scratch bark (0.25x). Same
## AOE range/targeting math as creature hits (reuses MeleeAttack.targets_in_range).
func _chop_step() -> void:
	var damage := _material_damage.effective_damage(BASE_CHOP_DAMAGE, _held_kind(), "wood")
	if damage <= 0.0:
		return

	var trees := get_tree().get_nodes_in_group(ChoppableTree.GROUP_NAME)
	var positions: Array = []
	for tree in trees:
		positions.append(tree.position)

	var hit_indices := _melee_attack.targets_in_range(position, positions, ATTACK_RANGE)
	for index in hit_indices:
		var tree: ChoppableTree = trees[index]
		tree.take_damage(damage)


## Authority-only: turns the tile the player is facing into bare earth (see
## Authority-only: on the rising edge of the pickup input (default E), sweeps
## up every ground item within PICKUP_RADIUS into the inventory (see
## DroppedItem.pick_up) -- a convenience gather alongside the existing
## click-to-pick-up. Rising-edge so holding E doesn't spam-pick every frame.
func _pickup_step() -> void:
	var pickup_pressed := (
		Input.is_action_pressed("pickup") if _controlled_locally() else _pending_pickup_pressed
	)
	var just_pressed := pickup_pressed and not _last_pickup_input_state
	_last_pickup_input_state = pickup_pressed
	if just_pressed:
		pickup_nearby()


## Picks up every ground item within PICKUP_RADIUS. Returns the number of item
## nodes fully collected.
func pickup_nearby() -> int:
	var collected := 0
	for item in get_tree().get_nodes_in_group(DroppedItem.GROUP_NAME):
		if item.is_queued_for_deletion():
			continue
		if position.distance_to(item.position) <= PICKUP_RADIUS and item.pick_up(self):
			collected += 1
	return collected


## Authority-only: the fishing minigame (see FishingSession / concept/fishing.md).
## Press the fish key next to water with a rod to cast -- a visible rod-throw
## swing and a bobber landing at the cast point (see FishingCast), drawing
## nearby fish toward it (EarthChunkManager.set_attraction_point). Wait for a
## bite (the bobber dips), then press the fish key again within the reaction
## window to land it (rarer catches yield more). Reeling too early or too
## late loses it. The HUD reads fishing_message.
func _fishing_step(delta: float) -> void:
	_fishing.advance(delta)
	if _fishing.phase() == FishingSession.CAUGHT:
		var rarity := _fishing.rarity()
		var count: int = FISH_REWARD_BY_RARITY.get(rarity, 1)
		# Rare/legendary catches become their own buff-granting item (see
		# FoodConsumption.FISH_BUFFS) so the rarity survives into the
		# inventory instead of being lost the moment the reward is granted.
		var fish_item_id: String = FISH_ITEM_ID_BY_RARITY.get(rarity, "fish")
		inventory.add(_item_catalog.make(fish_item_id), count)
		inventory_changed.emit()
		# If a real, visible fish (see FishRenderer) happens to be nearby,
		# make it disappear and name its species -- purely cosmetic, doesn't
		# change what's rewarded (still the rarity-scaled item/count above).
		var species := ""
		if _chunk_manager != null:
			species = _chunk_manager.catch_nearest_fish(position, FISH_CATCH_RADIUS)
		if species != "":
			_fishing_result_message = "Caught a %s %s! (x%d)" % [rarity, species, count]
		else:
			_fishing_result_message = "Caught a %s fish! (x%d)" % [rarity, count]
		_fishing_result_timer = FISH_MESSAGE_DURATION
		_fishing = FishingSession.new()
		_end_cast_visuals()
	elif _fishing.phase() == FishingSession.MISSED:
		_fishing_result_message = "The fish got away…"
		_fishing_result_timer = FISH_MESSAGE_DURATION
		_fishing = FishingSession.new()
		_end_cast_visuals()

	var fish_pressed := (
		Input.is_action_pressed("fish") if _controlled_locally() else _pending_fish_pressed
	)
	var just_pressed := fish_pressed and not _last_fish_input
	_last_fish_input = fish_pressed
	if just_pressed:
		if _fishing.is_active():
			_fishing.react()
		elif _has_fishing_rod() and _near_water():
			_fishing_cast_count += 1
			_fishing.cast(
				hash("%d_%d_%d" % [int(position.x), int(position.y), _fishing_cast_count]), 0.0
			)
			_start_cast_visuals()

	if _fishing.is_active() and _bobber != null:
		# A visible dip while a fish is on the line, on top of the HUD text.
		var bob := sin(_fishing.phase_elapsed_seconds() * BITE_BOB_SPEED) * BITE_BOB_AMPLITUDE_PX \
			if _fishing.phase() == FishingSession.BITING else 0.0
		_bobber.global_position = _bobber_target + Vector2(0, bob)
		if _chunk_manager != null:
			_chunk_manager.set_attraction_point(_bobber_target, ATTRACTION_RADIUS)

	_fishing_result_timer = maxf(0.0, _fishing_result_timer - delta)
	if _fishing.phase() == FishingSession.BITING:
		fishing_message = "! BITE — press the fish key!"
	elif _fishing.is_active():
		fishing_message = "Casting… wait for a bite."
	elif _fishing_result_timer > 0.0:
		fishing_message = _fishing_result_message
	else:
		fishing_message = ""


## Casting: a quick rod-throw swing (reusing the same swing animation as a
## melee attack) and the bobber landing at the cast point, drawing nearby
## fish in.
func _start_cast_visuals() -> void:
	_character_view.play_attack_swing(_facing_string(), SWING_DURATION)
	_bobber_target = _fishing_cast.cast_point(position, _last_facing_direction)
	if _bobber != null:
		_bobber.global_position = _bobber_target
		_bobber.visible = true
	if _chunk_manager != null:
		_chunk_manager.set_attraction_point(_bobber_target, ATTRACTION_RADIUS)


func _end_cast_visuals() -> void:
	if _bobber != null:
		_bobber.visible = false
	if _chunk_manager != null:
		_chunk_manager.clear_attraction_point()


func _has_fishing_rod() -> bool:
	return _inventory_counts().get("fishing_rod", 0) > 0


## True if any cardinal neighbor tile is open water (ocean) -- you fish from the
## shore, not from on top of the water.
func _near_water() -> bool:
	if _chunk_manager == null:
		return false
	var tile := current_tile()
	for offset in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if _chunk_manager.biome_at_global(tile.x + offset.x, tile.y + offset.y) == "ocean":
			return true
	return false


## Authority-only: press the trade key next to a merchant villager (see
## EarthChunkManager.has_merchant_near) to buy one item from Shop.CATALOG,
## cycling through it each successful purchase so repeated presses don't just
## buy the same cheapest thing forever. The HUD reads trade_message.
func _shop_step(delta: float) -> void:
	var trade_pressed := (
		Input.is_action_pressed("trade") if _controlled_locally() else _pending_trade_pressed
	)
	var just_pressed := trade_pressed and not _last_trade_input
	_last_trade_input = trade_pressed
	if just_pressed:
		if _chunk_manager == null or not _chunk_manager.has_merchant_near(position, TRADE_RADIUS):
			_trade_result_message = "No merchant nearby."
		else:
			_attempt_a_purchase()
		_trade_result_timer = TRADE_MESSAGE_DURATION

	_trade_result_timer = maxf(0.0, _trade_result_timer - delta)
	trade_message = _trade_result_message if _trade_result_timer > 0.0 else ""


## Tries each item in Shop.CATALOG in turn, starting from _trade_attempt_count
## (so repeated purchases cycle through the catalog rather than always
## re-buying the first affordable item), and buys the first one the wallet
## can afford.
func _attempt_a_purchase() -> void:
	var item_ids := _shop.known_item_ids()
	for offset in item_ids.size():
		var item_id: String = item_ids[(_trade_attempt_count + offset) % item_ids.size()]
		if _shop.buy(wallet, inventory, _item_catalog, item_id):
			_trade_attempt_count += 1
			inventory_changed.emit()
			_trade_result_message = "Bought %s for %d gold." % [
				_item_catalog.make(item_id).display_name, _shop.price_of(item_id)
			]
			return
	_trade_result_message = "Not enough gold."


## Authority-only: on the rising edge of the build input, either places the
## armed placeable structure (see _arm_placeable) or -- when nothing is armed
## -- turns the tile the player is facing into bare earth (see
## TerrainRenderer.EARTH_TILE_ID), exactly as before this structure-placement
## feature existed: intentional (Terraria-style terraforming), not a bug,
## build always replaces whatever biome tile is there, grass included.
func _build_step() -> void:
	var build_pressed := (
		Input.is_action_pressed("build") if _controlled_locally() else _pending_build_pressed
	)
	var just_pressed := build_pressed and not _last_build_input_state
	_last_build_input_state = build_pressed

	if not just_pressed or _chunk_manager == null:
		return

	var target := _tile_targeting.facing_tile(current_tile(), _last_facing_direction)

	if _selected_placeable_item != null:
		# A placeable is armed: place it instead of doing bare-earth
		# terraforming -- but only while the player still actually holds one.
		# Running out doesn't silently fall back to terraforming (that would
		# be a surprising bait-and-switch mid-build); it just does nothing
		# until the player restocks or arms something else.
		if _inventory_counts().get(_selected_placeable_item.id, 0) <= 0:
			return
		if _chunk_manager.build_at_global(target.x, target.y, _selected_placeable_item.id):
			# Only consume on a successful placement -- build_at_global
			# returns false if the target chunk isn't loaded or the tile is
			# already occupied by another modification.
			inventory.remove(_selected_placeable_item.id, 1)
			inventory_changed.emit()
		return

	_chunk_manager.build_at_global(target.x, target.y, TerrainRenderer.EARTH_TILE_ID)


## Authority-only: removes a modification from the tile the player is facing,
## on the rising edge of the destroy input. If that modification was a known
## placeable structure (campfire/furnace -- see item_catalog.gd), one unit of
## it is returned to the inventory -- the player is standing right there
## breaking it, no need for a ground-drop node. Destroying plain bare earth
## (today's existing behavior) stays exactly as-is: there's no "earth" item,
## so nothing is given back.
func _destroy_step() -> void:
	var destroy_pressed := (
		Input.is_action_pressed("destroy") if _controlled_locally() else _pending_destroy_pressed
	)
	var just_pressed := destroy_pressed and not _last_destroy_input_state
	_last_destroy_input_state = destroy_pressed

	if not just_pressed or _chunk_manager == null:
		return

	var target := _tile_targeting.facing_tile(current_tile(), _last_facing_direction)
	var tile_id := _chunk_manager.modification_at_global(target.x, target.y)
	if not _chunk_manager.destroy_at_global(target.x, target.y):
		return

	if tile_id != "" and _item_catalog.has(tile_id):
		var removed_item := _item_catalog.make(tile_id)
		if removed_item.kind == "placeable":
			inventory.add(removed_item, 1)
			inventory_changed.emit()


## Runs on every non-authority peer's copy of a player (including a client's
## copy of its own avatar): position comes from replication, not local
## simulation. Facing/animation are inferred from how the replicated position
## is actually moving; swim-vs-walk visuals reuse a local, deterministic
## water-depth lookup (safe -- it's not exploitable state) if a chunk manager
## is available, defaulting to a plain walk otherwise.
func _proxy_step() -> void:
	var movement := position - _last_position
	_last_position = position

	if _chunk_manager != null and is_set_up():
		var water_result := _resolve_water_state(current_tile(), get_physics_process_delta_time())
		current_mode = water_result.mode
		current_speed_multiplier = water_result.speed_multiplier

	var facing_direction := _last_facing_direction
	if movement.length() > PROXY_MOVEMENT_EPSILON:
		facing_direction = movement.normalized()
	_last_facing_direction = facing_direction

	var display_direction := facing_direction if movement.length() > PROXY_MOVEMENT_EPSILON else Vector2.ZERO
	_update_character_view(display_direction)


func _read_local_input() -> Vector2:
	return Input.get_vector("move_left", "move_right", "move_up", "move_down")


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _submit_input(direction: Vector2) -> void:
	if not is_multiplayer_authority():
		return
	_pending_input_direction = direction


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _submit_attack(pressed: bool) -> void:
	if not is_multiplayer_authority():
		return
	_pending_attack_pressed = pressed


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _submit_build(pressed: bool) -> void:
	if not is_multiplayer_authority():
		return
	_pending_build_pressed = pressed


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _submit_destroy(pressed: bool) -> void:
	if not is_multiplayer_authority():
		return
	_pending_destroy_pressed = pressed


func _resolve_water_state(tile: Vector2i, delta: float) -> Dictionary:
	var elevation := _chunk_manager.elevation_at_global(tile.x, tile.y)
	var water_depth := _biome_classifier.depth_meters_at(
		elevation, EarthChunkGenerator.EARTH_SEA_LEVEL, EarthChunkGenerator.EARTH_OCEAN_DEPTH_RANGE_METERS
	)

	var submerged := water_depth > 0.0
	wetness = _wetness_tracker.update(wetness, worn_material, submerged, delta)
	var total_weight := body_weight + worn_material.effective_weight(wetness)

	return _water_movement_model.resolve(water_depth, total_weight, max_swimmable_weight)


func _update_character_view(input_direction: Vector2) -> void:
	_character_view.set_facing(input_direction)
	if current_mode == "swimming":
		_character_view.set_movement_state(CharacterView.MovementState.SWIMMING)
	elif input_direction.length() > 0.01 and current_mode != "drowning":
		_character_view.set_movement_state(CharacterView.MovementState.WALKING)
	else:
		_character_view.set_movement_state(CharacterView.MovementState.IDLE)


## Toroidal wrap: walking off any edge of the (finite, real-Earth-sized) world lands on the opposite side.
func _wrap_position() -> void:
	var world_pixel_size := Vector2(
		EarthChunkGenerator.WORLD_WIDTH_TILES * _tile_size, EarthChunkGenerator.WORLD_HEIGHT_TILES * _tile_size
	)
	position.x = fposmod(position.x, world_pixel_size.x)
	position.y = fposmod(position.y, world_pixel_size.y)
