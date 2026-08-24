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
const EcologicalLiteracy = preload("res://src/gameplay/ecological_literacy.gd")
const Equipment = preload("res://src/gameplay/equipment.gd")
const Smelting = preload("res://src/gameplay/smelting.gd")
const FishingSession = preload("res://src/gameplay/fishing_session.gd")
const MaterialDamage = preload("res://src/gameplay/material_damage.gd")
const Block = preload("res://src/gameplay/block.gd")
const HotbarAction = preload("res://src/gameplay/hotbar_action.gd")
const CampfireCooking = preload("res://src/gameplay/campfire_cooking.gd")
const FoodConsumption = preload("res://src/gameplay/food_consumption.gd")
const VenomModel = preload("res://src/gameplay/venom_model.gd")
const DebuffStack = preload("res://src/gameplay/debuff_stack.gd")
const Shop = preload("res://src/gameplay/shop.gd")
const NpcGreeting = preload("res://src/world/npc_greeting.gd")
const Hotbar = preload("res://src/gameplay/hotbar.gd")
const FishingCast = preload("res://src/gameplay/fishing_cast.gd")
const ProceduralBobberSprite = preload("res://src/rendering/procedural_bobber_sprite.gd")
const ArtResolution = preload("res://src/rendering/art_resolution.gd")
const HeroAppearance = preload("res://src/rendering/hero_appearance.gd")
const ItemCatalog = preload("res://src/gameplay/item_catalog.gd")
const CreatureMarker = preload("res://src/rendering/creature_marker.gd")
const ChoppableTree = preload("res://src/rendering/choppable_tree.gd")
const SmashableStone = preload("res://src/rendering/smashable_stone.gd")
const WildCropMarker = preload("res://src/rendering/wild_crop_marker.gd")
const Carcass = preload("res://src/rendering/carcass.gd")
const DroppedItem = preload("res://src/rendering/dropped_item.gd")
const ItemStack = preload("res://src/gameplay/item_stack.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")
const Taming = preload("res://src/gameplay/taming.gd")
const ProceduralItemSprite = preload("res://src/rendering/procedural_item_sprite.gd")
const BiomeClassifier = preload("res://src/world/biome_classifier.gd")
const WorldCoordinates = preload("res://src/world/world_coordinates.gd")
const EarthChunkGenerator = preload("res://src/world/earth_chunk_generator.gd")
const TerrainPassability = preload("res://src/gameplay/terrain_passability.gd")
const EarthChunkManager = preload("res://src/world/earth_chunk_manager.gd")
const StoneSize = preload("res://src/world/stone_size.gd")
const Kick = preload("res://src/gameplay/kick.gd")
const Throwable = preload("res://src/gameplay/throwable.gd")
const ChargeMeter = preload("res://src/gameplay/charge_meter.gd")
const HeldItemThrow = preload("res://src/gameplay/held_item_throw.gd")
const ImpactResolver = preload("res://src/gameplay/impact_resolver.gd")
const StoneRenderer = preload("res://src/rendering/stone_renderer.gd")
const CollapsedPassage = preload("res://src/rendering/collapsed_passage.gd")

const BASE_SPEED := 80.0
const PLAYER_SIZE := 12

## Taming reach (see docs/concept/taming.md). The throw is deliberately short:
## having to close with a wary animal first is the part that makes stalking a
## horse feel like something. Feeding is closer still -- an arm's length, since
## the animal has to take it from your hand -- and tying off needs the tree
## within reach of where you are standing.
const LASSO_RANGE := 72.0
const FEED_RANGE := 28.0
const TIE_RANGE := 40.0
const TAMING_TREAT_ID := "carrot"
## How big one world tile should read on screen once camera-zoomed, in
## pixels -- the actual tuned/eyeballed value (CLAUDE.md: tuned constants
## must be pinned, not eyeballed comments). CAMERA_ZOOM below is DERIVED
## from this divided by TerrainRenderer.TILE_SIZE rather than a bare zoom
## number, so the framing is stated as an intent ("a tile should read this
## big") that stays correct on its own terms.
##
## The art-resolution pass (docs/concept/art_resolution.md) deliberately
## does NOT change this: it raises how many art PIXELS are painted per tile
## (TerrainRenderer.ART_TILE_SIZE), not how much WORLD a tile covers
## (TerrainRenderer.TILE_SIZE). Conflating those two -- the pass's first
## attempt bumped TILE_SIZE itself -- made every tile occupy 4x the world
## footprint, reported as "water squares are gigantic compared to the
## player".
const TARGET_TILE_SCREEN_PX := 64.0
## Applied in _ready() rather than left as a bare number in player.tscn, so
## it's a tested constant (see test_player_camera.gd) rather than an
## eyeballed scene property.
const CAMERA_ZOOM := Vector2.ONE * (TARGET_TILE_SCREEN_PX / TerrainRenderer.TILE_SIZE)
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

## A moderate, controlled swing's contact speed -- not a blade-TIP speed
## measurement (which runs much higher), but the speed at the point of
## impact a real swing delivers, the same grounding shape as
## Kick.KICK_SPEED_MPS. Feeds real weapon mass into knockback (see
## _knockback_force_for) through the SAME momentum model
## Throwable.impact_knockback already uses for thrown items
## (docs/concept/materials.md).
const SWING_IMPACT_SPEED_MPS := 5.0
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

## How often actively swimming spawns a water-ripple disturbance (see
## EarthChunkManager.record_water_disturbance) -- once per stroke, not every
## frame; the ring itself takes a couple of seconds to fade, so anything
## faster would just stack redundant rings at the same spot.
const WATER_RIPPLE_INTERVAL := 0.4
var _water_ripple_accumulator := 0.0

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
## Active venom stacks from a venomous snake's bite (see VenomModel,
## CreatureMarker._try_attack) -- DebuffStack-shaped, ticked down and
## dealing damage in _venom_step. Empty means not currently poisoned.
var active_venom_debuffs: Array = []
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
## XP-award arithmetic for non-combat "ecological literacy" sources (see
## harvest_fruit_from_tree/sell_food_to_village, docs/concept/progression.md).
var _ecological_literacy := EcologicalLiteracy.new()
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
## The authored look from the character creator (see HeroAppearance), kept
## around (not just applied-and-forgotten) so a save can restore the same
## face/hair/outfit instead of re-rolling one from the peer id -- see
## to_save_dict/apply_save_dict and docs/concept/persistence.md.
var appearance: Dictionary = {}
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
## Taming (see docs/concept/taming.md): the animal currently on the end of
## this player's lasso, and the point the rope's loose end is tied to (a tree)
## if it has been. A tied animal is held by the anchor rather than by the
## player, which is what lets them walk away.
var _lassoed: Node = null
var _tie_anchor = null  # Vector2 once tied, null while led by hand
## The tamed animal currently being ridden (see docs/concept/taming.md).
## Riding moves the player at the mount's pace and carries the animal along
## with them, rather than swapping which node the camera follows -- the rider
## stays the thing the player controls, which keeps every other system
## (inventory, combat, survival) working unchanged while mounted.
var _mount: Node = null
var _last_mount_input := false
var _pending_mount_pressed := false
var _last_lasso_input := false
var _pending_lasso_pressed := false
var lasso_message := ""

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

## -- Talking to any villager (see NpcGreeting, EarthChunkManager.
## nearest_npc_near) -- a minimal stand-in for the real Live Dialogue System
## (docs/concept/npc.md's "Minimal talk interaction"): press the talk key
## near any villager to hear one deterministic, personality/need-flavored
## greeting line. No branching, no memory, no quest hooks -- see the concept
## doc for why that's an honest placeholder rather than a cut-down feature.
var _npc_greeting := NpcGreeting.new()
var _last_talk_input := false
var _pending_talk_pressed := false
var _talk_result_message := ""
var _talk_result_timer := 0.0
## The current talk prompt/result, read by the HUD ("" == nothing to show).
var talk_message := ""
const TALK_MESSAGE_DURATION := 3.0
## How close a villager must be to talk to -- same reach as trading.
const TALK_RADIUS := 48.0

var _chunk_manager: EarthChunkManager
var _tile_size: int
var _wetness_tracker := WetnessTracker.new()
var _water_movement_model := WaterMovementModel.new()
var _biome_classifier := BiomeClassifier.new()
var _world_coordinates := WorldCoordinates.new()
var _health := Health.new()
var _melee_attack := MeleeAttack.new()
var _throwable := Throwable.new()
var _impact_resolver := ImpactResolver.new()
var _stone_renderer := StoneRenderer.new()

## The held-item concept (see docs/concept/stone.md): distinct from both
## inventory and Equipment's worn "weapon" slot -- a small object carried
## loose in hand, picked up from and thrown back into the world rather than
## stacked or equipped. -1.0 means empty-handed; a real value is the held
## stone's diameter_cm (its mass, for the throw's momentum, is derived from
## THAT the same way every other stone's mass is -- see StoneSize.mass_kg_for).
var _hand_stone_diameter_cm := -1.0

## How long the pickup input has been continuously held THIS charge (reset
## on a fresh press while already holding something -- see _pickup_step).
## Fed to ChargeMeter.fraction_at every frame while charging.
var _hand_charge_elapsed := 0.0

## Whether the CURRENT press-and-hold is a genuine charge cycle rather than
## the initial press that grabbed the stone into hand -- distinguishes "the
## pickup press's own release" (nothing happens, still holding) from "a
## later press-and-hold's release" (throws). Without this, releasing the
## very same E press that just picked the stone up would immediately throw
## it again.
var _charging := false
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
var _last_kick_input_state := false

## Authority-side: last input direction received from the owning client (or
## read directly from Input, in the no-networking singleplayer fallback).
var _pending_input_direction := Vector2.ZERO
var _pending_attack_pressed := false
var _pending_block_pressed := false
var _pending_build_pressed := false
var _pending_destroy_pressed := false
var _pending_pickup_pressed := false
var _pending_kick_pressed := false
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

	_build_rope_line()

	# The fishing bobber (see _fishing_step) -- hidden until a line is cast.
	_bobber = Sprite2D.new()
	_bobber.texture = ProceduralBobberSprite.new().generate_texture()
	# Oversized art scaled back to its world size (see
	# docs/concept/art_resolution.md).
	_bobber.scale = Vector2.ONE * ArtResolution.SPRITE_SCALE
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
	_bind_key_action("lasso", KEY_R)
	_bind_key_action("mount", KEY_V)
	_bind_key_action("trade", KEY_T)
	_bind_key_action("talk", KEY_G)
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
func apply_class(class_name_value: String, stats: Dictionary, chosen_appearance: Dictionary = {}) -> void:
	character_class = class_name_value
	max_health = maxf(20.0, 100.0 + float(stats.get("max_health", 0.0)))
	health = max_health
	class_attack_bonus = float(stats.get("attack_damage", 0.0))
	var look := chosen_appearance
	if look.is_empty():
		look = HeroAppearance.new().appearance_for(class_name_value, name.hash())
	appearance = look
	if _character_view != null:
		_character_view.apply_appearance(look)


## Snapshots exactly the state docs/concept/persistence.md defines as worth
## remembering across a restart -- see that doc for the full field-by-field
## rationale of what's included/excluded. Plain-Variant-only (Vector2/String/
## int/float/Dictionary/Array), so PlayerSave can store_var it as-is; PlayerSave
## itself is pure I/O with no knowledge of what these keys mean.
func to_save_dict() -> Dictionary:
	var inventory_data := []
	for stack in inventory.stacks():
		inventory_data.append({"id": stack.item.id, "count": stack.count})

	var equipment_data := {}
	for slot in Equipment.SLOTS:
		var worn = equipment.equipped_in(slot)
		if worn != null:
			equipment_data[slot] = worn.id

	var hotbar_data := []
	for i in range(hotbar.slot_count):
		hotbar_data.append(hotbar.item_id_at(i))

	return {
		"position": position,
		"respawn_position": respawn_position,
		"character_class": character_class,
		"appearance": appearance,
		"health": health,
		"max_health": max_health,
		"class_attack_bonus": class_attack_bonus,
		"skill_attack_bonus": _skill_attack_bonus,
		"wallet_balance": wallet.balance,
		"experience_total_xp": experience.total_xp,
		"experience_level": experience.level,
		"experience_unspent_points": experience.unspent_points,
		"allocated_nodes": allocated_nodes.duplicate(),
		"unlocked_keystones": unlocked_keystones.duplicate(),
		"inventory": inventory_data,
		"equipment": equipment_data,
		"hotbar": hotbar_data,
	}


## Restores state saved by to_save_dict onto this (already-_ready, already-
## setup) player, overwriting whatever apply_class/_ready's starter grants
## put there. Deliberately NOT part of apply_class -- apply_class always
## fully heals (health = max_health), correct for a brand new character but
## wrong for a loaded one, so callers must run this AFTER apply_class/_ready
## rather than folding it in (see World's load-game spawn path).
func apply_save_dict(data: Dictionary) -> void:
	position = data.get("position", position)
	respawn_position = data.get("respawn_position", respawn_position)
	character_class = data.get("character_class", character_class)
	appearance = data.get("appearance", appearance)
	health = data.get("health", health)
	max_health = data.get("max_health", max_health)
	class_attack_bonus = data.get("class_attack_bonus", class_attack_bonus)
	_skill_attack_bonus = data.get("skill_attack_bonus", _skill_attack_bonus)
	wallet.balance = data.get("wallet_balance", wallet.balance)
	experience.total_xp = data.get("experience_total_xp", experience.total_xp)
	experience.level = data.get("experience_level", experience.level)
	experience.unspent_points = data.get("experience_unspent_points", experience.unspent_points)
	allocated_nodes = (data.get("allocated_nodes", allocated_nodes) as Dictionary).duplicate()
	unlocked_keystones = (data.get("unlocked_keystones", unlocked_keystones) as Dictionary).duplicate()

	inventory = Inventory.new(inventory.slot_count)
	for entry in data.get("inventory", []):
		if _item_catalog.has(entry.id):
			inventory.add(_item_catalog.make(entry.id), entry.count)

	equipment = Equipment.new()
	equipped_item = null
	for slot in data.get("equipment", {}):
		var item_id: String = data["equipment"][slot]
		if not _item_catalog.has(item_id):
			continue
		var item := _item_catalog.make(item_id)
		if slot == "weapon":
			equip_item(item)
		else:
			equipment.equip(item)

	var hotbar_data: Array = data.get("hotbar", [])
	for i in range(hotbar_data.size()):
		hotbar.assign(i, hotbar_data[i])

	inventory_changed.emit()


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


var _debuff_stack := DebuffStack.new()
var _venom_model := VenomModel.new()


## Called by a venomous snake's bite (see CreatureMarker._try_attack):
## refreshes the venom debuff's duration and adds a stack (capped at
## VenomModel.MAX_STACKS) -- repeated bites hurt more, not just longer.
func apply_venom() -> void:
	active_venom_debuffs = _debuff_stack.apply(
		active_venom_debuffs, VenomModel.DEBUFF_ID, VenomModel.DURATION_SECONDS, VenomModel.MAX_STACKS
	)


## Authority-only: deals venom's real damage-over-time (see
## VenomModel.damage_per_second) for however many stacks are active, then
## ticks the debuff's remaining duration down (expiring it once it runs out).
func _venom_step(delta: float) -> void:
	var stacks := _debuff_stack.stacks_of(active_venom_debuffs, VenomModel.DEBUFF_ID)
	if stacks > 0:
		take_damage(_venom_model.damage_per_second(stacks) * delta)
	active_venom_debuffs = _debuff_stack.advance(active_venom_debuffs, delta)


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
	current_speed_multiplier = (
		water_result.speed_multiplier * _weather_speed_multiplier() * _terrain_speed_multiplier(tile)
	)

	var input_direction := _read_local_input() if _controlled_locally() else _pending_input_direction
	var desired_velocity := input_direction * current_speed() * current_speed_multiplier
	if _terrain_blocks_movement(input_direction):
		desired_velocity = Vector2.ZERO
	velocity = desired_velocity
	move_and_slide()
	_wrap_position()

	_last_facing_direction = input_direction if input_direction.length() > 0.01 else _last_facing_direction
	_update_character_view(input_direction)
	_step_water_ripples(delta, input_direction)

	survival.advance(delta)
	# Standing in any water (wading in the shallows or swimming) lets you drink
	# from it -- the "drink from water tiles" option. Wading is the easy way to
	# quench thirst without getting fully soaked.
	if current_mode == "swimming" or current_mode == "wading":
		survival.drink(DRINK_RATE_PER_SECOND * delta)
	if _chunk_manager != null:
		survival.regulate_temperature(_chunk_manager.ambient_warmth(position), wetness, delta)

	_attack_step(delta)
	_pickup_step(delta)
	_kick_step()
	_build_step()
	_destroy_step()
	_fishing_step(delta)
	_lasso_step(delta)
	_food_buff_step(delta)
	_venom_step(delta)
	_shop_step(delta)
	_talk_step(delta)


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


## Soft terrain slowdown from real slope (see docs/concept/terrain_relief.md,
## TerrainPassability.speed_multiplier) -- the same "environment scales a
## movement multiplier" shape _weather_speed_multiplier above already uses,
## driven by slope instead of weather. 1.0 when the world isn't wired
## (isolated tests), matching that function's own fallback.
func _terrain_speed_multiplier(tile: Vector2i) -> float:
	if _chunk_manager == null:
		return 1.0
	return TerrainPassability.speed_multiplier(_chunk_manager.slope_at_global(tile.x, tile.y))


## How far ahead (world pixels) to check terrain slope before committing to
## a step -- the same "ask before you step, don't correct after" principle
## CreatureMovementGate already established for creatures walking into
## trees, applied here to the player walking into a mountainside. Half a
## tile: far enough to be a real look-ahead, not so far that the player is
## refused entry to a tile before they're anywhere near its edge.
const TERRAIN_CHECK_DISTANCE_PX := 8.0

## Whether the tile the player is currently heading toward is too steep to
## enter at all (see TerrainPassability.is_passable). Checked BEFORE the
## step, not corrected after -- a refused step simply never becomes
## velocity, rather than the player being placed on impassable terrain and
## then pushed back out of it.
func _terrain_blocks_movement(input_direction: Vector2) -> bool:
	if _chunk_manager == null or input_direction.length() < 0.01:
		return false
	var look_ahead := position + input_direction.normalized() * TERRAIN_CHECK_DISTANCE_PX
	var raw := Vector2i(floori(look_ahead.x / _tile_size), floori(look_ahead.y / _tile_size))
	var world_size := Vector2i(EarthChunkGenerator.WORLD_WIDTH_TILES, EarthChunkGenerator.WORLD_HEIGHT_TILES)
	var ahead_tile := _world_coordinates.wrap(raw, world_size)
	var slope := _chunk_manager.slope_at_global(ahead_tile.x, ahead_tile.y)
	return not TerrainPassability.is_passable(slope, _has_climbing_gear())


## No item/equipment concept sets this true anywhere in live gameplay yet
## (see docs/progress.md's Transportation section -- the climbing rope
## `transportation.md`/`terrain_relief.md` both specify isn't built). The
## hook exists now so terrain passability is already correct and already
## tested for the day a real climbing rope exists, rather than needing this
## call site touched again later.
func _has_climbing_gear() -> bool:
	return false


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
		var knockback := _melee_attack.knockback_vector(
			position, creature.position, _knockback_force_for(_held_weapon())
		)
		creature.apply_knockback(knockback)
		creature.take_damage(damage)
		# A hit that kills the creature awards XP scaled by its level (see
		# ExperienceTrack / concept/progression.md).
		if creature.is_queued_for_deletion() and creature.info != null:
			gain_experience(XP_PER_KILL * creature.info.level)

	_chop_step()
	_smash_step()
	_harvest_grass_step()
	_pull_wild_crop_step()
	_butcher_step()


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


## Pulling: a swing over a mature wild carrot/potato patch pulls it out of
## the ground (see WildCropMarker.begin_pull, docs/concept/wild_crops.md) --
## same shared "stone"/"tree" group-scan + range-sweep shape as
## _smash_step/_chop_step, just targeting WildCropMarker.GROUP_NAME. The
## pull itself is animated over CropPull.DURATION_SECONDS and only drops the
## actual item once that finishes -- this swing just STARTS it.
func _pull_wild_crop_step() -> void:
	var crops := get_tree().get_nodes_in_group(WildCropMarker.GROUP_NAME)
	var positions: Array = []
	for crop in crops:
		positions.append(crop.position)

	for index in _melee_attack.targets_in_range(position, positions, ATTACK_RANGE):
		crops[index].begin_pull()


## Butchering: a swing over a nearby carcass (see Carcass.butcher,
## docs/concept/carrion.md) takes its next remaining part -- same shared
## group-scan + range-sweep shape as every other harvest step above. Meat
## yield reads the player's allocated butchering skill live (SkillTree's
## meat_yield stat, see Butchering.meat_count) rather than caching it --
## always in sync with allocated_nodes, no separate accumulator to drift.
func _butcher_step() -> void:
	var carcasses := get_tree().get_nodes_in_group(Carcass.GROUP_NAME)
	var positions: Array = []
	for carcass in carcasses:
		positions.append(carcass.position)

	if positions.is_empty():
		return
	var meat_yield_bonus := skill_tree.total_bonus("meat_yield", allocated_nodes)
	for index in _melee_attack.targets_in_range(position, positions, ATTACK_RANGE):
		carcasses[index].butcher(meat_yield_bonus)


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


## A swing's knockback force, fed by the held weapon's REAL mass through the
## same momentum model Throwable.impact_knockback already uses for thrown
## items (mass * velocity, docs/concept/materials.md), rather than the flat
## KNOCKBACK_FORCE every weapon used to deal identically regardless of what
## it actually was.
##
## Calibrated against an iron sword (this game's baseline melee weapon) so
## the EXISTING tuned KNOCKBACK_FORCE (60px) is exactly what an iron sword
## already delivers -- wiring in real mass does not silently retune every
## already-tuned attack, only weapons lighter/heavier than an iron sword
## diverge from that baseline. Bare hands, or a weapon with no mass modeled
## yet (mass_kg 0.0), fall back to the original constant untouched -- there
## is no invented "fist mass" standing in for a real one.
func _knockback_force_for(weapon) -> float:
	if weapon == null or weapon.mass_kg <= 0.0:
		return KNOCKBACK_FORCE
	var momentum := _throwable.impact_knockback(weapon.mass_kg, SWING_IMPACT_SPEED_MPS)
	return _knockback_force_for_momentum(momentum)


## Converts a real momentum value (kg * m/s) into the game's existing
## knockback-force scale (world pixels of displacement, see Knockback.step),
## calibrated so an iron sword's own momentum reproduces the original tuned
## KNOCKBACK_FORCE exactly (see _knockback_force_for's own doc comment).
## Shared by weapon swings (_knockback_force_for) and the held-item throw
## (_resolve_thrown_stone_impact) so both real-momentum sources land on the
## same pixel scale rather than each inventing their own conversion.
func _knockback_force_for_momentum(momentum: float) -> float:
	var reference_mass_kg: float = _item_catalog.make("iron_sword").mass_kg
	var reference_momentum := _throwable.impact_knockback(reference_mass_kg, SWING_IMPACT_SPEED_MPS)
	return KNOCKBACK_FORCE * (momentum / reference_momentum)


## True while the block input is held (and the player is alive): incoming
## damage is reduced weapon-dependently (see Block); blocking, like attacking,
## costs no stamina -- combat stays purely cooldown-based (see
## concept/survival.md's "Stamina scope: movement only, not combat").
func is_blocking() -> bool:
	if is_dead:
		return false
	return Input.is_action_pressed("block") if _controlled_locally() else _pending_block_pressed


## How much Carpentry (SkillTree's carpentry_1/2 nodes, summed via
## total_bonus) it takes to saw a bare trunk into beam/plank instead of
## bucking it into raw logs -- see docs/concept/woodworking.md. Requires
## BOTH nodes allocated, genuine investment rather than a single point.
const CARPENTRY_LEVEL_FOR_SAWING := 2.0

## Felling: any swing damages ChoppableTrees in range through the material
## damage model (see MaterialDamage), scaled by the HELD item -- an axe chops
## at full efficiency (3x wood multiplier), a sword hacks weakly (0.5x, so a
## tree takes many more swings), bare hands barely scratch bark (0.25x). Same
## AOE range/targeting math as creature hits (reuses MeleeAttack.targets_in_range).
##
## A saw + enough Carpentry tries ChoppableTree.saw_up first, on a bare
## trunk, turning the whole remaining trunk into beam+plank in one action
## instead of the ordinary one-log-per-swing chop -- saw_up itself is the
## authority on whether that's actually possible right now (is the trunk
## even bare yet?), so a swing that doesn't qualify just falls through to
## the normal take_damage() unchanged.
func _chop_step() -> void:
	var damage := _material_damage.effective_damage(BASE_CHOP_DAMAGE, _held_kind(), "wood")
	if damage <= 0.0:
		return

	var trees := get_tree().get_nodes_in_group(ChoppableTree.GROUP_NAME)
	var positions: Array = []
	for tree in trees:
		positions.append(tree.position)

	var has_saw: bool = equipped_item != null and equipped_item.is_saw()
	var carpentry_level := skill_tree.total_bonus("carpentry_level", allocated_nodes)
	var can_saw := has_saw and carpentry_level >= CARPENTRY_LEVEL_FOR_SAWING

	var hit_indices := _melee_attack.targets_in_range(position, positions, ATTACK_RANGE)
	for index in hit_indices:
		var tree: ChoppableTree = trees[index]
		if can_saw and tree.saw_up():
			continue
		tree.take_damage(damage)


## Authority-only: E (pickup) is now CONTEXTUAL (see docs/concept/stone.md):
## empty-handed near a liftable stone, E picks it into the HAND instead of
## straight to inventory (_try_pick_stone_into_hand); empty-handed with no
## stone nearby, E still does the ordinary ground-item sweep unchanged
## (pickup_nearby). With something already in hand, a NEW press starts a
## charge (ChargeMeter bounces while held -- see hand_charge_fraction), and
## releasing throws it (_throw_held_stone). Rising-edge detection throughout
## so holding E doesn't repeat the initial action every frame.
func _pickup_step(delta: float) -> void:
	var pickup_pressed := (
		Input.is_action_pressed("pickup") if _controlled_locally() else _pending_pickup_pressed
	)
	var just_pressed := pickup_pressed and not _last_pickup_input_state
	var just_released := _last_pickup_input_state and not pickup_pressed
	_last_pickup_input_state = pickup_pressed

	if not is_holding_stone():
		if just_pressed and not _try_pick_stone_into_hand():
			# A direct-from-the-tree harvest (see _try_harvest_peak_fruit) only
			# runs when the ordinary ground-item sweep found nothing -- one E
			# press does one thing, and a windfall already underfoot takes
			# priority over reaching for the branch.
			if pickup_nearby() == 0:
				_try_harvest_peak_fruit()
		return

	if just_pressed:
		# A NEW press while already holding something starts a real charge
		# cycle -- distinct from the press that grabbed the stone into hand
		# in the first place (see _charging's own doc comment).
		_charging = true
		_hand_charge_elapsed = 0.0
	elif _charging and pickup_pressed:
		_hand_charge_elapsed += delta

	if just_released and _charging:
		_charging = false
		_throw_held_stone()


## Whether something is currently held in hand (see _hand_stone_diameter_cm's
## own doc comment) -- distinct from both inventory and Equipment's worn
## weapon slot.
func is_holding_stone() -> bool:
	return _hand_stone_diameter_cm >= 0.0


## The charge meter's current reading in [0, 1] (see ChargeMeter) -- 0.0
## whenever nothing is in hand, or the pickup input isn't currently held.
## Read by World for the strengthometer UI.
func hand_charge_fraction() -> float:
	if not is_holding_stone() or not _charging:
		return 0.0
	return ChargeMeter.fraction_at(_hand_charge_elapsed)


## Takes the nearest liftable stone in reach (same nearby-target-finding
## convention as pickup_nearby/Kick -- EarthChunkManager.
## nearest_liftable_stone_near, PICKUP_RADIUS) into the HAND rather than
## straight to inventory. Returns whether anything was actually picked up,
## so the caller can fall back to the ordinary sweep when there's no stone
## nearby.
func _try_pick_stone_into_hand() -> bool:
	if _chunk_manager == null:
		return false
	var stone: Node2D = _chunk_manager.nearest_liftable_stone_near(position, PICKUP_RADIUS)
	if stone == null:
		return false
	_hand_stone_diameter_cm = stone.diameter_cm
	_hand_charge_elapsed = 0.0
	_charging = false
	stone.queue_free()
	return true


## Throws whatever is in hand: release power (wherever the ChargeMeter was
## at release) sets a real throw speed (HeldItemThrow.release_speed_mps),
## which feeds the SAME momentum model (Throwable.impact_knockback,
## docs/concept/materials.md) as every other hit in this game -- not a
## separate new physics path. The stone reappears in the world at its
## landing spot (see _spawn_thrown_stone) whether or not it struck anything
## on the way.
func _throw_held_stone() -> void:
	var diameter_cm := _hand_stone_diameter_cm
	_hand_stone_diameter_cm = -1.0

	var power := ChargeMeter.fraction_at(_hand_charge_elapsed)
	var release_speed := HeldItemThrow.release_speed_mps(power)
	var mass_kg := StoneSize.mass_kg_for(diameter_cm)
	var momentum := _throwable.impact_knockback(mass_kg, release_speed)
	var distance := HeldItemThrow.throw_distance_px(power)
	var direction := _last_facing_direction if _last_facing_direction.length() > 0.01 else Vector2.DOWN
	var landing_position := position + direction.normalized() * distance

	_resolve_thrown_stone_impact(landing_position, momentum)
	_resolve_stone_impact_on_obstacles(landing_position, momentum)
	_spawn_thrown_stone(landing_position, diameter_cm)


## How close a thrown stone's landing spot must be to a creature to count as
## a hit -- the same order of magnitude as ATTACK_RANGE, since both are
## "close enough to actually connect".
const THROWN_STONE_IMPACT_RADIUS_PX := 20.0

## Flat damage a thrown stone deals on a real (non-"bounce") impact.
## Simplification, documented rather than guessed at silently:
## ImpactResolver's outcome is read as a simple hit/no-hit here rather than
## mapped to a full per-outcome damage table -- docs/concept/materials.md
## itself lists per-outcome damage tuning as an open, project-wide design
## question, not something to invent unilaterally for this one feature.
const THROWN_STONE_BASE_DAMAGE := 4.0

## A thrown stone's impact against any creature at the landing spot --
## resolved through the SAME shared momentum model
## (ImpactResolver.resolve_impact, MeleeAttack.knockback_vector) every other
## hit in this game already uses.
func _resolve_thrown_stone_impact(landing_position: Vector2, momentum: float) -> void:
	var creatures := get_tree().get_nodes_in_group(CreatureMarker.GROUP_NAME)
	var positions: Array = []
	for creature in creatures:
		positions.append(creature.position)
	var hit_indices := _melee_attack.targets_in_range(landing_position, positions, THROWN_STONE_IMPACT_RADIUS_PX)
	for index in hit_indices:
		var creature: CreatureMarker = creatures[index]
		var outcome := _impact_resolver.resolve_impact(momentum, "blunt", "flesh")
		if outcome == "bounce":
			continue
		var knockback := _melee_attack.knockback_vector(
			landing_position, creature.position, _knockback_force_for_momentum(momentum)
		)
		creature.apply_knockback(knockback)
		creature.take_damage(THROWN_STONE_BASE_DAMAGE)


## Delivers `momentum` to any CollapsedPassage obstacle (docs/concept/
## exploration.md's "collapsed passage" momentum obstacle) within
## THROWN_STONE_IMPACT_RADIUS_PX of `landing_position` -- the SAME nearby-
## target proximity check (_melee_attack.targets_in_range) and the SAME
## momentum value _resolve_thrown_stone_impact already resolves against
## creatures above, just checked against the OTHER kind of thing a real
## delivered momentum can act on in this world. The obstacle itself decides
## clear-vs-stays-blocked via ImpactResolver (see CollapsedPassage.
## receive_impact) -- no second hit-detection system, no bespoke obstacle
## event.
func _resolve_stone_impact_on_obstacles(landing_position: Vector2, momentum: float) -> void:
	var obstacles := get_tree().get_nodes_in_group(CollapsedPassage.GROUP_NAME)
	var positions: Array = []
	for obstacle in obstacles:
		positions.append(obstacle.position)
	var hit_indices := _melee_attack.targets_in_range(landing_position, positions, THROWN_STONE_IMPACT_RADIUS_PX)
	for index in hit_indices:
		obstacles[index].receive_impact(momentum)


## Materializes a real, correctly-rendered liftable stone (see
## StoneRenderer.build_liftable_stone_node) at the throw's landing spot --
## whether or not it struck anything on the way, a thrown stone still ends
## up lying on the ground afterward, exactly like any other loose stone.
func _spawn_thrown_stone(landing_position: Vector2, diameter_cm: float) -> void:
	var stone := _stone_renderer.build_liftable_stone_node(randi(), diameter_cm)
	stone.position = landing_position
	get_parent().add_child(stone)


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


## Fallback for the pickup key when the ordinary ground sweep found nothing:
## takes real hanging fruit straight from the nearest tree in reach (see
## EarthChunkManager.harvest_peak_fruit_near, PICKUP_RADIUS) into inventory
## and awards real XP (see EcologicalLiteracy.harvest_xp) -- more when the
## harvest lands at genuine peak ripeness than off-peak (docs/concept/
## progression.md "Ecological literacy"). Returns whether anything was
## harvested. This is the only harvest path that can ever land AT peak: a
## windfall item on the ground (pickup_nearby above) has, by construction,
## already left that window (see fruiting_model.gd's is_peak_ripe).
func _try_harvest_peak_fruit() -> bool:
	if _chunk_manager == null:
		return false
	var found := _chunk_manager.harvest_peak_fruit_near(position, PICKUP_RADIUS)
	if found.is_empty():
		return false
	var species_id: String = found["species_id"]
	inventory.add(_item_catalog.make(species_id), 1)
	inventory_changed.emit()
	gain_experience(_ecological_literacy.harvest_xp(found.get("is_peak", false)))
	return true


## Authority-only: on the rising edge of the kick input (default K -- see
## Keybindings), delivers a real one-time momentum (Kick.KICK_MOMENTUM_KG_M_S)
## to the nearest kickable PHYSICAL OBJECT in reach -- a liftable stone
## (docs/concept/stone.md) OR a dropped item with a real, modeled mass (e.g.
## a pulled wild carrot/potato, docs/concept/wild_crops.md's "a real physical
## entity, not just an inventory grant"), whichever is genuinely closer.
## Reuses PICKUP_RADIUS and EarthChunkManager.nearest_liftable_stone_near --
## the SAME nearby-target-finding convention pickup/dispersion already use --
## rather than a new proximity query for the stone half. An object at or
## above leg mass (Kick.is_kickable) is too heavy for a kick to move at all;
## a lighter one flies a distance that scales with the delivered momentum
## vs. its own mass, exactly Throwable.impact_knockback's reasoning.
func _kick_step() -> void:
	var kick_pressed := (
		Input.is_action_pressed("kick") if _controlled_locally() else _pending_kick_pressed
	)
	var just_pressed := kick_pressed and not _last_kick_input_state
	_last_kick_input_state = kick_pressed
	if not just_pressed or _chunk_manager == null:
		return

	var stone: Node2D = _chunk_manager.nearest_liftable_stone_near(position, PICKUP_RADIUS)
	var stone_mass := StoneSize.mass_kg_for(stone.diameter_cm) if stone != null else 0.0
	var stone_kickable := stone != null and Kick.is_kickable(stone_mass)
	var stone_distance := position.distance_to(stone.position) if stone_kickable else INF

	var dropped_item := _nearest_kickable_dropped_item_near(position, PICKUP_RADIUS)
	var dropped_distance := position.distance_to(dropped_item.position) if dropped_item != null else INF

	if not stone_kickable and dropped_item == null:
		return

	# The leg's momentum is conserved into the kicked object (see kick.gd's
	# own doc comment: exit velocity = KICK_MOMENTUM_KG_M_S / its own mass, so
	# its own momentum at landing is exactly KICK_MOMENTUM_KG_M_S again) --
	# the same real momentum a thrown stone delivers via
	# _resolve_stone_impact_on_obstacles above, just from a kick instead of
	# a throw. Whichever candidate is genuinely nearer wins -- a farther
	# stone should not always take priority over a nearer dropped item just
	# because stones were the first kickable thing this game had.
	if stone_kickable and stone_distance <= dropped_distance:
		var landing_position := Kick.landing_position(position, stone.position, stone_mass)
		_resolve_stone_impact_on_obstacles(landing_position, Kick.KICK_MOMENTUM_KG_M_S)
		stone.position = landing_position
	else:
		var mass: float = dropped_item.item_stack.item.mass_kg
		var landing_position := Kick.landing_position(position, dropped_item.position, mass)
		_resolve_stone_impact_on_obstacles(landing_position, Kick.KICK_MOMENTUM_KG_M_S)
		dropped_item.position = landing_position


## Nearest DroppedItem within `radius` whose real item mass (Item.mass_kg) is
## light enough for Kick.is_kickable -- an item with no modeled mass yet
## (0.0, item.gd's own "not modeled" convention, still most food/material
## items) is deliberately excluded, the same as a stone at/above leg mass:
## kicking something with no real mass would be meaningless under the shared
## momentum model (docs/concept/materials.md).
func _nearest_kickable_dropped_item_near(from: Vector2, radius: float) -> DroppedItem:
	var nearest: DroppedItem = null
	var nearest_distance := radius
	for item in get_tree().get_nodes_in_group(DroppedItem.GROUP_NAME):
		if item.is_queued_for_deletion() or item.item_stack == null:
			continue
		var mass: float = item.item_stack.item.mass_kg
		if mass <= 0.0 or not Kick.is_kickable(mass):
			continue
		var distance := from.distance_to(item.position)
		if distance <= nearest_distance:
			nearest = item
			nearest_distance = distance
	return nearest


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


## Taming: throw the lasso, lead what it caught, tie it off, and feed it (see
## docs/concept/taming.md). One key does the lot, because what it means is
## unambiguous from what the player is currently holding:
##
##   nothing caught  -> throw at the nearest catchable animal in range
##   caught, near a tree -> tie the loose end off there
##   caught, tied    -> untie and take the rope back in hand
##   caught, in hand -> let it go
##
## Feeding is separate and automatic on contact, since walking a carrot up to
## a horse's mouth IS the interaction.
func _lasso_step(delta: float) -> void:
	if _lassoed != null and (not is_instance_valid(_lassoed) or not _lassoed.is_restrained()):
		# It broke the rope, died, or its chunk unloaded.
		_lassoed = null
		_tie_anchor = null

	var pressed := (
		Input.is_action_pressed("lasso") if _controlled_locally() else _pending_lasso_pressed
	)
	var just_pressed := pressed and not _last_lasso_input
	_last_lasso_input = pressed

	if just_pressed and _holding_lasso():
		if _lassoed == null and _nearest_tamed(LASSO_RANGE) != null:
			# Already tamed: the rope has nothing left to do, so the key means
			# "change your mind about what you're doing" instead.
			_cycle_order()
		elif _lassoed == null:
			_throw_lasso()
		elif _tie_anchor != null:
			_tie_anchor = null
		else:
			var tree = _nearest_tie_point()
			if tree != null:
				_tie_anchor = tree
			else:
				_lassoed.release()
				_lassoed = null

	_hold_the_rope(delta)
	_draw_rope()
	_mount_input_step()
	_step_mount_and_orders()
	_update_lasso_message()


## Keeps the rope attached: the anchor is pushed to the animal every frame, so
## "leading" is nothing more than an anchor that walks with the player.
func _hold_the_rope(_delta: float) -> void:
	if _lassoed == null or not is_instance_valid(_lassoed):
		return
	# Tied vs led: a tied animal is one the player deliberately left somewhere,
	# and is kept across a chunk unload on that basis (see KeptAnimals).
	_lassoed.restrain_to(
		_tie_anchor if _tie_anchor != null else position, _tie_anchor != null
	)
	_try_feed_lassoed()


## A carrot in the inventory, offered whenever the animal is close enough to
## take it and actually hungry. Consumed only when it counts (see
## CreatureMarker.feed_treat), so a full animal never eats the player's stock.
func _try_feed_lassoed() -> void:
	if inventory == null or _lassoed == null:
		return
	if position.distance_to(_lassoed.position) > FEED_RANGE:
		return
	if inventory.count_of(TAMING_TREAT_ID) <= 0:
		return
	if _lassoed.feed_treat():
		inventory.remove(TAMING_TREAT_ID, 1)


func _throw_lasso() -> void:
	var best: Node = null
	var best_distance := LASSO_RANGE
	for creature in get_tree().get_nodes_in_group(CreatureMarker.GROUP_NAME):
		if creature.info == null or creature.is_restrained():
			continue
		if not Taming.can_be_tamed(creature.info.species, creature.info.is_predator):
			continue
		var distance := position.distance_to(creature.position)
		if distance <= best_distance:
			best = creature
			best_distance = distance
	if best == null:
		return
	# The throw itself reuses the melee swing, the same way casting a rod does.
	_character_view.play_attack_swing(_facing_string(), SWING_DURATION)
	if best.restrain_to(position):
		_lassoed = best


## The nearest tree trunk worth tying off to. Trees are already solid bodies
## in the world (ChoppableTree), so "tie it to that one" needs no new entity.
func _nearest_tie_point():
	if _chunk_manager == null or not _chunk_manager.has_method("solid_obstacles_near"):
		return null
	var nearest = null
	var best := TIE_RANGE
	for obstacle in _chunk_manager.solid_obstacles_near(position, TIE_RANGE):
		var distance := position.distance_to(obstacle.position)
		if distance <= best:
			nearest = obstacle.position
			best = distance
	return nearest


func _update_lasso_message() -> void:
	if not _holding_lasso():
		lasso_message = ""
		return
	if _lassoed == null:
		lasso_message = "Lasso ready — press the lasso key near an animal."
		return
	var name_text: String = _lassoed.info.display_name if _lassoed.info != null else "Animal"
	if _lassoed.is_tame():
		lasso_message = "%s is tame." % name_text
	elif _tie_anchor != null:
		lasso_message = "%s tied up — trust %d%%" % [name_text, int(_lassoed.trust * 100.0)]
	else:
		lasso_message = "Leading %s — trust %d%%" % [name_text, int(_lassoed.trust * 100.0)]


## The rope, drawn between whatever holds it and the animal. Without it,
## "this animal is on a line" is something the player has to infer from
## behaviour -- and flora.md's rule that what is visible must be what is real
## cuts both ways: a real constraint should be visible.
##
## Deliberately `top_level`, so the line is drawn in world coordinates rather
## than inheriting the player's own transform (the same reason the creature
## health bars are).
const ROPE_COLOR := Color(0.78, 0.68, 0.42)
const ROPE_WIDTH := 1.5
var _rope_line: Line2D


func _build_rope_line() -> void:
	_rope_line = Line2D.new()
	_rope_line.top_level = true
	_rope_line.width = ROPE_WIDTH
	_rope_line.default_color = ROPE_COLOR
	_rope_line.visible = false
	_rope_line.z_index = 1
	add_child(_rope_line)


func _draw_rope() -> void:
	if _rope_line == null:
		return
	if _lassoed == null or not is_instance_valid(_lassoed):
		_rope_line.visible = false
		return
	var held_end: Vector2 = _tie_anchor if _tie_anchor != null else global_position
	_rope_line.visible = true
	_rope_line.points = PackedVector2Array([held_end, _lassoed.global_position])


# -- orders and riding --------------------------------------------------------

## How fast the player is moving right now: their own legs, or the mount's.
func current_speed() -> float:
	return Taming.MOUNTED_SPEED if is_mounted() else BASE_SPEED


func is_mounted() -> bool:
	return _mount != null and is_instance_valid(_mount)


## Cycles the nearest tamed animal between following and staying put. A wild
## animal ignores it (see CreatureMarker.set_order).
func _cycle_order() -> void:
	var animal = _nearest_tamed(LASSO_RANGE)
	if animal == null:
		return
	animal.set_order(Taming.next_order(animal.order))


func _try_mount() -> bool:
	if is_mounted():
		return false
	var animal = _nearest_tamed(LASSO_RANGE)
	if animal == null or animal.info == null:
		return false
	if not Taming.is_mountable(animal.info.species, animal.trust):
		return false
	_mount = animal
	return true


func _dismount() -> void:
	_mount = null


## The nearest fully tamed animal within `reach`. Tamed only: orders and
## riding are things a tamed animal accepts, and a wild horse standing nearby
## must not silently absorb the key press meant for the tamed one.
func _nearest_tamed(reach: float):
	var best = null
	var best_distance := reach
	for creature in get_tree().get_nodes_in_group(CreatureMarker.GROUP_NAME):
		if creature.info == null or not creature.is_tame():
			continue
		var distance := position.distance_to(creature.position)
		if distance <= best_distance:
			best = creature
			best_distance = distance
	return best


## Keeps a mount under its rider, and tells a following animal where its owner
## is. Both are "push the owner's position in each frame" rather than the
## animal holding a reference back to the player, matching how the rope anchor
## works.
func _step_mount_and_orders() -> void:
	if is_mounted():
		_mount.position = position
	for creature in get_tree().get_nodes_in_group(CreatureMarker.GROUP_NAME):
		if creature.info != null and creature.is_tame():
			creature.follow_target = position


func _mount_input_step() -> void:
	var pressed := (
		Input.is_action_pressed("mount") if _controlled_locally() else _pending_mount_pressed
	)
	var just_pressed := pressed and not _last_mount_input
	_last_mount_input = pressed
	if not just_pressed:
		return
	if is_mounted():
		_dismount()
	else:
		_try_mount()


func _holding_lasso() -> bool:
	return equipped_item != null and equipped_item.id == "lasso"


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
		if _chunk_manager != null and _chunk_manager.has_merchant_near(position, TRADE_RADIUS):
			_attempt_a_purchase()
		else:
			# No merchant in reach -- fall back to selling real gathered food
			# into a nearby villager's own VillageMarket (see
			# _attempt_village_food_sale), rather than the flat "No merchant
			# nearby." this branch used to be unconditionally.
			_attempt_village_food_sale()
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


## Fallback for the trade key when no merchant is near: sells one unit of the
## player's own gathered food into the nearest real villager's own
## VillageMarket (see sell_food_to_village, docs/concept/npc.md "Local trade
## is NPC-to-NPC, not just player-to-shop" -- extended here to cover a
## player-initiated sale) -- a real XP bonus if that village was genuinely
## hungry (see EcologicalLiteracy, docs/concept/progression.md "Ecological
## literacy"). Unchanged fallback message when there is truly nobody nearby
## at all (no merchant AND no villager), matching this branch's original
## behaviour before this feature existed.
func _attempt_village_food_sale() -> void:
	var npc = _chunk_manager.nearest_npc_near(position, TRADE_RADIUS) if _chunk_manager != null else null
	if npc == null or npc.economy == null:
		_trade_result_message = "No merchant nearby."
		return
	var item_id := _first_food_item_id()
	if item_id == "":
		_trade_result_message = "No food to sell."
		return
	sell_food_to_village(npc.economy.market, item_id, 1)
	_trade_result_message = "Sold %s to the village." % _item_catalog.make(item_id).display_name


## The first food item id the player is carrying (by inventory_counts()
## iteration order), or "" if none -- what _attempt_village_food_sale sells
## when the player doesn't name a specific item.
func _first_food_item_id() -> String:
	for item_id in inventory_counts():
		if _item_catalog.kind_of(item_id) == "food":
			return item_id
	return ""


## Sells `amount` of `item_id` from inventory into `market`'s real per-
## village food stock (see VillageMarket). Real XP bonus (see
## EcologicalLiteracy) only when the market was GENUINELY hungry right
## before the sale -- VillageMarket.can_buy_meal() already means exactly
## that ("could a hungry villager buy a meal from this stock right now"), so
## "hungry" reuses that real boolean rather than an invented stock
## threshold. No gold changes hands: VillageMarket has no village-side
## wallet to pay from (see its own doc comment -- it's fed by NPC
## production, not player commerce), and the reward for feeding a real
## hungry settlement is the XP itself, not a shop transaction. Returns
## false (no-op) if the player doesn't actually carry `amount` of the item.
func sell_food_to_village(market, item_id: String, amount: int) -> bool:
	if amount <= 0 or inventory.count_of(item_id) < amount:
		return false
	var was_hungry: bool = not market.can_buy_meal()
	inventory.remove(item_id, amount)
	inventory_changed.emit()
	market.add_stock(item_id, float(amount))
	gain_experience(_ecological_literacy.village_sale_xp(was_hungry))
	return true


## Authority-only: press the talk key next to any villager (see
## EarthChunkManager.nearest_npc_near) to hear that NPC's own deterministic
## greeting line (see NpcGreeting) -- the minimal talk-interaction stand-in,
## not the real Live Dialogue System. The HUD reads talk_message.
func _talk_step(delta: float) -> void:
	var talk_pressed := (
		Input.is_action_pressed("talk") if _controlled_locally() else _pending_talk_pressed
	)
	var just_pressed := talk_pressed and not _last_talk_input
	_last_talk_input = talk_pressed
	if just_pressed:
		var npc = _chunk_manager.nearest_npc_near(position, TALK_RADIUS) if _chunk_manager != null else null
		_talk_result_message = (
			_npc_greeting.greeting_for(npc.identity) if npc != null else "No one to talk to nearby."
		)
		_talk_result_timer = TALK_MESSAGE_DURATION

	_talk_result_timer = maxf(0.0, _talk_result_timer - delta)
	talk_message = _talk_result_message if _talk_result_timer > 0.0 else ""


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


## Modes in which the player is standing in enough water to disturb it (see
## WaterMovementModel) -- wading counts, not just swimming: sloshing through
## the shallows should ripple exactly as much as a stroke does.
const WATER_RIPPLE_MODES := ["swimming", "wading"]


## Records a water disturbance (see EarthChunkManager.record_water_disturbance)
## while actually moving through water -- water ripples are caused by things
## moving through it, not by wind, so an idle float shouldn't ripple, only
## movement. Throttled to WATER_RIPPLE_INTERVAL rather than every physics tick.
func _step_water_ripples(delta: float, input_direction: Vector2) -> void:
	if not WATER_RIPPLE_MODES.has(current_mode) or input_direction.length() <= 0.01:
		_water_ripple_accumulator = 0.0
		return
	_water_ripple_accumulator += delta
	if _water_ripple_accumulator < WATER_RIPPLE_INTERVAL:
		return
	_water_ripple_accumulator = 0.0
	_chunk_manager.record_water_disturbance(position)


func _update_character_view(input_direction: Vector2) -> void:
	_character_view.set_facing(input_direction)
	_character_view.is_moving = input_direction.length() > 0.01
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
